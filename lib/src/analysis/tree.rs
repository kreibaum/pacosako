//! Utility functions for tree manipulation.
//!
//! The rules in here are, that you are not allowed to reference any of our Paco
//! Ŝako specific data structures. I hope that way the core graph algorithms are
//! more easily understood.

use std::{
    collections::HashMap,
    hash::{BuildHasher, Hash},
};

/// This is a redesign of the trace_first_move function.
/// It still accepts a target state, but the map of edges is slightly different.
/// For the initial edge $initial, the connection $initial -> $x via $action is
/// represented as $x -> ($action, $initial). The original representation
/// was $x -> ($action, None). Where $initial is not part of the HashMap.
/// This means we now check if a state is initial by not finding it in the
/// HashMap. (Before, we would not have the initial state anywhere at all.)
pub fn trace_first_move_redesign_sparse<Node, Edge, S: BuildHasher>(
    start_from: &Node,
    found_via: &HashMap<Node, (Edge, Node), S>,
) -> Option<Vec<Edge>>
where
    Node: Hash + Eq,
    Edge: Clone,
{
    let mut trace: Vec<Edge> = Vec::new();
    let mut pivot = start_from;

    loop {
        let parent = found_via.get(pivot);
        let Some(parent) = parent else {
            // We have reached the initial state.
            trace.reverse();
            return Some(trace);
        };
        let (action, parent) = parent;
        trace.push(action.clone());
        pivot = parent;
    }
}
