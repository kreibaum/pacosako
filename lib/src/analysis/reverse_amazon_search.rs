//! Functions to check if we are in a Sako position.

use core::fmt::Debug;
use fxhash::{FxHashMap, FxHashSet};
use std::{
    collections::{hash_map::Entry, VecDeque},
    fmt::Formatter,
    ops::Add,
};
use tinyset::SetU32;

// TODO: This can get more performance by switching from Set<u32> to Set<{0..63}>
// and using a bit board for implementation.

use crate::{
    trace_first_move, BoardPosition, DenseBoard, PacoAction, PacoBoard, PacoError, PieceType,
    PlayerColor,
};

pub struct ExploredStateAmazon {
    pub paco_positions: FxHashSet<DenseBoard>,
    pub found_via: FxHashMap<DenseBoard, Vec<(PacoAction, Option<DenseBoard>)>>,
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

pub fn find_paco_sequences(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<Vec<Vec<PacoAction>>, PacoError> {
    let tree = explore_paco_tree(board, attacking_player)?;

    let mut result = vec![];

    for paco_position in tree.paco_positions.iter() {
        if let Some(trace) = trace_first_move(paco_position, &tree.found_via) {
            result.push(trace);
        }
    }

    Ok(result)
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
    if !board.is_settled() {
        return Err(PacoError::BoardNotSettled);
    }

    // First, find out if we actually need to do anything.
    let search = reverse_amazon_squares(board, attacking_player)?;
    if search.starting_tiles.is_empty() {
        return Ok(ExploredStateAmazon {
            paco_positions: FxHashSet::default(),
            found_via: FxHashMap::default(),
        });
    }

    // We found some starting tiles, this means we actually need to work.
    let mut todo_list: VecDeque<DenseBoard> = VecDeque::new();
    let mut paco_positions: FxHashSet<DenseBoard> = FxHashSet::default();
    let mut found_via: FxHashMap<DenseBoard, Vec<(PacoAction, Option<DenseBoard>)>> =
        FxHashMap::default();

    // Clone the board and correctly set the controlling player.
    let mut board = board.clone();
    board.controlling_player = attacking_player;

    // Put all starting moves into the initialization
    for starting_tile in search.starting_tiles {
        let action = PacoAction::Lift(BoardPosition(starting_tile as u8));
        let mut b = board.clone();
        b.execute_trusted(action)?;
        found_via
            .entry(b.clone())
            .and_modify(|v| v.push((action, None)))
            .or_insert_with(|| vec![(action, None)]);
        todo_list.push_back(b);
    }

    // The paco positions we are interested in are the one that end with a
    // king capture.
    let king_capture_action = PacoAction::Place(board.king_position(attacking_player.other())?);

    // Pull entries from the todo_list until it is empty.
    while let Some(todo) = todo_list.pop_front() {
        // Execute all actions within the chaining_tiles.
        'action_loop: for action in todo.actions()? {
            if let PacoAction::Place(p) = action {
                // Skip actions that are not in the chaining_tiles.
                // Promotions are never skipped.
                if !search.chaining_tiles.contains(p.0 as u32) {
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
                    o_entry.get_mut().push((action, Some(todo.clone())));
                }
                // We encounter this state for the first time.
                Entry::Vacant(v_entry) => {
                    v_entry.insert(vec![(action, Some(todo.clone()))]);
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

/// Holds information which squares are relevant for a paco search.
#[derive(Debug)]
pub struct ReverseAmazonSearchResult {
    pub chaining_tiles: SetU32,
    pub starting_tiles: SetU32,
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
pub fn reverse_amazon_squares(
    board: &DenseBoard,
    attacking_player: PlayerColor,
) -> Result<ReverseAmazonSearchResult, PacoError> {
    // Determine if there is an en-passant square we have to care about.
    let (en_passant_tile, en_passant_slide_from) = if let Some(pos) = board.en_passant {
        // Find square the pawn now is on.
        let en_passant_slide_from = pos
            .advance_pawn(attacking_player.other())
            .expect("En-passant square isn't at the border.");
        // Check if this is a pair. Otherwise we don't care.
        if board.get(attacking_player, en_passant_slide_from).is_some() {
            (Some(pos), Some(en_passant_slide_from))
        } else {
            (None, None)
        }
    } else {
        (None, None)
    };

    // In the first phase, we start at the kings location and then find all the
    // positions that are reachable with amazon chains.

    let mut tiles_seen = SetU32::default();
    let mut chaining_tiles = SetU32::default();
    let mut todo_list = SetU32::default();
    let mut starting_tiles = SetU32::default();
    let king_position = board.king_position(attacking_player.other())?;
    todo_list.insert(king_position.0 as u32);

    while let Some(p) = pop(&mut todo_list) {
        // let p = todo_list.iter().next().expect("len > 0");
        // todo_list.remove(p);
        if !tiles_seen.insert(p) {
            // Returns false if already present.
            continue;
        }
        chaining_tiles.insert(p);
        let from = BoardPosition(p as u8);

        knight_targets(
            board,
            from,
            attacking_player,
            &mut todo_list,
            &mut starting_tiles,
            en_passant_tile,
        );

        slide_targets(
            board,
            from,
            attacking_player,
            &mut todo_list,
            &mut starting_tiles,
            en_passant_tile,
            en_passant_slide_from,
        );
    }

    Ok(ReverseAmazonSearchResult {
        chaining_tiles,
        starting_tiles,
    })
}

/// Unfortunately this method does not exist in tinyset.
fn pop(todo_list: &mut SetU32) -> Option<u32> {
    if !todo_list.is_empty() {
        let p = todo_list.iter().next().expect("len > 0");
        todo_list.remove(p);
        Some(p)
    } else {
        None
    }
}

fn slide_targets(
    board: &DenseBoard,
    from: BoardPosition,
    attacking_player: PlayerColor,
    todo_list: &mut SetU32,
    starting_tiles: &mut SetU32,
    en_passant_tile: Option<BoardPosition>,
    en_passant_slide_from: Option<BoardPosition>,
) {
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
        let mut slide_counter = 0;
        let mut slipped_through_starter = false;
        'sliding: loop {
            slide_counter += 1;
            let new_tile = current.add((dx, dy));
            if new_tile.is_none() {
                break 'sliding;
            }
            current = new_tile.unwrap();

            if new_tile == en_passant_tile || new_tile == en_passant_slide_from {
                // The en-passant tile counts as a potential chaining tile and
                // we can also slide through it. This is also true for the tile
                // the pawn (which would get pulled back) is on.

                // We can still break here, because the en-passant tile
                // is also a chaining tile. That will take care of sliding through.
                todo_list.insert(current.0 as u32);
                break 'sliding;
            }

            let attacking_piece = board.get(attacking_player, current);
            let defending_piece = board.get(attacking_player.other(), current);

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
                    let is_rook_move = dx == 0 || dy == 0;
                    if is_rook_move {
                        if attacker == PieceType::Rook || attacker == PieceType::Queen {
                            starting_tiles.insert(current.0 as u32);
                        }
                    } else {
                        // is_bishop_move
                        if attacker == PieceType::Bishop || attacker == PieceType::Queen {
                            starting_tiles.insert(current.0 as u32);
                        } else if attacker == PieceType::Pawn && slide_counter == 1 {
                            // Signs are flipped here, because we are doing a
                            // reverse search.
                            let pawn_direction = if attacking_player == PlayerColor::White {
                                -1
                            } else {
                                1
                            };
                            if dy == pawn_direction {
                                starting_tiles.insert(current.0 as u32);
                            }
                        }
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
                    todo_list.insert(current.0 as u32);
                    break 'sliding;
                }
            }
        }
    }
}

fn knight_targets(
    board: &DenseBoard,
    from: BoardPosition,
    attacking_player: PlayerColor,
    todo_list: &mut SetU32,
    starting_tiles: &mut SetU32,
    en_passant_tile: Option<BoardPosition>,
) {
    let offsets = vec![
        (1, 2),
        (2, 1),
        (2, -1),
        (1, -2),
        (-1, -2),
        (-2, -1),
        (-2, 1),
        (-1, 2),
    ];

    let targets_on_board = offsets.iter().filter_map(|d| from.add(*d));

    for target in targets_on_board {
        // If en-passant is possible, the en-passant square may take part in a
        // chain. Starting from the en-passant square is not possible.
        if en_passant_tile == Some(target) {
            todo_list.insert(target.0 as u32);
            continue;
        }

        if let Some(attacker) = board.get(attacking_player, target) {
            if board.get(attacking_player.other(), target).is_none() {
                // Only knights can start the attack with a knight move.
                if attacker == PieceType::Knight {
                    starting_tiles.insert(target.0 as u32);
                }
            } else {
                todo_list.insert(target.0 as u32);
            }
        }
    }
}

/// Tests module
#[cfg(test)]
mod tests {
    use crate::{
        analysis::reverse_amazon_search::find_paco_sequences, const_tile::pos, DenseBoard,
        PacoAction, PacoBoard, PlayerColor,
    };

    use super::reverse_amazon_squares;

    #[test]
    fn initial_board() {
        let search = reverse_amazon_squares(&DenseBoard::new(), PlayerColor::White)
            .expect("Error in reverse amazon search.");

        assert!(search.starting_tiles.is_empty());
        assert_eq!(search.chaining_tiles.len(), 1);
        assert!(search.chaining_tiles.contains(60));
    }

    #[test]
    fn initial_board_black() {
        let search = reverse_amazon_squares(&DenseBoard::new(), PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        assert!(search.starting_tiles.is_empty());
        assert_eq!(search.chaining_tiles.len(), 1);
        assert!(search.chaining_tiles.contains(4));
    }

    #[test]
    fn g5692a93w() {
        let board = crate::fen::parse_fen(
            "2k1r3/ppc2ppp/3i4/3p1b2/PEtPpB1P/3L1NPB/2P1DP2/5K2 w 0 AHah - -",
        )
        .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(10));
        assert!(search.starting_tiles.contains(29));
        assert_eq!(search.chaining_tiles.len(), 7);
        assert!(search.chaining_tiles.contains(12));
        assert!(search.chaining_tiles.contains(19));
        assert!(search.chaining_tiles.contains(25));
        assert!(search.chaining_tiles.contains(26));
        assert!(search.chaining_tiles.contains(43));
        assert!(search.chaining_tiles.contains(50));
        assert!(search.chaining_tiles.contains(58));
    }

    #[test]
    fn g5692a93b() {
        let board = crate::fen::parse_fen(
            "2k1r3/ppc2ppp/3i4/3p1b2/PEtPpB1P/3L1NPB/2P1DP2/5K2 w 0 AHah - -",
        )
        .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(28));
        assert!(search.starting_tiles.contains(35));
        assert_eq!(search.chaining_tiles.len(), 7);
        assert!(search.chaining_tiles.contains(5));
        assert!(search.chaining_tiles.contains(12));
        assert!(search.chaining_tiles.contains(19));
        assert!(search.chaining_tiles.contains(25));
        assert!(search.chaining_tiles.contains(26));
        assert!(search.chaining_tiles.contains(43));
        assert!(search.chaining_tiles.contains(50));
    }

    #[test]
    fn g5464a32w() {
        // Checks if the en-passant square is handled at all.
        let mut board =
            crate::fen::parse_fen("rnbqkb1r/ppf2p1p/6p1/3D3d/2Bp4/8/PPPP1PPP/RNB1K2R b 0 AHah - -")
                .expect("Error in fen parsing.");

        board.execute_trusted(PacoAction::Lift(pos("c7"))).unwrap();
        board.execute_trusted(PacoAction::Place(pos("c5"))).unwrap();

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 1);
        assert!(search.starting_tiles.contains(26));
        assert_eq!(search.chaining_tiles.len(), 5);
        assert!(search.chaining_tiles.contains(34));
        assert!(search.chaining_tiles.contains(35));
        assert!(search.chaining_tiles.contains(39));
        assert!(search.chaining_tiles.contains(42));
        assert!(search.chaining_tiles.contains(60));
    }

    #[test]
    fn syn1() {
        // Checks if the en-passant square is pass-through.
        let mut board =
            crate::fen::parse_fen("1n2k1n1/ppp2ppp/3p2NE/6RB/2P3PA/i6C/P2F4/REBQ3K w 0 AHah - -")
                .expect("Error in fen parsing.");

        board.execute_trusted(PacoAction::Lift(pos("d2"))).unwrap();
        board.execute_trusted(PacoAction::Place(pos("d4"))).unwrap();

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 0);
        assert_eq!(search.chaining_tiles.len(), 7);
        assert!(search.chaining_tiles.contains(pos("b1").0 as u32));
        assert!(search.chaining_tiles.contains(pos("h1").0 as u32));
        assert!(search.chaining_tiles.contains(pos("a3").0 as u32));
        assert!(search.chaining_tiles.contains(pos("d3").0 as u32));
        assert!(search.chaining_tiles.contains(pos("h3").0 as u32));
        assert!(search.chaining_tiles.contains(pos("d4").0 as u32));
        assert!(search.chaining_tiles.contains(pos("h4").0 as u32));
    }

    #[test]
    fn syn2() {
        // Checks if we can slide through a single piece.
        let board =
            crate::fen::parse_fen("rnbqkbnr/pppp1p1p/8/5d2/4P3/4c3/PPPP1PPP/RNBQKB2 w 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 3);
        assert!(search.starting_tiles.contains(pos("d2").0 as u32));
        assert!(search.starting_tiles.contains(pos("f2").0 as u32));
        assert!(search.starting_tiles.contains(pos("e4").0 as u32));
        assert_eq!(search.chaining_tiles.len(), 3);
        assert!(search.chaining_tiles.contains(pos("e3").0 as u32));
        assert!(search.chaining_tiles.contains(pos("f5").0 as u32));
        assert!(search.chaining_tiles.contains(pos("e8").0 as u32));
    }

    #[test]
    fn syn3() {
        // Checks that we can't slide though two pieces.
        let board =
            crate::fen::parse_fen("rn1qkbnr/pppp2pp/4E3/4p3/3Pp3/8/PPP2PPP/RNBQKBNR b 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 0);
        assert_eq!(search.chaining_tiles.len(), 1);
        assert!(search.chaining_tiles.contains(pos("e1").0 as u32));
    }

    #[test]
    fn syn4() {
        // Very simple test for the paco sequence search.
        let board =
            crate::fen::parse_fen("rnbqkbnr/pppppppp/5N2/8/8/8/PPPPPPPP/RNBQKB1R w 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);

        let sequences = find_paco_sequences(&board, PlayerColor::White)
            .expect("Error in paco sequence search.");
        println!("{:?}", sequences);

        assert_eq!(sequences.len(), 1);
        assert_eq!(sequences[0].len(), 2);
        assert_eq!(sequences[0][0], PacoAction::Lift(pos("f6")));
        assert_eq!(sequences[0][1], PacoAction::Place(pos("e8")));
    }

    #[test]
    fn g5661a88w() {
        // A puzzle from the community
        let board =
            crate::fen::parse_fen("5rk1/ppp2pep/8/1B1AH2D/4f1b1/2N3SP/PPP2DP1/5L1K w 0 AHah - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::White)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);
        assert_eq!(search.starting_tiles.len(), 2);
        assert!(search.starting_tiles.contains(pos("c3").0 as u32));
        assert!(search.starting_tiles.contains(pos("b5").0 as u32));
        assert_eq!(search.chaining_tiles.len(), 9);
        assert!(search.chaining_tiles.contains(pos("f1").0 as u32));
        assert!(search.chaining_tiles.contains(pos("f2").0 as u32));
        assert!(search.chaining_tiles.contains(pos("g3").0 as u32));
        assert!(search.chaining_tiles.contains(pos("e4").0 as u32));
        assert!(search.chaining_tiles.contains(pos("d5").0 as u32));
        assert!(search.chaining_tiles.contains(pos("e5").0 as u32));
        assert!(search.chaining_tiles.contains(pos("h5").0 as u32));
        assert!(search.chaining_tiles.contains(pos("g7").0 as u32));
        assert!(search.chaining_tiles.contains(pos("g8").0 as u32));

        let mut sequences = find_paco_sequences(&board, PlayerColor::White)
            .expect("Error in paco sequence search.");
        println!("{:?}", sequences);

        // Sort the sequences by length.
        sequences.sort_by_key(|a| a.len());

        assert_eq!(sequences.len(), 3);
        assert_eq!(sequences[0].len(), 15);
        assert_eq!(sequences[0][0], PacoAction::Lift(pos("c3")));
        assert_eq!(sequences[0][1], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[0][2], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[0][3], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[0][4], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[0][5], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[0][6], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[0][7], PacoAction::Place(pos("g7")));
        assert_eq!(sequences[0][8], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[0][9], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[0][10], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[0][11], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[0][12], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[0][13], PacoAction::Place(pos("g7")));
        assert_eq!(sequences[0][14], PacoAction::Place(pos("g8")));

        assert_eq!(sequences[1].len(), 16);
        assert_eq!(sequences[1][0], PacoAction::Lift(pos("c3")));
        assert_eq!(sequences[1][1], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[1][2], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[1][3], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[1][4], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[1][5], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[1][6], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[1][7], PacoAction::Place(pos("g7")));
        assert_eq!(sequences[1][8], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[1][9], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[1][10], PacoAction::Place(pos("f2")));
        assert_eq!(sequences[1][11], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[1][12], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[1][13], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[1][14], PacoAction::Place(pos("g7")));
        assert_eq!(sequences[1][15], PacoAction::Place(pos("g8")));

        assert_eq!(sequences[2].len(), 18);
        assert_eq!(sequences[2][0], PacoAction::Lift(pos("c3")));
        assert_eq!(sequences[2][1], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[2][2], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[2][3], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[2][4], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[2][5], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[2][6], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[2][7], PacoAction::Place(pos("g7")));
        assert_eq!(sequences[2][8], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[2][9], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[2][10], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[2][11], PacoAction::Place(pos("f1")));
        assert_eq!(sequences[2][12], PacoAction::Place(pos("f2")));
        assert_eq!(sequences[2][13], PacoAction::Place(pos("g3")));
        assert_eq!(sequences[2][14], PacoAction::Place(pos("e4")));
        assert_eq!(sequences[2][15], PacoAction::Place(pos("e5")));
        assert_eq!(sequences[2][16], PacoAction::Place(pos("g7")));
        assert_eq!(sequences[2][17], PacoAction::Place(pos("g8")));
    }

    #[test]
    fn julia1() {
        // Tests a position that was failing in lunalearn.jl
        let board =
            crate::fen::parse_fen("k4Q2/2p4p/2a1E3/RPPN1Pbr/3nP1cr/BK1q2d1/P4p1p/1p2D2B b 2 - - -")
                .expect("Error in fen parsing.");

        let search = reverse_amazon_squares(&board, PlayerColor::Black)
            .expect("Error in reverse amazon search.");

        println!("{:?}", search);

        let mut sequences = find_paco_sequences(&board, PlayerColor::White)
            .expect("Error in paco sequence search.");
        println!("{:?}", sequences);
    }
}
