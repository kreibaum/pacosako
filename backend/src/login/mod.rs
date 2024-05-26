//! This module collects everything related to the login process.
//! It is introduced with the 20230826184016_user_management.sql script

use argon2::{
    Argon2,
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, rand_core::OsRng, SaltString},
};
use axum::{
    extract::{Query, State},
    Json,
    response::{IntoResponse, Response},
};
use hyper::StatusCode;
use serde::{Deserialize, Serialize};
use tower_cookies::{Cookie, cookie::SameSite, Cookies};

use crate::{
    config::EnvironmentConfig,
    db::{Connection, Pool},
    ServerError,
};

use self::session::SessionData;

mod crypto;
pub mod discord;
pub mod session;
pub mod user;
pub mod permission;

#[derive(Debug, PartialEq, Eq, Copy, Clone, Serialize, Deserialize)]
pub struct UserId(pub i64);

#[derive(Debug, Clone)]
pub struct SessionId(String);

#[derive(Deserialize)]
pub struct UsernamePasswordDTO {
    username: String,
    password: String,
}

const SESSION_COOKIE: &str = "session";

#[derive(Deserialize)]
pub struct DeleteUserQuery {
    delete_user: Option<UserId>,
}

/// POST a username and password to this endpoint to login.
/// The response will redirect you to "/" if the login was successful.
/// You'll also get a (http-only) cookie with the encrypted session id.
/// Username/password is expected as a JSON object in the body.
pub async fn username_password_route(
    Query(query): Query<DeleteUserQuery>,
    pool: State<Pool>,
    config: State<EnvironmentConfig>,
    cookies: Cookies,
    dto: Json<UsernamePasswordDTO>,
) -> Response {
    match username_password(query.delete_user, pool, config, cookies, dto).await {
        Ok(_) => (StatusCode::OK).into_response(),
        Err(_) => (StatusCode::UNAUTHORIZED).into_response(),
    }
}

async fn username_password(
    delete_user: Option<UserId>,
    pool: State<Pool>,
    config: State<EnvironmentConfig>,
    mut cookies: Cookies,
    dto: Json<UsernamePasswordDTO>,
) -> Result<impl IntoResponse, anyhow::Error> {
    info!("Login attempt for user {}", dto.username);
    let mut connection = pool.conn().await.expect("No connection available");
    let Ok(user_id) = get_user_for_login(&dto, &mut connection).await else {
        if config.dev_mode {
            // It is important that this is only enabled in dev mode, otherwise
            // the production server would log hashes of slightly wrong passwords.
            info!(
                "Password could hash to {}",
                generate_password_hash(&dto.password)
            );
        }
        anyhow::bail!("Login failed");
    };

    let can_delete = if let Some(delete_user) = delete_user {
        if delete_user != user_id {
            warn!("User {} tried to delete user {}", user_id.0, delete_user.0);
            anyhow::bail!("Unauthorized");
        } else {
            info!(
                "User {} signing in to a session with delete rights",
                user_id.0
            );
            true
        }
    } else {
        false
    };

    Ok(create_session_and_attach_cookie(
        user_id,
        can_delete,
        &config,
        &mut cookies,
        &mut connection,
    )
        .await?)
}

async fn create_session_and_attach_cookie(
    user_id: UserId,
    can_delete: bool,
    config: &EnvironmentConfig,
    cookies: &mut Cookies,
    connection: &mut Connection,
) -> Result<(), ServerError> {
    let session = session::create_session(user_id, can_delete, connection).await?;
    let client_session = crypto::encrypt_string(&session.0, &config.secret_key)?;

    let session_cookie = Cookie::build((SESSION_COOKIE, client_session))
        .path("/")
        .http_only(true)
        .secure(!config.dev_mode)
        .same_site(SameSite::Lax) // So links from other sites work
        .max_age(time::Duration::days(14))
        .build();
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
    let user_id = UserId(res.user_id);

    let Some(hashed_password) = res.hashed_password else {
        anyhow::bail!("No password found for user {}", dto.username)
    };

    // Check if the password is correct
    let argon2 = Argon2::default();
    let parsed_hash = PasswordHash::new(&hashed_password)?;
    argon2.verify_password(dto.password.as_bytes(), &parsed_hash)?;

    // Update the last_login field
    update_last_login(user_id, connection).await?;

    Ok(user_id)
}

pub async fn update_last_login(
    user_id: UserId,
    connection: &mut Connection,
) -> Result<(), ServerError> {
    sqlx::query!(
        "update login set last_login = CURRENT_TIMESTAMP where user_id = ?",
        user_id.0
    )
        .execute(connection)
        .await?;
    Ok(())
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
        Cookie::build((SESSION_COOKIE, ""))
            .path("/")
            .same_site(SameSite::Strict)
            .build(),
    );

    format!("Logout for user {}", session.user_id.0)
}
