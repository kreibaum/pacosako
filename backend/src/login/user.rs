//! Module to load user information from the database

use axum::{
    extract::{Path, State},
    response::{IntoResponse, Response},
};
use hyper::{header, Body, StatusCode};
use lazy_static::lazy_static;
use regex::Regex;
use serde::Serialize;
extern crate regex;
use super::{session::SessionData, UserId};
use crate::db::{Connection, Pool};

/// This struct holds data about a user that everyone (even unauthenticated users) can see.
#[derive(Serialize, Clone, Debug)]
pub struct PublicUserData {
    pub name: String,
    pub avatar: String,
}

/// Allows a logged in user to change their avatar by calling /api/me/avatar
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
        avatar: res.avatar,
    })
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

    let white_player = if let Some(white_player) = res.white_player {
        Some(load_public_user_data(UserId(white_player), &mut *connection).await?)
    } else {
        None
    };

    let black_player = if let Some(black_player) = res.black_player {
        Some(load_public_user_data(UserId(black_player), &mut *connection).await?)
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
