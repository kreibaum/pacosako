//! This module implements monte carlo tree search with a neural network.
//! The special thing for Paco Ŝako is, that each player can execute several
//! actions in a row.
//!
//! We also need the MCTS to be externally driven, like a rust async task.
//! This means we can stop it at any time and we also do the model evaluation
//! outside of the MCTS. That is required to have it work with sync & async eval.

use pacosako::{DenseBoard, PacoAction, PacoBoard, PlayerColor};
use thiserror::Error;
use MctsError::*;

/// Using thiserror to define custom error types.
#[derive(Error, Debug)]
pub enum MctsError {
    #[error("No node selected for expansion.")]
    NoNodeSelectedForExpansion,
}

pub struct Mcts {
    board: DenseBoard,
    nodes: Vec<Node>,
    max_size: u16,
    to_expand: Option<(Node, DenseBoard)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct NodeIndex(u16);

/// The value of a node from the perspective of the white player.
/// This way we make it clear which perspective we are talking about.
#[derive(Debug, Clone, Copy)]
struct WhiteValue(f32);

impl WhiteValue {
    fn from_perspective(value: f32, perspective: PlayerColor) -> Self {
        match perspective {
            PlayerColor::White => WhiteValue(value),
            PlayerColor::Black => WhiteValue(-value),
        }
    }

    fn for_perspective(&self, controlling_player: PlayerColor) -> f32 {
        match controlling_player {
            PlayerColor::White => self.0,
            PlayerColor::Black => -self.0,
        }
    }
}

struct Node {
    parent: NodeIndex,
    controlling_player: PlayerColor,

    // From the neural network
    value: WhiteValue,
    policy: Vec<(PacoAction, f32)>,

    // Graph information
    children: Vec<NodeIndex>,
    child_visits: Vec<u16>,
    index_in_parent_vectors: u8,
    // Decision information
    q_value_totals: Vec<f32>,
}

/// Tells the executor what to do next.
pub enum MctsPoll<'a> {
    SelectNodeToExpand,
    Evaluate(&'a DenseBoard),
    AtMaxSize,
}

impl Mcts {
    pub fn new(board: DenseBoard, max_size: u16) -> Self {
        let nodes = Vec::with_capacity(max_size as usize);
        let root = Node {
            // The root node points to itself, that is how we know it is the root.
            // Any recursion up the tree will stop at the root node.
            parent: NodeIndex(0),
            controlling_player: board.controlling_player(),
            index_in_parent_vectors: 0,
            value: WhiteValue(0.),
            policy: Vec::new(), // Vec::new() will not allocate memory.
            children: Vec::new(),
            child_visits: Vec::new(),
            q_value_totals: Vec::new(),
        };
        Mcts {
            board: board.clone(),
            nodes,
            max_size,
            to_expand: Some((root, board)),
        }
    }

    pub fn poll(&self) -> MctsPoll {
        if let Some((_, ref board)) = self.to_expand {
            MctsPoll::Evaluate(board)
        } else if self.nodes.len() >= self.max_size as usize {
            MctsPoll::AtMaxSize
        } else {
            MctsPoll::SelectNodeToExpand
        }
    }

    /// Tells the MCTS executor which node should be expanded next.
    pub fn evaluation_todo(&self) -> Option<&DenseBoard> {
        self.to_expand.as_ref().map(|(_, board)| board)
    }

    /// Call this when the MCTS waits for a model evaluation to drive it forward.
    pub fn insert_model_evaluation(
        &mut self,
        value: f32,
        policy: Vec<(PacoAction, f32)>,
    ) -> Result<(), MctsError> {
        // Verify that we are in the correct state to insert the model evaluation.
        let Some((mut to_expand, _)) = self.to_expand.take() else {
            return Err(NoNodeSelectedForExpansion);
        };

        // Insert the model evaluation into the node.
        let white_value = WhiteValue::from_perspective(value, to_expand.controlling_player);
        to_expand.value = white_value;
        to_expand.policy = policy;

        // Prepare the children information
        to_expand.children = vec![NodeIndex(0); to_expand.policy.len()];
        to_expand.child_visits = vec![0; to_expand.policy.len()];

        // Cache q values for the children. ???

        // Place the node in the nodes vector.
        let index = NodeIndex(self.nodes.len() as u16);
        let parent = to_expand.parent;
        let index_in_parent_vectors = to_expand.index_in_parent_vectors;
        self.nodes.push(to_expand);

        // Backpropagate the value to the root node.
        // This should be at the end so we have a shot at tail call optimization.
        self.backpropagate(parent, index, index_in_parent_vectors, white_value)
    }

    fn backpropagate(
        &mut self,
        parent_index: NodeIndex,
        child_index: NodeIndex,
        index_in_parent_vectors: u8,
        white_value: WhiteValue,
    ) -> Result<(), MctsError> {
        if child_index == parent_index {
            // We can finish the backpropagation here. The root node is marked with parent == 0, index = 0.
            return Ok(());
        }
        let parent = &mut self.nodes[parent_index.0 as usize];

        parent.children[index_in_parent_vectors as usize] = child_index;
        parent.child_visits[index_in_parent_vectors as usize] += 1;
        parent.q_value_totals[index_in_parent_vectors as usize] +=
            white_value.for_perspective(parent.controlling_player);

        // Continue the backpropagation.
        let grand_parent_index = parent.parent;
        let parent_index_in_grand_parent_vectors = parent.index_in_parent_vectors;
        self.backpropagate(
            grand_parent_index,
            parent_index,
            parent_index_in_grand_parent_vectors,
            white_value,
        )
    }

    pub fn max_size_reached(&self) -> bool {
        self.nodes.len() >= self.max_size as usize
    }
}
