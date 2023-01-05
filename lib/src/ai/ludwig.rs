use async_trait::async_trait;

use crate::{wasm::ai_inference_typed, DenseBoard, PacoError};

use super::{
    glue::{AiContext, HyperParameter, ModelResponse},
    repr::tensor_representation,
};

/// Implements the Ludwig model.
/// This does not really care about which model is used. But I'll only implement
/// model selection once I have a second model.
pub struct Ludwig {
    hyper_parameter: HyperParameter,
}

impl Ludwig {
    pub fn new(hyper_parameter: HyperParameter) -> Self {
        Self { hyper_parameter }
    }
}

#[async_trait(?Send)]
impl AiContext for Ludwig {
    async fn apply_model(&self, board: &DenseBoard) -> Result<ModelResponse, PacoError> {
        // Convert the dense board into a tensor representation.
        let mut tensor_repr = [0f32; 1920];
        tensor_representation(board, &mut tensor_repr);

        // Apply the model. This goes through wasm into onnx/webgl.
        Ok(ai_inference_typed(&tensor_repr).await)
    }

    fn hyper_parameter(&self) -> &HyperParameter {
        &self.hyper_parameter
    }
}
