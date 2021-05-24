use crate::{static_include, DenseBoard, PacoBoard, PieceType, PlayerColor};

pub fn print_all() {
    println!("{:?}", static_include::ZOBRIST[0]);
}

/// Freshly calculates the zobrist hash without relying on any stored value in
/// the board.
pub fn fresh_zobrist(board: DenseBoard) -> u64 {
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

    sum
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PacoAction;
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

        assert_eq!(fresh_zobrist(board), 0)
    }

    #[test]
    fn does_not_crash_with_lifted_piece() {
        let mut board = DenseBoard::new();
        lift!(board, "c2");
        fresh_zobrist(board);
    }
}
