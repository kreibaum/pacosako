use crate::{PieceType, PlayerColor};

use super::DenseBoard;
use rand::distributions::{Distribution, Standard};
use rand::seq::SliceRandom;
use rand::Rng;

/// Defines a random generator for Paco Ŝako games that are not over yet.
/// I.e. where both kings are still free. This works by placing the pieces
/// randomly on the board.
impl Distribution<DenseBoard> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> DenseBoard {
        let mut board = DenseBoard::new();

        // Shuffle white and black pieces around
        board.white.shuffle(rng);
        board.black.shuffle(rng);

        // Check all positions for violations
        // No pawns on the enemy home row
        for i in 0..64 {
            if i < 8 && board.black[i] == Some(PieceType::Pawn) {
                let free_index = loop {
                    let candidate = random_position_without_black(&board, rng);
                    if candidate >= 8 {
                        break candidate;
                    }
                };
                board.black.swap(i, free_index);
            }
            if i >= 56 && board.white[i] == Some(PieceType::Pawn) {
                let free_index = loop {
                    let candidate = random_position_without_white(&board, rng);
                    if candidate < 56 {
                        break candidate;
                    }
                };
                board.white.swap(i, free_index);
            }
        }

        // No single pawns on the own home row
        for i in 0..64 {
            if i < 8
                && board.white[i] == Some(PieceType::Pawn)
                && (board.black[i].is_none() || board.black[i] == Some(PieceType::King))
            {
                let free_index = loop {
                    let candidate = random_position_without_white(&board, rng);
                    if (8..56).contains(&candidate) {
                        break candidate;
                    }
                };
                board.white.swap(i, free_index);
            }
            if i >= 56
                && board.black[i] == Some(PieceType::Pawn)
                && (board.white[i].is_none() || board.white[i] == Some(PieceType::King))
            {
                let free_index = loop {
                    let candidate = random_position_without_black(&board, rng);
                    if (8..56).contains(&candidate) {
                        break candidate;
                    }
                };
                board.black.swap(i, free_index);
            }
        }

        // Ensure, that the king is single. (Done after all other pieces are moved).
        for i in 0..64 {
            if board.white[i] == Some(PieceType::King) && board.black[i].is_some() {
                let free_index = random_empty_position(&board, rng);
                board.white.swap(i, free_index);
            }
            if board.black[i] == Some(PieceType::King) && board.white[i].is_some() {
                let free_index = random_empty_position(&board, rng);
                board.black.swap(i, free_index);
            }
        }

        // Randomize current player
        board.controlling_player = if rng.gen() {
            PlayerColor::White
        } else {
            PlayerColor::Black
        };

        // Figure out if any castling permissions remain
        let white_king_in_position = board.white[4] == Some(PieceType::King);
        let black_king_in_position = board.black[60] == Some(PieceType::King);

        board.castling.white_queen_side =
            white_king_in_position && board.white[0] == Some(PieceType::Rook);
        board.castling.white_king_side =
            white_king_in_position && board.white[7] == Some(PieceType::Rook);
        board.castling.black_queen_side =
            black_king_in_position && board.black[56] == Some(PieceType::Rook);
        board.castling.black_king_side =
            black_king_in_position && board.black[63] == Some(PieceType::Rook);

        board
    }
}

/// This will not terminate if the board is full.
/// The runtime of this function is not deterministic. (Geometric distribution)
fn random_empty_position<R: Rng + ?Sized>(board: &DenseBoard, rng: &mut R) -> usize {
    loop {
        let candidate = rng.gen_range(0..64);
        if board.white[candidate].is_none() && board.black[candidate].is_none() {
            return candidate;
        }
    }
}

/// This will not terminate if the board is full.
/// The runtime of this function is not deterministic. (Geometric distribution)
fn random_position_without_white<R: Rng + ?Sized>(board: &DenseBoard, rng: &mut R) -> usize {
    loop {
        let candidate = rng.gen_range(0..64);
        if board.white[candidate].is_none() {
            return candidate;
        }
    }
}

/// This will not terminate if the board is full.
/// The runtime of this function is not deterministic. (Geometric distribution)
fn random_position_without_black<R: Rng + ?Sized>(board: &DenseBoard, rng: &mut R) -> usize {
    loop {
        let candidate = rng.gen_range(0..64);
        if board.black[candidate].is_none() {
            return candidate;
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{DenseBoard, PieceType};

    #[test]
    fn random_dense_board_consistent() {
        use rand::{thread_rng, Rng};

        let mut rng = thread_rng();
        for _ in 0..1000 {
            let board: DenseBoard = rng.gen();

            let mut whites_found = 0;
            let mut blacks_found = 0;

            // Check all positions for violations
            for i in 0..64 {
                // Count pieces
                if board.white[i].is_some() {
                    whites_found += 1;
                }
                if board.black[i].is_some() {
                    blacks_found += 1;
                }

                // The king should be single
                if board.white[i] == Some(PieceType::King) {
                    assert_eq!(
                        board.black[i], None,
                        "The white king is united.\n{:?}",
                        board
                    );
                }
                if board.black[i] == Some(PieceType::King) {
                    assert_eq!(
                        board.white[i], None,
                        "The black king is united.\n{:?}",
                        board
                    );
                }
                // No pawns on the enemy home row
                // No single pawns on the own home row
                if i < 8 {
                    assert_ne!(
                        board.black[i],
                        Some(PieceType::Pawn),
                        "There is a black pawn on the white home row\n{:?}",
                        board
                    );
                    if board.black[i].is_none() {
                        assert_ne!(
                            board.white[i],
                            Some(PieceType::Pawn),
                            "There is a single white pawn on the white home row\n{:?}",
                            board
                        );
                    }
                }
                if i >= 56 {
                    assert_ne!(
                        board.white[i],
                        Some(PieceType::Pawn),
                        "There is a white pawn on the black home row\n{:?}",
                        board
                    );
                    if board.white[i].is_none() {
                        assert_ne!(
                            board.black[i],
                            Some(PieceType::Pawn),
                            "There is a single black pawn on the black home row\n{:?}",
                            board
                        );
                    }
                }
            }
            assert_eq!(whites_found, 16);
            assert_eq!(blacks_found, 16);
        }
    }
}
