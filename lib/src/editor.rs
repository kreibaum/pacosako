use std::cmp::max;

/// Support functions for the pacoplay editor.
use crate::{analysis::reverse_amazon_search, DenseBoard, PacoError, SakoSearchResult};
use rand::{thread_rng, Rng};

/// Find a board with a long paco chain and return it.
/// This tries a fixed amount of times and returns the best result.
/// The best result is the one with the longest chain.
/// If no board is found, an initial board is returned.
/// To avoid everything involving promotions, we'll exclude boards which
/// have promotions as part of any chain.
pub fn random_position(tries: usize) -> Result<DenseBoard, PacoError> {
    let mut rng = thread_rng();
    let mut best_board = DenseBoard::new();
    let mut best_chain_length = 0;
    let mut best_amount_of_chains = 0;
    for _ in 0..tries {
        let board: DenseBoard = rng.gen();
        let white_sequences =
            reverse_amazon_search::find_paco_sequences(&board, crate::PlayerColor::White)?;

        let black_sequences =
            reverse_amazon_search::find_paco_sequences(&board, crate::PlayerColor::Black)?;

        let any_chain_involves_a_promotion = white_sequences
            .iter()
            .chain(black_sequences.iter())
            .any(|chain| chain.iter().any(|move_| move_.is_promotion()));

        // Promotions in chains are common on random boards and make the chain
        // long in a non-interesting way.
        if any_chain_involves_a_promotion {
            continue;
        }

        // Find the shortest sequence for each player
        let shortest_sequence_length_white = white_sequences
            .iter()
            .map(|seq| seq.len())
            .min()
            .unwrap_or(0);

        let shortest_sequence_length_black = black_sequences
            .iter()
            .map(|seq| seq.len())
            .min()
            .unwrap_or(0);

        let longest_shortest_sequence = max(
            shortest_sequence_length_white,
            shortest_sequence_length_black,
        );

        let amount_of_chains = white_sequences.len() + black_sequences.len();

        // If either the longest chain is better or the amount of chains is better,
        // we'll take this board.
        if longest_shortest_sequence > best_chain_length
            || (longest_shortest_sequence == best_chain_length
                && amount_of_chains > best_amount_of_chains)
        {
            best_board = board;
            best_chain_length = longest_shortest_sequence;
            best_amount_of_chains = amount_of_chains;
        }
    }
    Ok(best_board)
}
