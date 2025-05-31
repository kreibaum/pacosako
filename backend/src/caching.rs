use axum::{
    extract::Request,
    http::{header, HeaderValue},
    middleware::Next,
    response::IntoResponse,
};
use blake3::Hasher;
/// Functions related to caching and cache busting.
use cached::proc_macro::cached;
use std::{fs::File, io};

/// Generate the blake3 hash of the file at the given path.
/// Returns the hash as a string.
fn hash_file_no_cache(path: &str) -> String {
    let Ok(mut file) = File::open(path) else {
        panic!("Could not open static file at path: {path}")
    };
    let mut hasher = Hasher::new();
    let Ok(_) = io::copy(&mut file, &mut hasher) else {
        panic!("Could not hash static file at path: {path}")
    };
    hasher.finalize().to_hex().to_string()
}

/// Cached version that is only computed once.
/// The cache is only invalidated when the server is restarted.
/// This is the behavior we want for staging and production.
#[cached]
fn hash_file_with_cache(path: String) -> String {
    hash_file_no_cache(&path)
}

/// Get the hash of the file at the given path.
/// For local development, pass is use_cache = false.
pub fn hash_file(path: &str, use_cache: bool) -> String {
    if use_cache {
        hash_file_with_cache(path.to_owned())
    } else {
        hash_file_no_cache(path)
    }
}

/// This middleware adds a cache control header to all responses which were
/// requested for /a/* or /js/*.
/// The request must also contain a query parameter "hash" for the cache control
/// to be applied. It is then valid for one year and public.
pub async fn caching_middleware_fn(request: Request, next: Next) -> impl IntoResponse {
    let path = request.uri().path();
    let is_static_file = path.starts_with("/a/") || path.starts_with("/js/");
    let is_cache_busted = is_static_file
        && request
        .uri()
        .query()
        .is_some_and(|query| query.contains("hash"));

    let mut response = next.run(request).await;

    if is_static_file && is_cache_busted {
        response.headers_mut().insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static("public, max-age=31536000"),
        );
    }
    response
}
