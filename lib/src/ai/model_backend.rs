//! Bindings for either the frontend or backend model evaluation.

use crate::paco_action::PacoActionSet;
use crate::{DenseBoard, PacoAction, PlayerColor};
use rand::random;

/// Given a DenseBoard, we want to turn this into a model evaluation.
/// This is a list of the relative policy for various legal actions.
/// This also returns the value, but the raw Hedwig value isn't very good.
/// The action values have been normalized to sum up to 1.
#[derive(Debug)]
pub struct ModelEvaluation {
    pub value: f32,
    pub policy: Vec<(PacoAction, f32)>,
}

impl ModelEvaluation {
    pub fn new(
        legal_actions: PacoActionSet,
        // The viewpoint_color is required to "rotate back" the policy.
        viewpoint_color: PlayerColor,
        raw_model_output: &[f32],
    ) -> Self {
        let value = raw_model_output[0];

        let mut policy = Vec::with_capacity(legal_actions.len() as usize);
        for action in legal_actions {
            // action to action index already returns a one-based index.
            // This works great with the first entry being the value.
            let action_index =
                crate::ai::glue::action_to_action_index_with_viewpoint(action, viewpoint_color);
            let action_policy = raw_model_output[action_index as usize];
            policy.push((action, action_policy));
        }
        assert_eq!(policy.len(), legal_actions.len() as usize);

        let mut evaluation = ModelEvaluation { value, policy };

        evaluation.normalize_policy();
        evaluation
    }

    /// Make sure all the numbers sum to 1.
    pub fn normalize_policy(&mut self) {
        let sum: f32 = self.policy.iter().map(|(_, p)| p).sum();
        if sum == 0. {
            if !self.policy.is_empty() {
                let spread = 1. / self.policy.len() as f32;
                for (_, p) in &mut self.policy {
                    *p = spread;
                }
            }
            return;
        }
        for (_, p) in &mut self.policy {
            *p /= sum;
        }
    }

    /// A high temperature makes all possible results more likely.
    /// A low temperature (>0) makes the most likely result even more likely.
    pub fn with_temperature(&self, temperature: f32) -> Self {
        let mut new_policy = Vec::with_capacity(self.policy.len());
        for (action, p) in &self.policy {
            new_policy.push((*action, p.powf(1. / temperature)));
        }
        let mut evaluation = ModelEvaluation {
            value: self.value,
            policy: new_policy,
        };
        evaluation.normalize_policy();
        evaluation
    }

    /// Samples a random action, assuming the policy is normalized.
    pub fn sample(&self) -> PacoAction {
        let mut sum = 0.;
        let random = random::<f32>();
        for (action, p) in &self.policy {
            sum += p;
            if sum >= random {
                return *action;
            }
        }
        // This should never happen, but if it does, we return the last action.
        self.policy.last().map(|(a, _)| *a).unwrap()
    }

    /// Returns the policy sorted by action value, highest first.
    pub fn sorted(&self) -> Vec<(PacoAction, f32)> {
        let mut sorted = self.policy.clone();
        sorted.sort_by(|(_, a), (_, b)| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
        sorted
    }
}

/// Bindings for either the frontend or backend model evaluation.
pub trait ModelBackend {
    /// Evaluates the model for the given board.
    // you can suppress this lint if you plan to use the trait only in your own code, ...
    #[allow(async_fn_in_trait)]
    async fn evaluate_model(&self, board: &DenseBoard) -> ModelEvaluation;
}