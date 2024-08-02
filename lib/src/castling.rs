//! Castling moves the King and the Rook at the same time.
//! Once you move or castle the King, you forfeit castling rights. If you move either Rook, you
//! forfeit castling permissions is that direction. See `Castling` for the struct containing the
//! permissions.
//!
//! Several squares need to be empty or safe (non-threatened):
//!
//! - Every Field the King passes through (including start and end) must be safe.
//! - Every Field the Rook and King pass through must be empty (excl. starting squares)
//!
//! We are using a `BitBoard` to communicate those square sets.
//!
//! Example: Standard Queen-Side Castling:
//!
//! 1 R•••KBNR
//!   ABCDEFGH
//!
//! - C1, D1 and E1 must be safe (Bitboard 11100_2 = 28)
//! - B1, C1, D1 must be empty (Bitboard 01110_2 = 14)
//!
//! Afterwards:
//!
//! 1 ••KR•BNR
//!   ABCDEFGH
//!
//! Example: Chess960 / Paco1680
//!
//! 1 •••R••KR
//!   ABCDEFGH
//!
//! - C1 through G1 must be safe and empty (Bitboard 01111100_2 = 124)
//!
//! Afterwards:
//!
//! 1 ••KR•••R
//!   ABCDEFGH
//!
//! The King is again on the C column and the rook remains in the D column.
//!
//! As these are all bitboards we can just precompute them and provide them in constants.
//!
//! One thing is dangerous about castling in Chess960. We have the assumption, that a king that can
//! castle can also move. This no longer holds.
//!
//! 1 BQRKBNNR
//!   ABCDEFGH
//!
//! Here the King can castle, but not move to the right.
//!
//! See https://blog.kreibaum.dev/optimizing-paco-sako-with-flamegraphs for the optimization that
//! relies on this. :-( This just means determining legal lift actions gets another branch where
//! we guard against the king not being able to move.
//!
//! To still make this cheap, we allow lifting a fully surrounded king if it is starting in a
//! "May castle" position. If you get stuck with a lifted king, just rollback.

use std::fmt::Display;
use serde::{Deserialize, Serialize};
use crate::{BoardPosition, PlayerColor};
use crate::substrate::BitBoard;

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Castling {
    pub white_queen_side: bool,
    pub white_king_side: bool,
    pub black_queen_side: bool,
    pub black_king_side: bool,
}

impl Castling {
    /// Returns an initial Castling structure where all castling options are possible
    pub fn new() -> Self {
        Castling {
            white_queen_side: true,
            white_king_side: true,
            black_queen_side: true,
            black_king_side: true,
        }
    }

    pub fn remove_rights_for_color(&mut self, current_player: PlayerColor) {
        match current_player {
            PlayerColor::White => {
                self.white_queen_side = false;
                self.white_king_side = false;
            }
            PlayerColor::Black => {
                self.black_queen_side = false;
                self.black_king_side = false;
            }
        }
    }

    pub fn from_string(input: &str) -> Self {
        Castling {
            white_queen_side: input.contains('A'),
            white_king_side: input.contains('H'),
            black_queen_side: input.contains('a'),
            black_king_side: input.contains('h'),
        }
    }
}

impl Display for Castling {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut any_char = false;
        if self.white_queen_side {
            write!(f, "A")?;
            any_char = true;
        }
        if self.white_king_side {
            write!(f, "H")?;
            any_char = true;
        }
        if self.black_queen_side {
            write!(f, "a")?;
            any_char = true;
        }
        if self.black_king_side {
            write!(f, "h")?;
            any_char = true;
        }
        if !any_char {
            write!(f, "-")?;
        }
        Ok(())
    }
}

struct CastlingRequirements {
    empty_positions : BitBoard,
    safe_positions : BitBoard,
    lift_optimization_allowed: bool,
    // Naively we would have {king, rook}-{source, target} but when those are the same we would get
    // a no-op. Also, an overlap does not commute. So what do we put in the data field?
    // Maybe a multi-way swap?
    swap: Vec<u8>,
}

// I should really have input types "Column" here..

fn queen_side_casting( rook : BoardPosition, king: BoardPosition ) -> CastlingRequirements {
    // This is just called in test code to verify the precomputed value.
    // This means we can panic at will.
    assert!(rook.0 < king.0, "The Rook must be left of the King.");



    todo!()
}