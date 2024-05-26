//! AI module for paco ŝako. This is included in the lib crate, so we only have
//! a single wasm binary to care about.
//!
//! The AI is based on the alpha zero algorithm.
//!
//! It mirrors Jtac, which we are using to train our models.
//! https://github.com/roSievers/Jtac.jl/

pub mod flexible_representation;
pub mod glue;
pub mod repr;
mod model_targets;
