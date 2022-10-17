use wasm_bindgen::prelude::wasm_bindgen;

use crate::{fen, PacoBoard};

/// This module provides all the methods that should be available on the wasm
/// version of the library. Any encoding & decoding is handled in here.

#[wasm_bindgen]
pub fn legal_moves_fen(board: &str) -> String {
    let board = match fen::parse_fen(board) {
        Ok(board) => board,
        Err(e) => return format!("Error: {}", e),
    };

    // Serialize to json string and return
    let moves = board.actions();
    serde_json::to_string(&moves).unwrap()
}
