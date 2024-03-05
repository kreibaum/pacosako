mod utils;
mod websocket;

use pacosako::{
    analysis::{incremental_replay, puzzle, ReplayData},
    editor, fen,
    setup_options::SetupOptions,
    DenseBoard, PacoAction, PacoBoard, PacoError,
};
use serde::Deserialize;
use wasm_bindgen::{prelude::wasm_bindgen, JsValue};
extern crate console_error_panic_hook;

/// This module provides all the methods that should be available on the wasm
/// version of the library. Any encoding & decoding is handled in here.

#[wasm_bindgen]
extern "C" {
    fn forwardToMq(messageType: &str, data: &str);
    fn current_timestamp_ms() -> u32;
}

#[wasm_bindgen(js_name = "determineLegalActions")]
pub fn determine_legal_actions(data: String) -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    let data: ActionHistoryBoardRepr = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let try_into: Result<DenseBoard, PacoError> = (&data).try_into();
    let data: DenseBoard = try_into.map_err(|e| e.to_string())?;

    let legal_actions: Vec<PacoAction> =
        data.actions().map_err(|e| e.to_string())?.iter().collect();

    let legal_actions = serde_json::to_string(&legal_actions).map_err(|e| e.to_string())?;

    forwardToMq("legalActionsDetermined", &legal_actions);

    Ok(())
}

#[wasm_bindgen(js_name = "generateRandomPosition")]
pub fn generate_random_position(data: String) -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    // We are expecting a json string which just encodes an integer.
    let tries: u32 = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let fen = format!(
        "{{ \"board_fen\": \"{}\" }}",
        fen::write_fen(&editor::random_position(tries).map_err(|e| e.to_string())?)
    );

    forwardToMq("randomPositionGenerated", &fen);

    Ok(())
}

#[derive(Deserialize)]
struct ActionHistoryBoardRepr {
    board_fen: String,
    action_history: Vec<PacoAction>,
}

impl TryFrom<&ActionHistoryBoardRepr> for DenseBoard {
    type Error = PacoError;

    fn try_from(value: &ActionHistoryBoardRepr) -> Result<Self, Self::Error> {
        let mut board = fen::parse_fen(&value.board_fen)?;
        for action in &value.action_history {
            board.execute(*action)?;
        }
        Ok(board)
    }
}

#[wasm_bindgen(js_name = "analyzePosition")]
pub fn analyze_position(data: String) -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    let data: ActionHistoryBoardRepr = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let analysis = puzzle::analyze_position(&data).map_err(|e| e.to_string())?;

    let analysis = serde_json::to_string(&analysis).map_err(|e| e.to_string())?;

    forwardToMq("positionAnalysisCompleted", &analysis);

    Ok(())
}

#[derive(Deserialize)]
struct AnalyzeReplayData {
    board_fen: String,
    action_history: Vec<PacoAction>,
    setup: SetupOptions,
}

#[wasm_bindgen(js_name = "analyzeReplay")]
pub fn analyze_replay(data: String) -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    let data: AnalyzeReplayData = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let analysis = history_to_replay_notation(&data.board_fen, &data.action_history, &data.setup)
        .map_err(|e| e.to_string())?;

    analyze_replay_respond(&analysis);

    Ok(())
}

/// This function will report the replay data to Elm. This is extracted into a
/// separate method in order to be able to call it from the incremental replay.
pub fn analyze_replay_respond(analysis: &ReplayData) {
    if let Ok(analysis) = serde_json::to_string(analysis).map_err(|e| e.to_string()) {
        forwardToMq("replayAnalysisCompleted", &analysis);
    }
}

fn history_to_replay_notation(
    board_fen: &str,
    action_history: &[PacoAction],
    setup: &SetupOptions,
) -> Result<ReplayData, PacoError> {
    // This "initial_board" stuff really isn't great. This should be included
    // into the setup options eventually.
    let mut initial_board = fen::parse_fen(board_fen)?;

    // Apply setup options to the initial board
    initial_board.draw_state.draw_after_n_repetitions = setup.draw_after_n_repetitions;

    incremental_replay::history_to_replay_notation_incremental(
        &initial_board,
        action_history,
        current_timestamp_ms,
        analyze_replay_respond,
    )
}

////////////////////////////////////////////////////////////////////////////////
// Proxy function for games. This sits between the client and server. //////////
////////////////////////////////////////////////////////////////////////////////

/// Subscribes to the game on the server.
#[wasm_bindgen(js_name = "subscribeToMatch")]
pub fn subscribe_to_match(data: String) -> Result<(), JsValue> {
    forwardToMq("subscribeToMatchSocket", &data);

    Ok(())
}
