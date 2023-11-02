//! This module contains classifiers for openings.
use crate::PlayerColor::White;
use crate::{const_tile::*, BoardPosition};
use crate::{substrate::Substrate, DenseBoard, PacoAction, PacoBoard, PacoError, PieceType};

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

    if is_double_rai(initial_board, actions)? {
        all_found_openings.push("Double Rai".to_string());
    } else if is_rai(initial_board, actions)? {
        // You can't have Rai, if you already have Double Rai
        all_found_openings.push("Rai".to_string());
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
    // Apply the actions one by one to the initial board
    let mut board = initial_board.clone();
    let mut lift_counter = 0;
    for action in actions {
        board.execute(*action)?;

        // Check if we have a swedish knight
        // Is there a knight on c3 and f4?
        if board.substrate.is_piece(White, C3, PieceType::Knight)
            && board.substrate.is_piece(White, F4, PieceType::Knight)
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

/// Rai: h Rook goes to 3rd row by move 3, then to e3 or f3 within the next two
/// moves, without a pawn in front of it.
pub fn is_rai(initial_board: &DenseBoard, actions: &[PacoAction]) -> Result<bool, PacoError> {
    // Apply the actions one by one to the initial board
    let mut board = initial_board.clone();
    let mut lift_counter = 0;

    // In this first phase, we search until the h-rook is on the 3rd row.
    let mut action_pointer = 0;
    loop {
        if actions.len() <= action_pointer {
            return Ok(false);
        }
        let action = actions[action_pointer];
        board.execute(action)?;
        action_pointer += 1;

        // Is there a rook on h3
        if board.substrate.is_piece(White, H3, PieceType::Rook) {
            break;
        }

        // Is this a lift action? If so, increment the counter
        if let PacoAction::Lift(_) = action {
            lift_counter += 1;
            if lift_counter > 6 {
                return Ok(false);
            }
        }
    }

    // In this second phase, we search until the h-rook is on e3 or f3.
    // Reset the lift counter because you now have 2 move moves to do this.
    lift_counter = 0;
    loop {
        if actions.len() <= action_pointer {
            return Ok(false);
        }
        let action = actions[action_pointer];
        board.execute(action)?;
        action_pointer += 1;

        // Is there a rook on e3
        if board.substrate.is_piece(White, E3, PieceType::Rook) {
            // Check if there is a pawn in front of it
            if board.substrate.is_piece(White, E4, PieceType::Pawn) {
                return Ok(false);
            }
            return Ok(true);
        }

        // Is there a rook on f3
        if board.substrate.is_piece(White, F3, PieceType::Rook) {
            // Check if there is a pawn in front of it
            if board.substrate.is_piece(White, F4, PieceType::Pawn) {
                return Ok(false);
            }
            return Ok(true);
        }

        // Is this a lift action? If so, increment the counter
        if let PacoAction::Lift(_) = action {
            lift_counter += 1;
            if lift_counter > 4 {
                return Ok(false);
            }
        }
    }
}

/// Double Rai: Both rooks on row 3 by move 6.
fn is_double_rai(initial_board: &DenseBoard, actions: &[PacoAction]) -> Result<bool, PacoError> {
    // Apply the actions one by one to the initial board
    let mut board = initial_board.clone();
    let mut lift_counter = 0;

    // Search until both rooks are on the 3rd row.
    for action in actions {
        board.execute(*action)?;

        // How many rooks are on the 3rd row?
        let mut rooks_on_3rd_row = 0;
        let mut index = pos("a3").0;
        while index <= pos("h3").0 {
            if board
                .substrate
                .is_piece(White, BoardPosition(index), PieceType::Rook)
            {
                rooks_on_3rd_row += 1;
            }
            index += 1;
        }

        if rooks_on_3rd_row == 2 {
            return Ok(true);
        }

        // Is this a lift action? If so, increment the counter
        if let PacoAction::Lift(_) = action {
            lift_counter += 1;
            if lift_counter > 12 {
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

/// Tests module
#[cfg(test)]
mod tests {
    use crate::{analysis::history_to_replay_notation, const_tile::pos, DenseBoard, PacoAction::*};

    #[test]
    fn test_rai() {
        let replay = history_to_replay_notation(
            DenseBoard::new(),
            &[
                Lift(pos("d2")),
                Place(pos("d4")),
                Lift(pos("d7")),
                Place(pos("d5")),
                Lift(pos("h2")),
                Place(pos("h4")),
                Lift(pos("b8")),
                Place(pos("c6")),
                Lift(pos("h1")),
                Place(pos("h3")),
                Lift(pos("d8")),
                Place(pos("d6")),
                Lift(pos("b1")),
                Place(pos("c3")),
                Lift(pos("c8")),
                Place(pos("f5")),
                Lift(pos("h3")),
                Place(pos("e3")),
                Lift(pos("d6")),
                Place(pos("b4")),
                Lift(pos("c1")),
                Place(pos("d2")),
                Lift(pos("g8")),
                Place(pos("f6")),
            ],
        )
        .expect("Error in input data");

        assert_eq!(replay.opening, "Rai");
    }
}
