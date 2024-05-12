//! This module implements the opening book for the AI. The opening book is
//! pre-computed by the AI with a high search depth for all situations that
//! are commonly seen on pacoplay. The opening book is used to speed up the
//! AI's decision making and to provide a stronger opening game.

use pacosako::ai::glue::action_index_to_action_with_viewpoint;
use pacosako::{PacoAction, PlayerColor};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::OnceLock;

/// We store an instance of the opening book in memory after getting it once.
/// This is in some type  of cell

pub static OPENING_BOOK: OnceLock<OpeningBook> = OnceLock::new();

pub struct OpeningBook(HashMap<String, PositionData>);

pub struct PositionData {
    position_value: f32,
    suggested_moves: Vec<MoveData>,
}

pub struct MoveData {
    pub move_value: f32,
    pub actions: Vec<PacoAction>,
}

impl OpeningBook {
    /// Loads the opening book from a JSON string and stores it in memory.
    /// Future uses of the opening book won't need to provide the book.
    pub fn load_and_remember(json_string: &str) -> Result<(), serde_json::Error> {
        let opening_book = OpeningBook::parse(json_string)?;
        let _ = OPENING_BOOK.set(opening_book);
        Ok(())
    }

    fn parse(json_string: &str) -> Result<Self, serde_json::Error> {
        let raw: RawOpeningBook = serde_json::from_str(json_string)?;
        Ok(raw.into())
    }

    pub fn get(key: &str) -> Option<&PositionData> {
        let book = OPENING_BOOK.get()?;
        book.0.get(key)
    }
}

impl PositionData {
    pub fn best_move(&self) -> &MoveData {
        self.suggested_moves
            .iter()
            .max_by(|a, b| a.move_value.partial_cmp(&b.move_value).unwrap())
            .expect("No moves in position data")
    }
}

/// Actual layout of the JSON file:
#[derive(Deserialize)]
struct RawOpeningBook(HashMap<String, (f32, Vec<(f32, Vec<u8>)>)>);

impl MoveData {
    fn new((move_value, raw_actions): (f32, Vec<u8>), viewpoint_color: PlayerColor) -> Self {
        let actions: Option<Vec<PacoAction>> = raw_actions
            .iter()
            .map(|action| action_index_to_action_with_viewpoint(*action, viewpoint_color))
            .collect();
        let actions = actions.unwrap_or_else(|| panic!("Error parsing actions: {:?}", raw_actions));
        MoveData {
            move_value,
            actions,
        }
    }
}

impl PositionData {
    fn new(key: &str, (position_value, suggested_moves): (f32, Vec<(f32, Vec<u8>)>)) -> Self {
        // Find out if this is from the perspective of white or black. Look at the first space in the key.
        // "bla/bla/bla w bla" => White
        // "bla/bla/bla b bla" => Black
        let space_index = key
            .find(' ')
            .unwrap_or_else(|| panic!("Error parsing fen: {}", key));
        let viewpoint_color = match &key[space_index + 1..space_index + 2] {
            "w" => PlayerColor::White,
            "b" => PlayerColor::Black,
            _ => panic!("Error parsing fen: {}", key),
        };

        PositionData {
            position_value,
            suggested_moves: suggested_moves
                .into_iter()
                .map(|x| MoveData::new(x, viewpoint_color))
                .collect(),
        }
    }
}

impl From<RawOpeningBook> for OpeningBook {
    fn from(raw: RawOpeningBook) -> Self {
        OpeningBook(
            raw.0
                .into_iter()
                .map(|(key, value)| (key.clone(), PositionData::new(&key, value)))
                .collect(),
        )
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use pacosako::const_tile;

    #[test]
    fn test_parse() {
        let json = r#"{"r1bqkb1r/ppp1pppp/2n2n2/3p4/3P1B2/2N2N2/PPP1PPPP/R2QKB1R b 7 AHah - -":[-0.048420716,[[0.0030171957,[3,103]]]]}"#;

        let book = OpeningBook::parse(json).unwrap();

        assert_eq!(book.0.len(), 1);
        let position =
            &book.0["r1bqkb1r/ppp1pppp/2n2n2/3p4/3P1B2/2N2N2/PPP1PPPP/R2QKB1R b 7 AHah - -"];
        assert_eq!(position.position_value, -0.048420716);
        assert_eq!(position.suggested_moves[0].move_value, 0.0030171957);
        assert_eq!(
            position.suggested_moves[0].actions,
            vec![
                // Note that the actions are from the perspective of black in the book.
                PacoAction::Lift(const_tile::C8),
                PacoAction::Place(const_tile::G4)
            ]
        );
    }
}
