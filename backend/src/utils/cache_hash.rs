use blake3::Hasher;
use std::env;
use std::fs;
use std::io;

/// This is a utility program to hash files using blake3. I am reimplementing
/// this instead of relying on a utility to keep dependencies low.
fn main() {
    // Get the command line arguments
    let args: Vec<String> = env::args().collect();

    // Check if the filename argument is provided
    if args.len() != 2 {
        println!("Usage: {} <filename>", args[0]);
        return;
    }

    // Get the filename from the command line argument
    let filename = &args[1];

    // Read the content of the file
    let mut file = fs::File::open(filename).expect("Error opening file");
    let mut hasher = Hasher::new();
    io::copy(&mut file, &mut hasher)
        .unwrap_or_else(|_| panic!("Could not hash static file at path: {}", filename));
    println!("{}", hasher.finalize().to_hex());
}
