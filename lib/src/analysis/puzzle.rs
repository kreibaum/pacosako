//! Contains the puzzle solver.

use serde::Serialize;

use crate::{analysis::reverse_amazon_search, DenseBoard, PacoAction, PacoError, PlayerColor};

use super::incremental_replay;

/// What to show in the sidebar after analysis.
/// We'll want pretty move notation in the future.
#[derive(Serialize)]
pub struct AnalysisReport {
    text_summary: String,
}

pub fn analyze_position(
    board: impl TryInto<DenseBoard, Error = PacoError>,
) -> Result<AnalysisReport, PacoError> {
    let board: DenseBoard = board.try_into()?;

    let white_sequences = reverse_amazon_search::find_paco_sequences(&board, PlayerColor::White)?;

    let black_sequences = reverse_amazon_search::find_paco_sequences(&board, PlayerColor::Black)?;

    let mut analysis_report: String = String::new();

    if black_sequences.is_empty() && white_sequences.is_empty() {
        analysis_report.push_str("No Ŝako found.\n");
    }

    if !white_sequences.is_empty() {
        analysis_report.push_str("Ŝako White:\n");
        analysis_report.push_str(&write_all_sequences(
            white_sequences,
            board.clone(),
            PlayerColor::White,
        )?);
        analysis_report.push('\n');
    }

    if !black_sequences.is_empty() {
        analysis_report.push_str("Ŝako Black:\n");
        analysis_report.push_str(&write_all_sequences(
            black_sequences,
            board.clone(),
            PlayerColor::Black,
        )?);
        analysis_report.push('\n');
    }

    Ok(AnalysisReport {
        text_summary: analysis_report,
    })
}

fn write_all_sequences(
    sequences: Vec<Vec<PacoAction>>,
    input_board: DenseBoard,
    player_color: PlayerColor,
) -> Result<String, PacoError> {
    let mut analysis_report: String = String::new();
    for sequence in sequences {
        let mut colored_board = input_board.clone();
        colored_board.controlling_player = player_color;
        let sections =
            incremental_replay::segment_half_move_into_sections(&mut colored_board, &sequence, 0)?;
        for section in sections {
            analysis_report.push_str(&section.label);
        }
        analysis_report.push_str("; \n");
        analysis_report.push('\n');
    }
    Ok(analysis_report)
}
