use std::fmt::Display;

use crate::{static_include, DenseBoard, PacoAction, PacoBoard, PieceType, PlayerColor};

pub fn print_all() {
    println!("{:?}", static_include::ZOBRIST[0]);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ZobristHash(u64);

impl Display for ZobristHash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Z({})", self.0)
    }
}

/// Freshly calculates the zobrist hash without relying on any stored value in
/// the board.
pub fn fresh_zobrist(board: &DenseBoard) -> ZobristHash {
    let mut sum = 0;
    let is_white = board.controlling_player() == PlayerColor::White;

    for position in 0..64 {
        if let Some(piece_type) = board.white.get(position).unwrap() {
            sum ^= static_include::ZOBRIST
                [position + 64 * piece_type_index(*piece_type, PlayerColor::White)];
        }
        if let Some(piece_type) = board.black.get(position).unwrap() {
            sum ^= static_include::ZOBRIST
                [position + 64 * piece_type_index(*piece_type, PlayerColor::Black)];
        }
    }

    match board.lifted_piece {
        crate::Hand::Empty => {}
        crate::Hand::Single { piece, position } => {
            sum ^= static_include::ZOBRIST[position.0 as usize
                + 64 * piece_type_index(piece, board.controlling_player())
                + 12 * 64];
        }
        crate::Hand::Pair {
            piece,
            partner,
            position,
        } => {
            sum ^= static_include::ZOBRIST[position.0 as usize
                + 64 * piece_type_index(piece, board.controlling_player())
                + 12 * 64];

            sum ^= static_include::ZOBRIST[position.0 as usize
                + 64 * piece_type_index(partner, board.controlling_player().other())
                + 12 * 64];
        }
    }

    if board.castling.white_queen_side {
        sum ^= static_include::CASTLING[0];
    }
    if board.castling.white_king_side {
        sum ^= static_include::CASTLING[1];
    }
    if board.castling.black_queen_side {
        sum ^= static_include::CASTLING[2];
    }
    if board.castling.black_king_side {
        sum ^= static_include::CASTLING[3];
    }

    if is_white {
        sum ^= static_include::IS_WHITE;
    }

    if let Some((pos, _)) = board.en_passant {
        sum ^= static_include::EN_PASSANT[pos.0 as usize];
    }

    ZobristHash(sum)
}

fn piece_type_index(piece_type: PieceType, color: PlayerColor) -> usize {
    let a = match piece_type {
        PieceType::Pawn => 0,
        PieceType::Rook => 1,
        PieceType::Knight => 2,
        PieceType::Bishop => 3,
        PieceType::Queen => 4,
        PieceType::King => 5,
    };
    let b = match color {
        PlayerColor::White => 0,
        PlayerColor::Black => 6,
    };
    a + b
}

/// Given a board and an action, this computes the hash after executing the
/// action without actually doing it on the board.
///
/// It holds, that fresh_zobrist(board.execute(action)) == zobrist_step(board, action)
/// for all legal actions on a board state.
///
/// This function does not check if the action is legal. Behaviour is undefined
/// for illegal moves. Infinite loops are considered legal for this restriction.
pub fn zobrist_step(board: &DenseBoard, action: PacoAction) -> ZobristHash {
    // TODO: Once the zobrist hash is stored in the board, this should just
    // look at the current board.
    let mut sum = fresh_zobrist(board).0;

    match action {
        PacoAction::Lift(pos) => {
            let position = pos.0 as usize;
            // Remove all pieces sitting at the board position from the sum
            // Add them to the lifted layer.
            if let Some(piece_type) = board.white.get(position).unwrap() {
                sum ^= static_include::ZOBRIST
                    [position + 64 * piece_type_index(*piece_type, PlayerColor::White)];
                sum ^= static_include::ZOBRIST
                    [position + 64 * piece_type_index(*piece_type, PlayerColor::White) + 12 * 64];
            }
            if let Some(piece_type) = board.black.get(position).unwrap() {
                sum ^= static_include::ZOBRIST
                    [position + 64 * piece_type_index(*piece_type, PlayerColor::Black)];
                sum ^= static_include::ZOBRIST
                    [position + 64 * piece_type_index(*piece_type, PlayerColor::Black) + 12 * 64];
            }
            // Figure out if any castling rights are lost.

            // White Queenside
            if pos.0 == 0 && board.castling.white_queen_side {
                sum ^= static_include::CASTLING[0];
            }
            if pos.0 == 7 && board.castling.white_king_side {
                sum ^= static_include::CASTLING[1];
            }
            if pos.0 == 56 && board.castling.black_queen_side {
                sum ^= static_include::CASTLING[2];
            }
            if pos.0 == 63 && board.castling.black_king_side {
                sum ^= static_include::CASTLING[3];
            }
        }
        PacoAction::Place(_) => todo!(),
        PacoAction::Promote(_) => todo!(),
    }

    ZobristHash(sum)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PacoAction;
    use rand::Rng;
    use std::convert::TryInto;

    /// Helper macro to execute moves in unit tests.
    macro_rules! lift {
        ($board:expr, $square:expr) => {{
            $board
                .execute(PacoAction::Lift($square.try_into().unwrap()))
                .unwrap();
        }};
    }

    #[test]
    fn empty_board() {
        let mut board = DenseBoard::empty();

        board.castling.white_queen_side = false;
        board.castling.white_king_side = false;
        board.castling.black_queen_side = false;
        board.castling.black_king_side = false;

        board.current_player = PlayerColor::Black;

        assert_eq!(fresh_zobrist(&board).0, 0)
    }

    #[test]
    fn does_not_crash_with_lifted_piece() {
        let mut board = DenseBoard::new();
        lift!(board, "c2");
        fresh_zobrist(&board);
    }

    /// Generates a random (settled) board and lifts a piece. Evaluates if the
    /// Zobrist hash works properly. This is done 100 times.
    #[test]
    fn test_single_lift_action() {
        let mut rng = rand::thread_rng();
        for i in 0..100 {
            let board: DenseBoard = rng.gen();
            for action in board.actions().expect("Random board is broken.") {
                let mut board_copy = board.clone();
                board_copy
                    .execute(action)
                    .expect("Can't execute legal action on board.");
                assert_eq!(
                    fresh_zobrist(&board_copy),
                    zobrist_step(&board, action),
                    "\nIteration: {},\nAction: {:?},\nBoard: \n{}",
                    i,
                    action,
                    board
                );
            }
        }
    }
}
