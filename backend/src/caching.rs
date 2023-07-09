use blake3::Hasher;
/// Functions related to caching and cache busting.
use cached::proc_macro::cached;
use std::{fs::File, io};

/// Generate the blake3 hash of the file at the given path.
/// Returns the hash as a string.
fn hash_file_no_cache(path: &str) -> String {
    let Ok(mut file) = File::open(path) else {
        panic!("Could not open static file at path: {}", path)
    };
    let mut hasher = Hasher::new();
    let Ok(_) = io::copy(&mut file, &mut hasher) else {
        panic!("Could not hash static file at path: {}", path)
    };
    hasher.finalize().to_hex().to_string()
}

/// Cached version that is only computed once.
/// The cache is only invalidated when the server is restarted.
/// This is the behavior we want for staging and production.
#[cached]
fn hash_file_with_cache(path: String) -> String {
    hash_file_no_cache(&path)
}

/// Get the hash of the file at the given path.
/// For local development, pass is use_cache = false.
pub fn hash_file(path: &str, use_cache: bool) -> String {
    if use_cache {
        hash_file_with_cache(path.to_owned())
    } else {
        hash_file_no_cache(path)
    }
}
