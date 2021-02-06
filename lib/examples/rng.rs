/// This example shows you how to randomly generate board positions to
/// find interesting positions.
use pacosako::types::BoardPosition;
use pacosako::{DenseBoard, PacoAction, PacoError, SakoSearchResult};
use std::collections::HashSet;

// use rand::distributions::{Distribution, Standard};
use rand::{thread_rng, Rng};

fn main() -> Result<(), PacoError> {
    // Randomly generate DenseBoards and try to find one with long chains.

    let mut rng = thread_rng();
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

        // if let Some(_) = puzzle_book_for_children(&sequences) {
        //     println!("{}", board);
        // }

        if let Some(info) = long_chains_for_discord(&sequences) {
            println!("{}", info);
            println!("{}", board);
        }

        // if let Some(info) = many_start_positions(&sequences) {
        //     println!("{}", info);
        //     println!("{}", board);
        // }

        if counter >= 1000000 {
            return Ok(());
        }
    }
}

fn long_chains_for_discord(sequences: &SakoSearchResult) -> Option<String> {
    let shortest_sequence_white = sequences.white.iter().map(|o| o.len()).min().unwrap_or(0);
    let shortest_sequence_black = sequences.black.iter().map(|o| o.len()).min().unwrap_or(0);

    let no_promotion = !sequences.white.iter().any(chain_contains_promotion)
        && !sequences.black.iter().any(chain_contains_promotion);

    if (shortest_sequence_white >= 15 || shortest_sequence_black >= 15) && no_promotion {
        Some(format!(
            "w: {}, b: {}",
            shortest_sequence_white, shortest_sequence_black
        ))
    } else {
        None
    }
}

/// Puzzles with multiple solutions that avoid promoting in chains
fn many_start_positions(sequences: &SakoSearchResult) -> Option<String> {
    let white_has_direct_capture = sequences.white.iter().any(|chain| chain.len() <= 2);
    let black_has_direct_capture = sequences.black.iter().any(|chain| chain.len() <= 2);

    if (white_has_direct_capture || black_has_direct_capture) {
        return None;
    }

    let total_sequences = sequences.black.len() + sequences.white.len();
    let no_promotion = !sequences.white.iter().any(chain_contains_promotion)
        && !sequences.black.iter().any(chain_contains_promotion);
    let total_starting_points = starting_points(sequences).len();

    if total_sequences >= 5
        && total_starting_points >= 7
        && !white_has_direct_capture
        && !black_has_direct_capture
        && no_promotion
    {
        Some(format!("starting points: {}", total_starting_points))
    } else {
        None
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
