//! This module implements the server for the backend.
//! We are using Axum as the web framework.

use crate::{
    caching,
    db::Pool,
    game, grafana, language,
    login::{
        self,
        session::SessionData,
        user::{self, load_public_user_data},
    },
    replay_data, secret_login, templates, AppState, EnvironmentConfig,
};
use axum::{
    body::Body,
    extract::{Query, State},
    http::{header, HeaderMap},
    middleware,
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use serde::Deserialize;
use tera::Context;
use tokio::fs::File;
use tokio_util::io::ReaderStream;
use tower_cookies::{CookieManagerLayer, Cookies};
use tower_http::services::{ServeDir, ServeFile};

pub async fn run(state: AppState) {
    let api: Router<AppState> = game::add_to_router(Router::new())
        .route("/language", post(language::set_user_language))
        .route("/username_password", post(login::username_password_route))
        .route("/logout", get(login::logout_route))
        .route("/replay_meta_data/:game", get(replay_data::get_metadata))
        .route("/replay_meta_data/:game", post(replay_data::post_metadata))
        .route("/me/avatar", post(user::set_avatar))
        .route("/me/delete", get(user::delete_user))
        .route("/grafana", get(grafana::grafana_handler));

    // build our application with a single route
    let app: Router<AppState> = Router::new();
    let app: Router = app
        .route("/", get(index))
        .route("/js/elm.min.js", get(elm_js))
        .route("/statistics", get(crate::statistics::statistics_handler))
        .route("/secret_login", get(secret_login::secret_login))
        .route("/p/:avatar", get(user::proxy_avatar_route))
        .fallback(get(index))
        .route(
            "/websocket",
            get(crate::actors::websocket::websocket_handler),
        )
        .nest_service("/a", ServeDir::new("../target/assets/"))
        .nest_service("/js/lib.min.js", ServeFile::new("../target/js/lib.min.js"))
        .nest_service("/js/lib.wasm", ServeFile::new("../target/js/lib.wasm"))
        .nest_service(
            "/js/lib_worker.min.js",
            ServeFile::new("../target/js/lib_worker.min.js"),
        )
        .nest_service(
            "/js/main.min.js",
            ServeFile::new("../target/js/main.min.js"),
        )
        .nest("/api", api)
        .with_state(state.clone())
        .layer(middleware::from_fn(caching::caching_middleware_fn))
        .layer(CookieManagerLayer::new());

    let listener = tokio::net::TcpListener::bind(&state.config.bind)
        .await
        .unwrap();
    axum::serve(listener, app.into_make_service())
        .await
        .unwrap();
}

async fn index(
    headers: HeaderMap,
    mut cookies: Cookies,
    config: State<EnvironmentConfig>,
    pool: State<Pool>,
    session: Option<SessionData>,
) -> impl IntoResponse {
    let lang = language::user_language(&headers, &mut cookies);

    // Print what the hashes of elm.min.js and main.js are.
    // This is useful for debugging cache busting.
    let elm_filename = elm_filename(&lang.0, !config.dev_mode);
    debug!(
        "File {} has hash: {}",
        elm_filename,
        caching::hash_file(elm_filename, true)
    );
    debug!(
        "File {} has hash: {}",
        "../target/js/main.min.js",
        caching::hash_file("../target/js/main.min.js", true)
    );

    let mut context = Context::new();
    context.insert("lang", &lang.0);
    context.insert(
        "elm_hash",
        &caching::hash_file(elm_filename, !config.dev_mode),
    );
    context.insert(
        "main_hash",
        &caching::hash_file("../target/js/main.min.js", !config.dev_mode),
    );
    context.insert(
        "lib_worker_hash",
        &caching::hash_file("../target/js/lib_worker.min.js", !config.dev_mode),
    );
    context.insert(
        "wasm_js_hash",
        &caching::hash_file("../target/js/lib.min.js", !config.dev_mode),
    );
    context.insert(
        "wasm_hash",
        &caching::hash_file("../target/js/lib.wasm", !config.dev_mode),
    );
    context.insert(
        "favicon_hash",
        &caching::hash_file("../target/assets/favicon.svg", !config.dev_mode),
    );

    // Check data for currently logged in user.
    let mut connection = pool
        .conn()
        .await
        .expect("Could not get connection from pool");

    context.insert("name", "");
    context.insert("user_id", "-1");
    context.insert("avatar", "");

    if let Some(session) = session {
        if let Ok(user_data) = load_public_user_data(session.user_id, &mut connection).await {
            context.insert("name", &user_data.name);
            context.insert("user_id", &user_data.user_id);
            context.insert("avatar", &user_data.avatar);
        }
    }

    let body = templates::get_tera(config.dev_mode)
        .render("index.html.tera", &context)
        .expect("Could not render index.html");

    ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], body)
}

#[derive(Deserialize)]
struct LangQuery {
    lang: String,
}

/// A cache-able elm.min.js where cache busting happens via a url parameter.
/// The index.html is generated dynamically to point to the current hash and
/// this endpoint does not check the hash.
/// The language is also a parameter here so caching doesn't break the language
/// selection.
async fn elm_js(config: State<EnvironmentConfig>, query: Query<LangQuery>) -> impl IntoResponse {
    let filename = elm_filename(&query.lang, !config.dev_mode);
    info!(
        "Serving elm.js from {} with language {}",
        filename, query.lang
    );

    let file = File::open(filename)
        .await
        .unwrap_or_else(|_| panic!("Could not open static file at path: {filename}"));

    let body = Body::from_stream(ReaderStream::new(file));

    let headers = [
        (header::CONTENT_TYPE, "application/javascript"),
        (header::CACHE_CONTROL, "public, max-age=31536000"),
    ];

    (headers, body)
}

/// If the server is running in development mode, we are returning the regular
/// elm.js file. In staging and production we are returning the minified
/// version of it. Here we also need to make sure that we pick the correct
/// language version.
/// This is required for hot reloading to work. For typescript we don't have
/// hot reloading so we always use the minified version. Run
/// ./scripts/compile-ts.sh to (re-)build.
pub fn elm_filename(lang: &str, use_min_js: bool) -> &'static str {
    if use_min_js {
        language::get_static_language_file(lang).unwrap_or("../target/js/elm.en.min.js")
    } else {
        "../target/elm.js"
    }
}
