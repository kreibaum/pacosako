//! Module for Fischer random setup.
//!
//! https://en.wikipedia.org/wiki/Chess960

use crate::castling::CompactCastlingIdentifier;
use crate::types::BoardFile;
use crate::DenseBoard;
use crate::{substrate::Substrate, types::BoardRank::*, PieceType::*, PlayerColor::*};
use rand::Rng;

/// Randomly generates a Fischer random setup.
pub fn fischer_random() -> DenseBoard {
    let mut rng = rand::thread_rng();

    let mut board = DenseBoard::empty();
    let substrate = &mut board.substrate;

    // Fill ranks 2 and 7 with pawns.
    for file in 0..8 {
        substrate.set_piece(White, Rank2.and_u8(file), Pawn);
        substrate.set_piece(Black, Rank7.and_u8(file), Pawn);
    }

    // First we place the rooks and the king. The requirement here is, that the
    // king is between the rooks.
    let left_rook: u8 = rng.gen_range(0..6);
    let king = rng.gen_range((left_rook + 1)..7);
    let right_rook = rng.gen_range((king + 1)..8);

    substrate.set_piece(White, Rank1.and_u8(left_rook), Rook);
    substrate.set_piece(White, Rank1.and_u8(king), King);
    substrate.set_piece(White, Rank1.and_u8(right_rook), Rook);

    substrate.set_piece(Black, Rank8.and_u8(left_rook), Rook);
    substrate.set_piece(Black, Rank8.and_u8(king), King);
    substrate.set_piece(Black, Rank8.and_u8(right_rook), Rook);

    // Now we place the bishops. The requirement here is, that they can not
    // share the same color.
    let mut white_bishop = 1 + 2 * rng.gen_range(0..4);
    let mut black_bishop = 2 * rng.gen_range(0..4);

    while substrate.has_piece(White, Rank1.and_u8(white_bishop)) {
        white_bishop = 1 + 2 * rng.gen_range(0..4);
    }
    while substrate.has_piece(Black, Rank8.and_u8(black_bishop)) {
        black_bishop = 2 * rng.gen_range(0..4);
    }

    substrate.set_piece(White, Rank1.and_u8(white_bishop), Bishop);
    substrate.set_piece(White, Rank1.and_u8(black_bishop), Bishop);

    substrate.set_piece(Black, Rank8.and_u8(white_bishop), Bishop);
    substrate.set_piece(Black, Rank8.and_u8(black_bishop), Bishop);

    // Now we place the queen. It has no requirements.
    let mut queen = rng.gen_range(0..8);
    while substrate.has_piece(White, Rank1.and_u8(queen)) {
        queen = rng.gen_range(0..8);
    }

    substrate.set_piece(White, Rank1.and_u8(queen), Queen);
    substrate.set_piece(Black, Rank8.and_u8(queen), Queen);

    // All other tiles have knights
    for file in 0..8 {
        if !substrate.has_piece(White, Rank1.and_u8(file)) {
            substrate.set_piece(White, Rank1.and_u8(file), Knight);
            substrate.set_piece(Black, Rank8.and_u8(file), Knight);
        }
    }

    board.castling.white_queen_side = CompactCastlingIdentifier::new(
        BoardFile::expect_u8(king),
        BoardFile::expect_u8(left_rook),
        White,
    );

    board.castling.white_king_side = CompactCastlingIdentifier::new(
        BoardFile::expect_u8(king),
        BoardFile::expect_u8(right_rook),
        White,
    );

    board.castling.black_queen_side = CompactCastlingIdentifier::new(
        BoardFile::expect_u8(king),
        BoardFile::expect_u8(left_rook),
        Black,
    );

    board.castling.black_king_side = CompactCastlingIdentifier::new(
        BoardFile::expect_u8(king),
        BoardFile::expect_u8(right_rook),
        Black,
    );

    board
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::{fen, substrate::BitBoard};

    /// Verifies that a random board has the right piece count in roughly the
    /// right position.
    #[test]
    fn right_piece_count() {
        for _ in 0..100 {
            let board = fischer_random();

            // Assert first two ranks are filled.
            assert_eq!(
                board.substrate.bitboard_color(White),
                BitBoard(0b_11111111_11111111)
            );
            assert_eq!(
                board.substrate.bitboard_color(Black),
                BitBoard(0b_11111111_11111111 << (6 * 8))
            );

            // Assert piece counts.
            assert_eq!(board.substrate.find_pieces(White, Pawn).len(), 8);
            assert_eq!(board.substrate.find_pieces(Black, Pawn).len(), 8);

            assert_eq!(board.substrate.find_pieces(White, Rook).len(), 2);
            assert_eq!(board.substrate.find_pieces(Black, Rook).len(), 2);
            assert_eq!(board.substrate.find_pieces(White, Knight).len(), 2);
            assert_eq!(board.substrate.find_pieces(Black, Knight).len(), 2);
            assert_eq!(board.substrate.find_pieces(White, Bishop).len(), 2);
            assert_eq!(board.substrate.find_pieces(Black, Bishop).len(), 2);
            assert_eq!(board.substrate.find_pieces(White, Queen).len(), 1);
            assert_eq!(board.substrate.find_pieces(Black, Queen).len(), 1);
            assert_eq!(board.substrate.find_pieces(White, King).len(), 1);
            assert_eq!(board.substrate.find_pieces(Black, King).len(), 1);
        }
    }

    #[test]
    fn temp_show_me_some_fischer() {
        for _ in 0..10 {
            let fischer = fischer_random();
            let fen = fen::write_fen(&fischer);
            println!("{fen}");
        }
        assert_eq!(1, 2);
    }
}
