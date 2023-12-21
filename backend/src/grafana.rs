//! Module for statistics that I want my grafana dashboard to display.
//!
//! The first real use case for this was to monitor the available disk space on
//! the server.
//!
//! The endpoint verifies basic authentication with username = "grafana" and
//! the password from the config file, setting "grafana_password".

use crate::config::EnvironmentConfig;
use axum::{extract::State, response::IntoResponse, response::Response, Json};
use axum_auth::AuthBasic;
use hyper::StatusCode;

#[derive(serde::Serialize)]
struct GrafanaData {
    total_disc_space: u64,
    free_disc_space: u64,
}

/// Uses basic authentication to verify that the request comes from Grafana.
/// Password is set in config.grafana_password.
pub async fn grafana_handler(
    AuthBasic((username, password)): AuthBasic,
    State(config): State<EnvironmentConfig>,
) -> Response {
    if username != "grafana" || password != Some(config.grafana_password) {
        return (StatusCode::UNAUTHORIZED, "Unauthorized").into_response();
    }

    // Create a new System object and refresh disk information
    let mut disks = sysinfo::Disks::new();
    disks.refresh_list();
    println!("Disks: {:#?}", disks);

    let (total, available) = disks.iter().fold((0, 0), |acc, disk| {
        (acc.0 + disk.total_space(), acc.1 + disk.available_space())
    });

    (
        StatusCode::OK,
        Json(GrafanaData {
            total_disc_space: total,
            free_disc_space: available,
        }),
    )
        .into_response()
}
