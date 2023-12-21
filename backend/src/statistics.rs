use axum::{body::Body, extract::State, response::IntoResponse};
use hyper::header;

use crate::{actors::websocket::SocketId, config::EnvironmentConfig, templates};

/// Module to collect statistics about the server and to provide it as a route
/// for the frontend.

pub async fn statistics_handler(config: State<EnvironmentConfig>) -> impl IntoResponse {
    let tera = templates::get_tera(config.dev_mode);

    let mut context = tera::Context::new();
    context.insert("dev_mode", &config.dev_mode);
    context.insert("database_path", &config.database_path);
    context.insert("bind", &config.bind);
    context.insert("num_connected_clients", &SocketId::count_connections());

    let body = tera
        .render("statistics.html.tera", &context)
        .expect("Could not render statistics.html");

    (
        [(header::CONTENT_TYPE, "text/html; charset=utf-8")],
        Body::from(body),
    )
        .into_response()
}
