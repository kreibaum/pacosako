/// This example shows you how to randomly generate board positions to
/// find interesting positions.
use pacosako::types::BoardPosition;
use pacosako::{DenseBoard, PacoAction, PacoError, SakoSearchResult};
use std::cmp::{max, min};
use std::collections::HashSet;

// use rand::distributions::{Distribution, Standard};
use rand::{thread_rng, Rng};

fn main() -> Result<(), PacoError> {
    // Randomly generate DenseBoards and try to find one with long chains.

    let mut rng = thread_rng();
    let mut best_length = 0;
    let mut counter: usize = 0;

    loop {
        counter += 1;
        let board: DenseBoard = rng.gen();
        let sequences = pacosako::find_sako_sequences(&((&board).into()))?;
        // let max_white: usize = sequences
        //     .white
        //     .iter()
        //     .map(|chain| chain.len())
        //     .max()
        //     .unwrap_or(0);
        // let max_black: usize = sequences
        //     .black
        //     .iter()
        //     .map(|chain| chain.len())
        //     .max()
        //     .unwrap_or(0);
        // let min_white: usize = sequences
        //     .white
        //     .iter()
        //     .map(|chain| chain.len())
        //     .min()
        //     .unwrap_or(0);
        // let min_black: usize = sequences
        //     .black
        //     .iter()
        //     .map(|chain| chain.len())
        //     .min()
        //     .unwrap_or(0);
        // let max_chain_length: usize = max(max_white, max_black);
        // let min_chain_length: usize = max(min_white, min_black);

        if let Some(text) = puzzle_book_for_children(&sequences) {
            // println!("{}, ", text);

            // println!("\n\n");
            // println!("Randomly generated board (n = {}):", counter);
            println!("{}", board);

            // println!("White: {} - {}", min_white, max_white);
            // println!("Black: {} - {}", min_black, max_black);
            // println!("{:?}", sequences);
            // println!("Best Max length: {}", max_chain_length);
            // println!("Best Min length: {}", min_chain_length);
        }

        if (counter >= 1000) {
            return Ok(());
        }
    }
}

/// Puzzles with multiple short solutions that avoid promoting in chains
fn puzzle_book_for_children(sequences: &SakoSearchResult) -> Option<String> {
    let white_has_direct_capture = sequences.white.iter().any(|chain| chain.len() <= 2);
    let black_has_direct_capture = sequences.black.iter().any(|chain| chain.len() <= 2);

    let total_sequences = sequences.black.len() + sequences.white.len();
    let no_promotion = !sequences.white.iter().any(chain_contains_promotion)
        && !sequences.black.iter().any(chain_contains_promotion);
    let total_starting_points = starting_points(sequences).len();

    if total_sequences >= 5
        && total_starting_points >= 3
        && !white_has_direct_capture
        && !black_has_direct_capture
        && no_promotion
    {
        Some(format!("{}", total_sequences))
    } else {
        None
    }
}

fn chain_contains_promotion(chain: &Vec<PacoAction>) -> bool {
    chain.iter().any(PacoAction::is_promotion)
}

fn starting_points(sequences: &SakoSearchResult) -> HashSet<BoardPosition> {
    let mut result = HashSet::new();

    result.extend(
        sequences
            .white
            .iter()
            .filter_map(|chain| chain[0].position()),
    );

    result.extend(
        sequences
            .black
            .iter()
            .filter_map(|chain| chain[0].position()),
    );

    result
}
