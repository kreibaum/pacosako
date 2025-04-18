use axum::{
    http::{header::ACCEPT_LANGUAGE, HeaderMap},
    response::IntoResponse,
};
use lazy_static::lazy_static;
use regex::Regex;
use tower_cookies::{Cookie, Cookies};

/// Request guard that combines the accept-language header & the language cookie.
pub struct UserLanguage(pub String);

// // In this module we read the language settings the user is using and provide
// // the correct compiled version from it.

const LANGUAGE_COOKIE_NAME: &str = "language";

/// This first checks if there is a language defined in the cookies. If this is
/// not the case, it tries to guess a language from the accept-language header.
pub fn user_language(headers: &HeaderMap, cookies: &mut Cookies) -> UserLanguage {
    if let Some(cookie) = cookies.get(LANGUAGE_COOKIE_NAME) {
        let language = cookie.value().to_string();
        if is_language_supported(&language) {
            return UserLanguage(language);
        }
    }
    // No cookie or cookie points to a language that was removed.
    let language = parse_languages(headers).unwrap_or_else(|| "en".to_string());
    UserLanguage(language)
}

/// Sets the user's language cookie if the language is supported.
pub async fn set_user_language(cookies: Cookies, language: String) -> impl IntoResponse {
    if is_language_supported(&language) {
        cookies.add(
            Cookie::build((LANGUAGE_COOKIE_NAME, language))
                .path("/")
                .build(),
        );
    }
}

/// Parses the "Accept-Language" header and returns the first supported language.
/// If no supported language is found, returns None.
fn parse_languages(headers: &HeaderMap) -> Option<String> {
    // Extract the "Accept-Language" header value
    // Convert the HeaderValue to a string
    let header_str = headers.get(ACCEPT_LANGUAGE)?.to_str().ok()?;

    // Create a regular expression pattern to match language codes
    lazy_static! {
        static ref RE: Regex = Regex::new(r"(?i)([a-z]{2})(?:-[a-z]{2})?").unwrap();
    }

    // Iterate over language codes in the "Accept-Language" header
    for capture in RE.captures_iter(header_str) {
        // Get the "main" part of the language (e.g., "fr" from "fr-CH") as a lowercase string.
        let language = capture.get(1)?.as_str();

        // Check if the language is supported
        if is_language_supported(language) {
            // Return the first supported language
            return Some(language.to_string());
        }
    }

    // If no supported language is found, return None
    None
}

/// Checks if a language is supported by PacoPlay by checking if there is a
/// compiled version of the language.
fn is_language_supported(lang: &str) -> bool {
    get_static_language_file(lang).is_some()
}

/// Returns the path to the minified compiled elm file if the language is supported.
pub fn get_static_language_file(lang: &str) -> Option<&'static str> {
    match lang {
        "en" => Some("../web-target/js/elm.en.min.js"),
        "nl" => Some("../web-target/js/elm.nl.min.js"),
        "eo" => Some("../web-target/js/elm.eo.min.js"),
        "de" => Some("../web-target/js/elm.de.min.js"),
        "sv" => Some("../web-target/js/elm.sv.min.js"),
        "es" => Some("../web-target/js/elm.es.min.js"),
        _ => None,
    }
}
