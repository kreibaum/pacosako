extern crate console_error_panic_hook;

use js_sys::Float32Array;
use rand::random;
use serde::{Deserialize, Serialize};
use wasm_bindgen::{prelude::wasm_bindgen, JsValue};

use pacosako::opening_book::{MoveData, OpeningBook, PositionData};
use pacosako::{
    analysis::{incremental_replay, puzzle, ReplayData},
    editor, fen,
    setup_options::SetupOptions,
    DenseBoard, PacoAction, PacoBoard, PacoError, PlayerColor,
};

mod ml;
mod utils;

/// This module provides all the methods that should be available on the wasm
/// version of the library. Any encoding & decoding is handled in here.
#[wasm_bindgen]
extern "C" {
    fn forwardToMq(messageType: &str, data: &str);
    fn current_timestamp_ms() -> u32;
    fn console_log(msg: &str);
    pub async fn evaluate_hedwig(input_tensor: Float32Array) -> JsValue;
}

#[derive(Serialize)]
struct LegalActionsDeterminedData {
    legal_actions: Vec<PacoAction>,
    input_action_count: usize,
    can_rollback: bool,
    controlling_player: PlayerColor,
}

#[wasm_bindgen(js_name = "determineLegalActions")]
pub fn determine_legal_actions(data: String) -> Result<(), JsValue> {
    utils::set_panic_hook();
    let history_data: ActionHistoryBoardRepr =
        serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let try_into: Result<DenseBoard, PacoError> = (&history_data).try_into();
    let data: DenseBoard = try_into.map_err(|e| e.to_string())?;

    let legal_actions: Vec<PacoAction> =
        data.actions().map_err(|e| e.to_string())?.iter().collect();

    let checkpoint = pacosako::find_last_checkpoint_index(history_data.action_history.iter())
        .map_err(|e| e.to_string())?;
    let can_rollback = history_data.action_history.len() > checkpoint;

    let legal_actions = LegalActionsDeterminedData {
        legal_actions,
        input_action_count: history_data.action_history.len(),
        can_rollback,
        controlling_player: data.controlling_player,
    };

    let legal_actions = serde_json::to_string(&legal_actions).map_err(|e| e.to_string())?;

    forwardToMq("legalActionsDetermined", &legal_actions);

    Ok(())
}

#[wasm_bindgen(js_name = "generateRandomPosition")]
pub fn generate_random_position(data: String) -> Result<(), JsValue> {
    utils::set_panic_hook();
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
    utils::set_panic_hook();
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
    utils::set_panic_hook();
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

#[wasm_bindgen(js_name = "determineAiMove")]
pub async fn determine_ai_move(data: String) -> Result<(), JsValue> {
    utils::set_panic_hook();
    let data: ActionHistoryBoardRepr = serde_json::from_str(&data).map_err(|e| e.to_string())?;

    let try_into: Result<DenseBoard, PacoError> = (&data).try_into();
    let board: DenseBoard = try_into.map_err(|e| e.to_string())?;

    let actions = determine_ai_move_inner(&board).await?;

    for action in actions {
        let action = serde_json::to_string(&vec![action]).map_err(|e| e.to_string())?;
        forwardToMq("aiMoveDetermined", &action);
    }
    forwardToMq("aiStateUpdated", "\"AiReadyForRequest\"");

    Ok(())
}

/// Ai move determination function where all the message passing related wiring can be ignored.
async fn determine_ai_move_inner(board: &DenseBoard) -> Result<Vec<PacoAction>, JsValue> {
    let fen = fen::write_fen(&board);
    // Check if there is a move stored in the opening book. If so, then we take that.
    if let Some(position_data) = OpeningBook::get(&fen) {
        console_log("Found opening book move.");

        let best_move = sample_softmax(position_data)?;
        return Ok(best_move.actions.clone());
    } else {
        console_log(format!("No opening book move found for {}", fen).as_str());
    }

    let actions = decide_turn_intuition(&board, vec![])
        .await
        .map_err(|e| e.to_string())?;
    Ok(actions)
}

/// This is essentially a re-implementation of `decideturn` from Julia.
async fn decide_turn_intuition(
    board: &DenseBoard,
    mut exclude: Vec<u64>,
) -> Result<Vec<PacoAction>, PacoError> {
    let ai_player = board.controlling_player;

    let mut actions = vec![];

    let mut game = board.clone();

    while !game.victory_state().is_over() && game.controlling_player == ai_player {
        let mut eval = ml::evaluate_model(&game).await;

        let action = 'exclude: loop {
            eval.normalize_policy();
            let action = eval.sample();

            let mut preview = game.clone();
            preview.execute_trusted(action)?;

            let hash = pacosako::calculate_interning_hash(&preview);
            if !exclude.contains(&hash) {
                exclude.push(hash);
                break 'exclude action;
            }
            eval.policy.retain(|(a, _)| *a == action);
            if eval.policy.is_empty() {
                // Recursion with more forbidden states.
                return Box::pin(decide_turn_intuition(board, exclude)).await;
            }
        };

        game.execute_trusted(action)?;
        actions.push(action);
    }

    Ok(actions)
}

fn sample_softmax(position_data: &PositionData) -> Result<&MoveData, JsValue> {
    // First, we apply softmax to the position_data
    // position_data.suggested_moves[*].move_value holds the softmax input.
    let mut normalization_factor = 0.0;
    let mut softmax_values = Vec::with_capacity(position_data.suggested_moves.len());
    for move_data in &position_data.suggested_moves {
        let exp_scaled = (20.0 * move_data.move_value).exp();
        normalization_factor += exp_scaled;
        softmax_values.push(exp_scaled);
    }

    let random = random::<f32>();
    let mut sum = 0.0;
    for (i, value) in softmax_values.iter().enumerate() {
        sum += value / normalization_factor;
        if sum >= random {
            return Ok(&position_data.suggested_moves[i]);
        }
    }
    Err(JsValue::from_str(
        "Failed to sample position data from opening book.",
    ))
}

/// Accepts the opening book that was just downloaded / taken from cache.
#[wasm_bindgen(js_name = "initOpeningBook")]
pub fn init_opening_book(data: String) -> Result<(), JsValue> {
    utils::set_panic_hook();

    console_log("Initializing opening book.");

    let load_and_remember = OpeningBook::load_and_remember(&data);
    match &load_and_remember {
        Ok(_) => console_log("Opening book loaded."),
        Err(e) => console_log(format!("Opening book failed to load: {}", e).as_str()),
    }
    load_and_remember.map_err(|e| e.to_string())?;

    console_log("Opening book initialized.");

    Ok(())
}

////////////////////////////////////////////////////////////////////////////////
// Proxy function for games. This sits between the client and server. //////////
////////////////////////////////////////////////////////////////////////////////

/// TODO: This has proven not really useful, I should get rid of it again.

/// Subscribes to the game on the server.
#[wasm_bindgen(js_name = "subscribeToMatch")]
pub fn subscribe_to_match(data: String) -> Result<(), JsValue> {
    forwardToMq("subscribeToMatchSocket", &data);

    Ok(())
}

#[test]
fn dummy_test() {
    // Makes it easier to test compile this crate using Ctrl+F10 in IntelliJ.
}
