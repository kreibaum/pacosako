//! Discord Login
//!
//! This module is for the Discord OAuth2 login. It works with the following steps:
//! 1. Generates links for the client to redirect to Discord.
//! 2. Processes the "back from Discord" redirect. Which is:
//!   a. Receives the OAuth2 code from Discord,
//!   b. requests the access token and
//!   c. loads user information from /users/@me
//! 3. Processes new user onboarding.
//!   a. This also calls /users/@me
//!
//! Note that while Discord OAuth2 delivers a refresh token, we don't use it.
//! We only check with Discord once, to understand who logged in and then have
//! no further use for the token. The user gets a normal session token from us.
//! At that point, we don't even track anymore, how they logged in.
//! (Though if they have only a sigle auth method, it's not hard to guess...)

use crate::{
    config::EnvironmentConfig,
    db::{Connection, Pool},
    ServerError,
};
use axum::{
    extract::{Path, Query, State},
    response::{IntoResponse, Redirect},
};
use rand::{distributions::Alphanumeric, Rng};
use serde::{Deserialize, Serialize};
use tower_cookies::{cookie::SameSite, Cookie, Cookies};
use urlencoding::encode;

use super::{create_session_and_attach_cookie, crypto, update_last_login, user, UserId};

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

/// First level of redirection. This redirects to a link generated from
/// generate_link which makes it easier and more self contained to trigger
/// the OAuth2 login.
///
/// Lives at https://pacoplay.com/api/oauth/get_redirected
pub async fn get_redirected(
    cookies: Cookies,
    State(config): State<EnvironmentConfig>,
) -> impl IntoResponse {
    let link = generate_link(&config);
    cookies.add(link.state_cookie());
    Redirect::to(&link.url)
}

/// Example link that may be generate:
///
/// https://discord.com/api/oauth2/authorize
///     ?client_id=968955682504183858&redirect_uri=http%3A%2F%2Flocalhost%3A8000%2Fapi%2Foauth%2FbackFromDiscord
///     &response_type=code&scope=identify&state=9834kcv4cfv3
///
/// This will then redirect back to a link like
///
/// https://pacoplay.com/api/oauth/redirect
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
        user_display_name: user_info.display_name().to_owned(),
        user_discord_id: user_info.id,
    };

    let redirect_url = format!(
        "/me/create-account?encrypted_access_token={}&user_display_name={}&user_discord_id={}",
        make_base64_robust_against_elm(&creation_data.encrypted_access_token),
        creation_data.user_display_name,
        creation_data.user_discord_id,
    );

    Ok(Redirect::to(&redirect_url))
}

/// The encrypted access token is Base64 encoded. This means it will end with "=" in most cases.
/// Elm's query parser does not like this and will eat the equals sign. This breaks decryption.
/// To preserve the equals signs, we convert them to ";" which does not occur in Base64.
fn make_base64_robust_against_elm(input: &str) -> String {
    input.replace('=', ";")
}

/// Getting back to a regular Base64 encoded string, we replace ; by =
/// And we also have to replace space by +, that is axum's fault.
fn fix_back_to_base64(input: &str) -> String {
    input.replace(';', "=").replace(' ', "+")
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

impl UsersMeResponseBody {
    fn display_name(&self) -> &str {
        self.global_name.as_ref().unwrap_or(&self.username)
    }
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

#[derive(Deserialize)]
pub struct PleaseCreateAccountQuery {
    encrypted_access_token: String,
}

pub async fn please_create_account(
    Query(query): Query<PleaseCreateAccountQuery>,
    mut cookies: Cookies,
    State(config): State<EnvironmentConfig>,
    pool: State<Pool>,
) -> Result<impl IntoResponse, ServerError> {
    log::info!("Creating an account for a new user from Discord.");
    // Decrypt the access token
    let access_token = dbg!(crypto::decrypt_string(
        dbg!(&fix_back_to_base64(&query.encrypted_access_token)),
        &config.secret_key,
    ))?;

    // Use it another time to load user information
    let user_info = request_user_info(&access_token).await?;

    log::info!("Creating account for user {}", user_info.display_name());

    let mut conn = pool.conn().await?;

    // Create an account for the user
    let user_id = user::create_user(
        user_info.display_name(),
        &format!("identicon:{}", user_info.id),
        &mut conn,
    )
    .await?;

    // Associate the user with the discord login
    user::create_discord_login(user_id, user_info.id, &mut conn).await?;

    log::info!("Account created and linked to Discord.");

    // Set the session cookie
    create_session_and_attach_cookie(user_id, false, &config, &mut cookies, &mut conn).await?;

    // Return to /me with a redirect. On first login, the user likely want to
    // chose a profile picture and maybe set some other options once we put them
    // on the /me page as well.
    log::info!("User logged in, redirecting!");
    Ok(Redirect::to("/me").into_response())
}
