//! Contains the puzzle solver.

use serde::Serialize;

use crate::{analysis::reverse_amazon_search, fen, PacoAction, PacoBoard, PacoError};

/// What to show in the sidebar after analysis.
/// We'll want pretty move notation in the future.
#[derive(Serialize)]
pub struct AnalysisReport {
    text_summary: String,
}

pub fn analyze_position(
    board_fen: &str,
    action_history: &[PacoAction],
) -> Result<AnalysisReport, PacoError> {
    let mut board = fen::parse_fen(board_fen)?;

    for &action in action_history {
        board.execute(action)?;
    }
    let white_sequences =
        reverse_amazon_search::find_paco_sequences(&board, crate::PlayerColor::White)?;

    let black_sequences =
        reverse_amazon_search::find_paco_sequences(&board, crate::PlayerColor::Black)?;

    Ok(AnalysisReport {
        text_summary: format!("White: {:?}, Black: {:?}", white_sequences, black_sequences),
    })
}
