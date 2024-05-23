//! An ml model target that shows all the threatened squares on the board.

use crate::{DenseBoard, determine_all_threats, Hand};

/// Write out which squares are threatened by the current player and the opponent.
/// This is for both players, so we need 128 f32 values of output space.
///
/// If there currently is a lifted piece, this piece is removed before calculating the threats.
/// This means, while lifting and moving a piece, the model must understand that
/// lifting unblocks threats. This may help understand pinning.
///
/// # Errors
///
/// Returns -1 if the `reserved_space` is less than 128.
/// Returns -2 if there is an error determining the threats.
///
/// # Safety
///
/// The ps pointer must be valid. The out pointer must be valid and have at least `reserved_space` reserved.
#[no_mangle]
pub unsafe extern "C" fn threatened_squares_target(ps: *mut DenseBoard, out: *mut f32, reserved_space: i64) -> i64 {
    if reserved_space < 128 {
        return -1;
    }

    let board = &*ps;
    let Ok(my_threatened_squares) = determine_all_threats(board) else {
        return -2;
    };

    let mut opponents_board = board.clone();
    opponents_board.set_hand(Hand::Empty);
    opponents_board.controlling_player = board.controlling_player.other();

    let Ok(opponent_threatened_squares) = determine_all_threats(&opponents_board) else {
        return -2;
    };

    let out = std::slice::from_raw_parts_mut(out, 128);
    // Zero out the output space
    for i in 0..128 {
        out[i] = 0.0;
    }
    for square in my_threatened_squares {
        out[square.0 as usize] = 1.0;
    }
    for square in opponent_threatened_squares {
        out[square.0 as usize + 64] = 1.0;
    }

    0 // Success
}