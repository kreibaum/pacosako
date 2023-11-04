//! A zobrist hash implementation to be used by Substrate implementations.
//! See https://en.wikipedia.org/wiki/Zobrist_hashing for an introduction.

use crate::{static_include::ZOBRIST, BoardPosition, PieceType, PlayerColor};
use serde::{Deserialize, Serialize};
use std::fmt::Debug;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default, Serialize, Deserialize)]
pub struct Zobrist(u64);

impl Zobrist {
    pub fn piece_on_square(player: PlayerColor, pos: BoardPosition, piece: PieceType) -> Zobrist {
        // By putting piece to the left, we avoid having to multiply by 6 which
        // doesn't compile to a single bit-shift.
        let index = ((piece as usize * 2) + player as usize) * 64 + pos.0 as usize;
        Zobrist(ZOBRIST[index])
    }
    pub fn piece_on_square_opt(
        player: PlayerColor,
        pos: BoardPosition,
        piece: Option<PieceType>,
    ) -> Zobrist {
        match piece {
            Some(piece) => Self::piece_on_square(player, pos, piece),
            None => Zobrist(0),
        }
    }
    pub fn as_u64(self) -> u64 {
        self.0
    }
}

impl std::ops::BitXor for Zobrist {
    type Output = Self;

    fn bitxor(self, rhs: Self) -> Self::Output {
        Self(self.0 ^ rhs.0)
    }
}

impl std::ops::BitXorAssign for Zobrist {
    fn bitxor_assign(&mut self, rhs: Self) {
        self.0 ^= rhs.0;
    }
}

impl Debug for Zobrist {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Z({})", self.0)
    }
}
