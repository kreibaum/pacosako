//! Functions to check if we are in a Sako position.

use core::fmt::Debug;
use fxhash::{FxHashMap, FxHashSet};
use std::{
    borrow::Cow,
    collections::{hash_map::Entry, VecDeque},
    fmt::Formatter,
    ops::Add,
};

// TODO: This can get more performance by switching from Set<u32> to Set<{0..63}>
// and using a bit board for implementation.

use crate::{
    calculate_interning_hash,
    substrate::{constant_bitboards::KNIGHT_TARGETS, BitBoard, Substrate},
    BoardPosition, DenseBoard, PacoAction, PacoBoard, PacoError, PieceType, PlayerColor,
};

use super::tree;

#[derive(Default)]
pub struct ExploredStateAmazon {
    pub paco_positions: FxHashSet<DenseBoard>,
    pub found_via: FxHashMap<DenseBoard, Vec<(PacoAction, DenseBoard)>>,
}

impl Debug for ExploredStateAmazon {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.write_str(
            format!(
                "ExploredStateAmazon {{ paco_positions: {}, found_via: {} }}",
                self.paco_positions.len(),
                self.found_via.len()
            )
            .as_str(),
        )
    }
}

pub fn is_sako(board: &DenseBoard, for_player: PlayerColor) -> Result<bool, PacoError> {
    let tree = explore_paco_tree(board, for_player)?;

    Ok(!tree.paco_positions.is_empty())
}

pub fn is_sako_sparse(board: &DenseBoard, for_player: PlayerColor) -> Result<bool, PacoError> {
    let tree = explore_paco_tree_sparse(board, for_player)?;

    Ok(!tree.paco_positions.is_empty())
}

pub fn find_paco_sequences(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<Vec<Vec<PacoAction>>, PacoError> {
    let mut tree = explore_paco_tree(board, attacking_player)?;
    tree.found_via.remove(board);

    let mut result = vec![];

    for paco_position in tree.paco_positions.iter() {
        if let Some(trace) = tree::trace_first_move_redesign(paco_position, &tree.found_via) {
            result.push(trace);
        }
    }

    Ok(result)
}

pub fn find_paco_sequences_sparse(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<Vec<Vec<PacoAction>>, PacoError> {
    let board_hash = calculate_interning_hash(board);
    let mut tree = explore_paco_tree_sparse(board, attacking_player)?;
    tree.found_via.remove(&board_hash);

    let mut result = vec![];

    for paco_position in tree.paco_positions.iter() {
        if let Some(trace) = tree::trace_first_move_redesign_sparse(paco_position, &tree.found_via)
        {
            result.push(trace);
        }
    }

    Ok(result)
}

#[derive(Default)]
struct ExploredStateAmazonSparse {
    pub paco_positions: FxHashSet<u64>,
    pub found_via: FxHashMap<u64, (PacoAction, u64)>,
}

/// Variant of tree exploration that stores fewer "found via" entries.
/// Also stores hashes instead of full boards.
fn explore_paco_tree_sparse(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<ExploredStateAmazonSparse, PacoError> {
    let board = normalize_board_for_sako_search(board, attacking_player)?;

    // First, find out if we actually need to do anything.
    let search = reverse_amazon_squares(&board, attacking_player)?;
    if search.starting_tiles.is_empty() {
        return Ok(ExploredStateAmazonSparse::default());
    }

    // We found some starting tiles, this means we actually need to work.
    let mut todo_list: VecDeque<DenseBoard> = VecDeque::new();
    let mut paco_positions: FxHashSet<u64> = FxHashSet::default();
    let mut found_via: FxHashMap<u64, (PacoAction, u64)> = FxHashMap::default();

    // Clone the board (if not already cloned) and correctly set the controlling player.
    let mut board: DenseBoard = board.into_owned();
    board.controlling_player = attacking_player;
    // Clear the draw state to reduce what we need to copy.
    // This is only ok, because we are tracking hashes only that
    board.draw_state.reset_half_move_counter();

    // The paco positions we are interested in are the one that end with a
    // king capture.
    let king_capture_action =
        PacoAction::Place(board.substrate.find_king(attacking_player.other())?);

    // Add the starting positions to the todo list.
    todo_list.push_back(board);

    // Pull entries from the todo_list until it is empty.
    while let Some(todo) = todo_list.pop_front() {
        // Execute all actions within the chaining_tiles.
        'action_loop: for action in todo.actions()? {
            if let PacoAction::Lift(p) = action {
                if !search.starting_tiles.contains(p) {
                    continue 'action_loop;
                }
            } else if let PacoAction::Place(p) = action {
                // Skip actions that are not in the chaining_tiles.
                // Promotions are never skipped.
                if !search.chaining_tiles.contains(p) {
                    continue 'action_loop;
                }
            }
            let mut b = todo.clone();
            b.execute_trusted(action)?;
            let b_hash = calculate_interning_hash(&b);
            let todo_hash = calculate_interning_hash(&todo);

            if action == king_capture_action {
                // We found a paco position!
                paco_positions.insert(b_hash);
            }

            // look up if this action has already been found.
            match found_via.entry(b_hash) {
                // We encounter this state for the first time.
                Entry::Vacant(v_entry) => {
                    v_entry.insert((action, todo_hash));
                    if !b.is_settled() {
                        // We will look at the possible chain moves later.
                        todo_list.push_back(b);
                    }
                }
                // We have seen this state already, nothing to do.
                _ => {}
            }
        }
    }

    Ok(ExploredStateAmazonSparse {
        paco_positions,
        found_via,
    })
}

/// This uses the "reverse amazon algorithm" to find all the possible ways to
/// paco in a board position for a given player.
///
/// This can only be executed on settled boards without any pieces in hand.
///
/// This uses the amazon squares heuristic to shrink or eliminate the (possibly
/// cyclic) tree of all actions within this move.
pub fn explore_paco_tree(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<ExploredStateAmazon, PacoError> {
    let board = normalize_board_for_sako_search(board, attacking_player)?;

    // First, find out if we actually need to do anything.
    let search = reverse_amazon_squares(&board, attacking_player)?;
    if search.starting_tiles.is_empty() {
        return Ok(ExploredStateAmazon::default());
    }

    // We found some starting tiles, this means we actually need to work.
    let mut todo_list: VecDeque<DenseBoard> = VecDeque::new();
    let mut paco_positions: FxHashSet<DenseBoard> = FxHashSet::default();
    let mut found_via: FxHashMap<DenseBoard, Vec<(PacoAction, DenseBoard)>> = FxHashMap::default();

    // Clone the board (if not already cloned) and correctly set the controlling player.
    let mut board: DenseBoard = board.into_owned();
    board.controlling_player = attacking_player;
    // We had the idea to clear the draw state to reduce what we need to copy.
    // This fails the syn6 test. This is because we reach the "starting" position
    // again and then fail to properly remove it.
    // board.draw_state.reset_half_move_counter();

    // The paco positions we are interested in are the one that end with a
    // king capture.
    let king_capture_action =
        PacoAction::Place(board.substrate.find_king(attacking_player.other())?);

    // Add the starting positions to the todo list.
    todo_list.push_back(board);

    // Pull entries from the todo_list until it is empty.
    while let Some(todo) = todo_list.pop_front() {
        // Execute all actions within the chaining_tiles.
        'action_loop: for action in todo.actions()? {
            if let PacoAction::Lift(p) = action {
                if !search.starting_tiles.contains(p) {
                    continue 'action_loop;
                }
            } else if let PacoAction::Place(p) = action {
                // Skip actions that are not in the chaining_tiles.
                // Promotions are never skipped.
                if !search.chaining_tiles.contains(p) {
                    continue 'action_loop;
                }
            }
            let mut b = todo.clone();
            b.execute_trusted(action)?;

            if action == king_capture_action {
                // We found a paco position!
                paco_positions.insert(b.clone());
            }

            // look up if this action has already been found.
            match found_via.entry(b.clone()) {
                // We have seen this state already and don't need to add it to the todo list.
                Entry::Occupied(mut o_entry) => {
                    o_entry.get_mut().push((action, todo.clone()));
                }
                // We encounter this state for the first time.
                Entry::Vacant(v_entry) => {
                    v_entry.insert(vec![(action, todo.clone())]);
                    if !b.is_settled() {
                        // We will look at the possible chain moves later.
                        todo_list.push_back(b);
                    }
                }
            }
        }
    }

    Ok(ExploredStateAmazon {
        paco_positions,
        found_via,
    })
}

/// This eliminates some states that the board could be in. This simplifies the
/// search code a bit. We assure, that:
///
/// - On running chains, the attacking player must be in controll.
/// - On settled boards, this does not matter.
/// - We don't want to deal with the different promotion options in the search.
///   - So if the current move starts with a promotion, we just promote to a queen.
///   - This requires a copy of the board, so we have to return a Cow.
fn normalize_board_for_sako_search(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<Cow<'_, DenseBoard>, PacoError> {
    if !board.is_settled() && board.controlling_player() != attacking_player {
        return Err(PacoError::SearchNotAllowed(
            "Board is not settled but attacking player is not in control.".to_string(),
        ));
    }
    let board = if board.required_action.is_promote() {
        let mut board = board.clone();
        board.execute(PacoAction::Promote(PieceType::Queen))?;
        Cow::Owned(board)
    } else {
        Cow::Borrowed(board)
    };
    Ok(board)
}

/// Holds information which squares are relevant for a paco search.
#[derive(Debug)]
pub struct ReverseAmazonSearchResult {
    pub chaining_tiles: BitBoard,
    pub starting_tiles: BitBoard,
}

/// Tracks all the information that we need during a search.
struct AmazonContext<'a> {
    board: &'a DenseBoard,
    attacking_player: PlayerColor,
    attacking_pieces: BitBoard,
    defending_pieces: BitBoard,
    tiles_seen: BitBoard,
    todo_list: BitBoard,
    starting_tiles: BitBoard,
    chaining_tiles: BitBoard,
    en_passant_tile: Option<BoardPosition>,
    en_passant_slide_from: Option<BoardPosition>,
    en_passant_bb: BitBoard,
    lifted_tile: Option<BoardPosition>,
    lifted_type: Option<PieceType>,
}

impl<'a> AmazonContext<'a> {
    fn new(
        board: &'a DenseBoard,
        attacking_player: PlayerColor,
    ) -> Result<AmazonContext<'a>, PacoError> {
        // Determine if there is an en-passant square we have to care about.
        let (en_passant_tile, en_passant_slide_from) = if let Some(pos) = board.en_passant {
            // Find square the pawn now is on.
            let en_passant_slide_from = pos
                .advance_pawn(attacking_player.other())
                .expect("The en-passant square should never be at the border.");
            // Check if this is a pair. Otherwise we don't care.
            // We need our own piece in the pair there to chain into it.
            if board
                .substrate
                .has_piece(attacking_player, en_passant_slide_from)
            {
                (Some(pos), Some(en_passant_slide_from))
            } else {
                (None, None)
            }
        } else {
            (None, None)
        };

        let mut todo_list = BitBoard::default();
        let king_position = board.substrate.find_king(attacking_player.other())?;
        todo_list.insert(king_position);

        Ok(AmazonContext {
            board,
            attacking_pieces: board.substrate.bitboard_color(attacking_player),
            defending_pieces: board.substrate.bitboard_color(attacking_player.other()),
            attacking_player,
            tiles_seen: BitBoard::default(),
            todo_list,
            starting_tiles: BitBoard::default(),
            chaining_tiles: BitBoard::default(),
            en_passant_tile,
            en_passant_slide_from,
            en_passant_bb: en_passant_tile.into(),
            lifted_tile: board.lifted_piece.position(),
            lifted_type: board.lifted_piece.piece(),
        })
    }

    /// Takes an arbitrary tile from the todo list that was not visited yet and
    /// pops if off the todo list.
    /// We then also track that it has been visited and can be chained through.
    fn pop_todo(&mut self) -> Option<BoardPosition> {
        while !self.todo_list.is_empty() {
            // Get an entry and remove it from the todo list.
            let p = self.todo_list.iter().next().expect("len > 0");
            self.todo_list.remove(p);
            // Check to see if this entry has already been seen.
            if self.tiles_seen.insert(p) {
                self.chaining_tiles.insert(p);
                return Some(p);
            }
        }
        None
    }

    /// Discard the intermediate search context and return the result.
    fn result(self) -> ReverseAmazonSearchResult {
        ReverseAmazonSearchResult {
            chaining_tiles: self.chaining_tiles,
            starting_tiles: self.starting_tiles,
        }
    }
}

/// This is the core of the amazon search. It finds all tiles that are within
/// amazon range of the king. Or within chaining range of the king. The amazon
/// is a fairy piece that can move like a queen and a knight.
///
/// Special care needs to be taken to include the en-passant square as well,
/// if the en-passant pawn is in a pair.
///
/// There could also be an iterated version that checks after the first search
/// which piece types are available and which ones were used. If a piece type
/// was used but not available then we redo the search with restricted piece
/// types. This is not implemented right now. It again requires careful
/// consideration of the en-passant square as well as in-chain promotions.
///
/// Another optimization in an iteration would be to prevent slide through
/// for single attacker pieces that are not part of the starting_tiles set.
pub fn reverse_amazon_squares(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<ReverseAmazonSearchResult, PacoError> {
    // In the first phase, we start at the kings location and then find all the
    // positions that are reachable with amazon chains.
    let mut ctx = AmazonContext::new(board, attacking_player)?;

    while let Some(from) = ctx.pop_todo() {
        knight_targets(&mut ctx, from);

        slide_targets(&mut ctx, from);
    }

    Ok(ctx.result())
}

fn slide_targets(ctx: &mut AmazonContext, from: BoardPosition) {
    let directions = vec![
        (0, 1),
        (1, 1),
        (1, 0),
        (1, -1),
        (0, -1),
        (-1, -1),
        (-1, 0),
        (-1, 1),
    ];

    // In each direction, iterate until we hit a non-empty position.
    for (dx, dy) in directions {
        let mut current = from;
        let mut distance = 0;
        // If there already is a lifted piece in hand, then we can't slide
        // through any other single attacker piece anymore.
        let mut slipped_through_starter = ctx.lifted_tile.is_some();
        'sliding: loop {
            distance += 1;
            let new_tile = current.add((dx, dy));
            if new_tile.is_none() {
                break 'sliding;
            }
            current = new_tile.unwrap();

            if new_tile == ctx.en_passant_tile || new_tile == ctx.en_passant_slide_from {
                // The en-passant tile counts as a potential chaining tile and
                // we can also slide through it. This is also true for the tile
                // the pawn (which would get pulled back) is on.

                // We can still break here, because the en-passant tile
                // is also a chaining tile. That will take care of sliding through.
                ctx.todo_list.insert(current);
                break 'sliding;
            }

            if Some(current) == ctx.lifted_tile
                && we_can_start_from_here(
                    ctx,
                    ctx.lifted_type.expect(
                        "lifted type must always be available when lifted tile is available",
                    ),
                    dx,
                    dy,
                    distance,
                )
            {
                // We can also start from the lifted square.
                ctx.starting_tiles.insert(current);
            }

            let attacking_piece = ctx.board.substrate.get_piece(ctx.attacking_player, current);
            let defending_piece = ctx
                .board
                .substrate
                .get_piece(ctx.attacking_player.other(), current);

            match (attacking_piece, defending_piece) {
                (None, None) => {
                    // Empty square, continue.
                }
                (None, Some(_)) => {
                    // Enemy piece alone, stop.
                    break 'sliding;
                }
                (Some(attacker), None) => {
                    if slipped_through_starter {
                        // We already slipped through a starter piece to get
                        // here. This square is only relevant for chaining.
                        break 'sliding;
                    }
                    // Friendly piece alone, we may start from here.
                    // But we still need a plausibility check if this piece can
                    // actually move to the "from" position.
                    if we_can_start_from_here(ctx, attacker, dx, dy, distance) {
                        ctx.starting_tiles.insert(current);
                    }
                    // If this is the first time this slide that we encounter a
                    // friendly piece, we can still slide through it.
                    if !slipped_through_starter {
                        slipped_through_starter = true;
                    } else {
                        break 'sliding;
                    }
                }
                (Some(_), Some(_)) => {
                    // This is a pair, we can chain from here.
                    // Since chaining can change the piece that is on here,
                    // we can't check anything based on the piece type.
                    ctx.todo_list.insert(current);
                    break 'sliding;
                }
            }
        }
    }
}

fn we_can_start_from_here(
    ctx: &AmazonContext,
    attacker: PieceType,
    dx: i8,
    dy: i8,
    distance: i32,
) -> bool {
    let is_rook_action = dx == 0 || dy == 0;
    if is_rook_action {
        attacker == PieceType::Rook || attacker == PieceType::Queen
    } else {
        // is_bishop_move
        if attacker == PieceType::Bishop || attacker == PieceType::Queen {
            true
        } else if attacker == PieceType::Pawn && distance == 1 {
            // Signs are flipped here, because we are doing a
            // reverse search.
            let pawn_direction = if ctx.attacking_player == PlayerColor::White {
                -1
            } else {
                1
            };
            dy == pawn_direction
        } else {
            false
        }
    }
}

// Knight moves and slides are substantially different, because there is no
// inner "sliding" loop. We just check the position and then we are done.
fn knight_targets(ctx: &mut AmazonContext, from: BoardPosition) {
    let all_targets = KNIGHT_TARGETS[from.0 as usize];

    // Places the knight can come from, which have either a pair or the en_passant tile.
    let chain_options =
        all_targets & ((ctx.attacking_pieces & ctx.defending_pieces) | ctx.en_passant_bb);
    ctx.todo_list.insert_all(chain_options);

    // Places the knight can start from
    // Ideally we would already filter this for "knight only", but we don't have
    // a bitboard for that yet.
    let start_options = all_targets & ctx.attacking_pieces & !ctx.defending_pieces;
    for target in start_options {
        // Special case, if we are already working with a lifted piece.
        if Some(target) == ctx.lifted_tile && Some(PieceType::Knight) == ctx.lifted_type {
            // We can also start from the lifted square.
            ctx.starting_tiles.insert(target);
        } else {
            let is_knight =
                ctx.board
                    .substrate
                    .is_piece(ctx.attacking_player, target, PieceType::Knight);
            if is_knight && ctx.lifted_tile.is_none() {
                ctx.starting_tiles.insert(target);
            }
        }
    }
}

/// Tests module
#[cfg(test)]
mod tests {

    use super::*;
    use crate::{
        analysis::reverse_amazon_search::find_paco_sequences, const_tile::*, fen, DenseBoard,
        PacoAction, PacoBoard, PlayerColor,
    };
    use ntest::timeout;

    use super::reverse_amazon_squares;

    #[test]
    fn sparse_is_just_as_good() {
        for _ in 1..10_000 {
            let board: DenseBoard = rand::random();
            let mut full_tree_result_w = find_paco_sequences(&board, PlayerColor::White).unwrap();
            let mut full_tree_result_b = find_paco_sequences(&board, PlayerColor::Black).unwrap();

            let mut sparse_tree_result_w =
                find_paco_sequences_sparse(&board, PlayerColor::White).unwrap();
            let mut sparse_tree_result_b =
                find_paco_sequences_sparse(&board, PlayerColor::Black).unwrap();

            full_tree_result_w.sort();
            full_tree_result_b.sort();
            sparse_tree_result_w.sort();
            sparse_tree_result_b.sort();

            assert_eq!(full_tree_result_w, sparse_tree_result_w);
            assert_eq!(full_tree_result_b, sparse_tree_result_b);
        }
    }

    #[test]
    #[ignore] // Not really a test...
    fn sparse_vs_full_performance() {
        // First create a vector of 10_000 random boards.
        let mut boards: Vec<DenseBoard> = Vec::with_capacity(10_000);
        for _ in 1..1_000_000 {
            boards.push(rand::random());
        }

        let start = std::time::Instant::now();
        for board in boards.iter() {
            find_paco_sequences_sparse(&board, PlayerColor::White).unwrap();
            find_paco_sequences_sparse(&board, PlayerColor::Black).unwrap();
        }
        let sparse_tree_time = start.elapsed();

        // Then measure the time it takes to find paco sequences for all of them.
        let start = std::time::Instant::now();
        for board in boards.iter() {
            find_paco_sequences(&board, PlayerColor::White).unwrap();
            find_paco_sequences(&board, PlayerColor::Black).unwrap();
        }
        let full_tree_time = start.elapsed();

        println!(
            "Full tree: {:?}, Sparse tree: {:?}",
            full_tree_time, sparse_tree_time
        );

        println!(
            "Improvement pct: {}",
            (full_tree_time.as_nanos() as f64 - sparse_tree_time.as_nanos() as f64)
                / full_tree_time.as_nanos() as f64
        );
        todo!();
    }

    #[test]
    fn initial_board() {
        let search = reverse_amazon_squares(&DenseBoard::new(), PlayerColor::White)
            .expect("Error in reverse amazon search.");

        assert!(search.starting_tiles.is_empty());
        assert_eq!(search.chaining_tiles.len(), 1);
        assert!(search.chaining_tiles.contains(E8));
    }

    #[test]
    fn initial_board_black() {
        let search = reverse_amazon_squares(&DenseBoard::new(), PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        assert!(search.starting_tiles.is_empty());
        assert_eq!(search.chaining_tiles.len(), 1);
        assert!(search.chaining_tiles.contains(E1));
    }

    #[test]
    fn g5692a93w() {
        let board =
            fen::parse_fen("2k1r3/ppc2ppp/3i4/3p1b2/PEtPpB1P/3L1NPB/2P1DP2/5K2 w 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(C2));
        assert!(search.starting_tiles.contains(F4));
        assert_eq!(search.chaining_tiles.len(), 7);
        println!("{:?}", search.chaining_tiles);
        assert!(search.chaining_tiles.contains(E2));
        assert!(search.chaining_tiles.contains(D3));
        assert!(search.chaining_tiles.contains(B4));
        assert!(search.chaining_tiles.contains(C4));
        assert!(search.chaining_tiles.contains(D6));
        assert!(search.chaining_tiles.contains(C7));
        assert!(search.chaining_tiles.contains(C8));
    }

    #[test]
    fn g5692a93b() {
        let board =
            fen::parse_fen("2k1r3/ppc2ppp/3i4/3p1b2/PEtPpB1P/3L1NPB/2P1DP2/5K2 w 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(E4));
        assert!(search.starting_tiles.contains(D5));
        assert_eq!(search.chaining_tiles.len(), 7);
        assert!(search.chaining_tiles.contains(F1));
        assert!(search.chaining_tiles.contains(E2));
        assert!(search.chaining_tiles.contains(D3));
        assert!(search.chaining_tiles.contains(B4));
        assert!(search.chaining_tiles.contains(C4));
        assert!(search.chaining_tiles.contains(D6));
        assert!(search.chaining_tiles.contains(C7));
    }

    #[test]
    fn g5464a32w() {
        // Checks if the en-passant square is handled at all.
        let mut board =
            fen::parse_fen("rnbqkb1r/ppf2p1p/6p1/3D3d/2Bp4/8/PPPP1PPP/RNB1K2R b 0 AHah - -")
                .expect("Error in fen parsing.");

        board.execute_trusted(PacoAction::Lift(C7)).unwrap();
        board.execute_trusted(PacoAction::Place(C5)).unwrap();

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 1);
        assert!(search.starting_tiles.contains(C4));
        assert_eq!(search.chaining_tiles.len(), 5);
        assert!(search.chaining_tiles.contains(C5));
        assert!(search.chaining_tiles.contains(D5));
        assert!(search.chaining_tiles.contains(H5));
        assert!(search.chaining_tiles.contains(C6));
        assert!(search.chaining_tiles.contains(E8));
    }

    #[test]
    fn syn1() {
        // Checks if the en-passant square is pass-through.
        let mut board =
            fen::parse_fen("1n2k1n1/ppp2ppp/3p2NE/6RB/2P3PA/i6C/P2F4/REBQ3K w 0 AHah - -")
                .expect("Error in fen parsing.");

        board.execute_trusted(PacoAction::Lift(pos("d2"))).unwrap();
        board.execute_trusted(PacoAction::Place(pos("d4"))).unwrap();

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 0);
        assert_eq!(search.chaining_tiles.len(), 7);
        assert!(search.chaining_tiles.contains(B1));
        assert!(search.chaining_tiles.contains(H1));
        assert!(search.chaining_tiles.contains(A3));
        assert!(search.chaining_tiles.contains(D3));
        assert!(search.chaining_tiles.contains(H3));
        assert!(search.chaining_tiles.contains(D4));
        assert!(search.chaining_tiles.contains(H4));
    }

    #[test]
    fn syn2() {
        // Checks if we can slide through a single piece.
        let board = fen::parse_fen("rnbqkbnr/pppp1p1p/8/5d2/4P3/4c3/PPPP1PPP/RNBQKB2 w 0 AHah - -")
            .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 3);
        assert!(search.starting_tiles.contains(D2));
        assert!(search.starting_tiles.contains(F2));
        assert!(search.starting_tiles.contains(E4));
        assert_eq!(search.chaining_tiles.len(), 3);
        assert!(search.chaining_tiles.contains(E3));
        assert!(search.chaining_tiles.contains(F5));
        assert!(search.chaining_tiles.contains(E8));
    }

    #[test]
    fn syn3() {
        // Checks that we can't slide though two pieces.
        let board = fen::parse_fen("rn1qkbnr/pppp2pp/4E3/4p3/3Pp3/8/PPP2PPP/RNBQKBNR b 0 AHah - -")
            .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 0);
        assert_eq!(search.chaining_tiles.len(), 1);
        assert!(search.chaining_tiles.contains(E1));
    }

    #[test]
    fn syn4() {
        // Very simple test for the paco sequence search.
        let board = fen::parse_fen("rnbqkbnr/pppppppp/5N2/8/8/8/PPPPPPPP/RNBQKB1R w 0 AHah - -")
            .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);

        let sequences = find_paco_sequences(&board, PlayerColor::White)
            .expect("Error in paco sequence search.");
        println!("{:?}", sequences);

        assert_eq!(sequences.len(), 1);
        assert_eq!(sequences[0].len(), 2);
        assert_eq!(sequences[0][0], PacoAction::Lift(F6));
        assert_eq!(sequences[0][1], PacoAction::Place(E8));
    }

    #[test]
    fn g5661a88w() {
        // A puzzle from the community
        let board = fen::parse_fen("5rk1/ppp2pep/8/1B1AH2D/4f1b1/2N3SP/PPP2DP1/5L1K w 0 AHah - -")
            .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(C3));
        assert!(search.starting_tiles.contains(B5));
        assert_eq!(search.chaining_tiles.len(), 9);
        assert!(search.chaining_tiles.contains(F1));
        assert!(search.chaining_tiles.contains(F2));
        assert!(search.chaining_tiles.contains(G3));
        assert!(search.chaining_tiles.contains(E4));
        assert!(search.chaining_tiles.contains(D5));
        assert!(search.chaining_tiles.contains(E5));
        assert!(search.chaining_tiles.contains(H5));
        assert!(search.chaining_tiles.contains(G7));
        assert!(search.chaining_tiles.contains(G8));

        let mut sequences = find_paco_sequences(&board, PlayerColor::White)
            .expect("Error in paco sequence search.");
        println!("{:?}", sequences);

        // Sort the sequences by length.
        sequences.sort_by_key(|a| a.len());

        // Please note that the algorithm returns all possible end state where
        // the king is captured. And for each such end state we also get one
        // shortest path to it. However, there can be multiple shortest paths
        // and we don't really guarantee which one we get.
        // If we reorder in which order we inspect the moves, positions are
        // found in a different order and the returned sequences change.

        assert_eq!(sequences.len(), 3);
        assert_eq!(sequences[0].len(), 15);
        assert_eq!(sequences[0][0], PacoAction::Lift(C3));
        assert_eq!(sequences[0][1], PacoAction::Place(E4));
        assert_eq!(sequences[0][2], PacoAction::Place(E5));
        assert_eq!(sequences[0][3], PacoAction::Place(E4));
        assert_eq!(sequences[0][4], PacoAction::Place(G3));
        assert_eq!(sequences[0][5], PacoAction::Place(E4));
        assert_eq!(sequences[0][6], PacoAction::Place(E5));
        assert_eq!(sequences[0][7], PacoAction::Place(G7));
        assert_eq!(sequences[0][8], PacoAction::Place(E5));
        assert_eq!(sequences[0][9], PacoAction::Place(E4));
        assert_eq!(sequences[0][10], PacoAction::Place(G3));
        assert_eq!(sequences[0][11], PacoAction::Place(E4));
        assert_eq!(sequences[0][12], PacoAction::Place(E5));
        assert_eq!(sequences[0][13], PacoAction::Place(G7));
        assert_eq!(sequences[0][14], PacoAction::Place(G8));

        assert_eq!(sequences[1].len(), 16);
        assert_eq!(sequences[1][0], PacoAction::Lift(C3));
        assert_eq!(sequences[1][1], PacoAction::Place(E4));
        assert_eq!(sequences[1][2], PacoAction::Place(E5));
        assert_eq!(sequences[1][3], PacoAction::Place(E4));
        assert_eq!(sequences[1][4], PacoAction::Place(F2));
        assert_eq!(sequences[1][5], PacoAction::Place(G3));
        assert_eq!(sequences[1][6], PacoAction::Place(E4));
        assert_eq!(sequences[1][7], PacoAction::Place(E5));
        assert_eq!(sequences[1][8], PacoAction::Place(G7));
        assert_eq!(sequences[1][9], PacoAction::Place(E5));
        assert_eq!(sequences[1][10], PacoAction::Place(E4));
        assert_eq!(sequences[1][11], PacoAction::Place(F2));
        assert_eq!(sequences[1][12], PacoAction::Place(E4));
        assert_eq!(sequences[1][13], PacoAction::Place(E5));
        assert_eq!(sequences[1][14], PacoAction::Place(G7));
        assert_eq!(sequences[1][15], PacoAction::Place(G8));

        assert_eq!(sequences[2].len(), 18);
        assert_eq!(sequences[2][0], PacoAction::Lift(C3));
        assert_eq!(sequences[2][1], PacoAction::Place(E4));
        assert_eq!(sequences[2][2], PacoAction::Place(E5));
        assert_eq!(sequences[2][3], PacoAction::Place(E4));
        assert_eq!(sequences[2][4], PacoAction::Place(G3));
        assert_eq!(sequences[2][5], PacoAction::Place(E4));
        assert_eq!(sequences[2][6], PacoAction::Place(E5));
        assert_eq!(sequences[2][7], PacoAction::Place(G7));
        assert_eq!(sequences[2][8], PacoAction::Place(E5));
        assert_eq!(sequences[2][9], PacoAction::Place(E4));
        assert_eq!(sequences[2][10], PacoAction::Place(F2));
        assert_eq!(sequences[2][11], PacoAction::Place(G3));
        assert_eq!(sequences[2][12], PacoAction::Place(F1));
        assert_eq!(sequences[2][13], PacoAction::Place(F2));
        assert_eq!(sequences[2][14], PacoAction::Place(E4));
        assert_eq!(sequences[2][15], PacoAction::Place(E5));
        assert_eq!(sequences[2][16], PacoAction::Place(G7));
        assert_eq!(sequences[2][17], PacoAction::Place(G8));
    }

    #[test]
    fn g5697a74() {
        // Test that amazon also works with a lifted piece.
        let mut board =
            fen::parse_fen("rn2Srkt/pp3e1p/8/8/1P1AP1bA/4ed2/P1P1F2P/R3K2R b 0 AHah - -")
                .expect("Error in fen parsing.");

        board.execute_trusted(PacoAction::Lift(pos("g4"))).unwrap();

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 1);
        assert!(search.starting_tiles.contains(G4));
        assert_eq!(search.chaining_tiles.len(), 9);
        assert!(search.chaining_tiles.contains(E1));
        assert!(search.chaining_tiles.contains(E2));
        assert!(search.chaining_tiles.contains(E3));
        assert!(search.chaining_tiles.contains(F3));
        assert!(search.chaining_tiles.contains(D4));
        assert!(search.chaining_tiles.contains(H4));
        assert!(search.chaining_tiles.contains(F7));
        assert!(search.chaining_tiles.contains(E8));
        assert!(search.chaining_tiles.contains(H8));
    }

    #[test]
    fn syn5() {
        // After lifting one piece, you can't slide through any other pieces any more.
        let mut board =
            fen::parse_fen("rnb1ks2/pppp1pp1/3q4/7p/1E1p2C1/3P4/P1P1PP1P/RNBQK1NR b 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(D6));
        assert!(search.starting_tiles.contains(H5));
        assert_eq!(search.chaining_tiles.len(), 4);
        assert!(search.chaining_tiles.contains(E1));
        assert!(search.chaining_tiles.contains(B4));
        assert!(search.chaining_tiles.contains(G4));
        assert!(search.chaining_tiles.contains(F8));

        board.execute_trusted(PacoAction::Lift(pos("d6"))).unwrap();

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 1);
        assert!(search.starting_tiles.contains(D6));
        assert_eq!(search.chaining_tiles.len(), 3);
        assert!(search.chaining_tiles.contains(E1));
        assert!(search.chaining_tiles.contains(B4));
        assert!(search.chaining_tiles.contains(F8));

        let sequences = find_paco_sequences(&board, PlayerColor::Black)
            .expect("Error in paco sequence search.");

        println!("{:?}", sequences);
        assert_eq!(sequences.len(), 1);
        assert_eq!(sequences[0].len(), 2);
        assert_eq!(sequences[0][0], PacoAction::Place(B4));
        assert_eq!(sequences[0][1], PacoAction::Place(E1));
    }

    #[test]
    #[timeout(100)]
    fn syn6() {
        use std::vec::Splice;

        // Explores loops that we can get, because starting at an in-chain
        // position, we can loop back to the starting position. We then end
        // up with loops in the directed graph.
        let mut board =
            fen::parse_fen("rn2k1nr/pppppppp/4E2q/8/2E5/8/PP1PKPPP/RNBQ1BNR b 0 AHah - -")
                .expect("Error in fen parsing.");

        board.execute_trusted(PacoAction::Lift(pos("h6"))).unwrap();
        board.execute_trusted(PacoAction::Place(pos("e6"))).unwrap();

        let mut sequences = find_paco_sequences_sparse(&board, PlayerColor::Black)
            .expect("Error in paco sequence search.");

        sequences.sort_by_key(|a| a.len());
        println!("{:?}", sequences);
        assert_eq!(sequences.len(), 3);
        assert_eq!(sequences[0].len(), 2);
        assert_eq!(sequences[0][0], PacoAction::Place(C4));
        assert_eq!(sequences[0][1], PacoAction::Place(E2));
        assert_eq!(sequences[1].len(), 3);
        assert_eq!(sequences[1][0], PacoAction::Place(C4));
        assert_eq!(sequences[1][1], PacoAction::Place(E6));
        assert_eq!(sequences[1][2], PacoAction::Place(E2));
        assert_eq!(sequences[2].len(), 4);
        assert_eq!(sequences[2][0], PacoAction::Place(C4));
        assert_eq!(sequences[2][1], PacoAction::Place(E6));
        assert_eq!(sequences[2][2], PacoAction::Place(C4));
        assert_eq!(sequences[2][3], PacoAction::Place(E2));
    }
}
