//! Module for implementations of a board with only the board + resting pieces
//! avoiding as much other logic as possible. We can't call this "board",
//! because we were already using that for the board with all the logic.

use std::ops::{BitAnd, BitOr, Not};

use crate::{BoardPosition, PacoError, parser::Square, PieceType, PlayerColor};

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
    /// Determines whether the given player would be allowed to chain-dance to the given position.
    /// This is always possible for empty squares (end chain) and when there is an opponent piece.
    fn is_danceable(&self, player: PlayerColor, pos: BoardPosition) -> bool {
        self.is_empty(pos) || self.has_piece(player.other(), pos)
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

    /// Finds all pieces of the given color and type and returns them as a bitboard.
    fn find_pieces(&self, player_color: PlayerColor, piece_type: PieceType) -> BitBoard;
}

// Using a u64 as a [bool; 64]. This is known as a bitboard.
// This is a very common technique in chess programming.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Default)]
pub struct BitBoard(pub u64);

impl BitBoard {
    pub fn iter(self) -> BitBoardIter {
        BitBoardIter { bits: self.0 }
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

// Index into BitBoard with a BoardPosition, returning a bool.
impl std::ops::Index<BoardPosition> for BitBoard {
    type Output = bool;

    fn index(&self, index: BoardPosition) -> &Self::Output {
        if self.contains(index) {
            // Looks stupid, but lifetimes seem to force me to do this.
            &true
        } else {
            &false
        }
    }
}

pub struct BitBoardIter {
    bits: u64,
}

impl Iterator for BitBoardIter {
    type Item = BoardPosition;

    fn next(&mut self) -> Option<Self::Item> {
        if self.bits == 0 {
            None
        } else {
            // Get the index of the least significant set bit.
            let trailing_zeros = self.bits.trailing_zeros() as u8;
            // Clear the bit so that it's not considered in the next call.
            self.bits &= !(1 << trailing_zeros);
            Some(BoardPosition(trailing_zeros))
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        let len = self.bits.count_ones() as usize;
        (len, Some(len))
    }
}

impl DoubleEndedIterator for BitBoardIter {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.bits == 0 {
            None
        } else {
            // Get the index of the most significant set bit.
            let leading_zeros = self.bits.leading_zeros() as u8;
            let index = 63 - leading_zeros;
            // Clear the bit so that it's not considered in the next call.
            self.bits &= !(1 << index);
            Some(BoardPosition(index))
        }
    }
}

impl IntoIterator for BitBoard {
    type Item = BoardPosition;
    type IntoIter = BitBoardIter;

    fn into_iter(self) -> Self::IntoIter {
        BitBoardIter { bits: self.0 }
    }
}

impl FromIterator<BoardPosition> for BitBoard {
    fn from_iter<T: IntoIterator<Item=BoardPosition>>(iter: T) -> Self {
        let mut result = BitBoard(0);
        for pos in iter {
            result.insert(pos);
        }
        result
    }
}

impl<'a> FromIterator<&'a BoardPosition> for BitBoard {
    fn from_iter<T: IntoIterator<Item=&'a BoardPosition>>(iter: T) -> Self {
        let mut result = BitBoard(0);
        for pos in iter {
            result.insert(*pos);
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

#[cfg(test)]
mod tests {
    use crate::const_tile::*;

    use super::*;

    #[test]
    fn test_forward_iteration() {
        let bitboard = BitBoard(0b1010);
        let mut iter = bitboard.iter();
        assert_eq!(iter.next(), Some(B1));
        assert_eq!(iter.next(), Some(D1));
        assert_eq!(iter.next(), None);
    }

    #[test]
    fn test_backward_iteration() {
        let bitboard = BitBoard(0b1010);
        let mut iter = bitboard.iter().rev();
        assert_eq!(iter.next(), Some(D1));
        assert_eq!(iter.next(), Some(B1));
        assert_eq!(iter.next(), None);
    }
}