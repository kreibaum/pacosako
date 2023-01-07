//! Randomly generate Paco Ŝako positions which fit certain criteria.
//!
//! This needs to stay an example in here until I implement #80.

use std::cmp::max;

use pacosako::{
    analysis::reverse_amazon_search, fen, BoardPosition, DenseBoard, PacoError, PieceType,
    PlayerColor,
};

fn main() -> Result<(), PacoError> {
    'outer_loop: loop {
        let board: DenseBoard = rand::random();

        // Check if the kings are on the right side
        // We require each king to be on the first three rows for their color.
        if !white_king_in_position(&board) || !black_king_in_position(&board) {
            continue 'outer_loop;
        }

        // Find all promotions
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
        // But sometimes we actually want to find a chain with a promotion.
        // For this you can toggle the following line.
        if any_chain_involves_a_promotion {
            continue 'outer_loop;
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

        // We require that longest_shortest_sequence >= 10.

        if longest_shortest_sequence >= 10 {
            println!();
            println!(
                "White has a {}-chain, black has a {}-chain. Total is {}.",
                shortest_sequence_length_white, shortest_sequence_length_black, amount_of_chains
            );
            let fen = fen::write_fen(&board);
            // Replace spaces by %20 and prefix with https://pacoplay.com/editor?fen=
            let url = format!(
                "https://pacoplay.com/editor?fen={}",
                fen.replace(' ', "%20")
            );
            println!("{}", url);
        }
    }
}

fn white_king_in_position(board: &DenseBoard) -> bool {
    for i in 0..24 {
        if board[(PlayerColor::White, BoardPosition(i))] == Some(PieceType::King) {
            return true;
        }
    }
    false
}

fn black_king_in_position(board: &DenseBoard) -> bool {
    for i in 40..64 {
        if board[(PlayerColor::Black, BoardPosition(i))] == Some(PieceType::King) {
            return true;
        }
    }
    false
}
