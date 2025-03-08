use serde::Serialize;
use std::collections::HashMap;
use tera::{Context, Tera};
use std::fs::read_to_string;
use crate::{Cli, Language, LanguageFile, TranslationConfig, DEV_FILE};

#[derive(Debug, Serialize)]
pub struct TeraInfo {
    pub total_keys: usize,
    pub translated_keys: usize,
    pub languages: Vec<String>,
    pub this_language: String,
    pub dictionary: HashMap<String, String>,
}

// Define the Elm translation template as a static string
static TEMPLATE: &str = r#"module Translations exposing (..)

{-| Generated translation file for {{ this_language }}
-}


{-| List of all supported languages. Default language is '{{ this_language }}'.
-}
type Language
    {%- for lang in languages %}
        {%- if loop.first %}
            = {{ lang }}
        {%- else %}
            | {{ lang }}
        {%- endif %}
    {%- endfor %}


{-| The language that is currently active.
-}
compiledLanguage : Language
compiledLanguage =
    {{ this_language }}


totalKeys : Int
totalKeys =
    {{ total_keys }}


translatedKeys : Int
translatedKeys =
    {{ translated_keys }}

{% for key, value in dictionary %}
{{ key }} : String
{{ key }} =
    "{{ value }}"

{% endfor %}
"#;

pub fn render_file( info : &TeraInfo ) -> String {
    let mut tera = Tera::default();
    tera.add_raw_template("elm_template", TEMPLATE)
        .expect("Failed to add template");

    let mut context = Context::new();
    context.insert("total_keys", &info.total_keys);
    context.insert("translated_keys", &info.translated_keys);
    context.insert("languages", &info.languages);
    context.insert("this_language", &info.this_language);
    context.insert("dictionary", &info.dictionary);

    tera.render("elm_template", &context).expect("Template rendering failed")

}

pub fn render_one_file(cli: Cli, config: &TranslationConfig, current_dev_lang: String) {
    // No list, no run, so build an Elm file.
    let target_lang = match cli.language.clone() {
        None => current_dev_lang,
        Some(language) => {
            // Write language to dev language file
            std::fs::write(DEV_FILE, language.clone()).expect("Could not write dev language file");
            language
        }
    };

    // Read language file and fallback file
    let target_lang = find_language(&config, &target_lang);
    let language_file = read_language_file(&target_lang);

    let fallback_lang = find_language(&config, &config.main_language);
    let fallback_file = read_language_file(&fallback_lang);

    let mut merged_file = LanguageFile(HashMap::new());

    // We want to merge the language file with the fallback file.
    // Only the keys defined in the fallback_file are relevant.
    // Values from the language file take precedence
    // We also want to track the total amount of keys and the amount of keys that are translated.
    let total_keys = fallback_file.0.len();
    let mut translated_keys = 0;
    for (key, value) in &fallback_file.0 {
        let new_value = match language_file.0.get(key) {
            Some(value) => {
                translated_keys += 1;
                value.clone()
            }
            None => value.clone(),
        };
        merged_file.0.insert(key.clone(), escape(&new_value));
    }

    // Write the Elm file.
    let info = TeraInfo {
        total_keys,
        translated_keys,
        languages: config
            .translated_to
            .iter()
            .map(|lang| lang.name.clone())
            .collect(),
        this_language: target_lang.name.clone(),
        dictionary: merged_file.0.clone(),
    };

    let elm_file = render_file(&info);
    std::fs::write(&config.output, elm_file).expect("Could not write Elm file");
}

fn escape( translation : &str ) -> String {
    // Replace \ with \\, " with \" and newline with \n.
    translation.clone()
        .replace(r"\", r"\\")
        .replace(r#"""#, r#"\""#)
        .replace("\n", r#"\n"#)
}

fn find_language(config: &TranslationConfig, target_lang: &str) -> Language {
    let Some(target_lang) = config
        .translated_to
        .iter()
        .filter(|&l| l.name == target_lang)
        .next()
    else {
        eprintln!("Could not find language: {}", target_lang);
        std::process::exit(1);
    };
    target_lang.clone()
}

fn read_language_file(target_lang: &Language) -> LanguageFile {
    let Ok(language_file) = read_to_string(&target_lang.filename) else {
        eprintln!("Could not read language file: {}", target_lang.filename);
        std::process::exit(1);
    };
    let language_file: LanguageFile =
        serde_json::from_str(&language_file).expect("Failed to parse JSON");
    language_file
}