use std::fs::File;

use pacosako::{self, PacoAction, PacoBoard};
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

const SLOW_GAMES: &'static [usize] = &[4102, 2038, 4097, 2265, 2534, 3428, 3995, 1865, 3362, 464];

#[test]
fn regression_run() {
    println!("Testing the whole regression database...");
    let games = load_regression_database();

    for game in games {
        // Skip all slow games. We don't want to spend too much time on them.
        if SLOW_GAMES.contains(&game.id) {
            continue;
        }

        // For each game in games, time how long it takes to validate it.
        let start = std::time::Instant::now();
        let recomputed_game = map_input_to_validation(RegressionInput {
            id: game.id,
            history: game.history.clone(),
        });
        assert_eq!(game, recomputed_game);
        let end = start.elapsed();
        // Print time in microseconds.
        println!("Game {} took {} microseconds", game.id, end.as_micros());
    }
}

/// Loads the database from regression_database.json.
fn load_regression_database() -> Vec<RegressionValidation> {
    let mut file = File::open("tests/regression_database.json").unwrap();
    let mut contents = String::new();
    file.read_to_string(&mut contents).unwrap();
    serde_json::from_str(&contents).unwrap()
}

const FILTERED_OUT: &'static [usize] = &[218, 219];

#[ignore = "This is not a real test, but rather the utility used to build the regression database"]
#[test]
fn build_regression_file() {
    let input = load_game_database();

    // Remove games where the engine now does something else.
    let input: Vec<RegressionInput> = input
        .iter()
        .filter(|data| !FILTERED_OUT.contains(&data.id))
        .cloned()
        .collect();

    // Map each input to an output given the current logic
    let output = input
        .into_iter()
        .map(map_input_to_validation)
        .collect::<Vec<_>>();
    // Write the output to a file
    let mut file = File::create("tests/regression_database.json").unwrap();
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
    // Iterate over the history and apply each move. Then store all the legal
    // moves in the result.
    // We can ignore the legal moves on the empty board as they are the same
    // all the time.
    for action in input.history {
        board
            .execute(action)
            .unwrap_or_else(|e| panic!("Error executing: {:?}, {:?}", action, e));
        let legal_moves = board.actions().unwrap();
        result.legal_moves.push(legal_moves);
    }

    result
}

fn load_game_database() -> Vec<RegressionInput> {
    // Open the file all_non_empty_games.json
    let mut file = File::open("tests/all_non_empty_games.json").unwrap();
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
