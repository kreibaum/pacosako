use crate::{PlayerColor, VictoryState};

/// A float in the range [-1, 1] with helper functions to use this based on the
/// current player color.
///
/// We store the value that this represents for the white player. But that is an
/// implementation detail.
#[derive(Debug, Copy, Clone)]
pub(crate) struct ColoredValue(f32);

impl ColoredValue {
    pub(crate) fn new_for_player(value: f32, current_player: PlayerColor) -> Self {
        match current_player {
            PlayerColor::White => ColoredValue(value),
            PlayerColor::Black => ColoredValue(-value),
        }
    }

    pub(crate) fn new_for_victory_state(victory_state: VictoryState) -> Self {
        match victory_state {
            VictoryState::PacoVictory(PlayerColor::White) => ColoredValue(1.0),
            VictoryState::PacoVictory(PlayerColor::Black) => ColoredValue(-1.0),
            VictoryState::NoProgressDraw => ColoredValue(0.0),
            VictoryState::RepetitionDraw => ColoredValue(0.0),
            _ => panic!("Unexpected victory state"),
        }
    }

    pub(crate) fn value_for(&self, player: PlayerColor) -> f32 {
        match player {
            PlayerColor::White => self.0,
            PlayerColor::Black => -self.0,
        }
    }
}
