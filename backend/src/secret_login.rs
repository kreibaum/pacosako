use axum::{extract::State, response::IntoResponse};
use reqwest::header;

use crate::{
    config::EnvironmentConfig,
    db::Pool,
    login::{session::SessionData, user::load_public_user_data},
    templates,
};

/// Module for the "secret" login page where username/password login is allowed
/// for a few beta users.

pub async fn secret_login(
    config: State<EnvironmentConfig>,
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

    // No context to insert yet.

    let body = tera
        .render("secret_login.html.tera", &context)
        .expect("Could not render secret_login.html");

    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], body)
}
