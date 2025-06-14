//! A version of Substrate that is representing everything through bitboards.
//! This does not save a lot of space, but it makes various operations on the
//! whole substrate fast.

use crate::substrate::zobrist::Zobrist;
use crate::substrate::{BitBoard, Substrate};
use crate::PieceType::{Bishop, King, Knight, Pawn, Queen, Rook};
use crate::PlayerColor::{Black, White};
use crate::{BoardPosition, PacoError, PieceType, PlayerColor};
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::hash::Hash;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct BBSubstrate {
    pieces: [[BitBoard; 6]; 2],
    hash: Zobrist,
}

impl BBSubstrate {
    pub fn recompute_zobrist_hash(&self) -> Zobrist {
        let mut hash = Zobrist::default();
        for color in PlayerColor::all() {
            for piece in PieceType::all() {
                for pos in self.pieces[color as usize][piece as usize] {
                    hash ^= Zobrist::piece_on_square(color, pos, piece);
                }
            }
        }
        hash
    }
}

impl Hash for BBSubstrate {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        state.write_u64(self.hash.as_u64());
    }
}

impl Substrate for BBSubstrate {
    fn get_piece(&self, player: PlayerColor, pos: BoardPosition) -> Option<PieceType> {
        let pawn = self.pieces[player as usize][Pawn as usize][pos] as u8 * (Pawn as u8 + 8);
        let rook = self.pieces[player as usize][Rook as usize][pos] as u8 * (Rook as u8 + 8);
        let knight = self.pieces[player as usize][Knight as usize][pos] as u8 * (Knight as u8 + 8);
        let bishop = self.pieces[player as usize][Bishop as usize][pos] as u8 * (Bishop as u8 + 8);
        let queen = self.pieces[player as usize][Queen as usize][pos] as u8 * (Queen as u8 + 8);
        let king = self.pieces[player as usize][King as usize][pos] as u8 * (King as u8 + 8);

        let piece = pawn | rook | knight | bishop | queen | king;

        if piece & 8 == 8 {
            Some(PieceType::from_u8(piece & 0b111))
        } else {
            None
        }
    }

    fn has_piece(&self, player: PlayerColor, pos: BoardPosition) -> bool {
        self.bitboard_color(player)[pos]
    }

    fn is_empty(&self, pos: BoardPosition) -> bool {
        !self.occupied()[pos]
    }

    fn all_empty(&self, bitboard: BitBoard) -> bool {
        (bitboard & self.occupied()).is_empty()
    }

    fn is_piece(&self, player: PlayerColor, pos: BoardPosition, piece: PieceType) -> bool {
        self.pieces[player as usize][piece as usize][pos]
    }

    fn set_piece(&mut self, player: PlayerColor, pos: BoardPosition, piece: PieceType) {
        self.remove_piece(player, pos);
        self.pieces[player as usize][piece as usize].insert(pos);
        self.hash ^= Zobrist::piece_on_square(player, pos, piece);
    }

    fn remove_piece(&mut self, player: PlayerColor, pos: BoardPosition) -> Option<PieceType> {
        let result = self.get_piece(player, pos)?;
        self.pieces[player as usize][result as usize].remove(pos);
        self.hash ^= Zobrist::piece_on_square(player, pos, result);
        Some(result)
    }

    fn swap(&mut self, pos1: BoardPosition, pos2: BoardPosition) {
        self.swap_color(White, pos1, pos2);
        self.swap_color(Black, pos1, pos2);
    }

    fn bitboard_color(&self, player: PlayerColor) -> BitBoard {
        self.pieces[player as usize][Pawn as usize]
            | self.pieces[player as usize][Rook as usize]
            | self.pieces[player as usize][Knight as usize]
            | self.pieces[player as usize][Bishop as usize]
            | self.pieces[player as usize][Queen as usize]
            | self.pieces[player as usize][King as usize]
    }

    fn find_king(&self, player: PlayerColor) -> Result<BoardPosition, PacoError> {
        self.pieces[player as usize][King as usize]
            .iter()
            .next()
            .ok_or(PacoError::NoKingOnBoard(player))
    }

    fn find_pieces(&self, player_color: PlayerColor, piece_type: PieceType) -> BitBoard {
        self.pieces[player_color as usize][piece_type as usize]
    }

    fn get_zobrist_hash(&self) -> Zobrist {
        self.hash
    }

    fn shuffle<R: Rng + ?Sized>(&mut self, rng: &mut R) {
        for i in (1..64).rev() {
            // invariant: elements with index > i have been locked in place.
            // We have to randomise the colours individually
            self.swap_color(
                White,
                BoardPosition(i),
                BoardPosition(rng.gen_range(0..(i + 1))),
            );
            self.swap_color(
                Black,
                BoardPosition(i),
                BoardPosition(rng.gen_range(0..(i + 1))),
            );
        }
    }
}

impl BBSubstrate {
    fn occupied(&self) -> BitBoard {
        self.bitboard_color(White) | self.bitboard_color(Black)
    }

    // Swaps the pieces at the given positions for the given colour.
    fn swap_color(&mut self, player: PlayerColor, pos1: BoardPosition, pos2: BoardPosition) {
        let p1 = self.get_piece(player, pos1);
        let p2 = self.get_piece(player, pos2);

        self.hash ^= Zobrist::piece_on_square_opt(player, pos1, p1);
        self.hash ^= Zobrist::piece_on_square_opt(player, pos2, p1);
        self.hash ^= Zobrist::piece_on_square_opt(player, pos1, p2);
        self.hash ^= Zobrist::piece_on_square_opt(player, pos2, p2);

        // Just swap everything.
        for j in 0..6 {
            self.pieces[player as usize][j].swap(pos1, pos2);
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::const_tile::*;
    use crate::fen;

    use super::*;

    // Test the size of a DenseSubstrate
    #[test]
    fn test_size() {
        use std::mem::size_of;
        assert_eq!(size_of::<BBSubstrate>(), 2 * 6 * 8 + 8);
    }

    #[test]
    fn test_find_pieces() {
        // Load a board from a FEN notation:
        let board =
            fen::parse_fen("2nr3r/2pU1ppp/1pt1p3/p2p1b2/Pb1P3P/1R2R3/1PPWPPP1/1N2KB2 w 0 AHah - -")
                .expect("Failed to parse FEN");

        let bb = board.substrate.find_pieces(White, Pawn);
        assert_eq!(bb.len(), 8);
        assert!(bb.contains(A4));
        assert!(bb.contains(B2));
        assert!(bb.contains(C2));
        assert!(bb.contains(D4));
        assert!(bb.contains(E2));
        assert!(bb.contains(F2));
        assert!(bb.contains(G2));
        assert!(bb.contains(H4));

        let bb = board.substrate.find_pieces(White, Knight);
        assert_eq!(bb.len(), 2);
        assert!(bb.contains(B1));
        assert!(bb.contains(D7));

        let bb = board.substrate.find_pieces(Black, Bishop);
        assert_eq!(bb.len(), 2);
        assert!(bb.contains(B4));
        assert!(bb.contains(F5));
    }
}
