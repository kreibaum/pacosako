//! Various glue code related to the AI.

use async_trait::async_trait;

use crate::{BoardPosition, DenseBoard, PacoAction, PacoError};

/// Maps the action to the index which represents the action in the policy
/// vector. Julia uses 1-based indexing, so we add 1 to the index.
/// And the onnx model returns a vector of size 133 where index 0 is the value.
/// So we are fine with 1-based indexing there.
pub(crate) const fn action_to_action_index(action: PacoAction) -> u8 {
    use crate::PacoAction::*;
    use crate::PieceType::*;
    match action {
        Lift(p) => 1 + p.0,
        Place(p) => 1 + p.0 + 64,
        Promote(Rook) => 129,
        Promote(Knight) => 130,
        Promote(Bishop) => 131,
        Promote(Queen) => 132,
        Promote(_) => 255,
    }
}

pub(crate) const fn action_index_to_action(action_index: u8) -> Option<PacoAction> {
    use crate::PacoAction::*;
    use crate::PieceType::*;
    Some(match action_index {
        1..=64 => Lift(BoardPosition(action_index - 1)),
        65..=128 => Place(BoardPosition(action_index - 1 - 64)),
        129 => Promote(Rook),
        130 => Promote(Knight),
        131 => Promote(Bishop),
        132 => Promote(Queen),
        _ => return None,
    })
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

#[cfg(test)]
mod test {
    use crate::PieceType::*;

    use super::*;

    #[test]
    fn action_to_index_to_action() {
        for p in BoardPosition::all() {
            assert_eq!(
                action_index_to_action(action_to_action_index(PacoAction::Lift(p))),
                Some(PacoAction::Lift(p))
            );
            assert_eq!(
                action_index_to_action(action_to_action_index(PacoAction::Place(p))),
                Some(PacoAction::Place(p))
            );
        }
        for t in [Rook, Knight, Bishop, Queen] {
            assert_eq!(
                action_index_to_action(action_to_action_index(PacoAction::Promote(t))),
                Some(PacoAction::Promote(t))
            );
        }
    }

    #[test]
    fn index_to_action_to_index() {
        for i in 1..=132 {
            assert_eq!(
                action_to_action_index(action_index_to_action(i).unwrap()),
                i
            );
        }
    }
}
