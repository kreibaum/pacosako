//! Module for implementations of a board with only the board + resting pieces
//! avoiding as much other logic as possible. We can't call this board,
//! because we were already using that for the board with all the logic.

use std::ops::{BitAnd, BitOr, Not};

use crate::{parser::Square, BoardPosition, PacoError, PieceType, PlayerColor};
pub mod constant_bitboards;
pub mod dense;
pub mod zobrist;

pub trait Substrate {
    /// Returns the piece at the given position, if any.
    fn get_piece(&self, player: PlayerColor, pos: BoardPosition) -> Option<PieceType>;
    /// Returns whether the given position is occupied for the given player.
    fn has_piece(&self, player: PlayerColor, pos: BoardPosition) -> bool {
        self.get_piece(player, pos).is_some()
    }
    /// Returns whether the given position is empty for both players.
    fn is_empty(&self, pos: BoardPosition) -> bool {
        !self.has_piece(PlayerColor::White, pos) && !self.has_piece(PlayerColor::Black, pos)
    }
    /// Checks for a specific piece type
    fn is_piece(&self, player: PlayerColor, pos: BoardPosition, piece: PieceType) -> bool {
        self.get_piece(player, pos) == Some(piece)
    }
    /// Sets the piece at the given position.
    fn set_piece(&mut self, player: PlayerColor, pos: BoardPosition, piece: PieceType);
    /// Sets the square (Both players pieces) at the given position.
    fn set_square(&mut self, pos: BoardPosition, square: Square) {
        if let Some(white) = square.white {
            self.set_piece(PlayerColor::White, pos, white);
        }
        if let Some(black) = square.black {
            self.set_piece(PlayerColor::Black, pos, black);
        }
    }
    // Gets the square (Both players pieces) at the given position.
    fn get_square(&self, pos: BoardPosition) -> Square {
        Square {
            white: self.get_piece(PlayerColor::White, pos),
            black: self.get_piece(PlayerColor::Black, pos),
        }
    }
    /// Removes the piece at the given position.
    fn remove_piece(&mut self, player: PlayerColor, pos: BoardPosition) -> Option<PieceType>;
    /// Swaps the pieces at the given positions.
    fn swap(&mut self, pos1: BoardPosition, pos2: BoardPosition);
    /// Returns a bitboard with all pieces of the given player.
    /// We are already going via Bitboard here, as a substitute for an iterator.
    fn bitboard_color(&self, player: PlayerColor) -> BitBoard;
    /// Returns the position of the king of the given player.
    fn find_king(&self, player: PlayerColor) -> Result<BoardPosition, PacoError>;
}

// Using a u64 as a [bool; 64]. This is known as a bitboard.
// This is a very common technique in chess programming.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Default)]
pub struct BitBoard(pub u64);

pub struct BitBoardIter {
    bits: u64,
    current: u8,
}

impl BitBoard {
    pub fn iter(self) -> BitBoardIter {
        BitBoardIter {
            bits: self.0,
            current: 0,
        }
    }
    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
    pub fn contains(self, pos: BoardPosition) -> bool {
        (self.0 & (1u64 << pos.0)) != 0
    }
    pub fn insert(&mut self, pos: BoardPosition) -> bool {
        self.insert_all(BitBoard(1u64 << pos.0))
    }
    pub fn insert_all(&mut self, other: BitBoard) -> bool {
        let old = self.0;
        self.0 |= other.0;
        old != self.0
    }
    pub fn remove(&mut self, pos: BoardPosition) {
        self.0 &= !(1u64 << pos.0);
    }
    pub fn len(self) -> u8 {
        self.0.count_ones() as u8
    }
}

impl Iterator for BitBoardIter {
    type Item = BoardPosition;

    fn next(&mut self) -> Option<Self::Item> {
        while self.current < 64 {
            if (self.bits & (1u64 << self.current)) != 0 {
                let result = self.current;
                self.current += 1;
                return Some(BoardPosition(result));
            }
            self.current += 1;
        }
        None
    }
}

impl IntoIterator for BitBoard {
    type Item = BoardPosition;
    type IntoIter = BitBoardIter;

    fn into_iter(self) -> Self::IntoIter {
        BitBoardIter {
            bits: self.0,
            current: 0,
        }
    }
}

impl FromIterator<BoardPosition> for BitBoard {
    fn from_iter<T: IntoIterator<Item = BoardPosition>>(iter: T) -> Self {
        let mut result = BitBoard(0);
        for pos in iter {
            result.insert(pos);
        }
        result
    }
}

impl From<BoardPosition> for BitBoard {
    fn from(pos: BoardPosition) -> Self {
        BitBoard(1u64 << pos.0)
    }
}

impl From<Option<BoardPosition>> for BitBoard {
    fn from(pos: Option<BoardPosition>) -> Self {
        match pos {
            Some(pos) => BitBoard(1u64 << pos.0),
            None => BitBoard(0),
        }
    }
}

impl BitAnd for BitBoard {
    type Output = Self;

    fn bitand(self, rhs: Self) -> Self::Output {
        BitBoard(self.0 & rhs.0)
    }
}

impl BitOr for BitBoard {
    type Output = Self;

    fn bitor(self, rhs: Self) -> Self::Output {
        BitBoard(self.0 | rhs.0)
    }
}

impl Not for BitBoard {
    type Output = Self;

    fn not(self) -> Self::Output {
        BitBoard(!self.0)
    }
}
