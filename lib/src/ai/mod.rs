//! AI module for paco ŝako. This is included in the lib crate so we only have
//! a single wasm binary to care about.
//!
//! The AI is based on the alpha zero algorithm.
//!
//! It mirrors Jtac which we are using to train our models.
//! https://github.com/roSievers/Jtac.jl/

mod colored_value;
pub(crate) mod glue;
pub(crate) mod ludwig;
pub(crate) mod luna;
pub(crate) mod mcts;

#[cfg(test)]
mod tests {
    use crate::{
        ai::mcts::MctsPlayer,
        ai::{glue::HyperParameter, luna::Luna},
        const_tile::pos,
        fen, PacoAction, PacoBoard,
    };

    /// Verify that the AI can find the correct defense move in a simple position.
    #[tokio::test]
    async fn ai_finds_correct_defense_move() {
        let fen_string = "rq1pkbnr/1pp2ppp/p7/1E6/2D5/4f3/P2PPPPP/RNB1KBNR b 0 AHah - -";
        let mut board = fen::parse_fen(fen_string).unwrap();
        board.execute(PacoAction::Lift(pos("a6"))).unwrap();

        let ai_context = Luna::new(HyperParameter {
            exploration: 0.1,
            power: 20,
        });

        let mut player = MctsPlayer::new(board, ai_context).await.unwrap();
        player.think_for(20).await.expect("Error in think_for");
        let best_action = player.best_action().expect("Error in best_action");
        assert_eq!(best_action, PacoAction::Place(pos("b5")));
    }

    /// Verify that the AI can properly trace a sako sequence.
    #[tokio::test]
    async fn ai_finds_correct_attack_move() {
        let fen_string = "r2k1b1r/ppp2p1p/4p3/1O1An2e/3NF3/3wP3/PPP1B1PP/R2K3R b 0 AHah - -";
        let board = fen::parse_fen(fen_string).unwrap();

        let ai_context = Luna::new(HyperParameter {
            exploration: 0.1,
            power: 100,
        });

        let mut player = MctsPlayer::new(board, ai_context).await.unwrap();
        player.think_for(100).await.expect("Error in think_for");
        let best_action = player.best_action().expect("Error in best_action");
        assert_eq!(best_action, PacoAction::Lift(pos("e6")));
    }
}
