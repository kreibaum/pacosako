use std::sync::Arc;

use ort::{CUDAExecutionProvider, GraphOptimizationLevel, Session};
use pacosako::{DenseBoard, PacoBoard};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    ort::init()
        .with_name("Hedwig")
        .with_execution_providers([CUDAExecutionProvider::default().build()])
        .commit()?;

    let mut session = Session::builder()?
        .with_optimization_level(GraphOptimizationLevel::Level1)?
        .with_intra_threads(1)?
        //.commit_from_file("hedwig-0.8.onnx")?;
        .commit_from_file("hedwig-0.8-infer-int8.onnx")?;

    let board = DenseBoard::new();

    let start = std::time::Instant::now();
    let evaluation = evaluate_model(&board, &mut session)?;
    let elapsed = start.elapsed();
    println!("Elapsed: {:?}", elapsed);

    println!("Value: {}", evaluation.value);
    for (action, policy) in evaluation.policy {
        println!("Action: {:?}, Policy: {}", action, policy);
    }

    Ok(())
}

pub fn evaluate_model(
    board: &DenseBoard,
    session: &mut Session,
) -> Result<ModelEvaluation, ort::Error> {
    let input_repr: &mut [f32; 8 * 8 * 30] = &mut [0.; 8 * 8 * 30];
    pacosako::ai::repr::tensor_representation(board, input_repr);

    let input_shape: Vec<i64> = vec![1, 30, 8, 8_i64];
    let input_data: Box<[f32]> = input_repr.to_vec().into_boxed_slice();

    let input: ort::Value = ort::Value::try_from((input_shape, Arc::new(input_data)))?;

    let outputs = session.run(ort::inputs![input]?)?;

    let (o_shape, o_data): (Vec<i64>, &[f32]) = outputs["OUTPUT"].try_extract_raw_tensor()?;

    assert_eq!(o_shape, vec![1, 133]);

    let actions = board.actions().expect("Legal actions can't be determined");
    let mut policy = Vec::with_capacity(actions.len() as usize);
    for action in actions {
        // action to action index already returns a one-based index.
        // This works great with the first entry being the value.
        let action_index = pacosako::ai::glue::action_to_action_index(action);
        let action_policy = o_data[action_index as usize];
        policy.push((action, action_policy));
    }
    assert_eq!(policy.len(), actions.len() as usize);

    let mut evaluation = ModelEvaluation {
        value: o_data[0],
        policy,
    };
    evaluation.normalize_policy();

    Ok(evaluation)
}

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
