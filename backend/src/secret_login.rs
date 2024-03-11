//! Module for the "secret" login page where username/password login is allowed
//! for a few beta users.

use axum::{extract::State, response::IntoResponse};
use hyper::header;
use tower_cookies::Cookies;

use crate::{
    config::EnvironmentConfig,
    db::Pool,
    login::{self, session::SessionData, user::load_public_user_data},
    templates,
};

pub async fn secret_login(
    State(config): State<EnvironmentConfig>,
    cookies: Cookies,
    pool: State<Pool>,
    session: Option<SessionData>,
) -> impl IntoResponse {
    let tera = templates::get_tera(config.dev_mode);

    let mut connection = pool
        .conn()
        .await
        .expect("Could not get connection from pool");

    let mut context = tera::Context::new();

    context.insert("name", "-");
    context.insert("avatar", "-");

    if let Some(session) = session {
        if let Ok(user_data) = load_public_user_data(session.user_id, &mut connection).await {
            context.insert("name", &user_data.name);
            context.insert("avatar", &user_data.avatar);
        }
    }

    // Discord parameters & cookie
    let link = login::discord::generate_link(&config, false);
    context.insert("discord_url", &link.url);
    cookies.add(link.state_cookie());

    let body = tera
        .render("secret_login.html.tera", &context)
        .expect("Could not render secret_login.html");

    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], body)
}
