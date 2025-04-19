use rand::RngCore;
use std::{fs::File, io::Write};

fn main() {
    build_file("data/zobrist.txt", 12 * 64 * 2).unwrap();
    build_file("data/en_passant.txt", 64).unwrap();
    build_file("data/castling.txt", 4).unwrap();
}

pub fn build_file(path: &str, size: usize) -> Result<(), std::io::Error> {
    let mut rng = rand::rng();
    let mut file = File::create(path)?;
    write!(file, "[")?;
    write!(file, "{}", rng.next_u64())?;
    for _ in 1..size {
        write!(file, ", {}", rng.next_u64())?;
    }
    write!(file, "u64]")?;
    Ok(())
}
