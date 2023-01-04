//! Various glue code related to the AI.

use async_trait::async_trait;

use crate::{DenseBoard, PacoError};

/// Maps the action to the index which represents the action in the policy
/// vector. Julia uses 1-based indexing, so we add 1 to the index.
pub(crate) fn action_to_action_index(action: crate::PacoAction) -> u8 {
    use crate::PieceType::*;
    match action {
        crate::PacoAction::Lift(p) => 1 + p.0,
        crate::PacoAction::Place(p) => 1 + p.0 + 64,
        crate::PacoAction::Promote(Rook) => 129,
        crate::PacoAction::Promote(Knight) => 130,
        crate::PacoAction::Promote(Bishop) => 131,
        crate::PacoAction::Promote(Queen) => 132,
        crate::PacoAction::Promote(_) => 255,
    }
}

#[async_trait]
pub trait AiContext {
    /// A model is something that can be applied to a board to get a value and
    /// a policy prior. Usually this is a neural network. But we may also use
    /// the hand written Luna model.
    async fn apply_model(&self, board: &DenseBoard) -> Result<ModelResponse, PacoError>;
    /// The exploration parameter is used to balance between exploration and
    /// exploitation. It is usually a constant.
    fn hyper_parameter(&self) -> &HyperParameter;
}

pub struct HyperParameter {
    pub exploration: f32,
    pub power: usize,
}

// The model response can be an array of size 133 (value + policy).
// The calculation is 1 (value) + 64 (lift) + 64 (place) + 4 (promotion).
pub(crate) type ModelResponse = [f32; 133];
