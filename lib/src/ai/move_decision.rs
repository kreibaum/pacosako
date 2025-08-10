//! Module for building on an AI's move decision-making process.
//! This is essentially a re-implementation of `decideturn` from Julia.
//! The AI can only be called async.

use crate::ai::model_backend::ModelBackend;
use crate::{DenseBoard, PacoAction, PacoBoard, PacoError};

/// This is essentially a re-implementation of `decideturn` from Julia.
pub async fn decide_turn_intuition(
    mut backend: impl ModelBackend,
    board: &DenseBoard,
    mut exclude: Vec<u64>,
) -> Result<Vec<PacoAction>, PacoError> {
    let ai_player = board.controlling_player;

    let mut actions = vec![];

    let mut game = board.clone();

    while !game.victory_state().is_over() && game.controlling_player == ai_player {
        let mut eval = backend.evaluate_model(&game).await?;

        let action = 'exclude: loop {
            let action = eval.sample();

            let mut preview = game.clone();
            preview.execute_trusted(action)?;

            let hash = crate::calculate_interning_hash(&preview);
            if !exclude.contains(&hash) {
                exclude.push(hash);
                break 'exclude action;
            }

            // Remove the offending action from the policy and sample again.
            let Some(new_eval) = eval.remove(action) else            {
                // Well, if there is nothing else to sample from, we have to try
                // again, this time starting with a different first action.
                return Box::pin(decide_turn_intuition(backend, board, exclude)).await;
            };
            eval = new_eval;
        };

        game.execute_trusted(action)?;
        actions.push(action);
    }

    Ok(actions)
}