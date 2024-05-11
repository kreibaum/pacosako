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

const PUCT_EXPLORATION: f32 = 1.41;

/// Using thiserror to define custom error types.
#[derive(Error, Debug)]
pub enum MctsError {
    #[error("No node was selected for expansion.")]
    NoNodeSelectedForExpansion,
    #[error("There is already a node selected for expansion.")]
    NodeAlreadySelectedForExpansion,
    #[error("Error in Paco Ŝako: {0}")]
    PacoError(#[from] pacosako::PacoError),
}

pub struct Mcts {
    board: DenseBoard,
    nodes: Vec<Node>,
    max_size: u16,
    // Every time we selecting a node finds a terminal node, we backpropagate this
    // without incurring an additional model evaluation. That is why we call this "free".
    free_backpropagations: u16,
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

impl Node {
    fn new(
        parent: NodeIndex,
        controlling_player: PlayerColor,
        index_in_parent_vectors: u8,
    ) -> Self {
        Node {
            parent,
            controlling_player,
            value: WhiteValue(0.),
            policy: Vec::new(), // Vec::new() will not allocate memory.
            children: Vec::new(),
            child_visits: Vec::new(),
            index_in_parent_vectors,
            q_value_totals: Vec::new(),
        }
    }

    /// Selects the child node with the highest upper confidence bound (UCB) value.
    /// Returns the index of the selected child.
    ///
    /// Returns None if there are no children to select.
    /// This represents a terminal node, game over.
    fn select_child_ucb(&self) -> Option<u8> {
        if self.children.is_empty() {
            return None;
        }

        let mut max_ucb = f32::NEG_INFINITY;
        let mut selected_child: u8 = 0;

        let total_visits = self.child_visits.iter().sum::<u16>() as f32;
        let total_visits_sqrt = (1. + total_visits).sqrt();
        for i in 0..self.children.len() {
            let policy = self.policy[i].1;
            let q_value_total = self.q_value_totals[i];
            let child_visits = self.child_visits[i] as f32;
            let q_value = q_value_total / child_visits;

            let visit_scale = total_visits_sqrt / (1. + child_visits);

            let ucb_value = q_value + PUCT_EXPLORATION * policy * visit_scale;

            if ucb_value > max_ucb {
                max_ucb = ucb_value;
                selected_child = i as u8;
            }
        }

        Some(selected_child)
    }
}

/// Tells the executor what to do next.
pub enum MctsPoll<'a> {
    SelectNodeToExpand,
    Evaluate(&'a DenseBoard),
    AtMaxSize,
    // Every time we selecting a node finds a terminal node, we backpropagate and increase this.
    OutOfFreeBackpropagations,
}

impl Mcts {
    pub fn new(board: DenseBoard, max_size: u16) -> Self {
        let nodes = Vec::with_capacity(max_size as usize);
        let root = Node::new(NodeIndex(0), board.controlling_player(), 0);
        Mcts {
            board: board.clone(),
            nodes,
            max_size,
            free_backpropagations: 0,
            to_expand: Some((root, board)),
        }
    }

    /// Tells the executor what to do next.
    pub fn poll(&self) -> MctsPoll {
        if let Some((_, ref board)) = self.to_expand {
            MctsPoll::Evaluate(board)
        } else if self.nodes.len() >= self.max_size as usize {
            MctsPoll::AtMaxSize
        } else if self.nodes.len() + self.free_backpropagations as usize >= (u16::MAX - 1) as usize
        {
            MctsPoll::OutOfFreeBackpropagations
        } else {
            MctsPoll::SelectNodeToExpand
        }
    }

    /// Call this when the MCTS asks you to select a node to expand.
    /// This will walk down the tree to select a node to expand.
    pub fn select_node_to_expand(&mut self) -> Result<(), MctsError> {
        // Verify that we are in the correct state to select a node to expand.
        if self.to_expand.is_some() {
            return Err(NodeAlreadySelectedForExpansion);
        };

        self.walk_down_tree(NodeIndex(0), self.board.clone())
    }

    fn walk_down_tree(
        &mut self,
        node_index: NodeIndex,
        mut board: DenseBoard,
    ) -> Result<(), MctsError> {
        let node = &mut self.nodes[node_index.0 as usize];

        // Whenever we walk down the tree, we can expect that all the nodes have
        // received a model evaluation already. Any "not existing yet" nodes are
        // represented by a NodeIndex(0) entry in the children vector.

        // The root node can't be in a children vector, so it's not a problem,
        // that we use NodeIndex(0) as a special value.

        // Find the child with the highest upper confidence bound (UCB) value.
        let Some(child_index) = node.select_child_ucb() else {
            // If there is no child, then we backpropagate the value to the root node.
            let parent_index = node.parent;
            let child_index = node_index;
            let index_in_parent_vectors = node.index_in_parent_vectors;
            let white_value = node.value;

            self.free_backpropagations += 1;

            return self.backpropagate(
                parent_index,
                child_index,
                index_in_parent_vectors,
                white_value,
            );
        };

        // Execute the action on the board.
        let child_action = node.policy[child_index as usize].0;
        board.execute_trusted(child_action)?;

        let child_node_index = node.children[child_index as usize];

        if child_node_index == NodeIndex(0) {
            // We have found a non-expanded node. Note this down and return.
            self.to_expand = Some((
                Node::new(node_index, board.controlling_player(), child_index),
                board,
            ));

            Ok(())
        } else {
            // Continue walking down the tree.
            self.walk_down_tree(child_node_index, board)
        }
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
        to_expand.q_value_totals = vec![0.; to_expand.policy.len()];

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
}
