use crate::substrate::{BitBoard, Substrate};
use crate::{BoardPosition, DenseBoard, PieceType, PlayerColor};

/// Write out which paws are blocked from moving. This is for both players, so we need 128 f32 values
/// of output space.
///
/// # Errors
///
/// Returns -1 if the `reserved_space` is less than 128.
///
/// # Safety
///
/// The ps pointer must be valid. The out pointer must be valid and have at least `reserved_space` reserved.
// SAFETY: there is no other global function of this name.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn blocked_pawns_target(ps: *mut DenseBoard, out: *mut f32, reserved_space: i64) -> i64 {
    if reserved_space < 128 {
        return -1;
    }

    let board = unsafe { &*ps };
    let my_blocked_pawns = blocked_pawns(board, board.controlling_player);
    let opponent_blocked_pawns = blocked_pawns(board, board.controlling_player.other());

    let out = unsafe { std::slice::from_raw_parts_mut(out, 128) };
    // Zero out the output space
    for i in 0..128 {
        out[i] = 0.0;
    }
    for pawn in my_blocked_pawns {
        out[pawn.0 as usize] = 1.0;
    }
    for pawn in opponent_blocked_pawns {
        out[pawn.0 as usize + 64] = 1.0;
    }

    0 // Success
}

/// Returns a bitboard with all pawns of the given `player_color` that are blocked from moving.
///
/// This is a powerful concept to grasp, as uniting your pieces with blocked opponent pawns prevents
/// the opponent from yanking around your pieces. And a single blocked pawn is a square that the
/// opponent can't move to / move through.
pub fn blocked_pawns(board: &DenseBoard, player_color: PlayerColor) -> BitBoard {
    let pawns: BitBoard = board.substrate.find_pieces(player_color, PieceType::Pawn);
    let mut blocked = BitBoard::default();

    // Blocked pawns can block other pawns from dancing diagonally. As you can't dance into a
    // blocked pawn, this can produce a "backlog" of pawns that can't move.
    // To cheaply test this, we need to make sure to iterate the pawn "from front to back", this
    // way we can use `blocked` on pawns in lower rows.
    let pawn_positions: Box<dyn Iterator<Item=BoardPosition>> = if player_color.is_white() {
        Box::new(pawns.iter().rev())
    } else {
        // .iter() goes from A1 to H8, so it is already in the right order for black.
        Box::new(pawns.iter())
    };

    'pawn_loop: for pawn in pawn_positions {
        // Check if there is an empty space in front of the pawn:
        if let Some(front_square) = pawn.advance_pawn(player_color) {
            if board.substrate.is_empty(front_square) {
                continue 'pawn_loop;
            }
        }

        for dance_target in pawn.dance_with_pawn(player_color) {
            if !blocked.contains(dance_target) && board.substrate.has_piece(player_color.other(), dance_target) {
                continue 'pawn_loop;
            }
        }

        blocked.insert(pawn);
    }

    blocked
}

#[cfg(test)]
mod tests {
    use crate::const_tile::*;
    use crate::fen;

    use super::*;

    #[test]
    fn test_blocked_pawns() {
        let board =
            fen::parse_fen("2nr3r/2pU1ppp/1pt1p3/p2p1b2/Pb1P3P/1R2R3/1PPWPPP1/1N2KB2 w 0 AHah - -")
                .expect("Failed to parse FEN");

        let white_blocked_pawns = blocked_pawns(&board, PlayerColor::White);
        let black_blocked_pawns = blocked_pawns(&board, PlayerColor::Black);

        assert_eq!(white_blocked_pawns.len(), 4);
        assert!(white_blocked_pawns.contains(A4));
        assert!(white_blocked_pawns.contains(B2));
        assert!(white_blocked_pawns.contains(D4));
        assert!(white_blocked_pawns.contains(E2));

        assert_eq!(black_blocked_pawns.len(), 3);
        assert!(black_blocked_pawns.contains(A5));
        assert!(black_blocked_pawns.contains(C7));
        assert!(black_blocked_pawns.contains(D5));
    }

    #[test]
    fn test_blocked_pawns_2() {
        let board =
            fen::parse_fen("rnbqk2r/pp1p1B1e/1f2c3/3PN3/3w1A2/3P1OA1/PP5P/2KR4 w 0 AHah - -")
                .expect("Failed to parse FEN");

        let white_blocked_pawns = blocked_pawns(&board, PlayerColor::White);
        let black_blocked_pawns = blocked_pawns(&board, PlayerColor::Black);

        assert_eq!(white_blocked_pawns.len(), 1);
        assert!(white_blocked_pawns.contains(D3));

        assert_eq!(black_blocked_pawns.len(), 1);
        assert!(black_blocked_pawns.contains(B7));
    }

    #[test]
    fn test_pawn_backlog() {
        let board = fen::parse_fen("r2q1b2/p1pk1p2/2np1n1r/3QdSpA/4PAP1/3P1B2/PPP5/R3KB1R w 0 AHah - -").expect("Failed to parse FEN");

        let white_blocked_pawns = blocked_pawns(&board, PlayerColor::White);
        let black_blocked_pawns = blocked_pawns(&board, PlayerColor::Black);

        assert_eq!(white_blocked_pawns.len(), 1);
        assert!(white_blocked_pawns.contains(H5));

        assert_eq!(black_blocked_pawns.len(), 6);
        assert!(black_blocked_pawns.contains(C7));
        assert!(black_blocked_pawns.contains(F7));
        assert!(black_blocked_pawns.contains(D6));
        assert!(black_blocked_pawns.contains(E5));
        assert!(black_blocked_pawns.contains(F4));
        assert!(black_blocked_pawns.contains(G5));
    }
}
