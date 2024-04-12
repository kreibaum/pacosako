use std::sync::RwLock;

use pacosako::{paco_action::PacoActionSet, DenseBoard, PacoBoard};
use tract_onnx::prelude::*;

use super::console_log;

type OnnxModel = SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>;

// For simplicity, WASM is only allowed to keep one model loaded at a time.
// I.e. If you load Ludwig for one game and then play agains Hedwig, Ludwig
// is unloaded.
// The Arc<..> is in here to make borrowing/access easier.
static LOADED_MODEL: RwLock<Option<(String, OnnxModel)>> = RwLock::new(Option::None);

/// Given a DenseBoard, we want to turns this into a model evaluation.
/// This is a list of the relative policy for various legal actions.
/// This also returns the value, but the raw Hedwig value isn't very good.
/// The action values have been normalized to sum up to 1.
#[derive(Debug)]
pub struct ModelEvaluation {
    pub value: f32,
    pub policy: Vec<(pacosako::PacoAction, f32)>,
}

impl ModelEvaluation {
    fn new(legal_actions: PacoActionSet, raw_model_output: &[f32]) -> Self {
        let value = raw_model_output[0];

        let mut policy = Vec::with_capacity(legal_actions.len() as usize);
        for action in legal_actions {
            // action to action index already returns a one-based index.
            // This works great with the first entry being the value.
            let action_index = pacosako::ai::glue::action_to_action_index(action);
            let action_policy = raw_model_output[action_index as usize];
            policy.push((action, action_policy));
        }
        assert_eq!(policy.len(), legal_actions.len() as usize);

        let mut evaluation = ModelEvaluation { value, policy };

        evaluation.normalize_policy();
        evaluation
    }

    fn normalize_policy(&mut self) {
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
}

pub fn init_model(model_name: &str, onnx_file: Vec<u8>) -> TractResult<()> {
    console_log(&format!("Starting to load model {}.", model_name));
    // Check if the currently loaded model is already the right one.
    let mut loaded_model = LOADED_MODEL
        .write()
        .expect("Failed to aquire model write lock.");

    if let Some(arc) = loaded_model.as_ref() {
        if arc.0 == model_name {
            console_log("Model already loaded.");
            return Ok(());
        }
        // There is no need to unload the model here, this happens automatically
        // once the new value is stored in the RwLock.
    }

    console_log("Initializing AI model from ONNX file.");
    // Load the model
    let mut model = tract_onnx::onnx().model_for_read(&mut &onnx_file[..])?;
    console_log("Model loaded. (1/3)");

    // TODO: This seems to be where I can put in some additional facts.
    // That way the "INPUT" node can get its correct size.
    // Maybe OUTPUT needs that as well.

    // Define an explicit input shape. By default, the input shape would be
    // (?, 30, 8, 8) which allows an arbitrary amount of board representations
    // to be passed in along the first dimension.
    // This is not supported by tract which want to know the explicit input shape.
    // Running in WASM, we se this amount to 1.
    console_log(&format!(
        "Input shape of ONNX is defined as {:?}.",
        model.input_fact(0)
    ));
    model.input_fact_mut(0)?.shape = tvec!(1, 30, 8, 8).into();
    console_log(&format!(
        "Input shape of ONNX now changed to {:?}.",
        model.input_fact(0)
    ));

    // Optimize the model
    let model = model.into_optimized()?;
    console_log("Model optimized. (2/3)");

    let model = model.into_runnable()?;
    console_log("Model runnable. (3/3)");
    console_log("Model loaded successfully.");

    *loaded_model = Some((model_name.to_owned(), model));

    Ok(())
}

pub fn evaluate_model(board: &DenseBoard) -> Result<ModelEvaluation, tract_data::anyhow::Error> {
    let arc = LOADED_MODEL
        .read()
        .expect("Failed to aquire model read lock.");
    let Some(model) = arc.as_ref() else {
        tract_data::anyhow::bail!("No model loaded.")
    };
    let model = &model.1;

    // Represent board for the model to consume
    let input_repr: &mut [f32; 30 * 8 * 8] = &mut [0.; 30 * 8 * 8];
    pacosako::ai::repr::tensor_representation(&board, input_repr);
    let input = Tensor::from_shape(&[1, 30, 8, 8], &*input_repr)?;

    // Run model
    let result = model.run(tvec!(input.into()))?;

    // Extract result
    let result: Vec<_> = result[0].to_array_view::<f32>()?.iter().cloned().collect();
    let actions = board.actions().expect("Legal actions can't be determined");

    Ok(ModelEvaluation::new(actions, &result))
}
