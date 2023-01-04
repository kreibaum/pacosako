use async_trait::async_trait;

use crate::PacoError;

use super::glue::{AiContext, HyperParameter};

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

#[async_trait]
impl AiContext for Ludwig {
    async fn apply_model(
        &self,
        board: &crate::DenseBoard,
    ) -> Result<super::glue::ModelResponse, PacoError> {
        // Convert the dense board into a tensor representation.

        todo!();
    }

    fn hyper_parameter(&self) -> &HyperParameter {
        &self.hyper_parameter
    }
}
