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
}

impl Default for SetupOptions {
    fn default() -> Self {
        Self {
            safe_mode: true,
            // We default to 0 because we want to be able to deserialize legacy
            // versions from the database.
            draw_after_n_repetitions: 0,
        }
    }
}

impl From<SetupOptionsAllOptional> for SetupOptions {
    fn from(options: SetupOptionsAllOptional) -> Self {
        let mut result = Self::default();
        if let Some(safe_mode) = options.safe_mode {
            result.safe_mode = safe_mode;
        }
        if let Some(draw_after_n_repetitions) = options.draw_after_n_repetitions {
            result.draw_after_n_repetitions = draw_after_n_repetitions;
        }
        result
    }
}

/// A version with everything optional so we can deserialize it from legacy
/// versions still on the database.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct SetupOptionsAllOptional {
    safe_mode: Option<bool>,
    draw_after_n_repetitions: Option<u8>,
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
    fn with_all_options() {
        let json = r#"{"safe_mode": false, "draw_after_n_repetitions": 3}"#;
        let options: SetupOptionsAllOptional = serde_json::from_str(json).unwrap();
        let options: SetupOptions = options.into();
        assert!(!options.safe_mode);
        assert_eq!(options.draw_after_n_repetitions, 3);
    }
}
