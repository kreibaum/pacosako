use crate::db;
use crate::timer::{Timer, TimerConfig, TimerState};
use chrono::{DateTime, Utc};
use pacosako::{PacoAction, PacoBoard, PacoError};
use serde::{Deserialize, Serialize};
use serde_json::de::from_str;
use std::convert::TryFrom;
/// This module implements match synchonization on top of an instance manager.
/// That means when code in this module runs, the match it is running in is
/// already clear and we only implement the Paco Ŝako specific parts.

/// Parameters required to initialize a new instance of the match.
#[derive(Deserialize, Clone)]
pub struct MatchParameters {
    timer: Option<TimerConfig>,
}

/// A paco sako action together with a timestamp that remembers when it was done.
/// This timestamp is important for replays.
#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct StampedAction {
    #[serde(flatten)]
    action: PacoAction,
    timestamp: DateTime<Utc>,
}

/// A match is a recording of actions taken in it together with a unique
/// identifier that can be used to connect to the game.
/// It also takes care of tracking the timing and ensures actions are legal.
pub struct SyncronizedMatch {
    // TODO: Stop leaking private members by implementing stringify & parse in here.
    pub key: String,
    pub actions: Vec<StampedAction>,
    pub timer: Option<Timer>,
}

/// Message that may be send by the client to the server.
#[derive(Clone, Debug, Deserialize)]
pub enum ClientMatchMessage {
    GetCurrentState { key: String },
    Subscribe { key: String },
    DoAction { key: String, action: PacoAction },
    Rollback { key: String },
    SetTimer { key: String, timer: TimerConfig },
    StartTimer { key: String },
}

impl TryFrom<&str> for ClientMatchMessage {
    type Error = &'static str;

    fn try_from(text: &str) -> Result<Self, Self::Error> {
        if let Ok(client_message) = from_str(text) {
            Ok(client_message)
        } else {
            Err("Message could not be decoded.")
        }
    }
}

async fn _load_from_db(
    key: &str,
    mut conn: db::Connection,
) -> Result<SyncronizedMatch, anyhow::Error> {
    if let Some(game) = db::game::select(key.parse()?, &mut conn).await? {
        Ok(game)
    } else {
        Err(anyhow::anyhow!("Game with key {} not found.", key))
    }
}

async fn _store_to_db(
    game: &SyncronizedMatch,
    mut conn: db::Connection,
) -> Result<(), anyhow::Error> {
    db::game::update(game, &mut conn).await?;

    Ok(())
}

/// A complete description of the match state. This is currently send to all
/// clients whenever the game state changes. As it is only a list of some
/// actions, it should be lightweight enough that sending around the whole
/// history is not a bottleneck.
#[derive(Serialize, Clone, Debug)]
pub struct CurrentMatchState {
    key: String,
    actions: Vec<StampedAction>,
    legal_actions: Vec<PacoAction>,
    pub controlling_player: pacosako::PlayerColor,
    pub timer: Option<Timer>,
    pub victory_state: pacosako::VictoryState,
}

impl CurrentMatchState {
    /// Tries to create a new match state out of a syncronized match and an
    /// already projected board.
    fn try_new(
        sync_match: &SyncronizedMatch,
        board: &pacosako::DenseBoard,
    ) -> Result<Self, PacoError> {
        let victory_state = Self::victory_state(&board, &sync_match.timer);

        Ok(CurrentMatchState {
            key: sync_match.key.clone(),
            actions: sync_match.actions.clone(),
            legal_actions: if victory_state.is_over() {
                vec![]
            } else {
                board.actions()?
            },
            controlling_player: board.controlling_player(),
            timer: sync_match.timer.clone(),
            victory_state: victory_state,
        })
    }

    fn victory_state(
        board: &pacosako::DenseBoard,
        timer: &Option<Timer>,
    ) -> pacosako::VictoryState {
        if let Some(timer) = timer {
            if let TimerState::Timeout(color) = timer.get_state() {
                return pacosako::VictoryState::TimeoutVictory(color.other());
            }
        }
        board.victory_state()
    }
}

/// This implementation contains most of the "Business Logic" of the match.
impl SyncronizedMatch {
    pub fn new_with_key(key: &str, params: MatchParameters) -> Self {
        SyncronizedMatch {
            key: key.to_owned(),
            actions: Vec::default(),
            timer: params.timer.map(|t| t.into()),
        }
    }

    /// Reconstruct the board state
    fn project(&self) -> Result<pacosako::DenseBoard, PacoError> {
        // Here we don't need to validate the move, this was done before they
        // have been added to the action list.
        let mut board = pacosako::DenseBoard::new();
        for action in &self.actions {
            board.execute_trusted(action.action.clone())?;
        }
        Ok(board)
    }

    /// Validate and execute an action.
    pub fn do_action(&mut self, new_action: PacoAction) -> Result<CurrentMatchState, PacoError> {
        let mut board = self.project()?;
        let controlling_player = board.controlling_player();
        self.update_timer(controlling_player);

        // Check if the timer has run out, in that case we return an error.
        // Timing out the timer like this is not a problem, because the timeout
        // will ping this game instance (or may already have) and this will
        // broadcast the game state to all connections.
        if let Some(timer) = &self.timer {
            if let TimerState::Timeout(_) = timer.get_state() {
                return Err(PacoError::NotYourTurn);
            }
        }

        board.execute(new_action)?;
        self.actions.push(StampedAction {
            action: new_action,
            timestamp: Utc::now(),
        });

        // Check if controll changed. That would indicate that we need to add a
        // timer increment for the player that just finished their turn.
        if board.controlling_player() != controlling_player {
            if let Some(ref mut timer) = &mut self.timer {
                timer.increment(controlling_player);
            }
        }

        if board.victory_state().is_over() {
            if let Some(timer) = &mut self.timer {
                timer.stop()
            }
        }

        CurrentMatchState::try_new(self, &board)
    }

    /// Gets the current state and the currently available legal actions.
    pub fn current_state(&self) -> Result<CurrentMatchState, PacoError> {
        CurrentMatchState::try_new(self, &self.project()?)
    }

    /// Rolls back the game state to the start of the turn of the current player.
    pub fn rollback(&mut self) -> Result<CurrentMatchState, PacoError> {
        Self::rollback_trusted_action_stack(&mut self.actions)?;
        self.current_state()
    }

    /// Takes a board state that is provided in terms of an action history and
    /// rolls back an in-progress move. This will never change the active player.
    /// Rolling back on a settled board state does nothing.
    /// The action stack is assumed to only contain legal moves and the moves are
    /// not validated.
    fn rollback_trusted_action_stack(actions: &mut Vec<StampedAction>) -> Result<(), PacoError> {
        let last_checkpoint_index =
            pacosako::find_last_checkpoint_index(actions.iter().map(|a| &a.action))?;

        // Remove all moves to get back to last_checkpoint_index
        while actions.len() > last_checkpoint_index {
            actions.pop();
        }

        Ok(())
    }

    /// Updates the timer
    fn update_timer(&mut self, player: pacosako::PlayerColor) {
        if let Some(ref mut timer) = self.timer {
            if timer.get_state() == TimerState::NotStarted {
                timer.start(Utc::now());
            } else if timer.get_state() == TimerState::Running {
                timer.use_time(player, Utc::now());
            }
        }
    }

    /// Is triggered when there may have been significant timer progress.
    pub fn timer_progress(&mut self) -> Result<CurrentMatchState, PacoError> {
        let board = self.project()?;

        self.update_timer(board.controlling_player());

        CurrentMatchState::try_new(self, &board)
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use pacosako::types::BoardPosition;

    /// Does a move and mostly just checks that it does not crash.
    #[test]
    fn test_legal_moves_are_ok() {
        let mut game = SyncronizedMatch::new_with_key("Game1", MatchParameters { timer: None });

        game.do_action(PacoAction::Lift(BoardPosition(10))).unwrap();
        let current_state = game
            .do_action(PacoAction::Place(BoardPosition(18)))
            .unwrap();

        // recalculating the current state does not lead to surprises.
        let current_state_2 = game.current_state().unwrap();
        assert_eq!(current_state.key, current_state_2.key);
        let no_stamps: Vec<PacoAction> = current_state.actions.iter().map(|a| a.action).collect();
        let no_stamps_2: Vec<PacoAction> =
            current_state_2.actions.iter().map(|a| a.action).collect();
        assert_eq!(no_stamps, no_stamps_2);
        assert_eq!(current_state.legal_actions, current_state_2.legal_actions);

        // there are two moves in the state and 16 possible actions.
        assert_eq!(current_state.actions.len(), 2);
        assert_eq!(current_state.legal_actions.len(), 16);
    }
}
