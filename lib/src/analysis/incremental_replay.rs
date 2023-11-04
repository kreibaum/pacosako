//! When analyzing a replay, we can't do this in one shot but should analyze
//! it step by step. Otherwise the UI will take a while before showing anything.
//!
//! We don't analyze the game from front to back, but feature by feature.
//! This means basic and fast features show up first, and more complex features
//! show up later.

use super::{
    apply_action_semantically, chasing_paco, squash_notation_atoms, HalfMove, HalfMoveMetadata,
    ReplayData,
};
use crate::{
    analysis::{opening, reverse_amazon_search::is_sako},
    DenseBoard, PacoAction, PacoBoard, PacoError, PlayerColor,
};

/// Does incremental computation of the replay notation and reports the progress
/// with a callback.
/// We need to use the "teach me how" pattern on current_timestamp_ms, because
/// that function has a different implementation in WASM and non-WASM.
pub fn history_to_replay_notation_incremental(
    initial_board: &DenseBoard,
    actions: &[PacoAction],
    current_timestamp_ms: impl Fn() -> u32,
    progress_callback: impl Fn(&ReplayData),
) -> Result<ReplayData, PacoError> {
    // Step one, build something we can quickly show to the user.
    let raw_half_moves = sort_actions_into_half_moves(initial_board, actions)?;
    let mut half_moves = derive_notation(initial_board, raw_half_moves)?;

    // We call this 30% done. This included the download of the game data which
    // likely took ~100ms.
    progress_callback(&ReplayData {
        notation: half_moves.clone(),
        opening: "".to_string(),
        progress: 0.3,
    });

    // Step two, annotate the half moves with metadata related to Ŝako and opening.
    let opening = opening::classify_opening(initial_board, actions)?;
    annotate_sako(initial_board, &mut half_moves)?;

    // We'll call this 50% done. Somewhat arbitrary.
    progress_callback(&ReplayData {
        notation: half_moves.clone(),
        opening: opening.clone(),
        progress: 0.5,
    });

    // As a last step, we add Paco in 2 information.
    // This is the most expensive step. We give intermediate feedback.
    let mut last_callback_called = current_timestamp_ms();
    let mut board = initial_board.clone();
    // We can't use a for loop because that would mutably borrow half_moves.
    let mut i = 0;
    while i < half_moves.len() {
        let half_move = &mut half_moves[i];
        i += 1;

        let paco_in_2_moves =
            chasing_paco::is_chasing_paco_in_2(&board, board.controlling_player())?;
        // Execute half move
        for action in &half_move.paco_actions {
            board.execute_trusted(*action)?;
        }
        if !paco_in_2_moves.is_empty() {
            // We found a Paco in 2. Add it to the metadata.
            // Check, if the board is now in any state that works with Paco in 2.
            let found = paco_in_2_moves
                .iter()
                .any(|(good_state, _)| *good_state == board);

            if found {
                half_move.metadata.paco_in_2_found = true
            } else {
                half_move.metadata.paco_in_2_missed = true
            }
        }

        // Check if at least a second has passed. If so, call the callback.
        let now = current_timestamp_ms();
        if now - last_callback_called > 1000 {
            progress_callback(&ReplayData {
                notation: half_moves.clone(),
                opening: opening.clone(),
                progress: 0.5 + (i as f32 / half_moves.len() as f32) * 0.5,
            });
            last_callback_called = now;
        }
    }

    Ok(ReplayData {
        notation: half_moves,
        opening,
        progress: 1.0,
    })
}

/// This first step takes care of sorting the actions into half moves.
/// This is a prerequisite for all other steps, but doesn't annotate the half
/// moves with any metadata.
fn sort_actions_into_half_moves(
    initial_board: &DenseBoard,
    actions: &[PacoAction],
) -> Result<Vec<Vec<PacoAction>>, PacoError> {
    let mut half_moves = Vec::with_capacity(actions.len() / 2);

    let mut board = initial_board.clone();
    let mut current_player = board.controlling_player;
    let mut i = 0;

    while i < actions.len() {
        let mut half_move = Vec::with_capacity(2);

        // As long as the current player stays the same, add the action to the
        // current half move.
        'actions: while i < actions.len() {
            board.execute_trusted(actions[i])?;
            half_move.push(actions[i]);
            i += 1;

            if board.controlling_player != current_player {
                current_player = board.controlling_player;
                break 'actions;
            }
        }

        half_moves.push(half_move);
    }

    Ok(half_moves)
}

/// Figure out the notation for each half move.
/// This isn't algebraic notation, but way better than "Lift(34), Place(42)"
fn derive_notation(
    initial_board: &DenseBoard,
    raw_half_moves: Vec<Vec<PacoAction>>,
) -> Result<Vec<HalfMove>, PacoError> {
    let mut board = initial_board.clone();
    let mut half_moves = Vec::with_capacity(raw_half_moves.len());
    let mut initial_index = 0;
    // White starts => 0+1 is the first move. Black starts => 1+0 is the first move.
    let mut move_number = (board.controlling_player() == PlayerColor::Black) as u32;
    for actions in &raw_half_moves {
        // Whenever White starts a half move, increment the move number
        let current_player = board.controlling_player();
        if current_player == PlayerColor::White {
            move_number += 1;
        }
        let mut additional_actions_processed = 0;

        let mut notations = Vec::with_capacity(actions.len());
        for &action in actions {
            let notation = apply_action_semantically(&mut board, action)?;
            additional_actions_processed += 1;
            notations.push(notation);
        }
        let sections = squash_notation_atoms(initial_index, notations);
        initial_index += additional_actions_processed;

        let half_move = HalfMove {
            move_number,
            current_player,
            actions: sections,
            paco_actions: actions.clone(),
            metadata: HalfMoveMetadata::default(),
        };

        half_moves.push(half_move);
    }
    Ok(half_moves)
}

/// Mutates the half moves in place to add information when a player gives
/// Ŝako, misses a Ŝako opportunity, or gives the opponent a Ŝako opportunity.
fn annotate_sako(
    initial_board: &DenseBoard,
    half_moves: &mut Vec<HalfMove>,
) -> Result<(), PacoError> {
    let mut board = initial_board.clone();
    let mut current_player = board.controlling_player;
    let mut giving_sako_before = is_sako(&board, current_player)?;
    let mut in_sako_before = is_sako(&board, current_player.other())?;
    for half_move in half_moves {
        for &action in &half_move.paco_actions {
            board.execute_trusted(action)?;
        }

        let giving_sako_after = is_sako(&board, current_player)?;
        let in_sako_after = is_sako(&board, current_player.other())?;

        half_move.metadata.gives_sako = giving_sako_after;
        half_move.metadata.missed_paco = giving_sako_before && !board.victory_state().is_over();
        half_move.metadata.gives_opponent_paco_opportunity = in_sako_after && !in_sako_before;

        giving_sako_before = in_sako_after;
        in_sako_before = giving_sako_after;
        current_player = board.controlling_player;
    }
    Ok(())
}
