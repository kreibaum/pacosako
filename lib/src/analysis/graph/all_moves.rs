//! Module for functions like "determine all moves" that are used in analysis
//! but already required for Ŝako detection.

use crate::analysis::graph::edge::FirstEdge;
use crate::analysis::graph::{breadth_first_search, Graph};
use crate::{DenseBoard, PacoBoard, PacoError};

pub fn determine_all_reachable_settled_states(
    board: DenseBoard,
) -> Result<Graph<DenseBoard, FirstEdge>, PacoError> {
    breadth_first_search(
        board,
        |board, _hash, _g, ctx| {
            if ctx.player_changed || board.victory_state.is_over() {
                return Some(board.clone());
            } else {
                None
            }
        },
        |todo| todo.actions(),
    )
}
