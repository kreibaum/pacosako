//! Analysis methods for paco sako. This can be used to analyze a game and
//! give information about interesting moments. E.g. missed opportunities.

use std::fmt::Display;

use serde::Serialize;

use crate::{
    BoardPosition, DenseBoard, determine_all_threats, Hand, PacoAction, PacoBoard,
    PacoError, PieceType, PlayerColor, substrate::Substrate,
};

use self::incremental_replay::history_to_replay_notation_incremental;

pub mod chasing_paco;
pub mod incremental_replay;
mod opening;
pub mod puzzle;
pub mod reverse_amazon_search;
pub(crate) mod tree;

#[derive(Serialize, PartialEq, Debug)]
pub struct ReplayData {
    notation: Vec<HalfMove>,
    opening: String,
    progress: f32,
}

/// Represents a single line in the sidebar, like "g2>Pf3>Pe4>Pd5>d6".
/// This would be represented as [g2>Pf3][>Pe4][>Pd5][>d6].
/// Where each section also points to the action index to jump there easily.
#[derive(Serialize, PartialEq, Eq, Debug, Clone)]
pub struct HalfMove {
    move_number: u32,
    current_player: PlayerColor,
    actions: Vec<HalfMoveSection>,
    paco_actions: Vec<PacoAction>,
    metadata: HalfMoveMetadata,
}

/// Represents a single section in a half move. Like [g2>Pf3].
#[derive(Serialize, PartialEq, Eq, Debug, Clone)]
pub struct HalfMoveSection {
    action_index: usize,
    label: String,
}

#[derive(Serialize, PartialEq, Eq, Debug, Clone)]
pub struct HalfMoveMetadata {
    gives_sako: bool,
    missed_paco: bool,
    /// If you make a move that ends with yourself in Ŝako even if you didn't start there.
    gives_opponent_paco_opportunity: bool,
    paco_in_2_found: bool,
    paco_in_2_missed: bool,
}

/// Metadata with all flags set to false.
impl Default for HalfMoveMetadata {
    fn default() -> Self {
        HalfMoveMetadata {
            gives_sako: false,
            missed_paco: false,
            gives_opponent_paco_opportunity: false,
            paco_in_2_found: false,
            paco_in_2_missed: false,
        }
    }
}

/// A notation atom roughly corresponds to a Sako.Action but carries more metadata.
#[derive(Debug, Clone)]
pub(crate) enum NotationAtom {
    StartMoveSinge {
        mover: PieceType,
        at: BoardPosition,
    },
    StartMoveUnion {
        mover: PieceType,
        partner: PieceType,
        at: BoardPosition,
    },
    ContinueChain {
        exchanged: PieceType,
        at: BoardPosition,
    },
    EndMoveCalm {
        at: BoardPosition,
    },
    EndMoveFormUnion {
        partner: PieceType,
        at: BoardPosition,
    },
    Promote {
        to: PieceType,
    },
}

impl NotationAtom {
    fn is_place(&self) -> bool {
        matches!(
            self,
            NotationAtom::ContinueChain { .. }
                | NotationAtom::EndMoveCalm { .. }
                | NotationAtom::EndMoveFormUnion { .. }
        )
    }
    fn is_lift(&self) -> bool {
        matches!(
            self,
            NotationAtom::StartMoveSinge { .. } | NotationAtom::StartMoveUnion { .. }
        )
    }
}

impl Display for NotationAtom {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NotationAtom::StartMoveSinge { mover, at } => write!(f, "{}{}", letter(mover), at),
            NotationAtom::StartMoveUnion { mover, partner, at } => {
                write!(f, "{}{}{}", force_letter(mover), force_letter(partner), at)
            }
            NotationAtom::ContinueChain { exchanged, at } => {
                write!(f, ">{}{}", force_letter(exchanged), at)
            }
            NotationAtom::EndMoveCalm { at } => write!(f, ">{}", at),
            NotationAtom::EndMoveFormUnion { partner, at } => {
                write!(f, "x{}{}", letter(partner), at)
            }
            NotationAtom::Promote { to } => write!(f, "={}", letter(to)),
        }
    }
}


/// Turns a piece type into a letter, where Pawn is left out.
fn letter(piece: &PieceType) -> &str {
    match piece {
        PieceType::Pawn => "",
        PieceType::Knight => "N",
        PieceType::Bishop => "B",
        PieceType::Rook => "R",
        PieceType::Queen => "Q",
        PieceType::King => "K",
    }
}

/// Turns a piece type into a letter, where Pawn is printed as "P".
/// I'm calling it "force" because it feels like the "-f" variant of `letter`.
fn force_letter(piece: &PieceType) -> &str {
    match piece {
        PieceType::Pawn => "P",
        _ => letter(piece),
    }
}

/// Applies a given action to the board (mutation!) and returns some information
/// about what happened in a NotationAtom.
fn apply_action_semantically(
    board: &mut DenseBoard,
    action: PacoAction,
) -> Result<NotationAtom, PacoError> {
    match action {
        PacoAction::Lift(_) => {
            board.execute(action)?;
            match board.lifted_piece {
                Hand::Empty => Err(PacoError::LiftEmptyPosition),
                Hand::Single { piece, position } => Ok(NotationAtom::StartMoveSinge {
                    mover: piece,
                    at: position,
                }),
                Hand::Pair {
                    piece,
                    partner,
                    position,
                } => Ok(NotationAtom::StartMoveUnion {
                    mover: piece,
                    partner,
                    at: position,
                }),
            }
        }
        PacoAction::Place(at) => {
            // Remember the opponent's piece at the target position.
            let partner = board
                .substrate
                .get_piece(board.controlling_player.other(), at);
            board.execute(action)?;
            match board.lifted_piece {
                Hand::Empty => {
                    if let Some(partner) = partner {
                        Ok(NotationAtom::EndMoveFormUnion { partner, at })
                    } else {
                        Ok(NotationAtom::EndMoveCalm { at })
                    }
                }
                Hand::Single { piece, position } => Ok(NotationAtom::ContinueChain {
                    exchanged: piece,
                    at: position,
                }),
                Hand::Pair { .. } => Err(PacoError::PlacePairFullPosition),
            }
        }
        PacoAction::Promote(to) => {
            board.execute(action)?;
            Ok(NotationAtom::Promote { to })
        }
    }
}

/// Turns a list of notation atoms into a list of sections.
/// the initial 2-move is combined into a single section.
fn squash_notation_atoms(initial_index: usize, atoms: Vec<NotationAtom>) -> Vec<HalfMoveSection> {
    let mut result: Vec<HalfMoveSection> = Vec::new();

    let mut already_squashed = false;
    // Stores the king's original position to detect castling.
    let mut potentially_castling = None;

    'atom_loop: for (i, atom) in atoms.iter().enumerate() {
        if let NotationAtom::StartMoveSinge {
            mover: PieceType::King,
            at,
        } = atom
        {
            potentially_castling = Some(*at);
        }

        if let Some(from) = potentially_castling {
            if atom.is_place() {
                if let NotationAtom::EndMoveCalm { at } = atom {
                    // This can never happen when the result is empty, so we can unwrap.
                    let last = result.last_mut().unwrap();

                    let from = from.0 as i8;
                    let to = at.0 as i8;
                    if to - from == 2 {
                        last.label = "0-0".to_string();
                        last.action_index = i + initial_index + 1;
                        already_squashed = true;
                        continue 'atom_loop;
                    }
                    if to - from == -2 {
                        last.label = "0-0-0".to_string();
                        last.action_index = i + initial_index + 1;
                        already_squashed = true;
                        continue 'atom_loop;
                    }
                }
            }
            // Otherwise, we just continue. This is a regular King movement.
        }
        if !already_squashed && atom.is_place() {
            // This can never happen when the result is empty, so we can unwrap.
            let last = result.last_mut().unwrap();
            last.label.push_str(&atom.to_string());
            last.action_index = i + initial_index + 1;
            already_squashed = true;
        } else if atom.is_lift() && i >= 1 {
            result.push(HalfMoveSection {
                action_index: i + initial_index + 1,
                label: format!(":{}", atom.to_string()),
            });
        } else {
            result.push(HalfMoveSection {
                action_index: i + initial_index + 1,
                label: atom.to_string(),
            });
        }
    }

    result
}

pub fn history_to_replay_notation(
    initial_board: DenseBoard,
    actions: &[PacoAction],
) -> Result<ReplayData, PacoError> {
    // This turns off the clock and ignores the callback.
    history_to_replay_notation_incremental(&initial_board, actions, || 0, |_| {})
}

pub fn is_sako(board: &DenseBoard, for_player: PlayerColor) -> Result<bool, PacoError> {
    // If the game is already over, we don't need to check for ŝako.
    if board.victory_state().is_over() {
        return Ok(false);
    }
    let mut board = board.clone();
    // Required for e.g. r2q1Ck1/ppp1n2p/4f2c/3d4/1b1o1e1P/2E1P3/P1P2PP1/2KR1B2 w 1 AHah - -
    if board.required_action.is_promote() {
        board.execute(PacoAction::Promote(PieceType::Queen))?;
    }
    board.controlling_player = for_player;

    for threat in determine_all_threats(&board)? {
        // Check if the opponent's king is on this square.
        if board.substrate.is_piece(board.controlling_player.other(), threat, PieceType::King) {
            return Ok(true);
        }
    }

    Ok(false)
}

// Test module
#[cfg(test)]
mod tests {
    use PacoAction::*;

    use crate::{fen, testdata::REPLAY_13103};
    use crate::const_tile::*;

    use super::*;

    #[test]
    fn empty_list() {
        let replay =
            history_to_replay_notation(DenseBoard::new(), &[]).expect("Error in input data");
        assert_eq!(replay.notation, vec![]);
    }

    #[test]
    fn notation_compile_simple_move() {
        let replay = history_to_replay_notation(DenseBoard::new(), &[Lift(D2), Place(D4)])
            .expect("Error in input data");
        assert_eq!(
            replay.notation,
            vec![HalfMove {
                move_number: 1,
                current_player: PlayerColor::White,
                actions: vec![HalfMoveSection {
                    action_index: 2,
                    label: "d2>d4".to_string(),
                }, ],
                paco_actions: vec![Lift(D2), Place(D4)],
                metadata: HalfMoveMetadata::default(),
            }]
        );
    }

    #[test]
    fn chain_and_union_move() {
        let replay = history_to_replay_notation(
            DenseBoard::new(),
            &[
                Lift(E2),
                Place(E4),
                Lift(D7),
                Place(D5),
                Lift(E4),
                Place(D5),
                Lift(D8),
                Place(D5),
                Place(D4),
            ],
        )
            .expect("Error in input data");
        assert_eq!(
            replay.notation,
            vec![
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 2,
                        label: "e2>e4".to_string(),
                    }, ],
                    paco_actions: vec![Lift(E2), Place(E4)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 4,
                        label: "d7>d5".to_string(),
                    }, ],
                    paco_actions: vec![Lift(D7), Place(D5)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 6,
                        label: "e4xd5".to_string(),
                    }, ],
                    paco_actions: vec![Lift(E4), Place(D5)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::Black,
                    actions: vec![
                        HalfMoveSection {
                            action_index: 8,
                            label: "Qd8>Pd5".to_string(),
                        },
                        HalfMoveSection {
                            action_index: 9,
                            label: ">d4".to_string(),
                        },
                    ],
                    paco_actions: vec![Lift(D8), Place(D5), Place(D4)],
                    metadata: HalfMoveMetadata::default(),
                },
            ]
        );
    }

    #[test]
    fn start_move_with_promotion() {
        let setup = "rnbqkbn1/pppppp2/5p2/5p2/8/8/PPPPPPPC/RNBQKBNR b 0 AHah - -";
        let initial_board = fen::parse_fen(setup).unwrap();

        let replay = history_to_replay_notation(
            initial_board,
            &[
                Lift(H2),
                Place(H8),
                Promote(PieceType::Knight),
                Lift(H1),
                Place(H8),
                Place(G6),
            ],
        )
            .expect("Error in input data");

        assert_eq!(
            replay.notation,
            vec![
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 2,
                        label: "RPh2>h8".to_string(),
                    }, ],
                    paco_actions: vec![Lift(H2), Place(H8)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::White,
                    actions: vec![
                        HalfMoveSection {
                            action_index: 3,
                            label: "=N".to_string(),
                        },
                        HalfMoveSection {
                            action_index: 5,
                            label: ":Rh1>Nh8".to_string(),
                        },
                        HalfMoveSection {
                            action_index: 6,
                            label: ">g6".to_string(),
                        },
                    ],
                    paco_actions: vec![Promote(PieceType::Knight), Lift(H1), Place(H8), Place(G6)],
                    metadata: HalfMoveMetadata::default(),
                },
            ]
        );
    }

    #[test]
    fn test_castling_notation() {
        let setup = "r3kbnr/ppp2ppp/2n5/1B1pp3/1PP1P1bq/5N2/P2P1PPP/RNBQK2R w 0 AHah - -";
        let initial_board = fen::parse_fen(setup).unwrap();

        let replay = history_to_replay_notation(
            initial_board,
            &[
                Lift(E1),
                Place(G1),
                Lift(E8),
                Place(C8),
                Lift(G1),
                Place(H1),
                Lift(C8),
                Place(D7),
            ],
        )
            .expect("Error in input data");

        assert_eq!(
            replay.notation,
            vec![
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 2,
                        label: "0-0".to_string(),
                    }, ],
                    paco_actions: vec![Lift(E1), Place(G1)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 4,
                        label: "0-0-0".to_string(),
                    }, ],
                    paco_actions: vec![Lift(E8), Place(C8)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 6,
                        label: "Kg1>h1".to_string(),
                    }, ],
                    paco_actions: vec![Lift(G1), Place(H1)],
                    metadata: HalfMoveMetadata::default(),
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 8,
                        label: "Kc8>d7".to_string(),
                    }, ],
                    paco_actions: vec![Lift(C8), Place(D7)],
                    metadata: HalfMoveMetadata::default(),
                },
            ]
        );
    }

    // Moves a pinned piece out of the way, giving the opponent a chance to paco.
    #[test]
    fn gives_opponent_paco_opportunity() {
        let setup = "r1bqkbnr/ppp1pppp/2n5/1B1p4/3PP3/8/PPP2PPP/RNBQK1NR b 0 AHah - -";
        let initial_board = fen::parse_fen(setup).unwrap();

        let replay = history_to_replay_notation(initial_board, &[Lift(C6), Place(D4)])
            .expect("Error in input data");

        assert_eq!(
            replay.notation,
            vec![HalfMove {
                move_number: 1,
                current_player: PlayerColor::Black,
                actions: vec![HalfMoveSection {
                    action_index: 2,
                    label: "Nc6xd4".to_string(),
                }, ],
                paco_actions: vec![Lift(C6), Place(D4)],
                metadata: HalfMoveMetadata {
                    gives_opponent_paco_opportunity: true,
                    ..Default::default()
                },
            }, ]
        );
    }

    #[test]
    fn test_replay_13103() -> Result<(), PacoError> {
        let _notation = history_to_replay_notation(DenseBoard::new(), &REPLAY_13103)?;

        Ok(())
    }

    #[test]
    fn test_replay_16069() -> Result<(), PacoError> {
        let _notation = history_to_replay_notation(DenseBoard::new(), &crate::testdata::REPLAY_16069)?;

        Ok(())
    }
}
