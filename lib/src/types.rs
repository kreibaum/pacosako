use std::fmt;
use std::ops::Add;

use crate::substrate::BitBoard;
use serde::{Deserialize, Serialize};
use std::convert::TryFrom;
use std::fmt::Debug;
use std::fmt::Display;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum PieceType {
    Pawn = 0,
    Rook = 1,
    Knight = 2,
    Bishop = 3,
    Queen = 4,
    King = 5,
}

impl PieceType {
    pub fn to_char(self) -> &'static str {
        use PieceType::*;

        match self {
            Pawn => "P",
            Rook => "R",
            Knight => "N",
            Bishop => "B",
            Queen => "Q",
            King => "K",
        }
    }
    pub fn from_u8(value: u8) -> Self {
        use PieceType::*;

        match value {
            0 => Pawn,
            1 => Rook,
            2 => Knight,
            3 => Bishop,
            4 => Queen,
            5 => King,
            _ => panic!("Invalid piece type: {}", value),
        }
    }
    /// Support function for explicit binary serialization. See dense.rs.
    pub fn to_u8_optional(t: Option<PieceType>) -> u8 {
        match t {
            Some(t) => t as u8,
            None => 6,
        }
    }
    /// Support function for explicit binary deserialization. See dense.rs.
    pub fn from_u8_optional(value: u8) -> Option<Self> {
        use PieceType::*;

        match value {
            0 => Some(Pawn),
            1 => Some(Rook),
            2 => Some(Knight),
            3 => Some(Bishop),
            4 => Some(Queen),
            5 => Some(King),
            6 => None,
            _ => panic!("Invalid piece type: {}", value),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerColor {
    White = 0,
    Black = 1,
}

impl PlayerColor {
    pub const fn expect_u8(value: u8) -> PlayerColor {
        match value {
            0 => PlayerColor::White,
            1 => PlayerColor::Black,
            _ => panic!("Invalid player color"),
        }
    }

    pub fn forward_direction(self) -> i8 {
        match self {
            PlayerColor::White => 1,
            PlayerColor::Black => -1,
        }
    }

    pub const fn home_rank(self) -> BoardRank {
        match self {
            PlayerColor::White => BoardRank::Rank1,
            PlayerColor::Black => BoardRank::Rank8,
        }
    }

    #[deprecated(note = "Use home_rank() instead")]
    pub const fn home_row(self) -> u8 {
        self.home_rank() as u8
    }

    pub fn other(self) -> Self {
        use PlayerColor::*;
        match self {
            White => Black,
            Black => White,
        }
    }

    pub fn initial(self) -> char {
        match self {
            Self::White => 'W',
            Self::Black => 'B',
        }
    }

    pub fn is_white(self) -> bool {
        self == PlayerColor::White
    }

    pub(crate) fn all() -> impl Iterator<Item = Self> {
        [Self::White, Self::Black].iter().copied()
    }
}

#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum BoardRank {
    Rank1 = 0,
    Rank2 = 1,
    Rank3 = 2,
    Rank4 = 3,
    Rank5 = 4,
    Rank6 = 5,
    Rank7 = 6,
    Rank8 = 7,
}

#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum BoardFile {
    FileA = 0,
    FileB = 1,
    FileC = 2,
    FileD = 3,
    FileE = 4,
    FileF = 5,
    FileG = 6,
    FileH = 7,
}

impl BoardFile {
    pub const fn expect_u8(value: u8) -> BoardFile {
        match value {
            0 => BoardFile::FileA,
            1 => BoardFile::FileB,
            2 => BoardFile::FileC,
            3 => BoardFile::FileD,
            4 => BoardFile::FileE,
            5 => BoardFile::FileF,
            6 => BoardFile::FileG,
            7 => BoardFile::FileH,
            _ => panic!("Invalid file"),
        }
    }
}

// TODO: This should really be renamed "Tile" to match the frontend.
// That is also less ambiguous.
#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct BoardPosition(pub u8);

impl Add<(i8, i8)> for BoardPosition {
    type Output = Option<Self>;

    fn add(self, rhs: (i8, i8)) -> Self::Output {
        Self::new_checked(self.x() as i8 + rhs.0, self.y() as i8 + rhs.1)
    }
}

impl BoardPosition {
    pub const fn x(self) -> u8 {
        self.0 % 8
    }
    pub const fn y(self) -> u8 {
        self.0 / 8
    }
    pub const fn new(x: u8, y: u8) -> Self {
        Self(x + 8 * y)
    }
    pub fn new_checked(x: i8, y: i8) -> Option<Self> {
        if x >= 0 && y >= 0 && x < 8 && y < 8 {
            Some(Self::new(x as u8, y as u8))
        } else {
            None
        }
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
            Black => Self::new_checked(self.x() as i8, self.y() as i8 - 1),
        }
    }

    /// Returns the positions where a pawn could be after dancing diagonally.
    /// This depends on the color of the active `player_color`.
    /// May return an empty BitBoard if the pawn is already on the edge of the board.
    /// May return only one position if the pawn is on the edge of the board.
    pub fn dance_with_pawn(self, player_color: PlayerColor) -> BitBoard {
        let forward = player_color.forward_direction();

        [(-1, forward), (1, forward)]
            .iter()
            .filter_map(|d| self.add(*d))
            .collect()
    }

    /// Returns all possible positions on the board.
    pub fn all() -> impl Iterator<Item = Self> {
        (0..64).map(Self)
    }
}

/// The debug output for a position is a string like d4 that is easily human-readable.
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

/// The display output for a position is a string like d4 that is easily human-readable.
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
            // Unwrapping here is safe because I am checking the length first.
            let x = "abcdefgh".find(string.chars().next().unwrap());
            let y = "12345678".find(string.chars().nth(1).unwrap());
            if let (Some(x), Some(y)) = (x, y) {
                Self::new_checked(x as i8, y as i8).ok_or(ERROR_TEXT)
            } else {
                Err(ERROR_TEXT)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// This test verifies the TryFrom<&str> implementation for BoardPosition.
    #[test]
    fn string_to_board_position() {
        // Spot check a handful of positions, note the offset due to 0 based indexing.
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
    #[test]
    fn board_position_coordinate_round_trip() {
        for pos in BoardPosition::all() {
            let pos2 = BoardPosition::new_checked(pos.x() as i8, pos.y() as i8);
            assert_eq!(Some(pos), pos2);
        }
    }

    /// This test verifies that the TryFrom<&str> implementation for BoardPosition correctly
    /// decodes the debug output for a BoardPosition.
    #[test]
    fn board_position_string_round_trip() {
        for pos in BoardPosition::all() {
            let pos2 = BoardPosition::try_from(&*format!("{:?}", pos)).ok();
            assert_eq!(Some(pos), pos2);
        }
    }
}
