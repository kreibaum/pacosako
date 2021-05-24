use std::{fs::File, io::Write};

/// Testing out the zobrist hashing
use pacosako::{zobrist, DenseBoard};
use rand::RngCore;

fn main() {
    let board = DenseBoard::new();
    println!("{}", zobrist::fresh_zobrist(board));

    build_file("data/zobrist.txt", 12 * 64 * 2).unwrap();
}

pub fn build_file(path: &str, size: usize) -> Result<(), std::io::Error> {
    let mut rng = rand::thread_rng();
    let mut file = File::create(path)?;
    write!(file, "[")?;
    write!(file, "{}", rng.next_u64())?;
    for _ in 1..size {
        write!(file, ", {}", rng.next_u64())?;
    }
    write!(file, "u64]")?;
    Ok(())
}
