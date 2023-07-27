use lazy_static::lazy_static;
use std::borrow::Cow;
use tera::Tera;

/// Initializes a new tera template engine instance.
fn init_tera() -> Tera {
    match Tera::new("templates/**/*") {
        Ok(t) => t,
        Err(e) => {
            println!("Parsing error(s): {}", e);
            ::std::process::exit(1);
        }
    }
}

/// Gets a tera template engine instance.
/// If we are in dev mode, we are creating a new instance every time. This makes
/// sure that we don't have to restart the server when we change a template.
/// In production we are using a global instance.
pub fn get_tera(dev_mode: bool) -> Cow<'static, Tera> {
    lazy_static! {
        pub static ref TEMPLATES: Tera = init_tera();
    }

    if dev_mode {
        Cow::Owned(init_tera())
    } else {
        Cow::Borrowed(&TEMPLATES)
    }
}
