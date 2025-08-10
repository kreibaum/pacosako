use crate::console_log;
use pacosako::ai::model_backend::ModelBackend;
use pacosako::ai::model_evaluation::ModelEvaluation;
use pacosako::{fen, DenseBoard, PacoBoard, PacoError};

#[derive(Default, Clone, Copy, Debug)]
pub struct ModelBackendJs;

impl ModelBackend for ModelBackendJs {
    async fn evaluate_model(&mut self, board: &DenseBoard) -> Result<ModelEvaluation, PacoError> {
        // Represent board for the model to consume
        let input_repr: &mut [f32; 30 * 8 * 8] = &mut [0.; 30 * 8 * 8];
        pacosako::ai::repr::tensor_representation(board, input_repr);
        // let input = Tensor::from_shape(&[1, 30, 8, 8], &*input_repr)?;

        // convert to Float32Array
        let input_tensor = js_sys::Float32Array::from(input_repr.as_ref());

        let start_time = js_sys::Date::now();
        let result = super::evaluate_hedwig(input_tensor).await;
        let end_time = js_sys::Date::now();

        let result = js_sys::Float32Array::from(result).to_vec();
        let actions = board.actions()?;

        let evaluation = ModelEvaluation::new(actions, board.controlling_player, &result)?;

        console_log(&format!(
            "Model Evaluation for {} ({} ms) -> {:?}",
            fen::write_fen(board), end_time - start_time, evaluation.sorted()
        ));

        Ok(evaluation)
    }
}