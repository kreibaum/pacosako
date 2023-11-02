use super::DenseBoard;
use crate::const_tile::*;
use crate::substrate::Substrate;
use crate::PieceType::*;
use crate::PlayerColor::{Black, White};
use crate::{BoardPosition, PieceType};
use rand::distributions::{Distribution, Standard};
use rand::Rng;

/// Defines a random generator for Paco Ŝako games that are not over yet.
/// I.e. where both kings are still free. This works by placing the pieces
/// randomly on the board.
impl Distribution<DenseBoard> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> DenseBoard {
        let mut board = DenseBoard::new();

        // Shuffle white and black pieces around
        board.substrate.shuffle(rng);

        // Check all positions for violations
        // No pawns on the enemy home row
        for i in BoardPosition::all() {
            if i.0 < 8 && board.substrate.is_piece(Black, i, Pawn) {
                let free_index = loop {
                    let candidate = random_position_without_black(&board, rng);
                    if candidate.0 >= 8 {
                        break candidate;
                    }
                };
                board.substrate.remove_piece(Black, i);
                board.substrate.set_piece(Black, free_index, Pawn);
            }
            if i.0 >= 56 && board.substrate.is_piece(White, i, Pawn) {
                let free_index = loop {
                    let candidate = random_position_without_white(&board, rng);
                    if candidate.0 < 56 {
                        break candidate;
                    }
                };
                board.substrate.remove_piece(White, i);
                board.substrate.set_piece(White, free_index, Pawn);
            }
        }

        // No single pawns on the own home row
        for i in BoardPosition::all() {
            if i.0 < 8
                && board.substrate.is_piece(White, i, Pawn)
                && (!board.substrate.has_piece(Black, i)
                    || board.substrate.is_piece(Black, i, King))
            {
                let free_index = loop {
                    let candidate = random_position_without_white(&board, rng);
                    if (8..56).contains(&candidate.0) {
                        break candidate;
                    }
                };
                let piece = board
                    .substrate
                    .remove_piece(White, i)
                    .expect("Piece is missing, but we just checked.");
                board.substrate.set_piece(White, free_index, piece);
            }
            if i.0 >= 56
                && board.substrate.is_piece(Black, i, Pawn)
                && (!board.substrate.has_piece(White, i)
                    || board.substrate.is_piece(White, i, King))
            {
                let free_index = loop {
                    let candidate = random_position_without_black(&board, rng);
                    if (8..56).contains(&candidate.0) {
                        break candidate;
                    }
                };
                let piece = board
                    .substrate
                    .remove_piece(Black, i)
                    .expect("Piece is missing, but we just checked.");
                board.substrate.set_piece(Black, free_index, piece);
            }
        }

        // Ensure, that the king is single. (Done after all other pieces are moved).
        let white_king_position = board
            .substrate
            .find_king(White)
            .expect("White king is missing");
        if board.substrate.has_piece(Black, white_king_position) {
            let free_index = random_empty_position(&board, rng);
            board.substrate.remove_piece(White, white_king_position);
            board.substrate.set_piece(White, free_index, King);
        }

        let black_king_position = board
            .substrate
            .find_king(Black)
            .expect("Black king is missing");
        if board.substrate.has_piece(Black, black_king_position) {
            let free_index = random_empty_position(&board, rng);
            board.substrate.remove_piece(Black, black_king_position);
            board.substrate.set_piece(Black, free_index, King);
        }

        // Randomize current player
        board.controlling_player = if rng.gen() { White } else { Black };

        // Figure out if any castling permissions remain
        let white_king_in_position = board.substrate.is_piece(White, E1, King);
        let black_king_in_position = board.substrate.is_piece(White, E8, King);

        board.castling.white_queen_side =
            white_king_in_position && board.substrate.is_piece(White, A1, Rook);
        board.castling.white_king_side =
            white_king_in_position && board.substrate.is_piece(White, H1, Rook);
        board.castling.black_queen_side =
            black_king_in_position && board.substrate.is_piece(Black, A8, Rook);
        board.castling.black_king_side =
            black_king_in_position && board.substrate.is_piece(Black, H8, Rook);

        board
    }
}

/// This will not terminate if the board is full.
/// The runtime of this function is not deterministic. (Geometric distribution)
fn random_empty_position<R: Rng + ?Sized>(board: &DenseBoard, rng: &mut R) -> BoardPosition {
    loop {
        let candidate = BoardPosition(rng.gen_range(0..64));
        if board.substrate.is_empty(candidate) {
            return candidate;
        }
    }
}

/// This will not terminate if the board is full.
/// The runtime of this function is not deterministic. (Geometric distribution)
fn random_position_without_white<R: Rng + ?Sized>(
    board: &DenseBoard,
    rng: &mut R,
) -> BoardPosition {
    loop {
        let candidate = BoardPosition(rng.gen_range(0..64));
        if !board.substrate.has_piece(White, candidate) {
            return candidate;
        }
    }
}

/// This will not terminate if the board is full.
/// The runtime of this function is not deterministic. (Geometric distribution)
fn random_position_without_black<R: Rng + ?Sized>(
    board: &DenseBoard,
    rng: &mut R,
) -> BoardPosition {
    loop {
        let candidate = BoardPosition(rng.gen_range(0..64));
        if !board.substrate.has_piece(Black, candidate) {
            return candidate;
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{fen, substrate::Substrate, DenseBoard, PieceType, PlayerColor::*};

    #[test]
    fn random_dense_board_consistent() {
        use rand::{thread_rng, Rng};

        let mut rng = thread_rng();
        for _ in 0..1000 {
            let board: DenseBoard = rng.gen();
            let fen = fen::write_fen(&board);

            // Count pieces
            assert_eq!(
                board.substrate.bitboard_color(White).len(),
                16,
                "Wrong amount of White pieces: {:?}",
                fen
            );
            assert_eq!(
                board.substrate.bitboard_color(Black).len(),
                16,
                "Wrong amount of Black pieces: {:?}",
                fen
            );

            // The king should be single
            let white_king_position = board
                .substrate
                .find_king(White)
                .expect("White king is missing");
            assert!(
                !board.substrate.has_piece(Black, white_king_position),
                "The White king is united: {:?}",
                fen
            );

            let black_king_position = board
                .substrate
                .find_king(Black)
                .expect("Black king is missing");
            assert!(
                !board.substrate.has_piece(White, black_king_position),
                "The Black king is united: {:?}",
                fen
            );

            // Check all positions for violations
            for i in 0..64 {
                let white_piece = board
                    .substrate
                    .get_piece(White, crate::BoardPosition(i as u8));
                let black_piece = board
                    .substrate
                    .get_piece(Black, crate::BoardPosition(i as u8));
                // No pawns on the enemy home row
                // No single pawns on the own home row
                if i < 8 {
                    assert_ne!(
                        black_piece,
                        Some(PieceType::Pawn),
                        "There is a black pawn on the white home row\n{:?}",
                        fen
                    );
                    if black_piece.is_none() {
                        assert_ne!(
                            white_piece,
                            Some(PieceType::Pawn),
                            "There is a single white pawn on the white home row\n{:?}",
                            fen
                        );
                    }
                }
                if i >= 56 {
                    assert_ne!(
                        white_piece,
                        Some(PieceType::Pawn),
                        "There is a white pawn on the black home row\n{:?}",
                        fen
                    );
                    if white_piece.is_none() {
                        assert_ne!(
                            black_piece,
                            Some(PieceType::Pawn),
                            "There is a single black pawn on the black home row\n{:?}",
                            fen
                        );
                    }
                }
            }
        }
    }
}
