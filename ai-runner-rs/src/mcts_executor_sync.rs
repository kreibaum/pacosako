//! Module implementing a synchronous MCTS executor.
//! That is, we have direct access to the graphics card and can run the neural network on it.
//! There is no need to go through async/await to go to javascript and back.

use crate::{
    evaluation::ModelEvaluation,
    mcts::{Mcts, MctsError, MctsPoll},
};
use ort::Session;
use pacosako::{fen, DenseBoard, PacoBoard};
use std::sync::Arc;
use thiserror::Error;

/// Yes, we need to error types, because the inner "MCTS" error type can't depend
/// on the outer "MctsExecutor" error type. E.g. we can't have a reference to the
/// ort library in the webassembly version and vice versa.
#[derive(Error, Debug)]
pub enum MctsExecutorError {
    #[error("MCTS error: {0}")]
    MctsError(#[from] MctsError),
    #[error("ORT error: {0}")]
    OrtError(#[from] ort::Error),
}

pub struct SyncMctsExecutor<'a> {
    session: &'a mut Session,
    mcts: Mcts,
}

impl<'a> SyncMctsExecutor<'a> {
    pub fn new(session: &'a mut Session, board: DenseBoard, max_size: u16) -> Self {
        let mcts = Mcts::new(board, max_size);
        Self { session, mcts }
    }

    pub fn run(&mut self) -> Result<(), MctsExecutorError> {
        'infinite_loop: loop {
            match self.mcts.poll() {
                MctsPoll::Evaluate(board) => {
                    let fen = fen::write_fen(board);
                    let start = std::time::Instant::now();
                    let evaluation = evaluate_model(board, self.session)?;
                    self.mcts.insert_model_evaluation(evaluation)?;
                    let elapsed = start.elapsed();

                    println!("Ran evaluation in {:?} on board: {}", elapsed, fen);
                }
                MctsPoll::SelectNodeToExpand => {
                    self.mcts.select_node_to_expand()?;
                }
                MctsPoll::AtMaxSize | MctsPoll::OutOfFreeBackpropagations => {
                    println!("TODO: Max size reached / out of free backpropagations.");
                    break 'infinite_loop;
                }
            }
        }
        println!("Finish run method for SyncMctsExecutor");
        println!("Visit counts: {:?}", self.mcts.get_root()?.visit_counts()?);

        // Print the main line, following the highest visit count.
        let mut mcts = self.mcts.clone();
        while let Ok(root) = mcts.get_root() {
            println!("We are at {:#?}", root);
            let action = root.visit_counts()?[0].0;
            println!("Here we follow action {:?}.", action);
            println!();

            mcts = mcts.subtree(action)?;
        }

        println!("\n\n\n");

        Ok(())
    }
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
