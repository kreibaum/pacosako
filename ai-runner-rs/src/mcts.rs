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

use crate::evaluation::ModelEvaluation;

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
    #[error("Root node has no children.")]
    RootNodeHasNoChildren,
    #[error("Root node does not have this action available.")]
    ActionNotInPolicy,
    // This error fires when an action tries to access the root but that wasn't
    // expanded yet.
    #[error("Root node has not been expanded yet.")]
    RootNodeNotExpandedYet,
}

#[derive(Debug, Clone)]
pub struct Mcts {
    board: DenseBoard,
    nodes: Vec<Node>,
    max_size: u16,
    // Every time we selecting a node finds a terminal node, we backpropagate this
    // without incurring an additional model evaluation. That is why we call this "free".
    free_backpropagations: u32,
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

#[derive(Debug, Clone)]
pub struct Node {
    parent: NodeIndex,
    controlling_player: PlayerColor,

    // From the neural network
    value: WhiteValue,
    policy: Vec<(PacoAction, f32)>,

    // Graph information
    children: Vec<NodeIndex>,
    child_visits: Vec<u32>,
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

        let total_visits = self.child_visits.iter().sum::<u32>() as f32;
        let total_visits_sqrt = (1. + total_visits).sqrt();
        for i in 0..self.children.len() {
            let policy = self.policy[i].1;
            let q_value_total = self.q_value_totals[i];
            let child_visits = self.child_visits[i] as f32;
            let q_value = q_value_total / (1. + child_visits);

            let visit_scale = total_visits_sqrt / (1. + child_visits);

            let ucb_value = q_value + PUCT_EXPLORATION * policy * visit_scale;

            if ucb_value > max_ucb {
                max_ucb = ucb_value;
                selected_child = i as u8;
            }
        }

        Some(selected_child)
    }

    /// Gets the current visit count by action.
    /// Result is ordered by the visit count.
    pub fn visit_counts(&self) -> Result<Vec<(PacoAction, u32)>, MctsError> {
        if self.children.is_empty() {
            return Err(RootNodeHasNoChildren);
        }

        let mut result = Vec::with_capacity(self.children.len());
        for i in 0..self.children.len() {
            let action = self.policy[i].0;
            let visits = self.child_visits[i];
            result.push((action, visits));
        }
        result.sort_by_key(|(_, visits)| -(*visits as i64));
        Ok(result)
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
            free_backpropagations: 10 * (max_size as u32),
            to_expand: Some((root, board)),
        }
    }

    /// Allows you to directly look at the root node which can be helpful for debugging.
    /// Maybe we'll rebuild the API to move visit_counts to the Node instead, then
    /// this method becomes important.
    pub fn get_root(&self) -> Result<&Node, MctsError> {
        if self.nodes.is_empty() {
            Err(RootNodeNotExpandedYet)
        } else {
            Ok(&self.nodes[0])
        }
    }

    /// Tells the executor what to do next.
    pub fn poll(&self) -> MctsPoll {
        if let Some((_, ref board)) = self.to_expand {
            MctsPoll::Evaluate(board)
        } else if self.nodes.len() >= self.max_size as usize {
            MctsPoll::AtMaxSize
        } else if self.free_backpropagations == 0 {
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

            self.free_backpropagations -= 1;

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
        evaluation: ModelEvaluation,
    ) -> Result<(), MctsError> {
        // Verify that we are in the correct state to insert the model evaluation.
        let Some((mut to_expand, _)) = self.to_expand.take() else {
            return Err(NoNodeSelectedForExpansion);
        };

        // Insert the model evaluation into the node.
        let white_value =
            WhiteValue::from_perspective(evaluation.value, to_expand.controlling_player);
        to_expand.value = white_value;
        to_expand.policy = evaluation.policy;

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

    /// Takes a copy of the sub tree that is found by executing the action.
    /// This helps us reuse a lot of the evaluations, especially when the
    /// lift action was highly concentrated on one action.
    pub fn subtree(&self, action: PacoAction) -> Result<Self, MctsError> {
        let mut new_board = self.board.clone();
        new_board.execute_trusted(action)?;

        // Find the index where the action is in the policy.
        let root = &self.nodes[0];
        let action_index_in_policy = root
            .policy
            .iter()
            .position(|(a, _)| *a == action)
            .ok_or(ActionNotInPolicy)?;

        let new_root_old_node_index = root.children[action_index_in_policy];

        if new_root_old_node_index == NodeIndex(0) {
            // The node we are going to is not expanded yet.
            // We just return a new Mcts with the new board and no nodes.
            return Ok(Mcts::new(new_board, self.max_size));
        }

        // We need to mark the nodes that are in the subtree.
        let mut mark: Vec<bool> = vec![false; self.nodes.len()];
        let mut new_node_index = vec![NodeIndex(0); self.nodes.len()];
        mark[new_root_old_node_index.0 as usize] = true;
        let mut marked_count = 1;
        for i in (new_root_old_node_index.0 as usize + 1)..self.nodes.len() {
            let node = &self.nodes[i];
            if mark[node.parent.0 as usize] {
                mark[i] = true;
                new_node_index[i] = NodeIndex(marked_count);
                marked_count += 1;
            }
        }

        // Now we can copy the nodes.
        let mut new_nodes = Vec::with_capacity(self.max_size as usize);
        for i in 0..self.nodes.len() {
            if mark[i] {
                let old_node = &self.nodes[i];
                let new_node = Node {
                    parent: new_node_index[old_node.parent.0 as usize],
                    controlling_player: old_node.controlling_player,
                    value: old_node.value,
                    policy: old_node.policy.clone(),
                    children: old_node
                        .children
                        .iter()
                        .map(|index| new_node_index[index.0 as usize])
                        .collect(),
                    child_visits: old_node.child_visits.clone(),
                    index_in_parent_vectors: old_node.index_in_parent_vectors,
                    q_value_totals: old_node.q_value_totals.clone(),
                };
                new_nodes.push(new_node);
            }
        }

        Ok(Mcts {
            board: new_board.clone(),
            nodes: new_nodes,
            max_size: self.max_size,
            free_backpropagations: 10 * (self.max_size as u32),
            to_expand: None, // TODO: This should preserve the to_expand, if it is in the subtree.
        })
    }
}
