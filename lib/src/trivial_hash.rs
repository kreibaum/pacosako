use std::hash::{BuildHasher, Hasher};

#[derive(Default)]
pub struct TrivialHashBuilder;

impl BuildHasher for TrivialHashBuilder {
    type Hasher = TrivialHasher;

    fn build_hasher(&self) -> Self::Hasher {
        TrivialHasher::default()
    }
}

#[derive(Default)]
pub struct TrivialHasher(u64);

impl Hasher for TrivialHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write_u64(&mut self, i: u64) {
        // Just xor the input into the state.
        self.0 ^= i;
    }

    fn write(&mut self, _bytes: &[u8]) {
        unimplemented!("This hasher only supports write_u64");
    }
}
