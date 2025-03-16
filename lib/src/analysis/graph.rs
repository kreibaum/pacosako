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

use crate::trivial_hash::TrivialHashBuilder;
use crate::{calculate_interning_hash, DenseBoard, PacoAction, PacoBoard, PacoError};
use std::borrow::Cow;
use std::collections::hash_map::Entry;
use std::collections::{HashMap, VecDeque};

/// Abstract Graph type. Represents the board state as only a hash.
/// All the nodes are stored in `edges_in.keys` with optional additional
/// data stored in `marked_nodes`.
/// The edges may be stored in `edges_in.values` if this is something
/// your use of the resulting graph needs.
pub struct Graph<NodeMarker, E:EdgeData> {
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

/// Edge data that only tracks the first edge
pub struct FirstEdge {
    pub action: PacoAction,
    pub from_hash: u64,
}

pub trait EdgeData {
    fn init(action: PacoAction, from_hash: u64) -> Self;
    fn update(&mut self, action: PacoAction, from_hash: u64);
}

impl EdgeData for FirstEdge {
    fn init(action: PacoAction, from_hash: u64) -> Self {
        Self { action, from_hash }
    }
    fn update(&mut self, _action: PacoAction, _from_hash: u64) {
        // Nothing to do, we only track the first edge.
    }
}

pub fn breadth_first_search<M, E: EdgeData>(
    board: impl Into<DenseBoard>,
    marker_function: impl Fn(&DenseBoard, u64, &Graph<M, E>) -> Option<M>,
    is_action_considered: impl Fn(PacoAction) -> bool,
) -> Result<Graph<M, E>, PacoError> {
    // Search context. We search only inside a single move.
    let mut board = board.into();
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
    while let Some(todo) = todo_list.pop_front() {
        let todo_hash = calculate_interning_hash(&todo);
        'action_loop: for action in todo.actions()? {
            if !is_action_considered(action) {
                continue 'action_loop;
            }
            if let Some(marker) = marker_function(&todo, todo_hash, &result) {
                result.marked_nodes.insert(todo_hash, marker);
            }
            let mut next = todo.clone();
            next.execute_trusted(action)?;
            let next_hash = calculate_interning_hash(&next);

            match result.edges_in.entry(next_hash) {
                Entry::Vacant(vacant) => {
                    vacant.insert(E::init(action, todo_hash));
                    if next.controlling_player == search_player {
                        todo_list.push_back(next);
                    }
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
