//! This module uses serde to read the i18n json files as well as the i18n orchestration file.
//! It then generates the Elm output file using an embedded Tera template.
//! It replaces pytrans.py, removing the need for Python in the build process.
//! https://github.com/kreibaum/pytrans.py/
mod i18n_file_writer;

use clap::{Command, Parser};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::read_to_string;

static CONFIG_FILE: &str = "i18n_config.json";
static DEV_FILE: &str = ".i18n_dev_lang";

#[derive(Parser)]
#[command(about = r#"Processes json translation files into Elm files.

If you run this without arguments, it rebuilds using the dev language.
The dev language is stored in a file called .i18n_dev_lang.
Configuration happens in the i18n_config.json file."#)]
#[derive(Debug)]
struct Cli {
    #[arg(help = "Sets the dev language and rebuilds translation files. See 'i18n_gen list'.")]
    language: Option<String>,

    #[arg(
        long,
        help = "Shows a csv of available languages."
    )]
    list: bool,

    #[arg(
        long,
        help = "Shows currently configured dev language."
    )]
    show: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TranslationConfig {
    main_language: String,
    output: String,
    translated_to: Vec<Language>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Language {
    filename: String,
    name: String,
    locale: String,
}

#[derive(Debug, Deserialize)]
struct LanguageFile(HashMap<String, String>);

fn main() {
    // Read arguments
    let cli = Cli::parse();

    // Read the configuration file.
    let Ok(json_data) = read_to_string(CONFIG_FILE) else {
        eprintln!("Could not read configuration file: {}", CONFIG_FILE);
        std::process::exit(1);
    };
    let config: TranslationConfig = serde_json::from_str(&json_data).expect("Failed to parse JSON");

    // Read current dev language
    let current_dev_lang = read_to_string(DEV_FILE).unwrap_or(config.main_language.clone());

    if cli.list {
        show_list_of_available_languages(&config, current_dev_lang);
        std::process::exit(0);
    }

    if cli.show {
        println!("{current_dev_lang}");
    }

    i18n_file_writer::render_one_file(cli, &config, current_dev_lang);
}

fn show_list_of_available_languages(config: &TranslationConfig, current_dev_lang: String) {
    for lang in &config.translated_to {
        println!("{}\t{}\t{}", lang.name, lang.filename, lang.locale);
    }
}
