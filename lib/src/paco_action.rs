//! Module for the PacoAction and PacoActionSet

use crate::{substrate::BitBoard, BoardPosition, PieceType};
use serde::{Deserialize, Serialize};

/// A PacoAction is an action that can be applied to a PacoBoard to modify it.
/// An action is an atomic part of a move, like picking up a piece or placing it down.
#[derive(Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum PacoAction {
    /// Lifting a piece starts a move.
    Lift(BoardPosition),
    /// Placing the piece picked up earlier either ends a move or continues it in case of a chain.
    Place(BoardPosition),
    /// Promote the pawn that is currently up for promotion
    Promote(PieceType),
}

impl PacoAction {
    pub fn is_promotion(self) -> bool {
        matches!(self, PacoAction::Promote(_))
    }
    pub fn position(self) -> Option<BoardPosition> {
        match self {
            PacoAction::Lift(p) => Some(p),
            PacoAction::Place(p) => Some(p),
            PacoAction::Promote(_) => None,
        }
    }
}

/// BitBoard style representation of a set of PieceTypes.
/// Only the lower 6 bits are used.
#[derive(Clone, Copy, Debug)]
pub struct PieceTypeSet(u8);

impl PieceTypeSet {
    fn is_empty(self) -> bool {
        self.0 == 0
    }
    fn len(self) -> u8 {
        self.0.count_ones() as u8
    }
    fn contains(self, piece: PieceType) -> bool {
        self.0 & (1 << piece as u8) != 0
    }
    fn all_promotion_options() -> Self {
        PieceTypeSet(0b011110)
    }
}

/// Essentially a Set<PacoAction> which requires all actions to be of the same type.
/// Internally we can then represent it as a bit board.
/// This is suitable for replacing "list of valid actions" but unsuitable for
/// "sequence of moves".
#[derive(Clone, Copy, Debug)]
pub enum PacoActionSet {
    LiftSet(BitBoard),
    PlaceSet(BitBoard),
    PromoteSet(PieceTypeSet),
}

impl PacoActionSet {
    pub fn is_empty(self) -> bool {
        match self {
            PacoActionSet::LiftSet(set) => set.is_empty(),
            PacoActionSet::PlaceSet(set) => set.is_empty(),
            PacoActionSet::PromoteSet(set) => set.is_empty(),
        }
    }
    pub fn len(self) -> u8 {
        match self {
            PacoActionSet::LiftSet(set) => set.len(),
            PacoActionSet::PlaceSet(set) => set.len(),
            PacoActionSet::PromoteSet(set) => set.len(),
        }
    }
    pub fn contains(self, action: PacoAction) -> bool {
        match self {
            PacoActionSet::LiftSet(set) => match action {
                PacoAction::Lift(pos) => set.contains(pos),
                _ => false,
            },
            PacoActionSet::PlaceSet(set) => match action {
                PacoAction::Place(pos) => set.contains(pos),
                _ => false,
            },
            PacoActionSet::PromoteSet(set) => match action {
                PacoAction::Promote(piece) => set.contains(piece),
                _ => false,
            },
        }
    }
    pub fn iter(self) -> PacoActionSetIterator {
        self.into_iter()
    }
    pub fn all_promotion_options() -> Self {
        PacoActionSet::PromoteSet(PieceTypeSet::all_promotion_options())
    }
}

impl Default for PacoActionSet {
    fn default() -> Self {
        // Using Lift here is an arbitrary choice, as the set is empty anyway.
        PacoActionSet::LiftSet(BitBoard::default())
    }
}

/// I need an enum for the tag, in order to store the type of action in the
/// iterator.
enum PacoActionTag {
    Lift,
    Place,
    Promote,
}

pub struct PacoActionSetIterator {
    tag: PacoActionTag,
    bits: u64,
}

impl Iterator for PacoActionSetIterator {
    type Item = PacoAction;

    fn next(&mut self) -> Option<Self::Item> {
        if self.bits == 0 {
            None
        } else {
            // Get the index of the least significant set bit.
            let trailing_zeros = self.bits.trailing_zeros() as u8;
            // Clear the bit so that it's not considered in the next call.
            self.bits &= !(1 << trailing_zeros);
            match self.tag {
                PacoActionTag::Lift => Some(PacoAction::Lift(BoardPosition(trailing_zeros))),
                PacoActionTag::Place => Some(PacoAction::Place(BoardPosition(trailing_zeros))),
                PacoActionTag::Promote => {
                    Some(PacoAction::Promote(PieceType::from_u8(trailing_zeros)))
                }
            }
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        let len = self.bits.count_ones() as usize;
        (len, Some(len))
    }
}

impl IntoIterator for PacoActionSet {
    type Item = PacoAction;
    type IntoIter = PacoActionSetIterator;

    fn into_iter(self) -> Self::IntoIter {
        match self {
            PacoActionSet::LiftSet(set) => PacoActionSetIterator {
                tag: PacoActionTag::Lift,
                bits: set.0,
            },
            PacoActionSet::PlaceSet(set) => PacoActionSetIterator {
                tag: PacoActionTag::Place,
                bits: set.0,
            },
            PacoActionSet::PromoteSet(set) => PacoActionSetIterator {
                tag: PacoActionTag::Promote,
                bits: set.0 as u64,
            },
        }
    }
}
