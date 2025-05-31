use crate::fen;
use serde::Deserialize;

pub mod fischer_random;

pub const DEFAULT_STARTING_FEN: &str =
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -";

#[derive(Deserialize, Copy, Clone)]
pub enum PieceSetupParameters {
    DefaultPieceSetup,
    FischerRandom,
}

pub fn piece_setup_fen(setup: PieceSetupParameters) -> Option<String> {
    match setup {
        PieceSetupParameters::DefaultPieceSetup => None,
        PieceSetupParameters::FischerRandom => {
            Some(fen::write_fen(&fischer_random::fischer_random()))
        }
    }
}
