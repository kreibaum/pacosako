/// This module contains classifiers for openings.
use crate::{const_tile::pos, DenseBoard, PacoAction, PacoBoard, PacoError, PieceType};

/// Returns all the openings that can be detected on the given replay.
pub(crate) fn classify_opening(
    initial_board: &DenseBoard,
    actions: &[PacoAction],
) -> Result<String, PacoError> {
    if !is_default_starting_position(initial_board) {
        return Ok("".to_string());
    }

    let mut all_found_openings: Vec<String> = vec![];

    if is_swedish_knights(initial_board, actions)? {
        all_found_openings.push("Swedish Knights".to_string());
    }

    // Comma separated list of openings as a string
    Ok(all_found_openings.join(", "))
}

/// Swedish Knights: Anything that moves Nc3 as well as Nh3, Nf4 during
/// the first 5 moves of your color.
pub(crate) fn is_swedish_knights(
    initial_board: &DenseBoard,
    actions: &[PacoAction],
) -> Result<bool, PacoError> {
    if !is_default_starting_position(initial_board) {
        return Ok(false);
    }

    // Apply the actions one by one to the initial board
    let mut board = initial_board.clone();
    let mut lift_counter = 0;
    for action in actions {
        board.execute(*action)?;

        // Check if we have a swedish knight
        // Is there a knight on c3 and f4?
        if board.white[pos("c3").0 as usize] == Some(PieceType::Knight)
            && board.white[pos("f4").0 as usize] == Some(PieceType::Knight)
        {
            return Ok(true);
        }

        // Is this a lift action? If so, increment the counter
        if let PacoAction::Lift(_) = action {
            lift_counter += 1;
            if lift_counter > 10 {
                return Ok(false);
            }
        }
    }

    Ok(false)
}

/// Check if the given DenseBoard is the default starting position.
pub fn is_default_starting_position(initial_board: &DenseBoard) -> bool {
    initial_board == &DenseBoard::new()
}
