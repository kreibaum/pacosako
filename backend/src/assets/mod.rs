use rocket::{fs::NamedFile, State};
use rocket_cache_response::CacheResponse;

use crate::{language, DevEnvironmentConfig, ServerError};

/// This module collects the routes that serve static assets.
/// Not everything is in here right now, but it should generally move here.

// Code assets

#[allow(unused_variables)]
#[get("/js/lib.min.js?<hash>")]
pub async fn lib_js(hash: String) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Public {
        responder: static_file("../target/js/lib.min.js").await?,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    })
}

#[allow(unused_variables)]
#[get("/js/lib.wasm?<hash>")]
pub async fn lib_wasm(hash: String) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Public {
        responder: static_file("../target/js/lib.wasm").await?,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    })
}

/// If the server is running in development mode, we are returning the regular
/// elm.js file. In staging and production we are returning the minified
/// version of it. Here we also need to make sure that we pick the correct
/// language version.
/// This is required for hot reloading to work. For typescript we don't have
/// hot reloading so we always use the minified version. Run
/// ./scripts/compile-ts.sh to (re-)build.
pub fn elm_filename(lang: String, use_min_js: bool) -> &'static str {
    if use_min_js {
        language::get_static_language_file(&lang).unwrap_or("../target/js/elm.en.min.js")
    } else {
        "../target/elm.js"
    }
}

/// A cache-able elm.min.js where cache busting happens via a url parameter.
/// The index.html is generated dynamically to point to the current hash and
/// this endpoint does not check the hash.
/// The language is also a parameter here so caching doesn't break the language
/// selection.
#[get("/js/elm.min.js?<hash>&<lang>")]
pub async fn elm_cached(
    config: &State<DevEnvironmentConfig>,
    hash: String,
    lang: String,
) -> Result<CacheResponse<NamedFile>, ServerError> {
    info!("elm_cached: {} for language {}", hash, lang);
    Ok(CacheResponse::Public {
        responder: static_file(elm_filename(lang, config.use_min_js)).await?,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    })
}

/// If the server is running in development mode, we are returning the regular
/// main.js file. In staging and production we are returning the minified
/// version of it.
#[allow(unused_variables)]
#[get("/js/main.min.js?<hash>")]
pub async fn main_js_cached(
    config: &State<DevEnvironmentConfig>,
    hash: &str,
) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Public {
        responder: static_file("../target/js/main.min.js").await?,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    })
}

#[allow(unused_variables)]
#[get("/js/lib_worker.min.js?<hash>")]
pub async fn lib_worker(hash: &str) -> Result<CacheResponse<NamedFile>, ServerError> {
    Ok(CacheResponse::Public {
        responder: static_file("../target/js/lib_worker.min.js").await?,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    })
}

////////////////////////////////////////////////////////////////////////////////
// Static Files ////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

async fn static_file(path: &'static str) -> Result<NamedFile, ServerError> {
    Ok(NamedFile::open(path).await?)
}

#[allow(unused_variables)]
#[get("/a/favicon.svg?<hash>")]
pub async fn favicon(hash: &str) -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Public {
        responder: static_file("../target/assets/favicon.svg").await,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    }
}

#[allow(unused_variables)]
#[get("/a/pacosakoLogo.png?<hash>")]
pub async fn logo(hash: &str) -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Public {
        responder: static_file("../target/assets/pacosakoLogo.png").await,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    }
}

#[allow(unused_variables)]
#[get("/a/bg.jpg?<hash>")]
pub async fn bg(hash: &str) -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Public {
        responder: static_file("../target/assets/bg.jpg").await,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    }
}

#[allow(unused_variables)]
#[get("/a/placePiece.mp3?<hash>")]
pub async fn place_piece(hash: &str) -> CacheResponse<Result<NamedFile, ServerError>> {
    CacheResponse::Public {
        responder: static_file("../target/assets/placePiece.mp3").await,
        max_age: 356 * 24 * 3600,
        must_revalidate: false,
    }
}
