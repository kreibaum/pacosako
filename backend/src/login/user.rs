//! Module to load user information from the database

extern crate regex;

use axum::{extract::{Path, State}, Json, response::{IntoResponse, Response}};
use hyper::{header, StatusCode};
use lazy_static::lazy_static;
use regex::Regex;
use serde::{Deserialize, Serialize};

use pacosako::PlayerColor;

use crate::db::{Connection, Pool};
use crate::ServerError;

use super::{session::SessionData, UserId};

/// This struct holds data about a user that everyone (even unauthenticated users) can see.
#[derive(Serialize, Clone, Debug)]
pub struct PublicUserData {
    pub name: String,
    pub user_id: UserId,
    pub avatar: String,
    pub ai: Option<AiMetaData>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AiMetaData {
    pub model_name: String,
    pub model_strength: usize,
    pub model_temperature: f32,
    pub is_frontend_ai: bool,
}

pub fn is_frontend_ai(user: &Option<PublicUserData>) -> bool {
    if let Some(user) = user {
        if let Some(ai) = &user.ai {
            return ai.is_frontend_ai;
        }
    }
    false
}

/// Allows a logged-in user to change their avatar by calling /api/me/avatar
pub async fn set_avatar(
    session: SessionData,
    State(pool): State<Pool>,
    avatar: String,
) -> Response {
    if parse_avatar(&avatar).is_none() {
        return (StatusCode::BAD_REQUEST, "Invalid avatar").into_response();
    }

    let mut connection = pool
        .0
        .acquire()
        .await
        .expect("Failed to acquire connection");

    // Write avatar to the database
    sqlx::query!(
        "update user set avatar = ? where id = ?",
        avatar,
        session.user_id.0
    )
        .execute(&mut connection)
        .await
        .unwrap();

    // Return an empty OK response
    (StatusCode::OK, "").into_response()
}

pub async fn load_public_user_data(
    user_id: UserId,
    connection: &mut Connection,
) -> Result<PublicUserData, sqlx::Error> {
    let res = sqlx::query!("select name, avatar from user where id = ?", user_id.0)
        .fetch_one(connection)
        .await?;

    Ok(PublicUserData {
        name: res.name.unwrap_or("Anonymous".to_string()),
        user_id,
        avatar: res.avatar,
        ai: None,
    })
}

pub async fn load_ai_config_for_game(
    game_key: &str,
    connection: &mut Connection,
) -> Result<(Option<AiMetaData>, Option<AiMetaData>), sqlx::Error> {
    let white = load_one_ai_config_for_game(game_key, "w", connection).await?;
    let black = load_one_ai_config_for_game(game_key, "b", connection).await?;

    Ok((white, black))
}

/// Loads the AI configuration for a single player in a specific game.
/// This is used to display the AI configuration in the game and replay pages.
/// It can also be used to inform the browser which AI to load when it is
/// running the AI itself.
async fn load_one_ai_config_for_game(
    game_key: &str,
    color: &str,
    connection: &mut sqlx::pool::PoolConnection<sqlx::Sqlite>,
) -> Result<Option<AiMetaData>, sqlx::Error> {
    let res = sqlx::query!(
        "select model_name, model_strength, model_temperature, is_frontend_ai from game_aiConfig where game_id = ? and player_color = ?",
        game_key,
        color
    )
        .fetch_optional(&mut *connection)
        .await?;

    if let Some(res) = res {
        Ok(Some(AiMetaData {
            model_name: res.model_name,
            model_strength: res.model_strength as usize,
            model_temperature: res.model_temperature,
            is_frontend_ai: res.is_frontend_ai == Some(1),
        }))
    } else {
        Ok(None)
    }
}

/// Writes the AI configuration for a single player in a specific game.
pub async fn write_one_ai_config_for_game(
    game_key: &str,
    color: PlayerColor,
    ai: &AiMetaData,
    connection: &mut Connection,
) -> Result<(), sqlx::Error> {
    let color_string = match color {
        PlayerColor::White => "w",
        PlayerColor::Black => "b",
    };
    let model_strength = ai.model_strength as i64; // does not live long enough otherwise
    let is_frontend_ai = ai.is_frontend_ai as i64;
    sqlx::query!(
        "insert or replace into game_aiConfig (game_id, player_color, model_name, model_strength, model_temperature, is_frontend_ai) values (?, ?, ?, ?, ?, ?)",
        game_key,
        color_string,
        ai.model_name,
        model_strength,
        ai.model_temperature,
        is_frontend_ai
    ).execute(&mut *connection).await?;
    Ok(())
}

pub async fn load_user_data_for_game(
    game_key: &str,
    connection: &mut Connection,
) -> Result<(Option<PublicUserData>, Option<PublicUserData>), sqlx::Error> {
    // SQLite is running in the same process. There is no need to reduce the
    // number of queries. So we first get the user ids and then load the user
    // data.
    let res = sqlx::query!(
        "select white_player, black_player from game where id = ?",
        game_key
    )
        .fetch_one(&mut *connection)
        .await?;

    let (white_ai, black_ai) = load_ai_config_for_game(game_key, &mut *connection).await?;

    let white_player = if let Some(white_player) = res.white_player {
        let mut public_user_data =
            load_public_user_data(UserId(white_player), &mut *connection).await?;
        public_user_data.ai = white_ai;
        Some(public_user_data)
    } else {
        None
    };

    let black_player = if let Some(black_player) = res.black_player {
        let mut public_user_data =
            load_public_user_data(UserId(black_player), &mut *connection).await?;
        public_user_data.ai = black_ai;
        Some(public_user_data)
    } else {
        None
    };

    Ok((white_player, black_player))
}

/// Proxies a call to /p/identicon:204bedcd9a44b3e1db26e7619bca694d to
/// https://seccdn.libravatar.org/avatar/204bedcd9a44b3e1db26e7619bca694d?s=200&forcedefault=y&default=identicon
pub async fn proxy_avatar_route(Path(avatar): Path<String>) -> Response {
    let Some(avatar) = parse_avatar(&avatar) else {
        return (StatusCode::NOT_FOUND).into_response();
    };

    let mut body: Vec<u8> = Vec::with_capacity(2000);

    avatargen::identicon(&avatar, &mut body);

    (
        [
            (header::CONTENT_TYPE, "image/png"),
            (header::CACHE_CONTROL, "public, max-age=60480"),
        ],
        body,
    )
        .into_response()
}

fn parse_avatar(avatar: &str) -> Option<String> {
    lazy_static! {
        static ref RE: Regex = Regex::new(r"identicon:([\w\d]+)").unwrap();
    }

    if let Some(captures) = RE.captures(avatar) {
        if let Some(matched) = captures.get(1) {
            return Some(matched.as_str().to_string());
        }
    }
    None
}

pub async fn create_user(
    name: &str,
    avatar: &str,
    conn: &mut Connection,
) -> Result<UserId, sqlx::Error> {
    let res = sqlx::query!(
        "insert into user (name, avatar) values (?, ?)",
        name,
        avatar
    )
        .execute(conn)
        .await?;

    Ok(UserId(res.last_insert_rowid() as i64))
}

pub async fn delete_user(session: SessionData, State(pool): State<Pool>) -> Response {
    if !session.can_delete {
        return (
            StatusCode::FORBIDDEN,
            r#"User needs to do a special login first and trigger actual deletion fast! See "Danger Zone" in /me."#,
        )
            .into_response();
    }

    let mut connection = pool
        .0
        .acquire()
        .await
        .expect("Failed to acquire connection");

    // update game set white_player = NULL where white_player = 3;
    // update game set black_player = NULL where black_player = 3;
    // delete from session where user_id = 3;
    // delete from login where user_id = 3;
    // delete from user where id = 3;

    sqlx::query!(
        "update game set white_player = NULL where white_player = ?",
        session.user_id.0
    )
        .execute(&mut *connection)
        .await
        .expect("Error removing user from games");

    sqlx::query!(
        "update game set black_player = NULL where black_player = ?",
        session.user_id.0
    )
        .execute(&mut *connection)
        .await
        .expect("Error removing user from games");

    sqlx::query!("delete from session where user_id = ?", session.user_id.0)
        .execute(&mut *connection)
        .await
        .expect("Error removing sessions for user.");

    sqlx::query!("delete from login where user_id = ?", session.user_id.0)
        .execute(&mut *connection)
        .await
        .expect("Error removing login for user.");

    sqlx::query!("delete from user where id = ?", session.user_id.0)
        .execute(&mut *connection)
        .await
        .expect("Error removing user.");

    (StatusCode::OK, "").into_response()
}

/// For a user that already exists, we create a new login entry.
/// This makes the login work for this user in the future.
pub async fn create_discord_login(
    user_id: UserId,
    identifier: String,
    connection: &mut Connection,
) -> Result<(), sqlx::Error> {
    sqlx::query!(
        "insert into login (user_id, type, identifier) values (?, 'discord',?)",
        user_id.0,
        identifier
    )
        .execute(connection)
        .await?;
    Ok(())
}

/// Allows anyone to get the public information of any user.
/// Even if you are not logged in right now.
pub async fn get_public_user_info(
    Path(user_id): Path<i64>,
    State(pool): State<Pool>,
) -> Result<Json<PublicUserData>, ServerError> {
    let mut connection = pool.conn().await?;

    let user_data = load_public_user_data(UserId(user_id), &mut connection).await?;
    Ok(Json(user_data))
}