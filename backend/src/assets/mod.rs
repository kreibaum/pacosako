use rocket::{fs::NamedFile, State};
use rocket_cache_response::CacheResponse;

use crate::{language, DevEnvironmentConfig, ServerError};

/// This module collects the routes that serve static assets.
/// Not everything is in here right now, but it should generally move here.

// Code assets

#[allow(unused_variables)]
#[get("/cache/lib.min.js?<hash>")]
pub async fn lib_js(hash: String) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Private {
        responder: static_file("../target/lib.min.js").await?,
        max_age: 356 * 24 * 3600,
    })
}

#[allow(unused_variables)]
#[get("/cache/lib.wasm?<hash>")]
pub async fn lib_wasm(hash: String) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Private {
        responder: static_file("../target/lib.wasm").await?,
        max_age: 356 * 24 * 3600,
    })
}

/// If the server is running in development mode, we are returning the regular
/// elm.js file. In staging and production we are returning the minified
/// version of it. Here we also need to make sure that we pick the correct
/// language version.
pub fn elm_filename(lang: String, use_min_js: bool) -> &'static str {
    if use_min_js {
        language::get_static_language_file(&lang).unwrap_or("../target/elm.en.min.js")
    } else {
        "../target/elm.js"
    }
}

// If the server is running in development mode, we are returning the regular
// main.js file. In staging and production we are returning the minified
// version of it.
pub fn main_filename(use_min_js: bool) -> &'static str {
    if use_min_js {
        "../target/main.min.js"
    } else {
        "../target/main.js"
    }
}

/// A cache-able elm.min.js where cache busting happens via a url parameter.
/// The index.html is generated dynamically to point to the current hash and
/// this endpoint does not check the hash.
/// The language is also a parameter here so caching doesn't break the language
/// selection.
#[get("/cache/elm.min.js?<hash>&<lang>")]
pub async fn elm_cached(
    config: &State<DevEnvironmentConfig>,
    hash: String,
    lang: String,
) -> Result<CacheResponse<NamedFile>, ServerError> {
    info!("elm_cached: {} for language {}", hash, lang);
    Ok(CacheResponse::Private {
        responder: static_file(elm_filename(lang, config.use_min_js)).await?,
        max_age: 356 * 24 * 3600,
    })
}

/// If the server is running in development mode, we are returning the regular
/// main.js file. In staging and production we are returning the minified
/// version of it.
#[allow(unused_variables)]
#[get("/cache/main.min.js?<hash>")]
pub async fn main_js_cached(
    config: &State<DevEnvironmentConfig>,
    hash: &str,
) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Private {
        responder: static_file(main_filename(config.use_min_js)).await?,
        max_age: 356 * 24 * 3600,
    })
}

#[allow(unused_variables)]
#[get("/cache/lib_worker.min.js?<hash>")]
pub async fn lib_worker(hash: &str) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Private {
        responder: static_file("../target/lib_worker.min.js").await?,
        max_age: 356 * 24 * 3600,
    })
}

////////////////////////////////////////////////////////////////////////////////
// Static Files ////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

async fn static_file(path: &'static str) -> Result<NamedFile, ServerError> {
    Ok(NamedFile::open(path).await?)
}

#[get("/favicon.svg")]
pub async fn favicon() -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Private {
        responder: static_file("../target/favicon.svg").await,
        max_age: 24 * 3600,
    }
}

#[get("/pacosako-logo.png")]
pub async fn logo() -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Private {
        responder: static_file("../target/pacosako-logo.png").await,
        max_age: 24 * 3600,
    }
}

#[get("/bg.jpg")]
pub async fn bg() -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Private {
        responder: static_file("../target/bg.jpg").await,
        max_age: 24 * 3600,
    }
}

#[get("/static/place_piece.mp3")]
pub async fn place_piece() -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Private {
        responder: static_file("../target/place_piece.mp3").await,
        max_age: 24 * 3600,
    }
}
