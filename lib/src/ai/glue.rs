//! Various glue code related to the AI.

use crate::{ai::repr, BoardPosition, PacoAction, PlayerColor};

/// Maps the action to the index which represents the action in the policy
/// vector. Julia uses 1-based indexing, so we add 1 to the index.
/// And the onnx model returns a vector of size 133 where index 0 is the value.
/// So we are fine with 1-based indexing there.
pub const fn action_to_action_index(action: PacoAction) -> u8 {
    use crate::PacoAction::*;
    use crate::PieceType::*;
    match action {
        Lift(p) => 1 + p.0,
        Place(p) => 1 + p.0 + 64,
        Promote(Rook) => 129,
        Promote(Knight) => 130,
        Promote(Bishop) => 131,
        Promote(Queen) => 132,
        Promote(_) => 255,
    }
}

pub fn action_to_action_index_with_viewpoint(action: PacoAction, viewpoint: PlayerColor) -> u8 {
    use crate::PacoAction::*;
    use crate::PieceType::*;
    match action {
        Lift(p) => 1 + repr::viewpoint_tile(viewpoint, p).0,
        Place(p) => 1 + repr::viewpoint_tile(viewpoint, p).0 + 64,
        Promote(Rook) => 129,
        Promote(Knight) => 130,
        Promote(Bishop) => 131,
        Promote(Queen) => 132,
        Promote(_) => 255,
    }
}

pub const fn action_index_to_action(action_index: u8) -> Option<PacoAction> {
    use crate::PacoAction::*;
    use crate::PieceType::*;
    Some(match action_index {
        1..=64 => Lift(BoardPosition(action_index - 1)),
        65..=128 => Place(BoardPosition(action_index - 1 - 64)),
        129 => Promote(Rook),
        130 => Promote(Knight),
        131 => Promote(Bishop),
        132 => Promote(Queen),
        _ => return None,
    })
}

pub fn action_index_to_action_with_viewpoint(
    action_index: u8,
    viewpoint: PlayerColor,
) -> Option<PacoAction> {
    use crate::PacoAction::*;

    let action = action_index_to_action(action_index)?;
    Some(match action {
        Lift(p) => Lift(repr::viewpoint_tile(viewpoint, p)),
        Place(p) => Place(repr::viewpoint_tile(viewpoint, p)),
        Promote(_) => action,
    })
}

#[cfg(test)]
mod test {
    use crate::PieceType::*;

    use super::*;

    #[test]
    fn action_to_index_to_action() {
        for p in BoardPosition::all() {
            assert_eq!(
                action_index_to_action(action_to_action_index(PacoAction::Lift(p))),
                Some(PacoAction::Lift(p))
            );
            assert_eq!(
                action_index_to_action(action_to_action_index(PacoAction::Place(p))),
                Some(PacoAction::Place(p))
            );
        }
        for t in [Rook, Knight, Bishop, Queen] {
            assert_eq!(
                action_index_to_action(action_to_action_index(PacoAction::Promote(t))),
                Some(PacoAction::Promote(t))
            );
        }
    }

    #[test]
    fn index_to_action_to_index() {
        for i in 1..=132 {
            assert_eq!(
                action_to_action_index(action_index_to_action(i).unwrap()),
                i
            );
        }
    }
}
