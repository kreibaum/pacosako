use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::wasm_bindgen;

use crate::{
    analysis::{self, HalfMove},
    fen, PacoAction, PacoBoard, PacoError,
};

/// This module provides all the methods that should be available on the wasm
/// version of the library. Any encoding & decoding is handled in here.

/// Represents a message that is send from elm via ports to the wasm library.
/// We use this wrapper to make sure the intermediate typescript layer stays
/// dumb and doesn't need to know about the possible messages..
///
/// Values in here are already fully decoded into rust types.
#[derive(Deserialize)]
pub enum RpcCall {
    HistoryToReplayNotation {
        board_fen: String,
        action_history: Vec<PacoAction>,
    },
    LegalActions {
        board_fen: String,
        action_history: Vec<PacoAction>,
    },
}

/// Represents a message that is send from the wasm library to elm via ports.
///
/// Values in here are still rust types and need encoding.
#[derive(Serialize)]
pub enum RpcResponse {
    HistoryToReplayNotation { notation: Vec<HalfMove> },
    LegalActions { legal_actions: Vec<PacoAction> },
    RpcError(String),
}

#[wasm_bindgen]
pub fn rpc_call(call: String) -> String {
    let call: Result<RpcCall, _> = serde_json::from_str(&call);
    let response: RpcResponse = match call {
        Ok(call) => rpc_call_internal(call),
        Err(e) => RpcResponse::RpcError(format!("Failed to decode call: {:?}", e)),
    };
    serde_json::to_string(&response).unwrap()
}

pub fn rpc_call_internal(call: RpcCall) -> RpcResponse {
    match call {
        RpcCall::HistoryToReplayNotation {
            board_fen,
            action_history,
        } => history_to_replay_notation(&board_fen, &action_history)
            .map(|notation| RpcResponse::HistoryToReplayNotation { notation })
            .unwrap_or_else(|e| {
                RpcResponse::RpcError(format!("Failed to convert history: {:?}", e))
            }),
        RpcCall::LegalActions {
            board_fen,
            action_history,
        } => legal_actions(&board_fen, &action_history)
            .map(|legal_actions| RpcResponse::LegalActions { legal_actions })
            .unwrap_or_else(|e| {
                RpcResponse::RpcError(format!("Failed to get legal actions: {:?}", e))
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
) -> Result<Vec<HalfMove>, PacoError> {
    let initial_board = fen::parse_fen(board_fen)?;

    analysis::history_to_replay_notation(initial_board, action_history)
}
