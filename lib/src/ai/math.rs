//! Various AI helper functions.

use rand_distr::{Distribution, Normal};
use smallvec::{smallvec, SmallVec};

/// Generates a random vector of `N` logit-normal values.
pub fn logit_normal(n: usize, total: f32) -> SmallVec<[f32; 27]> {
    if total <= 0.0 {
        return smallvec![0.0; n];
    }

    let dist: Normal<f32> = Normal::new(0.0, 1.0).unwrap();
    let dist = dist.map(|x| x.exp());
    let mut rng = rand::thread_rng();

    let mut result = SmallVec::<[f32; 64]>::with_capacity(n);
    let mut sum = 0.0;

    for _ in 0..n {
        let sample = dist.sample(&mut rng);
        result.push(sample);
        sum += sample;
    }

    // Normalize the result.
    result.iter().map(|x| x * total / sum).collect()
}
