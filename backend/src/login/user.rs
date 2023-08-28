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
extern crate regex;
use super::UserId;

pub struct PublicUserData {
    pub name: String,
    pub avatar: String,
}

pub async fn load_public_user_data(
    user_id: UserId,
    connection: &mut Connection,
) -> Result<PublicUserData, anyhow::Error> {
    let res = sqlx::query!("select name, avatar from user where id = ?", user_id.0)
        .fetch_one(connection)
        .await?;

    Ok(PublicUserData {
        name: res.name.unwrap_or("Anonymous".to_string()),
        avatar: res.avatar,
    })
}

/// Proxies a call to /p/identicon:204bedcd9a44b3e1db26e7619bca694d to
/// https://seccdn.libravatar.org/avatar/204bedcd9a44b3e1db26e7619bca694d?s=200&forcedefault=y&default=identicon
pub async fn proxy_avatar_route(Path(avatar): Path<String>) -> Response {
    let Some(avatar) = parse_avatar(&avatar) else {
        return (StatusCode::NOT_FOUND).into_response();
    };

    // The target URL
    let url = format!(
        "https://seccdn.libravatar.org/avatar/{avatar}?s=200&forcedefault=y&default=identicon"
    );

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
