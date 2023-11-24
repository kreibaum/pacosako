//! Module to load user information from the database

use crate::db::Connection;
use axum::{
    extract::Path,
    response::{IntoResponse, Response},
};
use hyper::{header, HeaderMap, StatusCode};
use lazy_static::lazy_static;
use regex::Regex;
use reqwest;
use serde::Serialize;
extern crate regex;
use super::UserId;

/// This struct holds data about a user that everyone (even unauthenticated users) can see.
#[derive(Serialize, Clone, Debug)]
pub struct PublicUserData {
    pub name: String,
    pub avatar: String,
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

    // The target URL
    let url =
        format!("https://seccdn.libravatar.org/avatar/{avatar}?s=200&forcedefault=y&default=retro");

    let client = reqwest::Client::new();
    let resp = client.get(url).send().await.unwrap();

    let content_type = easy_header_value(resp.headers(), "content-type");

    let body = resp.bytes().await.unwrap();

    (
        [
            (header::CONTENT_TYPE, content_type),
            (header::CACHE_CONTROL, "public, max-age=60480".to_owned()),
        ],
        body,
    )
        .into_response()
}

fn easy_header_value(headers: &HeaderMap, header: &str) -> String {
    match headers.get(header) {
        Some(value) => value.to_str().unwrap_or("").to_owned(),
        None => "".to_owned(),
    }
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
