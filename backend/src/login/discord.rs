//! Discord Login
//!
//! This module is for the Discord OAuth2 login. It works with the following steps:
//! 1. Generates links for the client to redirect to Discord.
//! 2. Receives the OAuth2 code from Discord and
//! 3. requests the access token.

use crate::{
    config::EnvironmentConfig,
    db::{Connection, Pool},
    templates, ServerError,
};
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Redirect},
};
use hyper::header;
use rand::{distributions::Alphanumeric, Rng};
use serde::{Deserialize, Serialize};
use tower_cookies::{cookie::SameSite, Cookie, Cookies};
use urlencoding::encode;

use super::{create_session_and_attach_cookie, crypto, update_last_login, UserId};

static OAUTH_STATE_COOKIE_NAME: &str = "oauth_state";

/// The user should be redirected to the url while the state is stored in a cookie.
/// The cookie name is "oauth_state" and only the server should be able to read it.
pub struct DiscordLoginLink {
    pub url: String,
    pub state: String,
    /// We copy this over to the secure (aka SSL only) attribute of the cookie.
    pub dev_mode: bool,
}

impl DiscordLoginLink {
    pub fn state_cookie(&self) -> tower_cookies::Cookie<'static> {
        Cookie::build((OAUTH_STATE_COOKIE_NAME, self.state.clone()))
            .path("/")
            .http_only(true)
            .secure(!self.dev_mode)
            .same_site(SameSite::Lax)
            .max_age(time::Duration::hours(1))
            .build()
    }
}

fn redirect_uri(server_url: &str) -> String {
    format!("{}/api/oauth/backFromDiscord", server_url)
}

/// Example link that may be generate:
///
/// https://discord.com/api/oauth2/authorize
///     ?client_id=968955682504183858&redirect_uri=http%3A%2F%2Flocalhost%3A8000%2Fapi%2Foauth%2FbackFromDiscord
///     &response_type=code&scope=identify&state=9834kcv4cfv3
///
/// This will then redirect back to a link like
///
/// http://pacoplay.com/api/oauth/redirect
///     ?code=vVbfPzJUPuBaJTHaeSTknrBPLaxjxP
///     &state=9834kcv4cfv3
pub fn generate_link(config: &EnvironmentConfig) -> DiscordLoginLink {
    let redirect_uri = redirect_uri(&config.server_url);

    let state: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(12)
        .map(char::from)
        .collect();

    let url = format!("https://discord.com/api/oauth2/authorize?client_id={}&redirect_uri={}&response_type=code&scope=identify&state={}", 
        config.discord_client_id, encode(&redirect_uri), state);

    DiscordLoginLink {
        url,
        state,
        dev_mode: config.dev_mode,
    }
}

#[derive(Deserialize)]
pub struct BackFromDiscordQuery {
    code: String,
    state: String,
}

/// Register /api/oauth/backFromDiscord in axum so we can accept the code and state
/// from Discord. This is the endpoint that Discord will redirect to.
///
/// Something like this:
///
/// http://pacoplay.com/api/oauth/backFromDiscord?code=FhjuhJ1QerSoJmN7ARqA1U97Ax54yK&state=ANDWZgOY5u1z
pub async fn back_from_discord(
    Query(BackFromDiscordQuery { code, state }): Query<BackFromDiscordQuery>,
    mut cookies: Cookies,
    State(config): State<EnvironmentConfig>,
    pool: State<Pool>,
) -> Result<impl IntoResponse, ServerError> {
    let Some(state_cookie) = cookies.get(OAUTH_STATE_COOKIE_NAME) else {
        log::warn!("OAuth2 State cookie not found");
        return Err(ServerError::OAuth2Error("No state cookie found"));
    };
    if state_cookie.value() != state {
        log::warn!(
            "OAuth2 State does not match the expected value. Expected: {}, got: {}",
            state_cookie.value(),
            state
        );
        return Err(ServerError::OAuth2Error(
            "OAuth2 State does not match the expected value",
        ));
    }

    // Exchange code for a token
    let token_request_body = TokenRequestBody::new(&config, &code);
    let token_response = request_token(&token_request_body).await?;

    // Load user information from /users/@me
    let user_info = request_user_info(&token_response.access_token).await?;

    // Check if the user is already in the database
    let mut conn = pool.conn().await?;
    let user_id = get_user_for_discord_user_id(&user_info.id, &mut conn).await?;

    let Some(user_id) = user_id else {
        return Ok(
            account_creation_confirmation_redirect(token_response, user_info, &config)
                .await?
                .into_response(),
        );
    };

    create_session_and_attach_cookie(user_id, false, &config, &mut cookies, &mut conn).await?;

    // Redirect to the main page
    Ok(Redirect::to("/").into_response())
}

async fn account_creation_confirmation_redirect(
    token_response: TokenResponseBody,
    user_info: UsersMeResponseBody,
    config: &EnvironmentConfig,
) -> Result<impl IntoResponse, ServerError> {
    let creation_data = AccountCreationDataClient {
        encrypted_access_token: crypto::encrypt_string(
            &token_response.access_token,
            &config.secret_key,
        )?,
        user_display_name: user_info.global_name.unwrap_or(user_info.username),
        user_discord_id: user_info.id,
    };

    let redirect_url = format!(
        "/me/createAccount?encrypted_access_token={}&user_display_name={}&user_discord_id={}",
        creation_data.encrypted_access_token,
        creation_data.user_display_name,
        creation_data.user_discord_id,
    );

    Ok(Redirect::to(&redirect_url))
}

/// Returns a "confirm that you actually want to create an account" page.
async fn account_creation_confirmation_page(
    token_response: TokenResponseBody,
    user_info: UsersMeResponseBody,
    config: &EnvironmentConfig,
) -> Result<impl IntoResponse, ServerError> {
    let creation_data = AccountCreationDataClient {
        encrypted_access_token: crypto::encrypt_string(
            &token_response.access_token,
            &config.secret_key,
        )?,
        user_display_name: user_info.global_name.unwrap_or(user_info.username),
        user_discord_id: user_info.id,
    };

    let tera = templates::get_tera(config.dev_mode);
    let mut context = tera::Context::new();

    context.insert(
        "encrypted_access_token",
        &creation_data.encrypted_access_token,
    );
    context.insert("user_display_name", &creation_data.user_display_name);
    context.insert("user_discord_id", &creation_data.user_discord_id);

    let body = tera
        .render("account_creation_confirmation.html.tera", &context)
        .expect("Could not render account_creation_confirmation.html");

    Ok(([(header::CONTENT_TYPE, "text/html; charset=utf-8")], body))
}

/// The access token is encrypted. This makes sure the client can hand it back
/// to us without us being able to read it. The client gets to see its own
/// display name and discord id. The discord id is used to generate the initial
/// profile picture.
/// We can't rely on the user not tampering with those, so we don't even expect
/// them back. We just get back the encrypted access token when the user
/// confirms account creation and then request the user info again.
#[derive(Serialize, Debug)]
struct AccountCreationDataClient {
    encrypted_access_token: String,
    user_display_name: String,
    user_discord_id: String,
}

#[derive(Serialize, Debug)]
struct TokenRequestBody {
    client_id: String,
    client_secret: String,
    grant_type: &'static str,
    code: String,
    redirect_uri: String,
}

impl TokenRequestBody {
    fn new(config: &EnvironmentConfig, code: &str) -> Self {
        Self {
            client_id: config.discord_client_id.clone(),
            client_secret: config.discord_client_secret.clone(),
            grant_type: "authorization_code",
            code: code.to_string(),
            redirect_uri: redirect_uri(&config.server_url),
        }
    }
}

#[allow(dead_code)] // Makes the TokenResponseBody show what is actually returned
#[derive(Deserialize, Debug)]
struct TokenResponseBody {
    access_token: String,
    expires_in: usize,
    refresh_token: String,
    scope: String,
    token_type: String,
}

async fn request_token(body: &TokenRequestBody) -> Result<TokenResponseBody, ServerError> {
    let client = reqwest::Client::new();
    let response = client
        .post("https://discord.com/api/oauth2/token")
        .form(body)
        .send()
        .await?;
    Ok(serde_json::from_str(&response.text().await?)?)
}

#[derive(Deserialize, Debug)]
struct UsersMeResponseBody {
    id: String,
    username: String,
    global_name: Option<String>,
}

async fn request_user_info(access_token: &str) -> Result<UsersMeResponseBody, ServerError> {
    let client = reqwest::Client::new();
    let response = client
        .get("https://discord.com/api/users/@me")
        .bearer_auth(access_token)
        .send()
        .await?;
    Ok(serde_json::from_str(&response.text().await?)?)
}

/// Given a discord_user_id, like "80351110224678912", we look them up on the
/// database and return the user_id, it if exists.
///
/// If the user does exist, this also updates the last_login field.
async fn get_user_for_discord_user_id(
    discord_user_id: &str,
    conn: &mut Connection,
) -> Result<Option<UserId>, ServerError> {
    // select user_id from login where type = "discord" and identifier = ?
    let res = sqlx::query!(
        "SELECT user_id FROM login WHERE type = 'discord' AND identifier = ?",
        discord_user_id
    )
    .fetch_optional(&mut *conn)
    .await?;

    let Some(res) = res else {
        return Ok(None);
    };

    let user_id = UserId(res.user_id);

    // Update the last_login field
    update_last_login(user_id, conn).await?;

    Ok(Some(user_id))
}
