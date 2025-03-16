//! A "witness" of a Sako is just a list of actions. Similar, a "witness" of a
//! Paco is an action to be done and then a list of (conditionally legal) actions
//! that can defeat any defense.
//!
//! C.f. https://en.wikipedia.org/wiki/Witness_(mathematics)
//!
//! Goal of this module is to provide faster paco in 2 detection.

use crate::{determine_all_moves, DenseBoard, PacoAction, PacoBoard, PacoError, PlayerColor};

struct SakoWitness {
    pub actions: Vec<PacoAction>,
}

struct Paco2Witness {
    pub first_move: Vec<PacoAction>,
    pub finish_with: Vec<SakoWitness>,
}

pub fn find_paco_in_2_witness(
    board: &DenseBoard,
    attacker: PlayerColor,
) -> Result<Option<Paco2Witness>, PacoError> {
    assert!( board.is_settled(),
    "Board must be settled to determine paco in 2"
    );

    let mut board = board.clone();
    board.controlling_player = attacker;

    // Find all moves that put he opponent in sako.
    let explored_attacks = determine_all_moves(board)?;

    todo!()
}
