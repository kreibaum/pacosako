mod mcts;
mod mcts_executor_sync;
mod evaluation;


use ort::{CUDAExecutionProvider, GraphOptimizationLevel, Session};
use pacosako::DenseBoard;

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
    let evaluation = mcts_executor_sync::evaluate_model(&board, &mut session)?;
    let elapsed = start.elapsed();
    println!("Elapsed: {:?}", elapsed);

    println!("Value: {}", evaluation.value);
    for (action, policy) in evaluation.policy {
        println!("Action: {:?}, Policy: {}", action, policy);
    }

    let mut executor = mcts_executor_sync::SyncMctsExecutor::new(session, board, 1000);
    executor.run()?;

    Ok(())
}
