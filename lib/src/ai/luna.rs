//! A port of luna.jl to rust. This is a hand written model that is used to
//! require a neural network.
//! bootstrap the AI. It is also easy to test the MCTS with because it does not

use super::glue::{action_to_action_index, AiContext, HyperParameter};
use crate::{analysis::reverse_amazon_search::find_paco_sequences, PacoBoard, PacoError};
use async_trait::async_trait;

/// Implements the Luna model.
pub struct Luna {
    hyper_parameter: HyperParameter,
}

impl Luna {
    pub fn new(hyper_parameter: HyperParameter) -> Self {
        Self { hyper_parameter }
    }
}

#[async_trait(?Send)]
impl AiContext for Luna {
    async fn apply_model(
        &self,
        board: &crate::DenseBoard,
    ) -> Result<super::glue::ModelResponse, PacoError> {
        if board.victory_state.is_over() {
            // You are not supposed to ask the model if the game is already over.
            return Err(PacoError::GameIsOver);
        }

        // Find all sako sequences. If there is at least one, then we want to
        // play the first move of the first sequence.
        let paco_sequences = find_paco_sequences(board, board.controlling_player())?;

        if !paco_sequences.is_empty() {
            let mut policy = [0.0; 133];
            policy[0] = 1.0;

            let weight_per_action = 1.0 / paco_sequences.len() as f32;
            for sequence in paco_sequences {
                policy[action_to_action_index(sequence[0]) as usize] = weight_per_action;
            }

            return Ok(policy);
        }

        // All legal moves are equally likely. And we don't even have to
        // normalize the policy as that is not a requirement of the MCTS.
        let mut policy = [1.0; 133];

        // If we are in Ŝako, we haven't lost, but the position is not good.
        if board.is_settled()
            && !find_paco_sequences(board, board.controlling_player().other())?.is_empty()
        {
            policy[0] = -0.5;
        }

        Ok(policy)
    }

    fn hyper_parameter(&self) -> &HyperParameter {
        &self.hyper_parameter
    }
}
