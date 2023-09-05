//! This module is in charge of defining the configuration format with types
//! and reading the configuration.

use serde::Deserialize;
use std::{env, fs};

#[derive(Clone, Deserialize)]
pub struct EnvironmentConfig {
    pub dev_mode: bool,
    pub database_path: String,
    pub bind: String,
    pub secret_key: String,
}

/// Determines from the first command line argument which config file to load.
/// Then it loads the config file, parses the toml into a EnvironmentConfig
/// struct and returns it.
/// If no argument is provided, it will load the default config file. This is
/// useful for development.
pub fn load_config() -> EnvironmentConfig {
    match load_config_inner() {
        Ok(config) => config,
        Err(err) => {
            // With the immediate exit, we can't use error!() here.
            println!("Error loading config: {err}");
            std::process::exit(1);
        }
    }
}

/// Inner method to unify error handling
fn load_config_inner() -> Result<EnvironmentConfig, String> {
    // Get the command line arguments
    let args: Vec<String> = env::args().collect();

    let config_filename = match args.len() {
        1 => "dev-config.toml".to_string(),
        2 => args[1].clone(),
        _ => {
            return Err(format!("Usage: {} [config_file]", args[0]));
        }
    };

    // Read the config file
    let config_file = fs::read_to_string(&config_filename)
        .map_err(|_| format!("Could not read config file at path: {config_filename}"))?;

    info!("Loaded config file: {}", config_filename);

    // Parse the config file
    toml::from_str(&config_file).map_err(|e| {
        format!(
            "Could not parse config file at path: {}\nCaused by: {:?}",
            config_filename, e
        )
    })
}
