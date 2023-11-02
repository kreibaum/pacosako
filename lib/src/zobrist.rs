use std::fmt::Display;

use crate::{
    get_castling_auxiliary_move, static_include, substrate::Substrate, BoardPosition, Castling,
    DenseBoard, Hand, PacoAction, PacoBoard, PieceType, PlayerColor,
};

pub fn print_all() {
    println!("{:?}", static_include::ZOBRIST[0]);
}

/// See https://en.wikipedia.org/wiki/Zobrist_hashing for an introduction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Zobrist(u64);

impl Zobrist {
    pub(crate) fn piece_on_square(
        piece_type: PieceType,
        square: BoardPosition,
        color: PlayerColor,
        is_lifted: bool,
    ) -> Zobrist {
        let total_index = Zobrist::square_index(square)
            + Zobrist::type_index(piece_type) * 64
            + Zobrist::color_index(color) * 64 * 6
            + Zobrist::lift_index(is_lifted) * 64 * 12;
        Zobrist(static_include::ZOBRIST[total_index])
    }
    fn piece_on_square_opt(
        piece_type: Option<PieceType>,
        square: BoardPosition,
        color: PlayerColor,
        is_lifted: bool,
    ) -> Zobrist {
        match piece_type {
            Some(piece_type) => Zobrist::piece_on_square(piece_type, square, color, is_lifted),
            None => Zobrist(0),
        }
    }
    pub(crate) fn color(color: PlayerColor) -> Zobrist {
        match color {
            PlayerColor::White => Zobrist(static_include::IS_WHITE),
            PlayerColor::Black => Zobrist(0),
        }
    }
    pub(crate) fn castling(castle_rights: Castling) -> Zobrist {
        let mut sum = 0;
        if castle_rights.white_queen_side {
            sum ^= static_include::CASTLING[0];
        }
        if castle_rights.white_king_side {
            sum ^= static_include::CASTLING[1];
        }
        if castle_rights.black_queen_side {
            sum ^= static_include::CASTLING[2];
        }
        if castle_rights.black_king_side {
            sum ^= static_include::CASTLING[3];
        }
        Zobrist(sum)
    }
    pub(crate) fn en_passant(en_passant_square: Option<BoardPosition>) -> Zobrist {
        if let Some(pos) = en_passant_square {
            Zobrist(static_include::EN_PASSANT[pos.0 as usize])
        } else {
            Zobrist(0)
        }
    }

    /// For a given board, takes all the pieces that are placed on the board and
    /// returns a Zobrist hash for those only. This ignores a lot of the the
    /// other input. But we'll feed that in on demand instead.
    pub fn for_placed_pieces(board: &DenseBoard) -> Zobrist {
        let mut sum = 0;

        for position in 0..64 {
            if let Some(piece_type) = board
                .substrate
                .get_piece(PlayerColor::White, BoardPosition(position as u8))
            {
                sum ^= Zobrist::piece_on_square(
                    piece_type,
                    BoardPosition(position as u8),
                    PlayerColor::White,
                    false,
                )
                .0;
            }
            if let Some(piece_type) = board
                .substrate
                .get_piece(PlayerColor::Black, BoardPosition(position as u8))
            {
                sum ^= Zobrist::piece_on_square(
                    piece_type,
                    BoardPosition(position as u8),
                    PlayerColor::Black,
                    false,
                )
                .0;
            }
        }

        Zobrist(sum)
    }

    pub fn for_lifted_pieces(board: &DenseBoard) -> Zobrist {
        match board.lifted_piece {
            crate::Hand::Empty => Zobrist(0),
            crate::Hand::Single { piece, position } => {
                Zobrist::piece_on_square(piece, position, board.controlling_player(), true)
            }
            crate::Hand::Pair {
                piece,
                partner,
                position,
            } => {
                Zobrist::piece_on_square(piece, position, board.controlling_player(), true)
                    ^ Zobrist::piece_on_square(
                        partner,
                        position,
                        board.controlling_player().other(),
                        true,
                    )
            }
        }
    }

    fn square_index(square: BoardPosition) -> usize {
        square.0 as usize
    }
    fn type_index(piece_type: PieceType) -> usize {
        match piece_type {
            PieceType::Pawn => 0,
            PieceType::Rook => 1,
            PieceType::Knight => 2,
            PieceType::Bishop => 3,
            PieceType::Queen => 4,
            PieceType::King => 5,
        }
    }
    fn color_index(color: PlayerColor) -> usize {
        match color {
            PlayerColor::White => 0,
            PlayerColor::Black => 1,
        }
    }
    fn lift_index(is_lifted: bool) -> usize {
        match is_lifted {
            true => 1,
            false => 0,
        }
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

impl Display for Zobrist {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Z({})", self.0)
    }
}

/// Freshly calculates the zobrist hash without relying on any stored value in
/// the board.
pub fn fresh_zobrist(board: &DenseBoard) -> Zobrist {
    let mut sum = Zobrist::for_placed_pieces(board);

    sum ^= Zobrist::for_lifted_pieces(board);
    sum ^= Zobrist::castling(board.castling);
    sum ^= Zobrist::color(board.controlling_player());
    sum ^= Zobrist::en_passant(board.en_passant);

    sum
}

/// Given a board and an action, computes the zobrist XOR that would result from
/// executing this action. The resulting Zobrist is a "differential Zobrist",
/// not a full hash.
///
/// This only considers "placed" pieces. That is, pieces that are on the board.
///
/// This function does not check if the action is legal. Behavior is undefined
/// for illegal moves. Infinite loops are considered legal for this restriction.
pub fn zobrist_step_for_placed_pieces(board: &DenseBoard, action: PacoAction) -> Zobrist {
    match action {
        PacoAction::Lift(pos) => {
            // Get all the pieces that are on the board at pos and then xor their
            // hashes together.
            let pieces = board.get_at(pos);
            Zobrist::piece_on_square_opt(pieces.0, pos, PlayerColor::White, false)
                ^ Zobrist::piece_on_square_opt(pieces.1, pos, PlayerColor::Black, false)
        }
        PacoAction::Place(target) => {
            // Now this is a bit harder, because we need to differentiate
            // between ending the chain (paired / unpaired) and continuing the
            // chain.

            // Is there a white piece in hand? If so, then we put it down and take up the optional white piece at that position.
            // Same for black.

            let hand_pieces = board
                .lifted_piece
                .colored_optional_pair(board.controlling_player());

            let board_pieces = board.get_at(target);

            let mut sum = Zobrist(0);

            if let Some(piece_type) = hand_pieces.0 {
                // We have a white piece in hand. Put it down.
                sum ^= Zobrist::piece_on_square(piece_type, target, PlayerColor::White, false);
                // Take up the optional white piece at that position.
                sum ^=
                    Zobrist::piece_on_square_opt(board_pieces.0, target, PlayerColor::White, false);
            }
            if let Some(piece_type) = hand_pieces.1 {
                // We have a black piece in hand. Put it down.
                sum ^= Zobrist::piece_on_square(piece_type, target, PlayerColor::Black, false);
                // Take up the optional black piece at that position.
                sum ^=
                    Zobrist::piece_on_square_opt(board_pieces.1, target, PlayerColor::Black, false);
            }

            // If the king castles, then we need to xor the rook move.
            // As well as the potential partner piece.
            if let Hand::Single {
                piece: PieceType::King,
                position,
            } = board.lifted_piece
            {
                if let Some((rook_source, rook_target)) =
                    get_castling_auxiliary_move(position, target)
                {
                    // Remove all pieces from the rook source
                    sum ^= auxiliary_move(board, rook_source, rook_target);
                }
            }
            // If this is en passant, we need to xor the pawn.
            // As well as the potential partner piece.
            else if let Hand::Single {
                piece: PieceType::Pawn,
                position,
            } = board.lifted_piece
            {
                if board.is_place_using_en_passant(target, PieceType::Pawn, position) {
                    let en_passant_reset_from = target
                        .advance_pawn(board.controlling_player().other())
                        .unwrap();
                    sum ^= auxiliary_move(board, en_passant_reset_from, target);

                    // If we moved back a pair, then the own piece gets lifted and
                    // can chain.
                    sum ^= Zobrist::piece_on_square_opt(
                        board
                            .substrate
                            .get_piece(board.controlling_player, en_passant_reset_from),
                        target,
                        board.controlling_player(),
                        false,
                    );
                }
            }

            sum
        }
        PacoAction::Promote(target_type) => {
            // First, we need to figure out the color of the piece we're promoting.
            let color = board.controlling_player();
            let position = board.promotion.unwrap_or(BoardPosition(0));
            // let pieces = board.active_pieces().get(position.0 as usize).unwrap();

            // Remove the pawn.
            Zobrist::piece_on_square(PieceType::Pawn, position, color, false)
            // Add the new piece.
            ^ Zobrist::piece_on_square(target_type, position, color, false)
        }
    }
}

fn auxiliary_move(board: &DenseBoard, source: BoardPosition, target: BoardPosition) -> Zobrist {
    let pieces = board.get_at(source);

    // Remove from source square
    Zobrist::piece_on_square_opt(pieces.0, source, PlayerColor::White, false)
    ^ Zobrist::piece_on_square_opt(pieces.1, source, PlayerColor::Black, false)
    // Place them back at the target.
    ^ Zobrist::piece_on_square_opt(pieces.0, target, PlayerColor::White, false)
    ^ Zobrist::piece_on_square_opt(pieces.1, target, PlayerColor::Black, false)
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

        board.controlling_player = PlayerColor::Black;

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
    fn test_simple_action() {
        let mut rng = rand::thread_rng();
        for iteration_count in 0..100 {
            let board: DenseBoard = rng.gen();
            verify_each_action(&board, iteration_count, 2);
        }
    }

    fn verify_each_action(board: &DenseBoard, iteration_count: i32, depth: usize) {
        for action in board.actions().expect("Random board is broken.") {
            let mut board_copy = board.clone();
            board_copy
                .execute(action)
                .expect("Can't execute legal action on board.");

            let fresh_recalculation = Zobrist::for_placed_pieces(&board_copy);
            let incremental =
                Zobrist::for_placed_pieces(board) ^ zobrist_step_for_placed_pieces(board, action);

            assert_eq!(
                fresh_recalculation, incremental,
                "\nIteration: {},\nAction: {:?},\nBoard: \n{:?}",
                iteration_count, action, board
            );

            if depth > 1 {
                verify_each_action(&board_copy, iteration_count, depth - 1);
            }
        }
    }
}
