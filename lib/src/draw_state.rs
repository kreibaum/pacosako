//! All code related to checking draws.
//! There are two types of draw checks:
//! - Game is drawn after 100 half-moves without "progress".
//! - Game is drawn after 3-fold repetition.

use std::hash::{Hash, Hasher};

use fxhash::{FxHashMap, FxHasher};
use serde::{Deserialize, Serialize};

use crate::{setup_options::SetupOptions, DenseBoard, VictoryState};

/// Combines all the drawing logic into one struct.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DrawState {
    /// The half move counter counts up for every move that is done in the game.
    /// If the move made progress, then it is reset to 0 after the move.
    /// Progress is:
    ///  - Increasing the amount of dancing pieces by forming a pair.
    ///  - Promoting a pawn.
    ///
    /// Unlike regular chess moving a pawn forward does not count as progress.
    /// Castling does not count as progress either, just like in regular chess.
    pub no_progress_half_moves: u8,
    /// For legacy reasons, we must support a mode where a draw isn't reached
    /// after 3 repetitions. This is why we have a configuration value for this.
    pub draw_after_n_repetitions: u8,
    /// Settled positions that have been seen and how often they have been seen.
    /// This is used to check for draws. Since we can never see a position
    /// again after progress has been made, we can clear this map to save memory.
    /// The key is the hash of the board, the value is the number of times
    /// the board has been seen. This risks some bugs if the hash function
    /// is not perfect, but it should be good enough for real world use.
    /// This property is included in the hash of the board.
    ///
    /// This property is not included in the hash of the board, nor is it
    /// in equality checks.
    pub draw_check_map: FxHashMap<u64, u8>,
}

impl DrawState {
    /// Register that no progress was made in the move.
    /// This should already be tracked during lift, or in-chain promotion can'
    /// properly reset the counter.
    pub fn half_move_with_no_progress(&mut self) {
        self.no_progress_half_moves += 1;
    }

    /// Call this to reset the half move counter.
    /// This also clears the draw_check_map, als we can never see a position
    /// again after progress has been made.
    /// The allocated memory is kept for reuse.
    pub fn reset_half_move_counter(&mut self) {
        self.no_progress_half_moves = 0;
        self.draw_check_map.clear();
    }

    pub fn with_options(options: &SetupOptions) -> DrawState {
        DrawState {
            draw_after_n_repetitions: options.draw_after_n_repetitions,
            ..Default::default()
        }
    }
}

impl Default for DrawState {
    fn default() -> Self {
        Self {
            no_progress_half_moves: 0,
            draw_after_n_repetitions: 3,
            draw_check_map: FxHashMap::default(),
        }
    }
}

/// This records the current position in the draw_check_map.
/// This should be called after every move when the board is settled again.
///
/// We pass in the board instead of using the board in the state, because
/// otherwise the borrow checker would complain. (Pointer aliasing)
///
/// This function also checks if the game is drawn after 3-fold repetition.
/// If the repetition is switched off, then this function does nothing.
///
/// Additionally, this function checks if the game is drawn after 100 half-moves
pub fn record_position(board: &mut DenseBoard) {
    if board.victory_state != VictoryState::Running {
        return;
    }

    if board.draw_state.no_progress_half_moves >= 100 {
        board.victory_state = VictoryState::NoProgressDraw;
        return;
    }

    // If the repetition is switched off, then we don't need to do anything.
    if board.draw_state.draw_after_n_repetitions == 0 {
        return;
    }

    let hash = calculate_hash(board);
    let count = board.draw_state.draw_check_map.entry(hash).or_insert(0);
    *count += 1;

    if *count >= board.draw_state.draw_after_n_repetitions {
        board.victory_state = VictoryState::RepetitionDraw;
    }
}

fn calculate_hash(board: &DenseBoard) -> u64 {
    let mut s = FxHasher::default();

    // We care about the board state.
    board.substrate.hash(&mut s);
    // We care about the current player.
    board.controlling_player.hash(&mut s);
    // We care about en passant and castling.
    board.en_passant.hash(&mut s);
    board.castling.hash(&mut s);

    s.finish()
}

// Hash is allowed to be more lenient than Eq.
// #[allow(clippy::derive_hash_xor_eq)]
impl std::hash::Hash for DrawState {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.no_progress_half_moves.hash(state);
        // self.draw_check_map.hash(state);
    }
}

// Implement custom equality check, because we don't want to compare the
// draw_check_map.
impl PartialEq for DrawState {
    fn eq(&self, other: &Self) -> bool {
        self.no_progress_half_moves == other.no_progress_half_moves
    }
}

impl Eq for DrawState {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PacoAction;
    use crate::PacoBoard;

    /// Helper macro to execute moves in unit tests.
    macro_rules! execute_action {
        ($board:expr, lift, $square:expr) => {{
            $board
                .execute(PacoAction::Lift($square.try_into().unwrap()))
                .unwrap();
        }};
        ($board:expr, place, $square:expr) => {{
            $board
                .execute(PacoAction::Place($square.try_into().unwrap()))
                .unwrap();
        }};
        ($board:expr, promote, $pieceType:expr) => {{
            $board.execute(PacoAction::Promote($pieceType)).unwrap();
        }};
    }

    /// Just moving a knight pair back and forth should result in a draw.
    #[test]
    fn test_simple_knight_repetition() {
        let mut board = DenseBoard::default();
        board.draw_state.draw_after_n_repetitions = 3;

        execute_action!(board, lift, "g1");
        execute_action!(board, place, "f3");
        execute_action!(board, lift, "b8");
        execute_action!(board, place, "c6");

        execute_action!(board, lift, "f3");
        execute_action!(board, place, "e5");
        execute_action!(board, lift, "c6");
        execute_action!(board, place, "e5");

        execute_action!(board, lift, "e5");
        execute_action!(board, place, "f3");
        execute_action!(board, lift, "f3");
        execute_action!(board, place, "e5");

        execute_action!(board, lift, "e5");
        execute_action!(board, place, "f3");
        execute_action!(board, lift, "f3");
        execute_action!(board, place, "e5");

        assert_eq!(board.victory_state, VictoryState::RepetitionDraw);
    }
}
