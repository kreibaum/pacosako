mod assets;
mod caching;
mod db;
mod discord;
mod language;
mod sync_match;
mod timer;
mod ws;

#[macro_use]
extern crate rocket;
#[macro_use]
extern crate log;
extern crate simplelog;
use crate::ws::RocketToWsMsg;
use db::Pool;
use pacosako::{DenseBoard, SakoSearchResult};
use rand::{thread_rng, Rng};
use rocket::response::{Flash, Redirect};
use rocket::serde::json::Json;
use rocket::State;
use rocket::{http::Cookie, http::CookieJar};
use rocket::{
    request::{self, FromRequest, Request},
    Build,
};
use rocket_dyn_templates::{context, Template};
use serde::{Deserialize, Serialize};
use std::fs::File;
use sync_match::SynchronizedMatch;

#[get("/")]
async fn index(config: &State<DevEnvironmentConfig>, lang: language::UserLanguage) -> Template {
    // Print what the hashes of elm.min.js and main.js are.
    // This is useful for debugging cache busting.
    let elm_filename = assets::elm_filename(lang.0.clone(), config.use_min_js);
    debug!(
        "File {} has hash: {}",
        elm_filename,
        caching::hash_file(elm_filename, true)
    );
    let main_filename = assets::main_filename(config.use_min_js);
    debug!(
        "File {} has hash: {}",
        main_filename,
        caching::hash_file(main_filename, true)
    );

    Template::render(
        "index",
        context! {
            lang: lang.0,
            elm_hash: caching::hash_file(elm_filename, config.cache_js_hashes),
            main_hash: caching::hash_file(main_filename, config.cache_js_hashes),
            lib_worker_hash:  caching::hash_file("../target/lib_worker.min.js", config.cache_js_hashes),
            wasm_js_hash: caching::hash_file("../target/lib.min.js", config.cache_js_hashes),
            wasm_hash: caching::hash_file("../target/lib.wasm", config.cache_js_hashes),
        },
    )
}

#[get("/<_path..>", rank = 2)]
async fn index_fallback(
    _path: std::path::PathBuf,
    config: &State<DevEnvironmentConfig>,
    lang: language::UserLanguage,
) -> Template {
    index(config, lang).await
}

/// Various settings that differentiate the development environment from the
/// production environment.
#[derive(Deserialize)]
pub struct DevEnvironmentConfig {
    use_min_js: bool,
    cache_js_hashes: bool,
}

/// This enum holds all errors that can be returned by the API.
#[derive(Debug, thiserror::Error)]
pub enum ServerError {
    #[error("Database error")]
    DatabaseError(#[from] sqlx::Error),
    #[error("Could not deserialize data.")]
    DeserializationFailed,
    #[error("Error from the game logic.")]
    GameError(#[from] pacosako::PacoError),
    #[error("(De-)Serialization failed")]
    SerdeJsonError(#[from] serde_json::Error),
    #[error("Not allowed")]
    NotAllowed,
    #[error("Not found")]
    NotFound,
    #[error("IO-error")]
    IoError(#[from] std::io::Error),
    #[error("Error parsing Integer")]
    ParseIntError(#[from] std::num::ParseIntError),
}

impl<'r> rocket::response::Responder<'r, 'static> for ServerError {
    fn respond_to(self, _: &'r Request<'_>) -> rocket::response::Result<'static> {
        error!("Server Error: {:?}", self);
        Err(rocket::http::Status::InternalServerError)
    }
}

#[get("/puzzle/<id>")]
async fn puzzle_get(id: i64, pool: &State<Pool>) -> Result<String, ServerError> {
    if let Some(puzzle) = db::puzzle::get(id, &mut pool.0.acquire().await?).await? {
        Ok(puzzle)
    } else {
        Err(ServerError::NotFound)
    }
}

////////////////////////////////////////////////////////////////////////////////
// Saved Position Management - CRUD ////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
// Data is stored in a JSON string, because we probably don't need to join on
// any content of the board.
// { "notation" : "..." }

/// POST data of a request where the frontend wants to save a position.
/// We are just storing the plain JSON value to the database without inspecting it.
#[derive(Deserialize)]
struct SavePositionRequest {
    data: serde_json::Value,
}

/// Response of a request, where a position was successfully saved to the server.
#[derive(Serialize)]
struct SavePositionResponse {
    id: i64,
}

#[post("/position", data = "<create_request>")]
async fn position_create(
    create_request: Json<SavePositionRequest>,
    user: User,
    pool: &State<Pool>,
) -> Result<Json<SavePositionResponse>, String> {
    match pool.position_create(create_request.0, user).await {
        Ok(v) => Ok(Json(v)),
        Err(e) => Err(e.to_string()),
    }
}

#[post("/position/<id>", data = "<update_request>")]
async fn position_update(
    id: i64,
    update_request: Json<SavePositionRequest>,
    user: User,
    pool: &State<Pool>,
) -> Result<Json<SavePositionResponse>, ServerError> {
    // You can only update a position that you own.
    if pool.position_get(id).await?.owner != user.user_id {
        return Err(ServerError::NotAllowed);
    }

    Ok(Json(pool.position_update(id, update_request.0).await?))
}

#[derive(Serialize)]
struct Position {
    id: i64,
    owner: i64,
    data: serde_json::Value,
}

#[get("/position/<id>")]
async fn position_get(
    id: i64,
    user: User,
    conn: &State<Pool>,
) -> Result<Json<Position>, ServerError> {
    conn.position_get(id).await.and_then(|position| {
        if position.owner == user.user_id {
            Ok(Json(position))
        } else {
            Err(ServerError::NotAllowed)
        }
    })
}

/// List all positions owned by the currently logged in user.
#[get("/position")]
async fn position_get_list(
    user: User,
    conn: &State<Pool>,
) -> Result<Json<Vec<Position>>, ServerError> {
    Ok(Json(conn.position_get_list(user.user_id).await?))
}

////////////////////////////////////////////////////////////////////////////////
// User Authentication /////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/// Request guard that makes it easy to define routes that are only available
/// to logged in members of the website.
#[derive(Serialize)]
pub struct User {
    user_id: i64,
    username: String,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for User {
    type Error = ();

    async fn from_request(request: &'r Request<'_>) -> request::Outcome<User, ()> {
        use rocket::outcome::try_outcome;

        let pool: &State<db::Pool> = try_outcome!(request.guard::<&State<db::Pool>>().await);
        let conn = pool.conn().await;

        if conn.is_err() {
            return request::Outcome::Failure((rocket::http::Status::InternalServerError, ()));
        }
        let mut conn = conn.unwrap();

        let cookies = request.cookies();
        let session_id = cookies.get_private("session_id");

        if let Some(session_id) = session_id {
            let user = discord::get_user_for_session_id(session_id.value(), &mut conn).await;

            if user.is_err() {
                return request::Outcome::Failure((rocket::http::Status::InternalServerError, ()));
            }
            let user = user.unwrap();
            if let Some(user) = user {
                return request::Outcome::Success(User {
                    user_id: user.id,
                    username: user.username,
                });
            }
        }

        request::Outcome::Forward(())
    }
}

/// Retrieve the user's ID, if any.
#[get("/user_id")]
fn user_id(user: Option<User>) -> Json<Option<User>> {
    Json(user)
}

#[get("/oauth/discord_client_id")]
async fn discord_client_id(config: &State<CustomConfig>) -> Json<String> {
    Json(config.discord_client_id.clone())
}

#[get("/oauth/redirect?<code>&<state>")]
async fn authorize_discord_oauth_code(
    config: &State<CustomConfig>,
    code: &str,
    state: &str,
    jar: &CookieJar<'_>,
    pool: &State<Pool>,
) -> Flash<Redirect> {
    let conn = pool.conn().await;
    if conn.is_err() {
        return Flash::error(Redirect::to("/"), "Database error");
    }
    let mut conn = conn.unwrap();

    let res = discord::authorize_oauth_code(config, code, state, jar, &mut conn).await;
    match res {
        Ok(_) => Flash::success(Redirect::to("/"), "Login successful"),
        Err(e) => {
            warn!("Login failed: {}", e);
            Flash::error(
                Redirect::to("/login"),
                "Error during authentication. Please try again.",
            )
        }
    }
}

/// Remove the `user_id` cookie.
#[get("/logout")]
fn logout(jar: &CookieJar<'_>) -> Flash<Redirect> {
    jar.remove_private(Cookie::named("session_id"));
    Flash::success(Redirect::to("/"), "Successfully logged out.")
}

////////////////////////////////////////////////////////////////////////////////
// Analysis and random positions ///////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[derive(Serialize, Deserialize)]
struct PositionData {
    notation: String,
}

#[get("/random")]
fn random_position() -> Json<PositionData> {
    let mut rng = thread_rng();
    let board: DenseBoard = rng.gen();

    let notation: pacosako::ExchangeNotation = (&board).into();

    Json(PositionData {
        notation: notation.0,
    })
}

#[derive(Serialize)]
struct AnalysisReport {
    text_summary: String,
    search_result: SakoSearchResult,
}

#[post("/analyse", data = "<position>")]
fn analyze_position(
    position: Json<SavePositionRequest>,
) -> Result<Json<AnalysisReport>, ServerError> {
    use std::convert::TryInto;

    // Get data out of request.
    let position_data: PositionData = serde_json::from_value(position.0.data).unwrap();

    // Interpret data as a PacoSako Board, this may fail and produces a result.
    let board: Result<DenseBoard, ()> =
        (&pacosako::ExchangeNotation(position_data.notation)).try_into();
    if let Ok(board) = board {
        let sequences = pacosako::find_sako_sequences(&((&board).into()))?;
        Ok(Json(AnalysisReport {
            text_summary: format!("{:?}", sequences),
            search_result: sequences,
        }))
    } else {
        Err(ServerError::DeserializationFailed)
    }
}

////////////////////////////////////////////////////////////////////////////////
// Game management /////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[post("/create_game", data = "<game_parameters>")]
async fn create_game(
    game_parameters: Json<sync_match::MatchParameters>,
    pool: &State<Pool>,
) -> Result<String, ServerError> {
    // Create a match on the database and return the id.
    // The Websocket will then have to load it on its own. While that is
    // mildly inefficient, it decouples the websocket server from the rocket
    // server a bit.

    info!("Creating a new game on client request.");
    let mut conn = pool.conn().await?;
    let mut game = SynchronizedMatch::new_with_key("0", game_parameters.0.sanitize());
    db::game::insert(&mut game, &mut conn).await?;

    info!("Game created with id {}.", game.key);
    Ok(game.key.to_string())
}

/// Returns the current state of the given game. This is intended for use by the
/// replay page.
#[get("/game/<key>")]
async fn get_game(
    key: String,
    pool: &State<Pool>,
) -> Result<Json<sync_match::CurrentMatchState>, ServerError> {
    let key: i64 = key.parse()?;
    let mut conn = pool.conn().await?;

    if let Some(game) = db::game::select(key, &mut conn).await? {
        Ok(Json(game.current_state()?))
    } else {
        Err(ServerError::NotFound)
    }
}

#[post("/ai/game/<key>", data = "<action>")]
async fn post_action_to_game(
    key: String,
    action: Json<pacosako::PacoAction>,
    send_to_websocket: &State<async_channel::Sender<ws::RocketToWsMsg>>,
) {
    match send_to_websocket
        .send(RocketToWsMsg::AiAction {
            key,
            action: action.0,
        })
        .await
    {
        Ok(_) => {}
        Err(e) => {
            error!("Error sending from rocket to the websocket server: {:?}", e)
        }
    }
}

#[get("/game/recent")]
async fn recently_created_games(
    pool: &State<Pool>,
) -> Result<Json<Vec<sync_match::CurrentMatchState>>, ServerError> {
    let games = db::game::latest(&mut pool.conn().await?).await?;

    let vec: Result<Vec<sync_match::CurrentMatchState>, _> =
        games.iter().map(|m| m.current_state()).collect();

    Ok(Json(vec?))
}

#[derive(Deserialize, Clone)]
struct BranchParameters {
    source_key: String,
    action_index: usize,
    timer: Option<timer::TimerConfig>,
}

/// Create a match from an existing match
#[post("/branch_game", data = "<game_branch_parameters>")]
async fn branch_game(
    game_branch_parameters: Json<BranchParameters>,
    pool: &State<Pool>,
) -> Result<String, ServerError> {
    info!("Creating a new game on client request.");
    let mut conn = pool.conn().await?;

    let game = db::game::select(game_branch_parameters.source_key.parse()?, &mut conn).await?;

    if let Some(mut game) = game {
        game.actions.truncate(game_branch_parameters.action_index);

        game.timer = game_branch_parameters.timer.clone().map(|o| o.into());

        db::game::insert(&mut game, &mut conn).await?;

        Ok(game.key)
    } else {
        Err(ServerError::NotFound)
    }
}

////////////////////////////////////////////////////////////////////////////////
// Set up logging //////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

fn init_logger() {
    use simplelog::*;

    CombinedLogger::init(vec![
        TermLogger::new(
            LevelFilter::Info,
            Config::default(),
            TerminalMode::Mixed,
            ColorChoice::Auto,
        ),
        WriteLogger::new(
            LevelFilter::Debug,
            Config::default(),
            File::create("server.log").unwrap(),
        ),
    ])
    .unwrap();

    debug!("Logger successfully initialized");
}

////////////////////////////////////////////////////////////////////////////////
// Start the server ////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/// Struct to read the websocket_port config parameter from the rocket config
/// which is used to launch the websocket server.
struct WebsocketPort(u16);

#[get("/websocket/port")]
fn websocket_port(port: &State<WebsocketPort>) -> Json<u16> {
    Json(port.0)
}

/// Initialize the database Pool and register it as a Rocket state.
async fn init_database_pool(rocket: rocket::Rocket<Build>) -> rocket::Rocket<Build> {
    info!("Creating database pool");
    // If there is no database specified, the server is allowed to just
    // crash. This is why we can "safely" unwrap.
    let config: CustomConfig = rocket
        .figment()
        .extract()
        .expect("Config could not be parsed");

    let pool = db::Pool::new(&config.database_path)
        .await
        .expect("Pool can't be created.");

    // Apply all pending database migrations. (Important for automated updates)
    info!("Starting database migrations (if necessary)");
    let migration_result = sqlx::migrate!().run(&pool.0).await;
    if let Err(migration_error) = migration_result {
        panic!(
            "Migration error when starting the server: {:?}",
            migration_error
        );
    }
    info!("Database migrated successfully.");

    rocket.manage(pool)
}

/// Initialize the websocket server and provide it with a database connection.
fn init_new_websocket_server(rocket: rocket::Rocket<Build>) -> rocket::Rocket<Build> {
    let config: CustomConfig = rocket
        .figment()
        .extract()
        .expect("Config could not be parsed");

    let pool = rocket.state::<Pool>().expect("Database pool not in state!");
    let send_to_websocket: async_channel::Sender<ws::RocketToWsMsg> =
        ws::run_server(config.websocket_port, pool.clone())
            .expect("Error starting websocket server!");

    rocket
        .manage(WebsocketPort(config.websocket_port))
        .manage(send_to_websocket)
}

#[derive(Deserialize)]
pub struct CustomConfig {
    websocket_port: u16,
    database_path: String,
    discord_client_id: String,
    discord_client_secret: String,
    application_url: String,
}

#[launch]
fn rocket() -> _ {
    use rocket::fairing::AdHoc;

    init_logger();

    // All the other components are created inside rocket.attach because this
    // gives them access to the rocket configuration and I can properly separate
    // the different stages like that.
    rocket::build()
        .attach(AdHoc::on_ignite("Database Pool", |rocket| {
            init_database_pool(rocket)
        }))
        .attach(AdHoc::on_ignite("Websocket Server", |rocket| {
            Box::pin(async move { init_new_websocket_server(rocket) })
        }))
        .attach(AdHoc::config::<DevEnvironmentConfig>())
        .attach(AdHoc::config::<CustomConfig>())
        .attach(Template::fairing())
        .mount(
            "/",
            routes![
                index,
                assets::elm_cached,
                assets::favicon,
                assets::logo,
                assets::bg,
                assets::place_piece,
                assets::main_js_cached,
                assets::lib_worker,
                assets::lib_js,
                assets::lib_wasm
            ],
        )
        .mount(
            "/api/",
            routes![
                logout,
                user_id,
                position_create,
                position_update,
                position_get_list,
                position_get,
                post_action_to_game,
                random_position,
                analyze_position,
                create_game,
                branch_game,
                get_game,
                websocket_port,
                recently_created_games,
                language::user_language,
                language::set_user_language,
                discord_client_id,
                authorize_discord_oauth_code,
                puzzle_get,
            ],
        )
        .mount("/", routes![index_fallback])
}
