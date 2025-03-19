use std::fs::File;

use pacosako::{self, DenseBoard, PacoAction, PacoBoard};
use serde::{Deserialize, Serialize};
use std::io::Read;

/// In this regression test, we load a database of all games played on
/// pacoplay.com until 17.07.2022. Then we check that the engine still returns
/// all the same legal moves for them.
///
/// We may later use this as a benchmark for move generation.

#[derive(Deserialize, Clone)]
struct RegressionInput {
    id: usize,
    history: Vec<PacoAction>,
}

#[derive(Deserialize, Serialize, PartialEq, Eq, Debug)]
struct RegressionValidation {
    id: usize,
    history: Vec<PacoAction>,
    legal_moves: Vec<Vec<PacoAction>>,
}

impl RegressionValidation {
    fn sort(&mut self) {
        for legal_moves in &mut self.legal_moves {
            legal_moves.sort();
        }
    }
}

const SLOW_GAMES: &[usize] = &[4102, 2038, 4097, 2265, 2534, 3428, 3995, 1865, 3362, 464];

/// This test ensures that on all covered games, the set of legal moves can never change.
/// It does that by comparing the legal moves against a known database.
#[test]
fn regression_run() {
    println!("Testing the whole regression database...");
    let mut games: Vec<RegressionValidation> = load_regression_database();

    for game in &mut games {
        game.sort();
        // Skip all slow games. We don't want to spend too much time on them.
        if SLOW_GAMES.contains(&game.id) {
            continue;
        }

        // For each game in games, time how long it takes to validate it.
        let start = std::time::Instant::now();
        let input = RegressionInput {
            id: game.id,
            history: game.history.clone(),
        };
        let mut recomputed_game = map_input_to_validation(input);
        recomputed_game.sort();
        if *game != recomputed_game {
            println!("Regression in game {}", game.id);
            for i in 0..game.legal_moves.len() {
                let expected_actions = game.legal_moves[i].clone();
                let actual_actions = recomputed_game.legal_moves[i].clone();
                if expected_actions != actual_actions {
                    println!("First difference in legal actions on index {i}.");
                    println!("Action taken: {:?}", game.history[i]);
                    println!("Expected: {:?}", expected_actions);
                    println!("Actual: {:?}", actual_actions);
                    panic!();
                }
            }
        }
        assert_eq!(*game, recomputed_game);
        let end = start.elapsed();
        // Print time in microseconds.
        println!("Game {} took {} microseconds", game.id, end.as_micros());
    }
}

/// Validates that the zobrist hash never breaks for any game in the database.
/// We do this in addition to fuzzing the engine, to make sure we cover also
/// the likely cases very well.
#[test]
fn validate_zobrist_integrity() {
    let games: Vec<RegressionValidation> = load_regression_database();
    for game in games {
        let mut board = DenseBoard::new();

        for action in game.history {
            board.execute(action).expect("Error executing action");

            assert_eq!(
                board.substrate.get_zobrist_hash(),
                board.substrate.recompute_zobrist_hash(),
                "Hash broken for game {} after action {:?}",
                game.id,
                action
            );
        }
    }
}

/// Loads the database from regression_database.json.
fn load_regression_database() -> Vec<RegressionValidation> {
    let mut file = File::open("tests/regression_database.json").unwrap();
    let mut contents = String::new();
    file.read_to_string(&mut contents).unwrap();
    serde_json::from_str(&contents).unwrap()
}

const FILTERED_OUT: &[usize] = &[218, 219];

#[ignore = "This is not a real test, but rather the utility used to build the regression database"]
#[test]
fn build_regression_file() {
    let input: Vec<RegressionInput> = load_game_database("tests/all_non_empty_games.json");

    // Remove games where the engine now does something else.
    let input: Vec<RegressionInput> = input
        .iter()
        .filter(|data| !FILTERED_OUT.contains(&data.id))
        .cloned()
        .collect();

    // Map each input to an output given the current logic
    let output: Vec<RegressionValidation> = input
        .into_iter()
        .map(map_input_to_validation)
        .collect::<Vec<_>>();

    // Write the output to a file
    write_regression_database(output, "tests/regression_database.json");
}

fn write_regression_database(output: Vec<RegressionValidation>, path: &str) {
    let mut file = File::create(path).unwrap();
    serde_json::to_writer(&mut file, &output).unwrap();
}

fn map_input_to_validation(input: RegressionInput) -> RegressionValidation {
    let capacity = input.history.len();
    let mut result = RegressionValidation {
        id: input.id,
        history: input.history.clone(),
        legal_moves: Vec::with_capacity(capacity),
    };
    let mut board = pacosako::DenseBoard::new();
    board.draw_state.draw_after_n_repetitions = 0;
    // Iterate over the history and apply each move. Then store all the legal
    // moves in the result.
    // We can ignore the legal moves on the empty board as they are the same
    // all the time.
    for (action_index, &action) in input.history.iter().enumerate() {
        board.execute(action).unwrap_or_else(|e| {
            panic!(
                "Game {}, Action {action_index}, Error executing: {:?}, {:?}",
                input.id, action, e
            )
        });
        let legal_moves = board.actions().unwrap();
        result.legal_moves.push(legal_moves.iter().collect());
    }

    result
}

fn load_game_database(path: &str) -> Vec<RegressionInput> {
    // Open the file all_non_empty_games.json
    let mut file = File::open(path).unwrap();
    // Use serde json to deserialize the file into a Vec<RegressionData>
    let mut contents = String::new();
    file.read_to_string(&mut contents).unwrap();
    let regression_data: Vec<RegressionInput> = serde_json::from_str(&contents).unwrap();
    // Iterate over the regression data and check that the engine returns the
    // same legal moves for each game.
    assert_eq!(regression_data.len(), 3552);
    // Count how many Lift operations there are in total over all the histories.
    let sum = regression_data
        .iter()
        .map(|data| count_lift(&data.history))
        .sum::<usize>();
    assert_eq!(sum, 113589);

    regression_data
}

fn count_lift(history: &[PacoAction]) -> usize {
    history.iter().filter(is_lift).count()
}

fn is_lift(action: &&PacoAction) -> bool {
    matches!(action, PacoAction::Lift(_))
}
