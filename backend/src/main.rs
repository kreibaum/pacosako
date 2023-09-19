mod caching;
mod config;
mod db;
mod secret_login;
//mod discord;
mod actors;
mod game;
mod language;
mod login;
mod replay_data;
mod server;
mod statistics;
mod sync_match;
mod templates;
mod timer;
mod ws;

#[macro_use]
extern crate log;
extern crate simplelog;
use axum::{
    extract::FromRef,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use config::EnvironmentConfig;
use db::Pool;
use std::fs::File;

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

impl IntoResponse for ServerError {
    fn into_response(self) -> Response {
        match self {
            Self::NotAllowed => (StatusCode::FORBIDDEN, "Not allowed").into_response(),
            Self::NotFound => (StatusCode::NOT_FOUND, "Not found").into_response(),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()).into_response(),
        }
    }
}

// ////////////////////////////////////////////////////////////////////////////////
// // User Authentication /////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////////////

// /// Request guard that makes it easy to define routes that are only available
// /// to logged in members of the website.
// #[derive(Serialize)]
// pub struct User {
//     user_id: i64,
//     username: String,
// }

// #[rocket::async_trait]
// impl<'r> FromRequest<'r> for User {
//     type Error = ();

//     async fn from_request(request: &'r Request<'_>) -> request::Outcome<User, ()> {
//         use rocket::outcome::try_outcome;

//         let pool: &State<db::Pool> = try_outcome!(request.guard::<&State<db::Pool>>().await);
//         let conn = pool.conn().await;

//         if conn.is_err() {
//             return request::Outcome::Failure((rocket::http::Status::InternalServerError, ()));
//         }
//         let mut conn = conn.unwrap();

//         let cookies = request.cookies();
//         let session_id = cookies.get_private("session_id");

//         if let Some(session_id) = session_id {
//             let user = discord::get_user_for_session_id(session_id.value(), &mut conn).await;

//             if user.is_err() {
//                 return request::Outcome::Failure((rocket::http::Status::InternalServerError, ()));
//             }
//             let user = user.unwrap();
//             if let Some(user) = user {
//                 return request::Outcome::Success(User {
//                     user_id: user.id,
//                     username: user.username,
//                 });
//             }
//         }

//         request::Outcome::Forward(())
//     }
// }

// /// Retrieve the user's ID, if any.
// #[get("/user_id")]
// fn user_id(user: Option<User>) -> Json<Option<User>> {
//     Json(user)
// }

// #[get("/oauth/discord_client_id")]
// async fn discord_client_id(config: &State<CustomConfig>) -> Json<String> {
//     Json(config.discord_client_id.clone())
// }

// #[get("/oauth/redirect?<code>&<state>")]
// async fn authorize_discord_oauth_code(
//     config: &State<CustomConfig>,
//     code: &str,
//     state: &str,
//     jar: &CookieJar<'_>,
//     pool: &State<Pool>,
// ) -> Flash<Redirect> {
//     let conn = pool.conn().await;
//     if conn.is_err() {
//         return Flash::error(Redirect::to("/"), "Database error");
//     }
//     let mut conn = conn.unwrap();

//     let res = discord::authorize_oauth_code(config, code, state, jar, &mut conn).await;
//     match res {
//         Ok(_) => Flash::success(Redirect::to("/"), "Login successful"),
//         Err(e) => {
//             warn!("Login failed: {}", e);
//             Flash::error(
//                 Redirect::to("/login"),
//                 "Error during authentication. Please try again.",
//             )
//         }
//     }
// }

// /// Remove the `user_id` cookie.
// #[get("/logout")]
// fn logout(jar: &CookieJar<'_>) -> Flash<Redirect> {
//     jar.remove_private(Cookie::named("session_id"));
//     Flash::success(Redirect::to("/"), "Successfully logged out.")
// }

////////////////////////////////////////////////////////////////////////////////
// Game management /////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Set up logging //////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

fn init_logger() {
    use simplelog::{
        ColorChoice, CombinedLogger, Config, LevelFilter, TermLogger, TerminalMode, WriteLogger,
    };

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

/// Initialize the database Pool and register it as a Rocket state.
async fn init_database_pool(config: EnvironmentConfig) -> Pool {
    info!("Creating database pool");
    let now = std::time::Instant::now();

    // If there is no database specified, the server is allowed to just
    // crash. This is why we can "safely" unwrap.

    let pool = db::Pool::new(&config.database_path)
        .await
        .expect("Pool can't be created.");

    // Apply all pending database migrations. (Important for automated updates)
    info!("Starting database migrations (if necessary)");
    let migration_result = sqlx::migrate!().run(&pool.0).await;
    if let Err(migration_error) = migration_result {
        panic!("Migration error when starting the server: {migration_error:?}");
    }
    info!("Database migrated successfully.");
    info!("Pool ready in {}ms", now.elapsed().as_millis());

    pool
}

/// Initialize the websocket server and provide it with a database connection.
fn init_new_websocket_server(pool: Pool) {
    info!("Starting websocket server");
    let now = std::time::Instant::now();

    ws::run_server(pool);

    info!(
        "Websocket server started in {}ms",
        now.elapsed().as_millis()
    );
}

#[derive(Clone)]
pub struct AppState {
    config: EnvironmentConfig,
    pool: Pool,
}

// support converting an `AppState` in an `EnvironmentConfig`
impl FromRef<AppState> for EnvironmentConfig {
    fn from_ref(app_state: &AppState) -> Self {
        app_state.config.clone()
    }
}

// support converting an `AppState` in an `Pool`
impl FromRef<AppState> for Pool {
    fn from_ref(app_state: &AppState) -> Self {
        app_state.pool.clone()
    }
}

#[tokio::main]
async fn main() {
    let config = config::load_config();

    init_logger();

    let pool = init_database_pool(config.clone()).await;

    init_new_websocket_server(pool.clone());

    let state = AppState { config, pool };

    server::run(state).await;
}
