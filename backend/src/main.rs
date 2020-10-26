#![feature(proc_macro_hygiene, decl_macro)]

mod instance_manager;
mod sync_match;
mod timeout;
mod timer;
mod websocket;

#[macro_use]
extern crate rocket;
#[macro_use]
extern crate rocket_contrib;
extern crate pbkdf2;
#[macro_use]
extern crate log;
extern crate simplelog;
use pacosako::{DenseBoard, PacoError, SakoSearchResult};
use rand::{thread_rng, Rng};
use rocket::http::{Cookie, Cookies};
use rocket::outcome::IntoOutcome;
use rocket::request::{self, FromRequest, Request};
use rocket::response::{Flash, Redirect};
use rocket::State;
use rocket_contrib::databases::rusqlite;
use rocket_contrib::json::Json;
use serde::{Deserialize, Serialize};
use std::fs::File;
use websocket::WebsocketServer;

#[database("sqlite_logs")]
struct DbConn(rusqlite::Connection);

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

#[get("/static/examples.txt")]
fn examples() -> File {
    File::open("../target/examples.txt").unwrap()
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

impl From<rusqlite::Error> for ServerError {
    fn from(db_error: rusqlite::Error) -> Self {
        ServerError::DatabaseError {
            message: db_error.to_string(),
        }
    }
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
    conn: DbConn,
) -> Result<Json<SavePositionResponse>, String> {
    match position_create_db(create_request.0, user, conn) {
        Ok(v) => Ok(Json(v)),
        Err(e) => Err(e.to_string()),
    }
}

fn position_create_db(
    request: SavePositionRequest,
    user: User,
    conn: DbConn,
) -> Result<SavePositionResponse, rusqlite::Error> {
    conn.execute(
        "INSERT INTO position (owner, data) VALUES (?1, ?2)",
        &[&user.user_id.to_string(), &request.data.to_string()],
    )?;

    let board_id = conn.last_insert_rowid();

    Ok(SavePositionResponse { id: board_id })
}

#[post("/position/<id>", data = "<update_request>")]
fn position_update(
    id: i64,
    update_request: Json<SavePositionRequest>,
    user: User,
    conn: DbConn,
) -> Result<Json<SavePositionResponse>, Json<ServerError>> {
    // You can only update a position that you own.
    if position_get_db(id, &conn)?.owner != user.user_id {
        return Err(Json(ServerError::NotAllowed));
    }

    json_result(position_update_db(id, update_request.0, &conn))
}

fn position_update_db(
    board_id: i64,
    request: SavePositionRequest,
    conn: &DbConn,
) -> Result<SavePositionResponse, ServerError> {
    conn.execute(
        "UPDATE position SET data = ?1 WHERE id = ?2",
        &[&board_id.to_string(), &request.data.to_string()],
    )?;

    Ok(SavePositionResponse { id: board_id })
}

#[derive(Serialize)]
struct Position {
    id: i64,
    owner: i64,
    data: serde_json::Value,
}

#[get("/position/<id>")]
fn position_get(id: i64, user: User, conn: DbConn) -> Result<Json<Position>, Json<ServerError>> {
    let position = position_get_db(id, &conn).and_then(|position| {
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

fn position_get_db(id: i64, conn: &DbConn) -> Result<Position, ServerError> {
    let stmt = "SELECT id, owner, data FROM position WHERE id = :id";

    let mut stmt = conn.prepare(&stmt)?;
    let position: Result<Position, ServerError> = stmt
        .query_map_named(&[(":id", &id)], |row| {
            let data: String = row.get(2);
            Position {
                id: row.get(0),
                owner: row.get(1),
                data: serde_json::from_str(&data).unwrap(),
            }
        })?
        .nth(0)
        .map_or(Err(ServerError::NotFound), |res| Ok(res?));

    position
}

/// List all positions owned by the currently logged in user.
#[get("/position")]
fn position_get_list(user: User, conn: DbConn) -> Result<Json<Vec<Position>>, Json<ServerError>> {
    json_result(position_get_list_db(user.user_id, &conn))
}

fn position_get_list_db(user_id: i64, conn: &DbConn) -> Result<Vec<Position>, ServerError> {
    let stmt = "SELECT id, owner, data FROM position WHERE owner = :owner";

    let mut stmt = conn.prepare(&stmt)?;
    let positions: Result<Vec<Position>, ServerError> = stmt
        .query_map_named(&[(":owner", &user_id)], |row| {
            let data: String = row.get(2);
            Position {
                id: row.get(0),
                owner: row.get(1),
                data: serde_json::from_str(&data).unwrap(),
            }
        })?
        .map(|position| Ok(position?)) // convert rusqlite::Error -> ServerError
        .collect();

    positions
}

////////////////////////////////////////////////////////////////////////////////
// Article CRUD ////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[derive(Serialize, Deserialize)]
struct Article {
    id: i64,
    creator: i64,
    title: String,
    body: String,
    visible: i64,
}

trait Crud: Sized {
    fn save(self, conn: &DbConn) -> Result<Self, ServerError>;
    fn load(id: i64, conn: &DbConn) -> Result<Self, ServerError>;
    fn from_row(row: &rocket_contrib::databases::rusqlite::Row<'_, '_>) -> Self;
}

impl Crud for Article {
    fn save(mut self, conn: &DbConn) -> Result<Self, ServerError> {
        if self.id > 1 {
            conn.execute(
                "UPDATE article SET creator = ?1, title = ?2, body = ?3, visible = ?4 WHERE id = ?5",
                &[
                    &self.creator.to_string(),
                    &self.title,
                    &self.body,
                    &self.visible,
                    &self.id.to_string(),
                ],
            )?;
        } else {
            conn.execute(
                "INSERT INTO article (creator, title, body, visible) VALUES (?1, ?2, ?3, ?4)",
                &[
                    &self.creator.to_string(),
                    &self.title,
                    &self.body,
                    &self.visible,
                ],
            )?;
            self.id = conn.last_insert_rowid();
        }
        Ok(self)
    }
    fn load(id: i64, conn: &DbConn) -> Result<Self, ServerError> {
        let stmt = "select id, creator, title, body, visible from article where id = :id";
        let mut stmt = conn.prepare(&stmt)?;
        let article: Result<Article, ServerError> = stmt
            .query_map_named(&[(":id", &id)], Article::from_row)?
            .nth(0)
            .map_or(Err(ServerError::NotFound), |res| Ok(res?));

        article
    }
    fn from_row(row: &rocket_contrib::databases::rusqlite::Row<'_, '_>) -> Self {
        Article {
            id: row.get(0),
            creator: row.get(1),
            title: row.get(2),
            body: row.get(3),
            visible: row.get(4),
        }
    }
}

/// List all articles created by the currently logged in user.
#[get("/article/my")]
fn article_get_my_list(user: User, conn: DbConn) -> Result<Json<Vec<Article>>, Json<ServerError>> {
    json_result(article_get_my_list_db(user.user_id, &conn))
}

fn article_get_my_list_db(user_id: i64, conn: &DbConn) -> Result<Vec<Article>, ServerError> {
    let stmt = "select id, creator, title, body, visible from article where creator = :creator";

    let mut stmt = conn.prepare(&stmt)?;
    let positions: Result<Vec<Article>, ServerError> = stmt
        .query_map_named(&[(":creator", &user_id)], Article::from_row)?
        .map(|position| Ok(position?)) // convert rusqlite::Error -> ServerError
        .collect();

    positions
}

/// List all articles created by the currently logged in user.
#[get("/article/public")]
fn article_get_public_list(conn: DbConn) -> Result<Json<Vec<Article>>, Json<ServerError>> {
    json_result(article_get_public_list_db(&conn))
}

fn article_get_public_list_db(conn: &DbConn) -> Result<Vec<Article>, ServerError> {
    let stmt = "select id, creator, title, body, visible from article where visible = 1";

    let mut stmt = conn.prepare(&stmt)?;
    let positions: Result<Vec<Article>, ServerError> = stmt
        .query_map_named(&[], Article::from_row)?
        .map(|position| Ok(position?)) // convert rusqlite::Error -> ServerError
        .collect();

    positions
}

/// Returns a particular article, if this article exists and is visible to the
/// logged in user.
/// TODO: I should take an Option<User> to allow non-logged in users to access
/// public articles.
#[get("/article/<id>")]
fn article_get(id: i64, user: User, conn: DbConn) -> Result<Json<Article>, Json<ServerError>> {
    let article = Article::load(id, &conn).and_then(|article| {
        if article.creator == user.user_id {
            Ok(article)
        } else {
            Err(ServerError::NotAllowed)
        }
    });
    json_result(article)
}

#[post("/article", data = "<article>")]
fn article_post(
    mut article: Json<Article>,
    user: User,
    conn: DbConn,
) -> Result<Json<Article>, Json<ServerError>> {
    let new_article = if article.id <= 0 {
        // Create a new article
        article.creator = user.user_id;
        article.0.save(&conn)
    } else {
        let old_article = Article::load(article.id, &conn)?;
        // Check if the user owns article, then update
        if old_article.creator == article.creator && old_article.creator == user.user_id {
            article.0.save(&conn)
        } else {
            Err(ServerError::NotAllowed)
        }
    };

    json_result(new_article)
}

#[post("/article/visible", data = "<article>")]
fn article_post_visible(
    article: Json<Article>,
    user: User,
    conn: DbConn,
) -> Result<Json<Article>, Json<ServerError>> {
    let mut old_article = Article::load(article.id, &conn)?;
    let new_article = if old_article.creator == user.user_id {
        old_article.visible = article.visible;
        article.0.save(&conn)
    } else {
        Err(ServerError::NotAllowed)
    };

    json_result(new_article)
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
        let conn = request.guard::<DbConn>()?;
        request
            .cookies()
            .get_private("user_id")
            .map(|cookie| cookie.value().to_owned())
            .and_then(|username| get_user(username.to_owned(), &conn).ok())
            .or_forward(())
    }
}

fn get_user(username: String, conn: &DbConn) -> Result<User, rusqlite::Error> {
    let stmt = "SELECT id, username FROM user WHERE username = :username";

    let mut stmt = conn.prepare(&stmt)?;
    let user_id: i64 = stmt
        .query_map_named(&[(":username", &username)], |row| row.get(0))?
        .nth(0)
        .unwrap()?;

    Ok(User { user_id, username })
}

/// Log in with username and password
#[post("/login/password", data = "<login>")]
fn login(
    login: Json<LoginRequest>,
    mut cookies: Cookies,
    conn: DbConn,
) -> Result<Json<User>, Json<ServerError>> {
    match check_password(&login.0, &conn) {
        Ok(true) => {
            cookies.add_private(Cookie::new("user_id", login.username.clone()));
            let user = get_user(login.username.clone(), &conn).unwrap();
            Ok(Json(user))
        }
        Ok(false) => Err(Json(ServerError::NotFound)),
        Err(db_error) => Err(Json(ServerError::DatabaseError {
            message: db_error.to_string(),
        })),
    }
}

fn check_password(login: &LoginRequest, conn: &DbConn) -> Result<bool, rusqlite::Error> {
    use pbkdf2::pbkdf2_check;
    let stmt = "SELECT password FROM user WHERE username = :username";

    let mut stmt = conn.prepare(&stmt)?;
    let password_hash: String = stmt
        .query_map_named(&[(":username", &login.username)], |row| row.get(0))?
        .nth(0)
        .unwrap()?;

    Ok(pbkdf2_check(&login.password, &password_hash).is_ok())
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

    // Launch the websocket server
    let websocket_server = websocket::prepare_websocket();

    // Launch the regular webserver
    rocket::ignite()
        .manage(websocket_server.clone())
        .attach(AdHoc::on_attach("Websocket Config", |rocket| {
            let websocket_port: u16 =
                rocket.config().get_int("websocket_port").unwrap_or(1111) as u16;

            websocket::init_websocket(websocket_server, websocket_port);

            Ok(rocket.manage(WebsocketPort(websocket_port)))
        }))
        .attach(DbConn::fairing())
        .attach(AdHoc::on_request("Request Logger", |req, _| {
            info!("Request started for: {}", req.uri());
        }))
        .attach(AdHoc::on_response("Response Logger", |res, _| {
            info!("Request ended for: {}", res.uri());
        }))
        .mount("/", routes![index, elm, favicon, examples])
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
                article_get_my_list,
                article_get_public_list,
                article_get,
                article_post,
                article_post_visible,
                share,
                create_game,
                get_game,
                websocket_port,
            ],
        )
        .launch();
}
