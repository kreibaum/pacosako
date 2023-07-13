mod utils;
mod websocket;

use serde::{Deserialize, Serialize};
use wasm_bindgen::{prelude::wasm_bindgen, JsValue};

use pacosako::{
    analysis::{self, puzzle, ReplayData},
    editor, fen,
    setup_options::SetupOptions,
    PacoAction, PacoBoard, PacoError,
};

/// This module provides all the methods that should be available on the wasm
/// version of the library. Any encoding & decoding is handled in here.

#[wasm_bindgen]
extern "C" {
    fn forwardToMq(messageType: &str, data: &str);
}

#[wasm_bindgen(js_name = "generateRandomPosition")]
pub fn generate_random_position(data: String) -> Result<(), JsValue> {
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
struct AnalyzePositionData {
    board_fen: String,
    action_history: Vec<PacoAction>,
}

#[wasm_bindgen(js_name = "analyzePosition")]
pub fn analyze_position(data: String) -> Result<(), JsValue> {
    let data: AnalyzePositionData = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let analysis = puzzle::analyze_position(&data.board_fen, &data.action_history)
        .map_err(|e| e.to_string())?;

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
    let data: AnalyzeReplayData = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let analysis = history_to_replay_notation(&data.board_fen, &data.action_history, &data.setup)
        .map_err(|e| e.to_string())?;

    let analysis = serde_json::to_string(&analysis).map_err(|e| e.to_string())?;

    forwardToMq("replayAnalysisCompleted", &analysis);

    Ok(())
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

    analysis::history_to_replay_notation(initial_board, action_history)
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
