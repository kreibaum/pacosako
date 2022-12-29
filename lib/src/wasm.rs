use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::wasm_bindgen;

use crate::{
    analysis::{self, puzzle, ReplayData},
    editor, fen,
    setup_options::SetupOptions,
    PacoAction, PacoBoard, PacoError,
};

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);

    fn ai_inference(input: f32) -> f32;
}

// Export a function that will be called in JavaScript
// but call the "imported" console.log.
#[wasm_bindgen]
pub fn console_log_from_wasm() {
    log("This console.log is from wasm!");

    ai_inference(1.0);
}

/// This module provides all the methods that should be available on the wasm
/// version of the library. Any encoding & decoding is handled in here.

/// Represents a message that is send from elm via ports to the wasm library.
/// We use this wrapper to make sure the intermediate typescript layer stays
/// dumb and doesn't need to know about the possible messages..
///
/// Values in here are already fully decoded into rust types.
#[derive(Deserialize, Debug)]
pub enum RpcCall {
    HistoryToReplayNotation {
        board_fen: String,
        action_history: Vec<PacoAction>,
        setup: SetupOptions,
    },
    LegalActions {
        board_fen: String,
        action_history: Vec<PacoAction>,
    },
    RandomPosition {
        tries: usize,
    },
    AnalyzePosition {
        board_fen: String,
        action_history: Vec<PacoAction>,
    },
}

/// Represents a message that is send from the wasm library to elm via ports.
///
/// Values in here are still rust types and need encoding.
#[derive(Serialize)]
pub enum RpcResponse {
    HistoryToReplayNotation(ReplayData),
    LegalActions { legal_actions: Vec<PacoAction> },
    RandomPosition { board_fen: String },
    AnalyzePosition { analysis: puzzle::AnalysisReport },
    RpcError(String),
}

#[wasm_bindgen]
pub fn rpc_call(call: String) -> String {
    let call: Result<RpcCall, _> = serde_json::from_str(&call);
    let response: RpcResponse = match &call {
        Ok(call) => match rpc_call_internal(call) {
            Ok(response) => response,
            Err(err) => RpcResponse::RpcError(format!(
                "Error handling rpc call: {:?} \nError: {:?}",
                call, err
            )),
        },
        Err(e) => RpcResponse::RpcError(format!("Failed to decode rpc call: {:?}", e)),
    };
    serde_json::to_string(&response).unwrap()
}

pub fn rpc_call_internal(call: &RpcCall) -> Result<RpcResponse, PacoError> {
    match call {
        RpcCall::HistoryToReplayNotation {
            board_fen,
            action_history,
            setup,
        } => Ok(RpcResponse::HistoryToReplayNotation(
            history_to_replay_notation(board_fen, action_history, setup)?,
        )),

        RpcCall::LegalActions {
            board_fen,
            action_history,
        } => Ok(RpcResponse::LegalActions {
            legal_actions: legal_actions(board_fen, action_history)?,
        }),
        RpcCall::RandomPosition { tries } => Ok(RpcResponse::RandomPosition {
            board_fen: fen::write_fen(&editor::random_position(*tries)?),
        }),
        RpcCall::AnalyzePosition {
            board_fen,
            action_history,
        } => Ok(RpcResponse::AnalyzePosition {
            analysis: puzzle::analyze_position(board_fen, action_history)?,
        }),
    }
}

/// Takes a settled legal board as a fen string and returns a list of all
/// legal moves, turned into json.
pub fn legal_actions(
    board_fen: &str,
    action_history: &[PacoAction],
) -> Result<Vec<PacoAction>, PacoError> {
    let mut board = fen::parse_fen(board_fen)?;
    for &action in action_history {
        board.execute(action)?;
    }

    // Serialize to json string and return
    board.actions()
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
