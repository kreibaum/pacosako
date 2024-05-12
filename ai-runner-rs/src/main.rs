mod evaluation;
mod mcts;
mod mcts_executor_sync;

use ort::{CUDAExecutionProvider, GraphOptimizationLevel, Session};
use pacosako::{fen, DenseBoard};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    ort::init()
        .with_name("Hedwig")
        .with_execution_providers([CUDAExecutionProvider::default().build()])
        .commit()?;

    let mut session = Session::builder()?
        .with_optimization_level(GraphOptimizationLevel::Level1)?
        .with_intra_threads(1)?
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

    // // Run the MCTS executor on an initial board state.
    // let mut executor = mcts_executor_sync::SyncMctsExecutor::new(&mut session, board, 100);
    // executor.run()?;

    // Run the MCTS executor on an almost finished board state.
    let board =
        fen::parse_fen("2R3B1/1p3p1p/1A3n2/2p1r3/pPAp1D2/B3P1N1/P2KbPYk/2C2S1R w 0 AHah - -")?;
    let mut executor = mcts_executor_sync::SyncMctsExecutor::new(&mut session, board, 100);
    executor.run()?;

    Ok(())
}
