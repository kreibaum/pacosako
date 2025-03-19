//! I don't exactly have the best track record for sticking with a single
//! graph implementation in this project. This is another attempt at
//! unifying all the graphs used.
//!
//! Specifically, I need to replace:
//!
//! ```none
//! struct ExploredStateAmazon {
//!     pub paco_positions: HashSet<u64, TrivialHashBuilder>,
//!     pub found_via: HashMap<u64, (PacoAction, u64), TrivialHashBuilder>,
//! }
//! ```
//! as well as
//! ```none
//! pub struct ExploredState<T: PacoBoard> {
//!     pub by_hash: FxHashMap<u64, T>,
//!     pub settled: HashSet<u64>,
//!     pub found_via: HashMap<u64, Vec<(PacoAction, Option<u64>)>>,
//! }
//! ```
//! with a single graph implementation.
//!
//! This module makes the assumption, that the hash is free from collisions.

use crate::analysis::graph::edge::EdgeData;
use crate::trivial_hash::TrivialHashBuilder;
use crate::{calculate_interning_hash, DenseBoard, PacoAction, PacoBoard, PacoError};
use std::collections::hash_map::Entry;
use std::collections::{HashMap, VecDeque};

pub mod edge;

/// Abstract Graph type. Represents the board state as only a hash.
/// All the nodes are stored in `edges_in.keys` with optional additional
/// data stored in `marked_nodes`.
/// The edges may be stored in `edges_in.values` if this is something
/// your use of the resulting graph needs.
#[derive(Debug)]
pub struct Graph<NodeMarker, E: EdgeData> {
    pub marked_nodes: HashMap<u64, NodeMarker, TrivialHashBuilder>,
    pub edges_in: HashMap<u64, E, TrivialHashBuilder>,
}

impl<M, E: EdgeData> Default for Graph<M, E> {
    fn default() -> Graph<M, E> {
        Graph {
            marked_nodes: HashMap::with_hasher(TrivialHashBuilder),
            edges_in: HashMap::with_hasher(TrivialHashBuilder),
        }
    }
}

/// Performs a breadth first search through the actions in a move and discovers
/// a graph.
///
/// The `marker_function` is called for every node in the graph.
/// Use it to mark the nodes you are looking for.
///
/// The `is_action_considered` function allows you to further restrict the
/// action set that is considered.
pub fn breadth_first_search<M, E: EdgeData>(
    mut board: DenseBoard,
    marker_function: impl Fn(&DenseBoard, u64, &Graph<M, E>) -> Option<M>,
    is_action_considered: impl Fn(PacoAction) -> bool,
) -> Result<Graph<M, E>, PacoError> {
    // Search context. We search only inside a single move.
    let search_player = board.controlling_player;

    // Working sets / lists. These drive the algorithm.
    let mut todo_list: VecDeque<DenseBoard> = VecDeque::new();

    // Result sets / lists.
    let mut result: Graph<M, E> = Graph {
        marked_nodes: HashMap::default(),
        edges_in: HashMap::default(),
    };

    // Removes the need to copy the draw state.
    // That we have to do this for performance points at a problem with
    // our data model...
    board.draw_state.reset_half_move_counter();
    todo_list.push_back(board);

    // Pull entries from the todo_list until it is empty.
    'todo_loop: while let Some(todo) = todo_list.pop_front() {
        let todo_hash = calculate_interning_hash(&todo);
        if let Some(marker) = marker_function(&todo, todo_hash, &result) {
            result.marked_nodes.insert(todo_hash, marker);
        }
        if todo.controlling_player != search_player {
            // We don't search from these, but still mark them. (just did that)
            continue 'todo_loop;
        }
        'action_loop: for action in todo.actions()? {
            if !is_action_considered(action) {
                continue 'action_loop;
            }
            let mut next = todo.clone();
            next.execute_trusted(action)?;
            let next_hash = calculate_interning_hash(&next);

            match result.edges_in.entry(next_hash) {
                Entry::Vacant(vacant) => {
                    vacant.insert(E::init(action, todo_hash));
                    todo_list.push_back(next);
                }
                Entry::Occupied(mut occupied) => {
                    let edge = occupied.get_mut();
                    edge.update(action, todo_hash);
                }
            }
        }
    }

    Ok(result)
}


/// Follows the "edges_in" map until the "break_at_hash" is reached or there is
/// no more edge to follow.
/// It records the actions taken in a vector.
pub fn trace_actions_back_to<E: EdgeData>(
    start_from_hash: u64,
    break_at_hash: u64,
    edges_in: &HashMap<u64, E, TrivialHashBuilder>,
) -> Vec<PacoAction> {
    let mut trace: Vec<PacoAction> = Vec::new();
    let mut pivot = start_from_hash;

    loop {
        if pivot == break_at_hash {
            trace.reverse();
            return trace;
        }

        let parent = edges_in.get(&pivot);
        let Some(parent) = parent else {
            // We have reached the initial state.
            trace.reverse();
            return trace;
        };
        let (action, next) = parent.first();
        trace.push(action);
        pivot = next;
    }
}