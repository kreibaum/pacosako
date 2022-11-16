//! Contains the puzzle solver.

use serde::Serialize;

use crate::{fen, find_sako_sequences, PacoAction, PacoBoard, PacoError};

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
    let sequences = find_sako_sequences(&((&board).into()))?;
    Ok(AnalysisReport {
        text_summary: format!("{:?}", sequences),
    })
}
