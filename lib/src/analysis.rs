/// Analysis methods for paco sako. This can be used to analyze a game and
/// give information about interesting moments. E.g. missed opportunities.
use serde::Serialize;

use crate::{
    BoardPosition, DenseBoard, Hand, PacoAction, PacoBoard, PacoError, PieceType, PlayerColor,
};

/// Represents a single line in the sidebar, like "g2>Pf3>Pe4>Pd5>d6".
/// This would be represented as [g2>Pf3][>Pe4][>Pd5][>d6].
/// Where each section also points to the action index to jump there easily.
#[derive(Serialize, PartialEq, Eq, Debug)]
pub struct HalfMove {
    move_number: u32,
    current_player: PlayerColor,
    actions: Vec<HalfMoveSection>,
    metadata: HalfMoveMetadata,
}

/// Represents a single section in a half move. Like [g2>Pf3].
#[derive(Serialize, PartialEq, Eq, Debug)]
pub struct HalfMoveSection {
    action_index: usize,
    label: String,
}

#[derive(Serialize, PartialEq, Eq, Debug)]
pub struct HalfMoveMetadata {
    gives_sako: bool,
    missed_paco: bool,
}

/// A notation atom roughly corresponds to a Sako.Action but carries more metadata.
#[derive(Debug)]
enum NotationAtom {
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
        match self {
            NotationAtom::ContinueChain { .. } => true,
            NotationAtom::EndMoveCalm { .. } => true,
            NotationAtom::EndMoveFormUnion { .. } => true,
            _ => false,
        }
    }
    fn is_lift(&self) -> bool {
        match self {
            NotationAtom::StartMoveSinge { .. } => true,
            NotationAtom::StartMoveUnion { .. } => true,
            _ => false,
        }
    }
}

impl ToString for NotationAtom {
    fn to_string(&self) -> String {
        match self {
            NotationAtom::StartMoveSinge { mover, at } => format!("{}{}", letter(mover), at),
            NotationAtom::StartMoveUnion { mover, partner, at } => {
                format!("{}{}{}", force_letter(mover), force_letter(partner), at)
            }
            NotationAtom::ContinueChain { exchanged, at } => {
                format!(">{}{}", force_letter(exchanged), at.to_string())
            }
            NotationAtom::EndMoveCalm { at } => format!(">{}", at.to_string()),
            NotationAtom::EndMoveFormUnion { partner, at } => {
                format!("x{}{}", letter(partner), at.to_string())
            }
            NotationAtom::Promote { to } => format!("={}", letter(to)),
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
/// I'm calling it "force" because it feels like the "-f" variant of letter.
fn force_letter(piece: &PieceType) -> &str {
    match piece {
        PieceType::Pawn => "P",
        _ => letter(piece),
    }
}

// Applies an action and returns information about what happened.
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
            // Remember the opponents piece that is at the target position.
            let &partner = board.opponent_pieces().get(at.0 as usize).unwrap();
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

// Turns a list of notation atoms into a list of sections.
// the initial 2-move is combined into a single section.
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

        if potentially_castling.is_some() && atom.is_place() {
            if let NotationAtom::EndMoveCalm { at } = atom {
                // This can never happen when the result is empty, so we can unwrap.
                let last = result.last_mut().unwrap();

                let from = potentially_castling.unwrap().0 as i8;
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
            // Otherwise, we just continue, this is a regular King movement.
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
) -> Result<Vec<HalfMove>, PacoError> {
    let mut half_moves = Vec::with_capacity(actions.len() / 2);

    let mut initial_index = 0;
    let mut move_count = 1;
    let mut current_player = initial_board.controlling_player();

    let mut current_half_move = HalfMove {
        move_number: move_count,
        current_player,
        actions: Vec::new(),
        metadata: HalfMoveMetadata {
            gives_sako: false,
            missed_paco: false,
        },
    };

    let mut board = initial_board;

    // Pick moves off the stack and add them to the current half move.

    let mut notations = Vec::new();
    for (action_index, &action) in actions.iter().enumerate() {
        let notation = apply_action_semantically(&mut board, action)?;
        notations.push(notation);

        if board.controlling_player() != current_player {
            // finalize half move, change color
            current_half_move.actions =
                squash_notation_atoms(initial_index, std::mem::replace(&mut notations, Vec::new()));

            half_moves.push(current_half_move);

            if board.controlling_player() == PlayerColor::White {
                move_count += 1;
            }
            current_player = board.controlling_player();
            initial_index = action_index + 1;

            current_half_move = HalfMove {
                move_number: move_count,
                current_player,
                actions: Vec::new(),
                metadata: HalfMoveMetadata {
                    gives_sako: false,
                    missed_paco: false,
                },
            };
        }
    }

    Ok(half_moves)
}

// Test module
#[cfg(test)]
mod tests {
    use crate::fen;

    use super::*;

    #[test]
    fn empty_list() {
        let notation =
            history_to_replay_notation(DenseBoard::new(), &[]).expect("Error in input data");
        assert_eq!(notation, vec![]);
    }

    #[test]
    fn notation_compile_simple_move() {
        let notation = history_to_replay_notation(
            DenseBoard::new(),
            &[
                PacoAction::Lift("d2".try_into().unwrap()),
                PacoAction::Place("d4".try_into().unwrap()),
            ],
        )
        .expect("Error in input data");
        assert_eq!(
            notation,
            vec![HalfMove {
                move_number: 1,
                current_player: PlayerColor::White,
                actions: vec![HalfMoveSection {
                    action_index: 2,
                    label: "d2>d4".to_string(),
                },],
                metadata: HalfMoveMetadata {
                    gives_sako: false,
                    missed_paco: false,
                }
            }]
        );
    }

    #[test]
    fn chain_and_union_move() {
        let notation = history_to_replay_notation(
            DenseBoard::new(),
            &[
                PacoAction::Lift("e2".try_into().unwrap()),
                PacoAction::Place("e4".try_into().unwrap()),
                PacoAction::Lift("d7".try_into().unwrap()),
                PacoAction::Place("d5".try_into().unwrap()),
                PacoAction::Lift("e4".try_into().unwrap()),
                PacoAction::Place("d5".try_into().unwrap()),
                PacoAction::Lift("d8".try_into().unwrap()),
                PacoAction::Place("d5".try_into().unwrap()),
                PacoAction::Place("d4".try_into().unwrap()),
            ],
        )
        .expect("Error in input data");
        assert_eq!(
            notation,
            vec![
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 2,
                        label: "e2>e4".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 4,
                        label: "d7>d5".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 6,
                        label: "e4xd5".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
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
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                }
            ]
        );
    }

    #[test]
    fn start_move_with_promotion() {
        let setup = "rnbqkbn1/pppppp2/5p2/5p2/8/8/PPPPPPPC/RNBQKBNR b 0 AHah - -";
        let initial_board = fen::parse_fen(setup).unwrap();

        let notation = history_to_replay_notation(
            initial_board,
            &[
                PacoAction::Lift("h2".try_into().unwrap()),
                PacoAction::Place("h8".try_into().unwrap()),
                PacoAction::Promote(PieceType::Knight),
                PacoAction::Lift("h1".try_into().unwrap()),
                PacoAction::Place("h8".try_into().unwrap()),
                PacoAction::Place("g6".try_into().unwrap()),
            ],
        )
        .expect("Error in input data");

        assert_eq!(
            notation,
            vec![
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 2,
                        label: "RPh2>h8".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
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
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
            ]
        );
    }

    #[test]
    fn test_castling_notation() {
        let setup = "r3kbnr/ppp2ppp/2n5/1B1pp3/1PP1P1bq/5N2/P2P1PPP/RNBQK2R w 0 AHah - -";
        let initial_board = fen::parse_fen(setup).unwrap();

        let notation = history_to_replay_notation(
            initial_board,
            &[
                PacoAction::Lift("e1".try_into().unwrap()),
                PacoAction::Place("g1".try_into().unwrap()),
                PacoAction::Lift("e8".try_into().unwrap()),
                PacoAction::Place("c8".try_into().unwrap()),
                PacoAction::Lift("g1".try_into().unwrap()),
                PacoAction::Place("h1".try_into().unwrap()),
                PacoAction::Lift("c8".try_into().unwrap()),
                PacoAction::Place("d7".try_into().unwrap()),
            ],
        )
        .expect("Error in input data");

        assert_eq!(
            notation,
            vec![
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 2,
                        label: "0-0".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
                HalfMove {
                    move_number: 1,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 4,
                        label: "0-0-0".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::White,
                    actions: vec![HalfMoveSection {
                        action_index: 6,
                        label: "Kg1>h1".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
                HalfMove {
                    move_number: 2,
                    current_player: PlayerColor::Black,
                    actions: vec![HalfMoveSection {
                        action_index: 8,
                        label: "Kc8>d7".to_string(),
                    },],
                    metadata: HalfMoveMetadata {
                        gives_sako: false,
                        missed_paco: false,
                    }
                },
            ]
        );
    }

    // TODO: Add an integration test were we test all games that were ever played.
}
