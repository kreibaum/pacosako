//! Using petgraph to implement a Monte Carlo Tree Search.
//! This is using a directed GraphMap.

use std::cmp::min;

use super::{
    colored_value::ColoredValue,
    glue::{action_to_action_index, AiContext},
    math::logit_normal,
};
use crate::{DenseBoard, PacoAction, PacoBoard, PacoError, PlayerColor};
use petgraph::{graph::NodeIndex, stable_graph::StableGraph, Direction::Incoming};
use petgraph::{visit::EdgeRef, Direction::Outgoing};
use smallvec::SmallVec;

/// This is the main struct for the MCTS algorithm.
/// It manages the search graph and the board.
pub struct MctsPlayer<Ai: AiContext> {
    graph: Graph,
    root: NodeIndex,
    board: DenseBoard,
    ai: Ai,
    /// How many nodes have we expanded so far.
    invested_power: usize,
}

impl<Ai: AiContext> MctsPlayer<Ai> {
    pub async fn new(board: DenseBoard, ai: Ai) -> Result<Self, PacoError> {
        let graph = init_search_graph(&board, &ai).await?;
        let root = graph.node_indices().next().unwrap();

        Ok(Self {
            graph,
            root,
            board,
            ai,
            invested_power: 1,
        })
    }
    /// Apply the MCTS algorithm for up to n iterations, or until the invested
    /// power reaches the given limit ai.hyper_parameter().power.
    pub async fn think_for(&mut self, n: usize) -> Result<usize, PacoError> {
        let n = min(n, self.ai.hyper_parameter().power - self.invested_power);
        for _ in 0..n {
            expand_tree_by_one(&mut self.graph, self.root, &self.board, &self.ai).await?;
            self.invested_power += 1;
        }
        Ok(n)
    }
    /// Get the best action for the current board.
    /// This is the action with the highest visit counter.
    /// If there are multiple actions with the same visit counter, we choose
    /// one of them randomly, biased towards later ones.
    pub fn best_action(&self) -> Result<PacoAction, PacoError> {
        let mut best_action = None;
        let mut best_visit_counter = 0.0;
        for edge in self.graph.edges(self.root) {
            let visit_counter = edge.weight().visit_counter;
            if visit_counter > best_visit_counter {
                best_visit_counter = visit_counter;
                best_action = Some(edge.weight().action);
            } else if visit_counter == best_visit_counter && rand::random() {
                best_action = Some(edge.weight().action);
            }
        }
        best_action.ok_or(PacoError::NoLegalActions)
    }
    /// Apply an action to the board and update the search graph.
    /// For now we just drop the search graph and start over.
    /// TODO: We should be able to reuse the search graph. That also unlocks
    /// pondering.
    pub async fn apply_action(&mut self, action: PacoAction) -> Result<(), PacoError> {
        self.board.execute(action)?;
        self.graph = init_search_graph(&self.board, &self.ai).await?;
        self.root = self.graph.node_indices().next().unwrap();
        self.invested_power = 1;
        Ok(())
    }
}

const MCTS_EPSILON: f32 = 1e-6;

type Graph = StableGraph<NodeData, EdgeData>;

#[derive(Debug)]
enum NodeData {
    Unexpanded,
    // A node that has been expanded. We make sure that each node that is
    // Expanded has at least one outgoing edge.
    Expanded {
        model_value: f32,
        current_player: PlayerColor,
    },
    // A node that has been expanded and has no further outgoing edges.
    // This usually happens when the game is over but can also happen when
    // loops get stuck on a blocked pawn.
    GameOver {
        value: ColoredValue,
    },
}

struct EdgeData {
    // The action this edge represents.
    action: PacoAction,
    // The player that made this action.
    current_player: PlayerColor,
    // How often have we visited this edge.
    visit_counter: f32,
    // The total reward we earned from this edge.
    total_reward: f32,
    // A precomputed total_reward / visit_counter that is safe against divide by 0.
    expected_reward: f32,
    // The policy prior for this edge.
    model_policy: f32,
}

async fn init_search_graph(board: &DenseBoard, ai: &impl AiContext) -> Result<Graph, PacoError> {
    let mut g = StableGraph::new();

    let root_node = g.add_node(NodeData::Unexpanded);
    expand_node(&mut g, root_node, board, ai, ai.hyper_parameter().noise).await?;

    Ok(g)
}

async fn expand_tree_by_one(
    g: &mut Graph,
    root: NodeIndex,
    board: &DenseBoard,
    ai: &impl AiContext,
) -> Result<(), PacoError> {
    // Descending to a leaf work a bit different from the Jtac implementation.
    // Instead of mutating the board, we just keep track of the actions we
    // would need to apply to get to the leaf.
    // Then we only need to actually apply the actions to the board if we hit
    // an unexpanded node. Any terminal node will have a value and we can
    // just backpropagate that. This is more efficient for end game situations.
    let (leaf, trace) = descend_to_leaf(g, root, ai, SmallVec::new())?;

    // Check if the leaf is unexpanded.
    let existing_value = g.node_weight(leaf).expect("Node should exist").value();
    if let Some(value) = existing_value {
        backpropagate(g, leaf, value);
        return Ok(());
    }

    // Apply the actions to the board.
    let mut board = board.clone();
    for action in trace {
        board.execute_trusted(action)?;
    }

    let value = expand_node(g, leaf, &board, ai, 0.0).await?;
    backpropagate(g, leaf, value);

    Ok(())
}

/// Expands a node. This means that we apply the model to the board and create
/// all the outgoing edges.
async fn expand_node(
    g: &mut Graph,
    node: NodeIndex,
    board: &DenseBoard,
    ai: &impl AiContext,
    noise: f32,
) -> Result<ColoredValue, PacoError> {
    // Check that the node is unexpanded. Otherwise just return the value.
    let existing_value = g.node_weight(node).expect("Node should exist").value();
    if let Some(value) = existing_value {
        return Ok(value);
    }

    // Handle special case where the game is over.
    if board.victory_state.is_over() {
        return expand_node_trivial(g, node, board);
    }

    let node_data = g.node_weight_mut(node).expect("Node should exist");

    // Handle special case with no actions
    let all_actions = board.actions()?;
    let current_player = board.controlling_player();
    if all_actions.is_empty() {
        // This is the special state where the ai chained into a blocked pawn.
        // For the MCTS search, this counts as loosing the game.
        let value = ColoredValue::new_for_player(-1.0, current_player);
        *node_data = NodeData::GameOver { value };
        return Ok(value);
    }

    // Handle general case with at least one action. Only this case needs to
    // evaluate the model.
    let model_response = ai.apply_model(board).await?;
    let model_value = model_response[0];

    *node_data = NodeData::Expanded {
        model_value,
        current_player,
    };

    let logit_noise = logit_normal(all_actions.len(), noise);

    // Sum up the model policy to normalize it, only looking at the actions
    // that are actually possible.
    let mut model_policy_sum = MCTS_EPSILON;
    for (i, action) in all_actions.iter().enumerate() {
        let action_index = action_to_action_index(*action);
        model_policy_sum += model_response[action_index as usize] + logit_noise[i];
    }

    for (i, &action) in all_actions.iter().enumerate() {
        let action_index = action_to_action_index(action);
        // Add random noise for symmetry breaking.
        let noise: f32 = rand::random();
        let model_policy = (model_response[action_index as usize] + logit_noise[i])
            / model_policy_sum
            + noise * MCTS_EPSILON;

        let child_node = g.add_node(NodeData::Unexpanded);
        let child_edge_data = EdgeData {
            action,
            current_player,
            visit_counter: 0.0,
            total_reward: 0.0,
            expected_reward: 0.0,
            model_policy,
        };
        g.add_edge(node, child_node, child_edge_data);
    }

    Ok(ColoredValue::new_for_player(model_value, current_player))
}

/// For a node where the game is already over, we can just set the value.
/// This can be done over and over again without changing the graph structure.
fn expand_node_trivial(
    g: &mut Graph,
    node: NodeIndex,
    board: &DenseBoard,
) -> Result<ColoredValue, PacoError> {
    let value = ColoredValue::new_for_victory_state(board.victory_state());
    let node_data = g.node_weight_mut(node).expect("Node should exist");
    *node_data = NodeData::GameOver { value };
    Ok(value)
}

type ActionTrace = SmallVec<[PacoAction; 64]>;

/// Descend the tree until we reach a leaf node. This is either an unexpanded
/// node or a node where the game is over.
fn descend_to_leaf(
    g: &mut Graph,
    node: NodeIndex,
    ai: &impl AiContext,
    trace: ActionTrace,
) -> Result<(NodeIndex, ActionTrace), PacoError> {
    let node_data = g.node_weight(node).expect("Node should exist");

    let NodeData::Expanded { .. } = node_data else {
        return Ok((node, trace));
    };

    let (child_node, trace) = follow_best_edge(g, node, ai, trace);

    descend_to_leaf(g, child_node, ai, trace)
}

/// Find the edge with maximal confidence, based on a policy informed upper
/// confidence bound (puct).
fn follow_best_edge(
    g: &Graph,
    node: NodeIndex,
    ai: &impl AiContext,
    mut trace: ActionTrace,
) -> (NodeIndex, ActionTrace) {
    let edges: Vec<_> = g.edges_directed(node, Outgoing).collect();

    // The constant MCTS_EPSILON is added to make sure that the model policy
    // matters for finding the maximum even if visit counter is always 0.
    // The general relation is "exploration ~ sqrt( node visits )".
    let exploration_weight = ai.hyper_parameter().exploration
        * edges
            .iter()
            .map(|e| e.weight().visit_counter)
            .sum::<f32>()
            .sqrt()
        + MCTS_EPSILON;

    let mut max_puct = f32::NEG_INFINITY;
    let mut max_edge = None;

    for edge in edges {
        let explore =
            exploration_weight * edge.weight().model_policy / (1.0 + edge.weight().visit_counter);
        let puct = edge.weight().expected_reward + explore;

        if puct > max_puct {
            max_puct = puct;
            max_edge = Some(edge);
        }
    }

    let max_edge = max_edge.expect("At least one edge should exist");

    trace.push(max_edge.weight().action);

    (max_edge.target(), trace)
}

impl NodeData {
    fn value(&self) -> Option<ColoredValue> {
        match self {
            NodeData::Unexpanded => None,
            NodeData::Expanded {
                model_value,
                current_player,
            } => Some(ColoredValue::new_for_player(*model_value, *current_player)),
            NodeData::GameOver { value } => Some(*value),
        }
    }
}

// This recursively takes the value of the node and adds it to the edge that
// leads to it. Then it does the same for the parent node.
fn backpropagate(g: &mut Graph, node: NodeIndex, value: ColoredValue) {
    let node_value = g
        .node_weight(node)
        .expect("Node should exist")
        .value()
        .expect("Node should have a value");

    let edge = g
        .edges_directed(node, Incoming)
        .next()
        .map(|e| (e.id(), e.source()));

    let Some((edge, parent)) = edge else {
        return; // We are at the root node.
    };

    let edge_data = g.edge_weight_mut(edge).expect("Edge should exist");

    edge_data.visit_counter += 1.0;
    edge_data.total_reward += value.value_for(edge_data.current_player);
    edge_data.expected_reward = edge_data.total_reward / edge_data.visit_counter;

    backpropagate(g, parent, node_value);
}
