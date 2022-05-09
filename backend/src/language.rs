use lazy_static::lazy_static;
use regex::Regex;
use rocket::http::hyper::header::ACCEPT_LANGUAGE;
use rocket::http::Cookie;
use rocket::http::CookieJar;
use rocket::{
    request::{self, FromRequest},
    Request,
};
// In this module we read the language settings the user is using and provide
// the correct compiled version from it.

const LANGUAGE_COOKIE_NAME: &str = "language";

/// Example endpoint where the user can see what language they currently get.
#[get("/language")]
pub async fn user_language<'r>(lang: AcceptLanguage, jar: &CookieJar<'_>) -> String {
    if let Some(language_cookie) = jar.get(LANGUAGE_COOKIE_NAME) {
        format!(
            "accept: {:?}; cookie: {:?}",
            lang.0,
            language_cookie.value()
        )
    } else {
        format!("accept: {:?}; no cookie", lang.0)
    }
}

#[post("/language", data = "<language>")]
pub async fn set_user_language<'r>(language: String, jar: &CookieJar<'_>) {
    jar.add(Cookie::new(LANGUAGE_COOKIE_NAME, language));
}

pub fn get_static_language_file(lang: &str) -> Option<&'static str> {
    match lang {
        "en" => Some("../target/elm.en.min.js"),
        "nl" => Some("../target/elm.nl.min.js"),
        "eo" => Some("../target/elm.eo.min.js"),
        _ => None,
    }
}

/// Request guard that combines the accept-language header & the language cookie.
pub struct UserLanguage(pub String);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for UserLanguage {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> request::Outcome<Self, Self::Error> {
        if let Some(language_cookie) = req.cookies().get(LANGUAGE_COOKIE_NAME) {
            let lang = language_cookie.value();
            if get_static_language_file(lang).is_some() {
                return request::Outcome::Success(UserLanguage(lang.to_string()));
            }
        }

        if let request::Outcome::Success(allowed) = AcceptLanguage::from_request(req).await {
            for lang in allowed.0 {
                if get_static_language_file(&lang).is_none() {
                    return request::Outcome::Success(UserLanguage(lang));
                }
            }
        }

        return request::Outcome::Success(UserLanguage("en".to_string()));
    }
}

/// Request guard that parses the accept-language header.
pub struct AcceptLanguage(Vec<String>);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for AcceptLanguage {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> request::Outcome<Self, Self::Error> {
        let accept_language: Option<&str> = req.headers().get_one(ACCEPT_LANGUAGE.as_str());

        if let Some(accept_language) = accept_language {
            request::Outcome::Success(AcceptLanguage(parse_languages(accept_language)))
        } else {
            request::Outcome::Success(AcceptLanguage(vec![]))
        }
    }
}

fn parse_languages(header: &str) -> Vec<String> {
    lazy_static! {
        static ref RE: Regex = Regex::new("([a-z\\*]+)(-[A-Z]+)?(;q=[0-9\\.]+)?").unwrap();
    }

    let mut languages = vec![];

    for lang in RE.captures_iter(header) {
        languages.push(lang[1].to_string());
    }
    languages
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn en_example() -> Result<(), anyhow::Error> {
        const EXAMPLE: &str = "en-US";
        assert_eq!(vec!["en".to_string()], parse_languages(EXAMPLE));
        Ok(())
    }

    #[test]
    fn mdn_example() -> Result<(), anyhow::Error> {
        const EXAMPLE: &str = "fr-CH, fr;q=0.9, en;q=0.8, de;q=0.7, *;q=0.5";

        assert_eq!(
            vec![
                "fr".to_string(),
                "fr".to_string(),
                "en".to_string(),
                "de".to_string(),
                "*".to_string()
            ],
            parse_languages(EXAMPLE)
        );

        Ok(())
    }
}
