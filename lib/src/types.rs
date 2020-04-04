use std::fmt;

use std::convert::TryFrom;
use std::fmt::Debug;
use std::fmt::Display;
use serde::{Serialize, Deserialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PieceType {
    Pawn,
    Rock,
    Knight,
    Bishop,
    Queen,
    King,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerColor {
    White,
    Black,
}

#[derive(Copy, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct BoardPosition(pub u8);

impl BoardPosition {
    pub fn x(self) -> u8 {
        self.0 % 8
    }
    pub fn y(self) -> u8 {
        self.0 / 8
    }
    pub fn new(x: u8, y: u8) -> Self {
        Self(x + 8 * y)
    }
    pub fn new_checked(x: i8, y: i8) -> Option<Self> {
        if x >= 0 && y >= 0 && x < 8 && y < 8 {
            Some(Self::new(x as u8, y as u8))
        } else {
            None
        }
    }
    pub fn add(self, other: (i8, i8)) -> Option<Self> {
        Self::new_checked(self.x() as i8 + other.0, self.y() as i8 + other.1)
    }

    /// Indicates whether the given position in on the pawn row of the `player` parameter.
    pub fn in_pawn_row(self, player: PlayerColor) -> bool {
        use PlayerColor::*;
        match player {
            White => self.y() == 1,
            Black => self.y() == 6,
        }
    }

    /// If the position is on a players home row, return that player.
    pub fn home_row(self) -> Option<PlayerColor> {
        use PlayerColor::*;
        if self.y() == 0 {
            Some(White)
        } else if self.y() == 7 {
            Some(Black)
        } else {
            None
        }
    }

    /// Returns the position where a pawn would be after moving forward by one step.
    /// This depends on the color of the active `player`.
    /// Returns `None` if the pawn is already on the home row of the other player.
    pub fn advance_pawn(self, player: PlayerColor) -> Option<Self> {
        use PlayerColor::*;
        match player {
            White => Self::new_checked(self.x() as i8, self.y() as i8 + 1),
            Black => Self::new_checked(self.x() as i8, self.y() as i8 + 1),
        }
    }
}

/// The debug output for a position is a string like d4 that is easily human readable.
impl Debug for BoardPosition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}{}",
            ["a", "b", "c", "d", "e", "f", "g", "h"][self.x() as usize],
            self.y() + 1
        )
    }
}

/// The display output for a position is a string like d4 that is easily human readable.
/// The Display implementation just wraps the Debug implementation.
impl Display for BoardPosition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl TryFrom<&str> for BoardPosition {
    type Error = &'static str;

    fn try_from(string: &str) -> Result<Self, Self::Error> {
        // This is a closure to lazily
        const ERROR_TEXT: &str =
            "Error: I am looking for a board square coordinate like 'd5' or 'f2'.";

        if string.len() != 2 {
            Err(ERROR_TEXT)
        } else {
            let x = "abcdefgh".find(string.chars().nth(0).unwrap());
            let y = "12345678".find(string.chars().nth(1).unwrap());
            if x.is_none() || y.is_none() {
                Err(ERROR_TEXT)
            } else {
                Self::new_checked(x.unwrap() as i8, y.unwrap() as i8).ok_or(ERROR_TEXT)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use quickcheck::TestResult;

    /// This test verifies the TryFrom<&str> implementation for BoardPosition.
    #[test]
    fn string_to_board_position() {
        // Spot check a handfull of positions, note the offset due to 0 based indexing.
        assert_eq!(BoardPosition::try_from("g7"), Ok(BoardPosition::new(6, 6)));
        assert_eq!(BoardPosition::try_from("c4"), Ok(BoardPosition::new(2, 3)));
        assert_eq!(BoardPosition::try_from("a1"), Ok(BoardPosition::new(0, 0)));
        assert_eq!(BoardPosition::try_from("f2"), Ok(BoardPosition::new(5, 1)));
        assert_eq!(BoardPosition::try_from("h6"), Ok(BoardPosition::new(7, 5)));

        // Check a few error cases
        assert!(BoardPosition::try_from("").is_err());
        assert!(BoardPosition::try_from("a0").is_err());
        assert!(BoardPosition::try_from("j4").is_err());
        assert!(BoardPosition::try_from("c6a").is_err());
    }

    /// This test verifies that disassembling a BoardPosition into coordinates and back does
    /// not change the BoardPosition.
    #[quickcheck]
    fn board_position_coordinate_roundtrip(index: u8) -> TestResult {
        if index >= 8 * 8 {
            TestResult::discard()
        } else {
            let pos = BoardPosition(index);
            let pos2 = BoardPosition::new_checked(pos.x() as i8, pos.y() as i8);
            TestResult::from_bool(Some(pos) == pos2)
        }
    }

    /// This test verifies that the TryFrom<&str> implementation for BoardPosition correcty
    /// decodes the debug output for a BoardPosition.
    #[quickcheck]
    fn board_position_string_roundtrip(index: u8) -> TestResult {
        if index >= 8 * 8 {
            TestResult::discard()
        } else {
            let pos = BoardPosition(index);
            let pos2 = BoardPosition::try_from(&*format!("{:?}", pos)).ok();
            TestResult::from_bool(Some(pos) == pos2)
        }
    }
}
