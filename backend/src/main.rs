mod db;
mod editor;
mod instance_manager;
mod sync_match;
mod timeout;
mod timer;
mod websocket;
mod ws2;

#[macro_use]
extern crate rocket;
extern crate pbkdf2;
extern crate rocket_contrib;
#[macro_use]
extern crate log;
extern crate simplelog;
use anyhow::bail;
use async_std::task;
use db::{
    game::{RawGame, StoreAs},
    Pool,
};
use instance_manager::Instance;
use pacosako::{DenseBoard, SakoSearchResult};
use rand::{thread_rng, Rng};
use rocket::request::{self, FromRequest, Request};
use rocket::response::NamedFile;
use rocket::response::{Flash, Redirect};
use rocket::State;
use rocket::{http::Cookie, http::CookieJar};
use rocket_contrib::json::Json;
use serde::{Deserialize, Serialize};
use std::fs::File;
use sync_match::SyncronizedMatch;
use websocket::WebsocketServer;
use ws2::WS2;

/// Anyhow integration into Rocket 0.5+
#[derive(rocket::response::Responder)]
pub enum ErrorResponse {
    Debug(rocket::response::Debug<anyhow::Error>),
}

impl From<anyhow::Error> for ErrorResponse {
    fn from(e: anyhow::Error) -> Self {
        ErrorResponse::Debug(rocket::response::Debug(e))
    }
}

////////////////////////////////////////////////////////////////////////////////
// Static Files ////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

async fn static_file(path: &'static str) -> Result<NamedFile, ServerError> {
    Ok(NamedFile::open(path).await?)
}

#[get("/")]
async fn index() -> Result<NamedFile, ServerError> {
    static_file("../target/index.html").await
}

#[get("/<_path..>", rank = 2)]
async fn index_fallback(_path: std::path::PathBuf) -> Result<NamedFile, ServerError> {
    index().await
}

#[get("/favicon.svg")]
async fn favicon() -> Result<NamedFile, ServerError> {
    static_file("../target/favicon.html").await
}

#[derive(Deserialize)]
struct UseMinJs {
    use_min_js: bool,
}

/// If the server is running in development mode, we are returning the regular
/// elm.js file. In staging and production we are returning the minified
/// version of it.
#[get("/elm.min.js")]
async fn elm(config: State<'_, UseMinJs>) -> Result<NamedFile, ServerError> {
    if config.use_min_js {
        static_file("../target/elm.min.js").await
    } else {
        static_file("../target/elm.js").await
    }
}

/// If the server is running in development mode, we are returning the regular
/// main.js file. In staging and production we are returning the minified
/// version of it.
#[get("/main.min.js")]
async fn main_js(config: State<'_, UseMinJs>) -> Result<NamedFile, ServerError> {
    if config.use_min_js {
        static_file("../target/main.min.js").await
    } else {
        static_file("../target/main.js").await
    }
}

#[get("/ai_worker.js")]
async fn ai_worker() -> Result<NamedFile, ServerError> {
    static_file("../target/ai_worker.js").await
}

#[get("/static/examples.txt")]
async fn examples() -> Result<NamedFile, ServerError> {
    static_file("../target/examples.js").await
}

#[get("/static/place_piece.mp3")]
async fn place_piece() -> Result<NamedFile, ServerError> {
    static_file("../target/place_piece.js").await
}

/// This enum holds all errors that can be returned by the API. The errors are
/// returned as a JSON and may be displayed in the user interface.
#[derive(Debug, thiserror::Error)]
pub enum ServerError {
    #[error("Database error")]
    DatabaseError(#[from] sqlx::Error),
    #[error("Could not deserialize data.")]
    DeserializationFailed,
    #[error("Error from the game logic.")]
    GameError(#[from] pacosako::PacoError),
    #[error("Not allowed")]
    NotAllowed,
    #[error("Not found")]
    NotFound,
    #[error("IO-error")]
    IoError(#[from] std::io::Error),
}

impl<'r> rocket::response::Responder<'r, 'static> for ServerError {
    fn respond_to(self, _: &'r Request<'_>) -> rocket::response::Result<'static> {
        error!("Server Error: {:?}", self);
        return Err(rocket::http::Status::InternalServerError);
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
    pool: State<'_, Pool>,
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
    pool: State<'_, Pool>,
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
    conn: State<'_, Pool>,
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
    conn: State<'_, Pool>,
) -> Result<Json<Vec<Position>>, ServerError> {
    Ok(Json(conn.position_get_list(user.user_id).await?))
}

////////////////////////////////////////////////////////////////////////////////
// User Authentication /////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[derive(Deserialize)]
pub struct LoginRequest {
    username: String,
    password: String,
}

/// Request guard that makes it easy to define routes that are only available
/// to logged in members of the website.
#[derive(Serialize)]
pub struct User {
    user_id: i64,
    username: String,
}

#[rocket::async_trait]
impl<'a, 'r> FromRequest<'a, 'r> for User {
    type Error = ();

    async fn from_request(request: &'a Request<'r>) -> request::Outcome<User, ()> {
        let pool: State<'_, db::Pool> = try_outcome!(request.guard::<State<'_, db::Pool>>().await);

        let cookies = request.cookies();
        let user_id = cookies.get_private("user_id");

        if let Some(user_id) = user_id {
            let username = user_id.value().to_owned();
            if let Ok(user) = pool.get_user(username.clone()).await {
                return request::Outcome::Success(user);
            }
        }

        request::Outcome::Forward(())
    }
}

/// Log in with username and password
#[post("/login/password", data = "<login>")]
async fn login(
    login: Json<LoginRequest>,
    jar: &CookieJar<'_>,
    conn: State<'_, Pool>,
) -> Result<Json<User>, ServerError> {
    let mut conn = conn.conn().await?;

    if db::user::check_password(&mut conn, &login.0).await? {
        jar.add_private(Cookie::new("user_id", login.username.clone()));
        let user = db::user::get_user(&mut conn, login.username.clone())
            .await
            .unwrap();
        Ok(Json(user))
    } else {
        Err(ServerError::NotAllowed)
    }
}

/// Retrieve the user's ID, if any.
#[get("/user_id")]
fn user_id(user: Option<User>) -> Json<Option<User>> {
    Json(user)
}

/// Remove the `user_id` cookie.
#[get("/logout")]
fn logout(jar: &CookieJar<'_>) -> Flash<Redirect> {
    jar.remove_private(Cookie::named("user_id"));
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
fn analyse_position(
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

#[post("/share", data = "<steps>")]
fn share(
    steps: Json<Vec<serde_json::Value>>,
    websocket_server: State<WebsocketServer>,
) -> Result<String, &'static str> {
    websocket::share(&(*websocket_server), steps.0)
}

#[post("/create_game", data = "<game_parameters>")]
async fn create_game(
    game_parameters: Json<sync_match::MatchParameters>,
    pool: State<'_, Pool>,
) -> Result<String, ErrorResponse> {
    // Create a match on the database and return the id.
    // The Websocket will then have to load it on its own. While that is
    // mildly inefficient, it decouples the websocket server from the rocket
    // server a bit.

    let key = _create_game(game_parameters.0.clone(), pool).await?;
    Ok(key)
}

async fn _create_game(
    game_parameters: sync_match::MatchParameters,
    pool: State<'_, Pool>,
) -> Result<String, anyhow::Error> {
    info!("Creating a new game on client request.");
    let mut game = SyncronizedMatch::new_with_key("0", game_parameters).store()?;
    let mut conn = pool.0.acquire().await?;
    game.insert(&mut conn).await?;

    info!("Creating game created with id {}.", game.id);
    Ok(format!("{}", game.id))
}

/// Returns the current state of the given game. This is intended for use by the
/// replay page.
#[get("/game/<key>")]
async fn get_game(
    key: String,
    pool: State<'_, Pool>,
) -> Result<Json<sync_match::CurrentMatchState>, ErrorResponse> {
    Ok(Json(_get_game(key, pool).await?))
}

async fn _get_game(
    key: String,
    pool: State<'_, Pool>,
) -> Result<sync_match::CurrentMatchState, anyhow::Error> {
    let key: i64 = key.parse()?;

    if let Ok(Some(raw)) = db::game::RawGame::select(key, &mut pool.0.acquire().await?).await {
        let game: SyncronizedMatch = SyncronizedMatch::load(&raw)?;
        Ok(game.current_state()?)
    } else {
        Err(anyhow::anyhow!("Game with id {} not found.", key))
    }
}

#[get("/game/recent")]
async fn recently_created_games(
    pool: State<'_, Pool>,
) -> Result<Json<Vec<sync_match::CurrentMatchState>>, ErrorResponse> {
    Ok(Json((_recently_created_games(pool).await)?))
}

async fn _recently_created_games(
    pool: State<'_, Pool>,
) -> Result<Vec<sync_match::CurrentMatchState>, anyhow::Error> {
    let raw = db::game::RawGame::latest(&mut pool.0.acquire().await?).await?;
    let vec: Result<Vec<SyncronizedMatch>, anyhow::Error> =
        raw.iter().map(|r| SyncronizedMatch::load(r)).collect();

    let vec: Result<Vec<sync_match::CurrentMatchState>, _> =
        vec?.iter().map(|m| m.current_state()).collect();

    Ok(vec?)
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
    pool: State<'_, Pool>,
) -> Result<String, ErrorResponse> {
    let key = _branch_game(game_branch_parameters.0.clone(), pool).await?;
    Ok(key)
}

async fn _branch_game(
    game_parameters: BranchParameters,
    pool: State<'_, Pool>,
) -> Result<String, anyhow::Error> {
    info!("Creating a new game on client request.");
    let mut conn = pool.0.acquire().await?;

    let raw_game = RawGame::select(game_parameters.source_key.parse()?, &mut conn).await?;

    if let Some(raw_game) = raw_game {
        let mut game = SyncronizedMatch::load(&raw_game)?;
        game.actions.truncate(game_parameters.action_index);
        game.timer = game_parameters.timer.map(|o| o.into());

        let mut new_raw_game = game.store()?;

        new_raw_game.insert(&mut conn).await?;
        Ok(format!("{}", new_raw_game.id))
    } else {
        bail!("The game you want to branch from does not exist.")
    }
}

////////////////////////////////////////////////////////////////////////////////
// Set up logging //////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

fn init_logger() {
    use simplelog::*;

    CombinedLogger::init(vec![
        TermLogger::new(LevelFilter::Info, Config::default(), TerminalMode::Mixed),
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
fn websocket_port(port: State<WebsocketPort>) -> Json<u16> {
    Json(port.0)
}

/// Initialize the database Pool and register it as a Rocket state.
fn init_database_pool(rocket: rocket::Rocket) -> Result<rocket::Rocket, rocket::Rocket> {
    info!("Creating database pool");
    // If there is no database specified, the server is allowed to just
    // crash. This is why we can "safely" unwrap.
    let config: CustomConfig = rocket
        .figment()
        .extract()
        .expect("Config could not be parsed");

    let pool = task::block_on(db::Pool::new(&config.database_path)).unwrap();

    Ok(rocket.manage(pool))
}

/// Initialize the websocket server and register it as a rocket state.
/// By registering it as a rocket state it can be used as a service by handlers.
/// At the moment I need that for creating games, but I may be able to avoid this in the future.
fn init_websocket_server(rocket: rocket::Rocket) -> Result<rocket::Rocket, rocket::Rocket> {
    let websocket_server = websocket::prepare_websocket();

    let config: CustomConfig = rocket
        .figment()
        .extract()
        .expect("Config could not be parsed");

    if let Some(pool) = rocket.state::<Pool>() {
        websocket_server
            .borrow_match_manager()
            .with_pool(pool.clone());
    }

    websocket::init_websocket(websocket_server.clone(), config.websocket_port);

    Ok(rocket
        .manage(websocket_server)
        .manage(WebsocketPort(config.websocket_port)))
}

#[derive(Deserialize)]
struct CustomConfig {
    websocket_port: u16,
    database_path: String,
}

#[launch]
fn rocket() -> rocket::Rocket {
    use rocket::fairing::AdHoc;

    init_logger();

    // WS2::spawn(3020);

    // All the other components are created inside rocket.attach because this
    // gives them access to the rocket configuration and I can properly separate
    // the different stages like that.
    rocket::ignite()
        .attach(AdHoc::on_attach("Database Pool", |rocket| {
            Box::pin(async move { init_database_pool(rocket) })
        }))
        .attach(AdHoc::on_attach("Websocket Config", |rocket| {
            Box::pin(async move { init_websocket_server(rocket) })
        }))
        .attach(AdHoc::config::<UseMinJs>())
        .mount(
            "/",
            routes![
                index,
                elm,
                favicon,
                examples,
                place_piece,
                main_js,
                ai_worker
            ],
        )
        .mount(
            "/api/",
            routes![
                login,
                logout,
                user_id,
                position_create,
                position_update,
                position_get_list,
                position_get,
                random_position,
                analyse_position,
                share,
                create_game,
                branch_game,
                get_game,
                websocket_port,
                recently_created_games,
            ],
        )
        .mount("/", routes![index_fallback])
}
