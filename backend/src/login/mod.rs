//! This module collects everything related to the login process.
//! It is introduced with the 20230826184016_user_management.sql script

mod crypto;
pub mod session;
pub mod user;

use crate::{
    config::EnvironmentConfig,
    db::{Connection, Pool},
};
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::{
    extract::State,
    response::{IntoResponse, Response},
    Json,
};
use reqwest::StatusCode;
use serde::Deserialize;
use tower_cookies::{cookie::SameSite, Cookie, Cookies};

use self::session::SessionData;

#[derive(Debug, PartialEq, Eq, Copy, Clone)]
pub struct UserId(pub i64);
#[derive(Debug, Clone)]
pub struct SessionId(String);

#[derive(Deserialize)]
pub struct UsernamePasswordDTO {
    username: String,
    password: String,
}

const SESSION_COOKIE: &str = "session";

/// POST a username and password to this endpoint to login.
/// The response will redirect you to "/" if the login was successful.
/// You'll also get a (http-only) cookie with the encrypted session id.
/// Username/password is expected as a JSON object in the body.
pub async fn username_password_route(
    pool: State<Pool>,
    config: State<EnvironmentConfig>,
    cookies: Cookies,
    dto: Json<UsernamePasswordDTO>,
) -> Response {
    match username_password(pool, config, cookies, dto).await {
        Ok(_) => (StatusCode::OK).into_response(),
        Err(_) => (StatusCode::UNAUTHORIZED).into_response(),
    }
}

async fn username_password(
    pool: State<Pool>,
    config: State<EnvironmentConfig>,
    cookies: Cookies,
    dto: Json<UsernamePasswordDTO>,
) -> Result<impl IntoResponse, anyhow::Error> {
    info!("Login attempt for user {}", dto.username);
    let mut connection = pool.conn().await.expect("No connection available");
    let Ok(user_id) = get_user_for_login(&dto, &mut connection).await else {
        if config.dev_mode {
            info!(
                "Password could hash to {}",
                generate_password_hash(&dto.password)
            );
        }
        anyhow::bail!("Login failed");
    };

    let session = session::create_session(user_id, &mut connection).await?;
    let client_session = crypto::encrypt_session_key(&session, &config.secret_key)?;

    let session_cookie = Cookie::build(SESSION_COOKIE, client_session)
        .path("/")
        .http_only(true)
        .secure(!config.dev_mode)
        .same_site(SameSite::Strict)
        .max_age(time::Duration::days(14))
        .finish();
    cookies.add(session_cookie);

    Ok(())
}

/// Resolves the hashed password for a user identifier (password)
/// This will update the `last_login` field in the database.
async fn get_user_for_login(
    dto: &UsernamePasswordDTO,
    connection: &mut Connection,
) -> Result<UserId, anyhow::Error> {
    let res = sqlx::query!(
        "select user_id, hashed_password, id from login where identifier = ?",
        dto.username
    )
    .fetch_one(&mut *connection)
    .await?;

    let Some(hashed_password) = res.hashed_password else {
        anyhow::bail!("No password found for user {}", dto.username)
    };

    // Check if the password is correct
    let argon2 = Argon2::default();
    let parsed_hash = PasswordHash::new(&hashed_password)?;
    argon2.verify_password(dto.password.as_bytes(), &parsed_hash)?;

    // Update the last_login field
    sqlx::query!(
        "update login set last_login = CURRENT_TIMESTAMP where id = ?",
        res.id
    )
    .execute(connection)
    .await?;

    Ok(UserId(res.user_id))
}

fn generate_password_hash(password: &str) -> String {
    let argon2 = Argon2::default();
    let salt = SaltString::generate(&mut OsRng);
    argon2
        .hash_password(password.as_bytes(), &salt)
        .unwrap()
        .to_string()
}

pub async fn logout_route(
    session: SessionData,
    cookies: Cookies,
    pool: State<Pool>,
) -> impl IntoResponse {
    let mut connection = pool.conn().await.expect("No connection available");
    sqlx::query!("delete from session where user_id = ?", session.user_id.0)
        .execute(&mut connection)
        .await
        .expect("Error removing sessions for user.");

    cookies.remove(
        Cookie::build(SESSION_COOKIE, "")
            .path("/")
            .same_site(SameSite::Strict)
            .finish(),
    );

    format!("Logout for user {}", session.user_id.0)
}
