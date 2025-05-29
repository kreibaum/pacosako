//! Module for the `SetupOptions` struct.
//!
//! Together with some tests to ensure that the `SetupOptions` struct is
//! serializable and deserializable as expected.

use serde::{Deserialize, Serialize};

/// The options that can be set when setting up a game.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SetupOptions {
    pub safe_mode: bool,
    pub draw_after_n_repetitions: u8,
    /// For Fischer random we capture the initial position as a fen string.
    /// May be optional
    pub starting_fen: Option<String>,
}

impl Default for SetupOptions {
    fn default() -> Self {
        Self {
            safe_mode: true,
            // We default to 0 because we want to be able to deserialize legacy
            // versions from the database.
            draw_after_n_repetitions: 0,
            starting_fen: None,
        }
    }
}

/// Custom deserialization to be more robust against future additions to the
/// `SetupOptions` struct. This way we can deserialize old versions from the
/// database. Goes hand in hand with the `SetupOptionsAllOptional` struct.
impl<'de> Deserialize<'de> for SetupOptions {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let options: SetupOptionsAllOptional = SetupOptionsAllOptional::deserialize(deserializer)?;
        Ok(options.into())
    }
}

impl From<SetupOptionsAllOptional> for SetupOptions {
    fn from(options: SetupOptionsAllOptional) -> Self {
        let default = Self::default();
        SetupOptions {
            safe_mode: options.safe_mode.unwrap_or(default.safe_mode),
            draw_after_n_repetitions: options
                .draw_after_n_repetitions
                .unwrap_or(default.draw_after_n_repetitions),
            starting_fen: options.starting_fen.or(default.starting_fen),
        }
    }
}

/// A version with everything optional so we can deserialize it from legacy
/// versions still on the database.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct SetupOptionsAllOptional {
    safe_mode: Option<bool>,
    draw_after_n_repetitions: Option<u8>,
    starting_fen: Option<String>,
}

/// Test module to see if this works as expected on known strings.
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_object() {
        let json = "{}";
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        let options: SetupOptions = options.into();
        assert_eq!(options, SetupOptions::default());
    }

    #[test]
    fn without_safe_mode() {
        let json = r#"{"safe_mode": false}"#;
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        let options: SetupOptions = options.into();
        assert!(!options.safe_mode);
        assert_eq!(options.draw_after_n_repetitions, 0);
    }

    #[test]
    fn with_safe_mode() {
        let json = r#"{"safe_mode": true}"#;
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        let options: SetupOptions = options.into();
        assert!(options.safe_mode);
        assert_eq!(options.draw_after_n_repetitions, 0);
    }

    #[test]
    fn with_draw_after_n_repetitions() {
        let json = r#"{"draw_after_n_repetitions": 3}"#;
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        let options: SetupOptions = options.into();
        assert!(options.safe_mode);
        assert_eq!(options.draw_after_n_repetitions, 3);
    }

    #[test]
    fn with_all_options_2022() {
        let json = r#"{"safe_mode": false, "draw_after_n_repetitions": 3}"#;
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        let options: SetupOptions = options.into();
        assert!(!options.safe_mode);
        assert_eq!(options.draw_after_n_repetitions, 3);
    }

    #[test]
    fn with_fen() {
        let json =
            r#"{"starting_fen": "bqnnrbkr/pppppppp/8/8/8/8/PPPPPPPP/BQNNRBKR w 0 EHeh - -"}"#;
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        println!("{:?}", options);
        let options: SetupOptions = options.into();
        assert_eq!(
            options.starting_fen.unwrap(),
            "bqnnrbkr/pppppppp/8/8/8/8/PPPPPPPP/BQNNRBKR w 0 EHeh - -"
        );
    }
}
