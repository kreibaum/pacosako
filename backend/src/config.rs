//! This module is in charge of defining the configuration format with types
//! and reading the configuration.

use serde::Deserialize;
use std::{env, fs};

#[derive(Clone, Deserialize)]
pub struct EnvironmentConfig {
    pub dev_mode: bool,
    pub database_path: String,
    pub websocket_port: u16,
    pub bind: String,
}

/// Determines from the first command line argument which config file to load.
/// Then it loads the config file, parses the toml into a EnvironmentConfig
/// struct and returns it.
/// If no argument is provided, it will load the default config file. This is
/// useful for development.
pub fn load_config() -> EnvironmentConfig {
    // Get the command line arguments
    let args: Vec<String> = env::args().collect();

    let config_filename = match args.len() {
        1 => "dev-server.toml".to_string(),
        2 => args[1].clone(),
        _ => {
            println!("Usage: {} [config_file]", args[0]);
            std::process::exit(1);
        }
    };

    // Read the config file
    let config_file = fs::read_to_string(&config_filename)
        .unwrap_or_else(|_| panic!("Could not read config file at path: {}", config_filename));

    // Parse the config file
    toml::from_str(&config_file)
        .unwrap_or_else(|_| panic!("Could not parse config file at path: {}", config_filename))
}
