//! Discord Login
//!
//! This module is for the Discord OAuth2 login. It works with the following steps:
//! 1. Generates links for the client to redirect to Discord.
//! 2. Receives the OAuth2 code from Discord and
//! 3. requests the access token.

use crate::db::Connection;
use crate::CustomConfig;
use anyhow::bail;
use rocket::{http::Cookie, http::CookieJar};
use serde::{Deserialize, Serialize};

struct DiscordLoginLink {
    url: String,
}

/// Example link that may be generate:
///
/// https://discord.com/api/oauth2/authorize
///     ?client_id=968955682504183858&redirect_uri=http%3A%2F%2Flocalhost%3A8000%2Fapi%2Foauth%2Fredirect
///     &response_type=code&scope=identify&state=9834kcv4cfv3
///
/// This will then redirect back to a link like
///
/// http://pacoplay.com/api/oauth/redirect
///     ?code=vVbfPzJUPuBaJTHaeSTknrBPLaxjxP
///     &state=9834kcv4cfv3
pub fn generate_link() -> DiscordLoginLink {
    "https://discord.com/api/oauth2/authorize?client_id=YOUR_CLIENT_ID&redirect_uri=YOUR_URL_ENCODED_REDIRECT_URI&response_type=code&scope=identify&state=YOUR_RANDOMLY_GENERATED_STATE"
}

pub async fn authorize_oauth_code(
    config: &CustomConfig,
    code: &str,
    state: &str,
    jar: &CookieJar<'_>,
    conn: &mut Connection,
) -> anyhow::Result<()> {
    check_oauth_state_cookie(state, jar)?;
    let resp = request_token(config, code).await?;
    let discord_auth_response = read_response(resp).await?;

    trace!("{:?}", discord_auth_response);

    let user_account_info = request_user_info(&discord_auth_response).await?;
    trace!("{:?}", user_account_info);

    let user = get_or_create_user_id_by_discord_id(user_account_info, conn).await?;

    // Generate a new random session id
    let session_id = uuid::Uuid::new_v4().to_string();
    add_session_id_to_user(&session_id, user.id, conn).await?;

    jar.add_private(Cookie::new("session_id", session_id));

    // TODO: Handle Discord Avatar

    Ok(())
}

#[derive(Serialize, Debug)]
pub struct UserData {
    pub id: i64,
    pub username: String,
}

/// Given a session id, returns the user data. This may return None if the
/// session id is invalid or the session expired.
pub async fn get_user_for_session_id(
    session_id: &str,
    conn: &mut Connection,
) -> anyhow::Result<Option<UserData>> {
    // select u.id, u.username
    // from user u
    // inner join user_session s on s.user_id = u.id
    // where s.session_id = '5560263d-75ad-4d95-9cab-2f4fc5c31f3f'
    let user = sqlx::query_as!(
        UserData,
        "SELECT u.id, u.username FROM user u INNER JOIN user_session s ON s.user_id = u.id WHERE s.session_id = ?1",
        session_id
    ).fetch_optional(conn).await?;

    Ok(user)
}

/// Database function to put a session id into a user
async fn add_session_id_to_user(
    session_id: &str,
    user_id: i64,
    conn: &mut Connection,
) -> anyhow::Result<()> {
    sqlx::query!(
        "INSERT INTO user_session (user_id, session_id, expires_at) VALUES (?1, ?2, 0)",
        user_id,
        session_id
    )
    .execute(conn)
    .await?;

    Ok(())
}

/// Database function to get a user by their discord id
/// If the user doesn't exist, create a new user.
async fn get_or_create_user_id_by_discord_id(
    user_account_info: UserInfoResponse,
    conn: &mut sqlx::pool::PoolConnection<sqlx::Sqlite>,
) -> Result<UserId, anyhow::Error> {
    let user = get_user_id_by_discord_id(&user_account_info.id, conn).await?;
    let user = if user.is_none() {
        let user_id = create_user(&user_account_info, conn).await?;
        info!("Created user with id: {:?}", user_id);
        user_id
    } else {
        user.unwrap()
    };
    Ok(user)
}

/// Type wrapper for technical PacoSako user ids. These are internal and not
/// shared with any login provider. We do expose them to the client though.
#[derive(Debug, Copy, Clone)]
struct UserId {
    id: i64,
}

async fn get_user_id_by_discord_id(
    discord_id: &str,
    conn: &mut Connection,
) -> anyhow::Result<Option<UserId>> {
    let user = sqlx::query_as!(
        UserId,
        "SELECT id FROM user WHERE discord_id = ?1",
        discord_id
    )
    .fetch_optional(conn)
    .await?;

    Ok(user)
}

async fn create_user(
    user_account_info: &UserInfoResponse,
    conn: &mut Connection,
) -> anyhow::Result<UserId> {
    let user_id = sqlx::query!(
        "INSERT INTO user (discord_id, username) VALUES (?1, ?2)",
        user_account_info.id,
        user_account_info.username
    )
    .execute(conn)
    .await?
    .last_insert_rowid();

    Ok(UserId { id: user_id })
}

#[derive(Deserialize, Debug)]
struct AuthResponse {
    access_token: String,
    expires_in: usize,
    refresh_token: String,
    scope: String,
    token_type: String,
}

#[derive(Deserialize, Debug)]
struct UserInfoResponse {
    pub id: String,
    pub username: String,
    pub avatar: String,
}

async fn request_user_info(auth_response: &AuthResponse) -> anyhow::Result<UserInfoResponse> {
    // Use reqwest to fetch the user info from Discord.
    // This is available on https://discord.com/api/oauth2/@me with Bearer token.
    let client = reqwest::Client::new();
    let resp = client
        .get("https://discord.com/api/users/@me")
        .bearer_auth(&auth_response.access_token)
        .send()
        .await?;

    let user_info_response: UserInfoResponse = serde_json::from_str(&dbg!(resp.text().await?))?;

    Ok(user_info_response)
}

async fn read_response(resp: reqwest::Response) -> anyhow::Result<AuthResponse> {
    let text = resp.text().await?;
    let auth_response: AuthResponse = serde_json::from_str(&text)?;
    if auth_response.scope != "identify" {
        bail!("Discord OAuth scope is not 'identify'");
    }
    if auth_response.token_type != "Bearer" {
        bail!("Discord OAuth token type is not 'Bearer'");
    }

    Ok(auth_response)
}

async fn request_token(config: &CustomConfig, code: &str) -> anyhow::Result<reqwest::Response> {
    // Post to the Discord API to get the access_token.
    let client = reqwest::Client::new();
    Ok(client
        .post("https://discordapp.com/api/oauth2/token")
        .form(&[
            ("client_id", config.discord_client_id.as_str()),
            ("client_secret", config.discord_client_secret.as_str()),
            ("grant_type", "authorization_code"),
            ("code", code),
            (
                "redirect_uri",
                format!("{}/api/oauth/redirect", config.application_url).as_str(),
            ),
        ])
        .send()
        .await?)
}

/// Access the state from the session cookie to compare it to the one that was send back.
/// This is important for the security of OAuth2.
fn check_oauth_state_cookie(state: &str, jar: &CookieJar<'_>) -> anyhow::Result<()> {
    let cookie_state = jar.get("oauth_state");
    if let Some(cookie_state) = cookie_state {
        if cookie_state.value() == state {
            Ok(())
        } else {
            bail!("State does not match");
        }
    } else {
        bail!("No state cookie found");
    }
}
