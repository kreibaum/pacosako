use std::error::Error;

use pacosako::{determine_all_moves, fen, PacoBoard, trace_first_move};
use pacosako::opening_book::{MoveData, OpeningBook};

fn main() -> Result<(), Box<dyn Error>> {
    // Load the opening book and print some information about it

    let mut opening_book = OpeningBook::parse(include_str!("2024-05-12-book-hedwig0.8-1000-1.0.json"))?;
    let book_clone = opening_book.clone();

    println!("Opening book loaded with {} positions", opening_book.0.len());

    let mut connections_found = 0;

    // Loop through all
    'book_entries: for (key, value) in opening_book.0.iter_mut() {
        // println!("Fen: {}", key);
        let board = fen::parse_fen(key)?;

        // Generate all possible moves / chains of actions
        let moves = determine_all_moves(board.clone())?;
        'legal_chains: for settled_board_hash in moves.settled {
            // Trace out the moves
            let Some(trace) = trace_first_move(settled_board_hash, &moves.found_via) else {
                println!("Error tracing first move for board with fen: {}", key);
                continue 'book_entries;
            };
            let mut settled_board = board.clone();
            for action in &trace {
                settled_board.execute_trusted(*action)?;
            }
            let settled_board_fen = fen::write_fen(&settled_board);
            let Some(book_info) = book_clone.0.get(&settled_board_fen) else {
                continue 'legal_chains;
            };

            // If we found a connection, then we store it in the opening book
            let move_data = MoveData {
                move_value: book_info.position_value,
                actions: trace,
            };

            value.suggested_moves.push(move_data);
            connections_found += 1;
        }
    }

    // Deduplicate all the connections
    for (_, value) in opening_book.0.iter_mut() {
        value.deduplicate();
    }

    println!("Found {} connections", connections_found);

    // Write the opening book back to disk
    let json_string = opening_book.write()?;
    std::fs::write("examples/2024-05-12-book-hedwig0.8-1000-1.0-with-connections.json", json_string)?;

    Ok(())
}