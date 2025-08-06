use ort::execution_providers::CPUExecutionProvider;
use ort::execution_providers::CUDAExecutionProvider;
use ort::inputs;
use ort::session::Session;
use ort::session::builder::GraphOptimizationLevel;
use ort::value::{Tensor, Value};
use pacosako::PacoError::MlModelError;
use pacosako::ai::model_backend::ModelBackend;
use pacosako::ai::model_evaluation::ModelEvaluation;
use pacosako::{DenseBoard, PacoBoard, PacoError, fen};
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct OrtBackend {
    session: Arc<Mutex<Session>>,
}

impl ModelBackend for OrtBackend {
    async fn evaluate_model(&mut self, board: &DenseBoard) -> Result<ModelEvaluation, PacoError> {
        let input_repr: &mut [f32; 8 * 8 * 30] = &mut [0.; 8 * 8 * 30];
        pacosako::ai::repr::tensor_representation(board, input_repr);

        let input_shape: Vec<i64> = vec![1, 30, 8, 8_i64];
        let input_data: Box<[f32]> = input_repr.to_vec().into_boxed_slice();

        let input: Tensor<f32> = Value::from_array((input_shape, input_data))
            .map_err(|_| MlModelError("Error building input tensor".to_string()))?;

        let mut session = self
            .session
            .lock()
            .map_err(|_| MlModelError("Error locking session".to_string()))?;
        let outputs = session
            .run(inputs![input])
            .map_err(|_| MlModelError("Error evaluating model".to_string()))?;

        let output = &outputs["OUTPUT"];
        let (o_shape, o_data): (_, &[f32]) = output.try_extract_tensor().map_err(|_| {
            MlModelError("ONNX didn't return the expected 'OUTPUT' tensor as Tensor.".to_string())
        })?;

        if o_shape[0] != 1 || o_shape[1] != 133 {
            return Err(MlModelError(format!(
                "Model returned invalid shape: {:?}",
                o_shape
            )));
        }

        let evaluation = ModelEvaluation::new(board.actions()?, board.controlling_player, o_data);

        Ok(evaluation)
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Execution providers are loaded in the order they are provided until a suitable execution
    // provider is found.
    ort::init()
        .with_name("Hedwig")
        .with_execution_providers([
            CUDAExecutionProvider::default().build(),
            CPUExecutionProvider::default().build(),
        ])
        .commit()?;

    let session = Session::builder()?
        .with_optimization_level(GraphOptimizationLevel::Level1)?
        .with_intra_threads(1)?
        .commit_from_file("hedwig-0.8-infer-int8.onnx")?;

    let board = DenseBoard::new();

    let mut backend = OrtBackend {
        session: Arc::new(Mutex::new(session)),
    };

    println!("{:?}", backend.evaluate_model(&board).await?.sorted());

    // Run the model executor on an almost finished board state.
    let board =
        fen::parse_fen("2R3B1/1p3p1p/1A3n2/2p1r3/pPAp1D2/B3P1N1/P2KbPYk/2C2S1R w 0 AHah - -")?;

    println!("{:?}", backend.evaluate_model(&board).await?.sorted());

    // Determine a full move on this board state.
    pacosako::ai::move_decision::decide_turn_intuition(backend, &board, vec![])
        .await?
        .into_iter()
        .for_each(|action| println!("{:?}", action));

    Ok(())
}
