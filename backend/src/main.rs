#![feature(proc_macro_hygiene, decl_macro)]

mod db;
mod instance_manager;
mod sync_match;
mod timeout;
mod timer;
mod websocket;

#[macro_use]
extern crate rocket;
extern crate pbkdf2;
extern crate rocket_contrib;
#[macro_use]
extern crate log;
extern crate simplelog;
use async_std::task;
use async_std::task::block_on;
use db::Pool;
use pacosako::{DenseBoard, PacoError, SakoSearchResult};
use rand::{thread_rng, Rng};
use rocket::http::{Cookie, Cookies};
use rocket::outcome::IntoOutcome;
use rocket::request::{self, FromRequest, Request};
use rocket::response::{Flash, Redirect};
use rocket::State;
use rocket_contrib::json::Json;
use serde::{Deserialize, Serialize};
use std::fs::File;
use websocket::WebsocketServer;

////////////////////////////////////////////////////////////////////////////////
// Static Files ////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[get("/")]
fn index() -> File {
    File::open("../target/index.html").unwrap()
}

#[get("/favicon.svg")]
fn favicon() -> File {
    File::open("../target/favicon.svg").unwrap()
}

#[get("/elm.js")]
fn elm() -> File {
    File::open("../target/elm.js").unwrap()
}

#[get("/main.js")]
fn main_js() -> File {
    File::open("../target/main.js").unwrap()
}

#[get("/static/examples.txt")]
fn examples() -> File {
    File::open("../target/examples.txt").unwrap()
}

#[get("/static/place_piece.mp3")]
fn place_piece() -> File {
    File::open("../target/place_piece.mp3").unwrap()
}

/// This enum holds all errors that can be returned by the API. The errors are
/// returned as a JSON and may be displayed in the user interface.
#[derive(Serialize, Debug)]
enum ServerError {
    DatabaseError { message: String },
    DeserializationFailed,
    GameError { message: String },
    NotAllowed,
    NotFound,
}

impl From<ServerError> for Json<ServerError> {
    fn from(error: ServerError) -> Self {
        Json(error)
    }
}

impl From<pacosako::PacoError> for ServerError {
    fn from(error: PacoError) -> Self {
        ServerError::GameError {
            message: format!("{:?}", error),
        }
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
fn position_create(
    create_request: Json<SavePositionRequest>,
    user: User,
    pool: State<Pool>,
) -> Result<Json<SavePositionResponse>, String> {
    match task::block_on(pool.position_create(create_request.0, user)) {
        Ok(v) => Ok(Json(v)),
        Err(e) => Err(e.to_string()),
    }
}

#[post("/position/<id>", data = "<update_request>")]
fn position_update(
    id: i64,
    update_request: Json<SavePositionRequest>,
    user: User,
    pool: State<Pool>,
) -> Result<Json<SavePositionResponse>, Json<ServerError>> {
    // You can only update a position that you own.
    if task::block_on(pool.position_get(id))?.owner != user.user_id {
        return Err(Json(ServerError::NotAllowed));
    }

    json_result(task::block_on(pool.position_update(id, update_request.0)).map_err(|e| e.into()))
}

#[derive(Serialize)]
struct Position {
    id: i64,
    owner: i64,
    data: serde_json::Value,
}

#[get("/position/<id>")]
fn position_get(
    id: i64,
    user: User,
    conn: State<Pool>,
) -> Result<Json<Position>, Json<ServerError>> {
    let position = block_on(conn.position_get(id)).and_then(|position| {
        if position.owner == user.user_id {
            Ok(position)
        } else {
            Err(ServerError::NotAllowed)
        }
    });
    json_result(position)
}

fn json_result<T, U>(result: Result<T, U>) -> Result<Json<T>, Json<U>> {
    match result {
        Ok(val) => Ok(Json(val)),
        Err(e) => Err(Json(e)),
    }
}

/// List all positions owned by the currently logged in user.
#[get("/position")]
fn position_get_list(
    user: User,
    conn: State<Pool>,
) -> Result<Json<Vec<Position>>, Json<ServerError>> {
    json_result(block_on(conn.position_get_list(user.user_id)))
}

////////////////////////////////////////////////////////////////////////////////
// User Authentication /////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
}

/// Request guard that makes it easy to define routes that are only available
/// to logged in members of the website.
#[derive(Serialize)]
struct User {
    user_id: i64,
    username: String,
}

impl<'a, 'r> FromRequest<'a, 'r> for User {
    type Error = ();

    fn from_request(request: &'a Request<'r>) -> request::Outcome<User, ()> {
        let pool: State<Pool> = request.guard()?;

        request
            .cookies()
            .get_private("user_id")
            .map(|cookie| cookie.value().to_owned())
            .and_then(|username| block_on(pool.get_user(username.to_owned())).ok())
            .or_forward(())
    }
}

/// Log in with username and password
#[post("/login/password", data = "<login>")]
fn login(
    login: Json<LoginRequest>,
    mut cookies: Cookies,
    conn: State<Pool>,
) -> Result<Json<User>, Json<ServerError>> {
    match block_on(conn.check_password(&login.0)) {
        Ok(true) => {
            cookies.add_private(Cookie::new("user_id", login.username.clone()));
            let user = block_on(conn.get_user(login.username.clone())).unwrap();
            Ok(Json(user))
        }
        Ok(false) => Err(Json(ServerError::NotFound)),
        Err(db_error) => Err(Json(db_error)),
    }
}

/// Retrieve the user's ID, if any.
#[get("/user_id")]
fn user_id(user: Option<User>) -> Json<Option<User>> {
    Json(user)
}

/// Remove the `user_id` cookie.
#[get("/logout")]
fn logout(mut cookies: Cookies) -> Flash<Redirect> {
    cookies.remove_private(Cookie::named("user_id"));
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
) -> Result<Json<AnalysisReport>, Json<ServerError>> {
    use std::convert::TryInto;

    // Get data out of request.
    let position_data: PositionData = serde_json::from_value(position.0.data).unwrap();

    // Interpret data as a PacoSako Board, this may fail and produces a result.
    let board: Result<DenseBoard, ()> =
        (&pacosako::ExchangeNotation(position_data.notation)).try_into();
    if let Ok(board) = board {
        let sequences = pacosako::find_sako_sequences(&((&board).into()));
        match sequences {
            Ok(sequences) => Ok(Json(AnalysisReport {
                text_summary: format!("{:?}", sequences),
                search_result: sequences,
            })),
            Err(error) => Err(Json(error.into())),
        }
    } else {
        Err(Json(ServerError::DeserializationFailed))
    }
}

////////////////////////////////////////////////////////////////////////////////
// Websocket integration ///////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[post("/share", data = "<steps>")]
fn share(
    steps: Json<Vec<serde_json::Value>>,
    websocket_server: State<WebsocketServer>,
) -> Result<String, &'static str> {
    websocket::share(&(*websocket_server), steps.0)
}

#[post("/create_game", data = "<game_parameters>")]
fn create_game(
    websocket_server: State<WebsocketServer>,
    game_parameters: Json<sync_match::MatchParameters>,
) -> String {
    websocket_server.new_match(game_parameters.0)
}

#[get("/game/<key>")]
fn get_game(
    key: String,
    websocket_server: State<WebsocketServer>,
) -> Result<Json<sync_match::CurrentMatchState>, Json<ServerError>> {
    let manager = websocket_server.borrow_match_manager();
    let state = manager.run(key, |sync_match| sync_match.current_state());

    match state {
        None => Err(Json(ServerError::NotFound)),
        Some(Ok(state)) => Ok(Json(state)),
        Some(Err(_)) => Err(Json(ServerError::GameError {
            message: "The game state is corrupted".to_string(),
        })),
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

fn main() {
    use rocket::fairing::AdHoc;

    init_logger();

    info!("Creating database pool");
    let pool = task::block_on(db::Pool::new("data/database.sqlite")).unwrap();

    // Launch the websocket server
    let websocket_server = websocket::prepare_websocket();

    // Launch the regular webserver
    rocket::ignite()
        .manage(websocket_server.clone())
        .manage(pool)
        .attach(AdHoc::on_attach("Websocket Config", |rocket| {
            let websocket_port: u16 =
                rocket.config().get_int("websocket_port").unwrap_or(1111) as u16;

            websocket::init_websocket(websocket_server, websocket_port);

            Ok(rocket.manage(WebsocketPort(websocket_port)))
        }))
        .attach(AdHoc::on_request("Request Logger", |req, _| {
            info!("Request started for: {}", req.uri());
        }))
        .attach(AdHoc::on_response("Response Logger", |res, _| {
            info!("Request ended for: {}", res.uri());
        }))
        .mount(
            "/",
            routes![index, elm, favicon, examples, place_piece, main_js],
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
                get_game,
                websocket_port,
            ],
        )
        .launch();
}
