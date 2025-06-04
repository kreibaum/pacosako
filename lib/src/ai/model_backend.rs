//! Bindings for either the frontend or backend model evaluation.

use crate::ai::model_evaluation::ModelEvaluation;
use crate::{DenseBoard, PacoError};

/// Bindings for either the frontend or backend model evaluation.
pub trait ModelBackend {
    /// Evaluates the model for the given board.
    // you can suppress this lint if you plan to use the trait only in your own code, ...
    #[allow(async_fn_in_trait)]
    async fn evaluate_model(&mut self, board: &DenseBoard) -> Result<ModelEvaluation, PacoError>;
}