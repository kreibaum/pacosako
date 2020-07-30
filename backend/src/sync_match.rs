use crate::instance_manager::{ClientMessage, Instance, ProvidesKey, ServerMessage};
use crate::timer::{Timer, TimerConfig, TimerState};
use chrono::Utc;
use pacosako::{PacoAction, PacoBoard, PacoError};
use serde::Serialize;
use std::borrow::Cow;

/// This module implements match synchonization on top of an instance manager.
/// That means when code in this module runs, the match it is running in is
/// already clear and we only implement the Paco Ŝako specific parts.

/// A match is a recording of actions taken in it together with a unique
/// identifier that can be used to connect to the game.
/// It also takes care of tracking the timing and ensures actions are legal.
pub struct SyncronizedMatch {
    key: String,
    actions: Vec<PacoAction>,
    timer: Option<Timer>,
}

/// Message that may be send by the client to the server.
#[derive(Clone)]
pub enum ClientMatchMessage {
    GetCurrentState { key: String },
    DoAction { key: String, action: PacoAction },
    Rollback { key: String },
    SetTimer { key: String, timer: TimerConfig },
    StartTimer { key: String },
}

impl ClientMessage for ClientMatchMessage {
    fn subscribe(key: String) -> Self {
        ClientMatchMessage::GetCurrentState { key }
    }
}

impl ProvidesKey for ClientMatchMessage {
    fn key(&self) -> Cow<String> {
        match self {
            ClientMatchMessage::DoAction { key, .. } => Cow::Borrowed(key),
            ClientMatchMessage::GetCurrentState { key } => Cow::Borrowed(key),
            ClientMatchMessage::Rollback { key } => Cow::Borrowed(key),
            ClientMatchMessage::SetTimer { key, .. } => Cow::Borrowed(key),
            ClientMatchMessage::StartTimer { key } => Cow::Borrowed(key),
        }
    }
}

/// Messages that may be send by the server to the client.
#[derive(Clone, Serialize)]
pub enum ServerMatchMessage {
    CurrentMatchState(CurrentMatchState),
    Error(String),
}

impl ServerMessage for ServerMatchMessage {
    fn error(message: std::borrow::Cow<String>) -> Self {
        ServerMatchMessage::Error(message.into_owned())
    }
}

impl From<ServerMatchMessage> for ws::Message {
    fn from(msg: ServerMatchMessage) -> Self {
        use serde_json::ser::to_string;

        let text = match to_string(&msg) {
            Ok(value) => value,
            Err(e) => format!(
                "An error occurred when serializing a websocket server message: {}",
                e
            ),
        };

        ws::Message::text(text)
    }
}

/// Instance is the magic trait that makes the instance_manager work.
impl Instance for SyncronizedMatch {
    type ClientMessage = ClientMatchMessage;
    type ServerMessage = ServerMatchMessage;

    fn key(&self) -> std::borrow::Cow<String> {
        Cow::Borrowed(&self.key)
    }

    fn new_with_key(key: &str) -> Self {
        SyncronizedMatch {
            key: key.to_owned(),
            actions: Vec::default(),
            timer: None,
        }
    }

    fn handle_message(
        &mut self,
        message: Self::ClientMessage,
        ctx: &mut crate::instance_manager::Context<Self>,
    ) {
        match message {
            ClientMatchMessage::DoAction { action, .. } => {
                match self.do_action(action) {
                    Ok(state) => {
                        // The state was changed, this must be broadcast to
                        // all subscribed players.
                        ctx.broadcast(ServerMatchMessage::CurrentMatchState(state))
                    }
                    Err(e) => {
                        // An error occured, this is only reported back to the
                        // player that caused it.
                        ctx.reply(ServerMatchMessage::Error(format!(
                            "Game logic is violated by this action: {:?}",
                            e
                        )))
                    }
                }
            }

            ClientMatchMessage::GetCurrentState { .. } => match self.current_state() {
                Ok(state) => ctx.reply(ServerMatchMessage::CurrentMatchState(state)),
                Err(e) => ctx.reply(ServerMatchMessage::Error(format!(
                    "Game logic is violated by this action: {:?}",
                    e
                ))),
            },

            ClientMatchMessage::Rollback { .. } => match self.rollback() {
                Ok(state) => ctx.reply(ServerMatchMessage::CurrentMatchState(state)),
                Err(e) => ctx.reply(ServerMatchMessage::Error(format!(
                    "Game logic is violated by this action: {:?}",
                    e
                ))),
            },

            ClientMatchMessage::SetTimer { timer, .. } => match self.set_timer(timer) {
                Ok(state) => ctx.broadcast(ServerMatchMessage::CurrentMatchState(state)),
                Err(e) => ctx.reply(ServerMatchMessage::Error(format!(
                    "The timer can't be modified: {:?}",
                    e
                ))),
            },
            ClientMatchMessage::StartTimer { .. } => {
                self.start_timer();

                match self.current_state() {
                    Ok(state) => ctx.broadcast(ServerMatchMessage::CurrentMatchState(state)),
                    Err(_) => {}
                }
            }
        }
    }
}

/// A complete description of the match state. This is currently send to all
/// clients whenever the game state changes. As it is only a list of some
/// actions, it should be lightweight enough that sending around the whole
/// history is not a bottleneck.
#[derive(Serialize, Clone)]
pub struct CurrentMatchState {
    key: String,
    actions: Vec<PacoAction>,
    legal_actions: Vec<PacoAction>,
    controlling_player: pacosako::PlayerColor,
    timer: Option<Timer>,
}

/// This implementation contains most of the "Business Logic" of the match.
impl SyncronizedMatch {
    /// Reconstruct the board state
    fn project(&self) -> Result<pacosako::DenseBoard, PacoError> {
        // Here we don't need to validate the move, this was done before they
        // have been added to the action list.
        let mut board = pacosako::DenseBoard::new();
        for action in &self.actions {
            board.execute_trusted(action.clone())?;
        }
        Ok(board)
    }

    /// Validate and execute an action.
    fn do_action(&mut self, new_action: PacoAction) -> Result<CurrentMatchState, PacoError> {
        let mut board = self.project()?;
        let controlling_player = board.controlling_player();

        board.execute(new_action)?;
        self.actions.push(new_action);

        self.update_timer(controlling_player);

        Ok(CurrentMatchState {
            key: self.key.clone(),
            actions: self.actions.clone(),
            legal_actions: board.actions()?,
            controlling_player: board.controlling_player(),
            timer: self.timer.clone(),
        })
    }

    /// Gets the current state and the currently available legal actions.
    fn current_state(&self) -> Result<CurrentMatchState, PacoError> {
        let board = self.project()?;
        Ok(CurrentMatchState {
            key: self.key.clone(),
            actions: self.actions.clone(),
            legal_actions: board.actions()?,
            controlling_player: board.controlling_player(),
            timer: self.timer.clone(),
        })
    }

    /// Rolls back the game state to the start of the turn of the current player.
    fn rollback(&mut self) -> Result<CurrentMatchState, PacoError> {
        pacosako::rollback_trusted_action_stack(&mut self.actions)?;
        self.current_state()
    }

    /// Sets the timer configuration of the game. This will return an error if
    /// the game is already running.
    fn set_timer(&mut self, timer_config: TimerConfig) -> Result<CurrentMatchState, PacoError> {
        if self.can_change_timer() {
            self.timer = Some(timer_config.into());
        } else {
            return Err(PacoError::ActionNotLegal);
        }

        self.current_state()
    }

    /// Decides if changing the timer is still allowed.
    fn can_change_timer(&self) -> bool {
        if !self.actions.is_empty() {
            false
        } else if let Some(ref timer) = self.timer {
            timer.get_state() == TimerState::NotStarted
        } else {
            true
        }
    }

    /// Starts the timer if it exists and is not Running or Timeout(..) yet.
    /// This function does nothing otherwise.
    fn start_timer(&mut self) {
        if let Some(ref mut timer) = self.timer {
            if timer.get_state() == TimerState::NotStarted {
                timer.start(Utc::now())
            }
        }
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
}

#[cfg(test)]
mod test {
    use super::*;
    use chrono::Duration;
    use pacosako::types::BoardPosition;

    /// Does a move and mostly just checks that it does not crash.
    #[test]
    fn test_legal_moves_are_ok() {
        let mut game = SyncronizedMatch::new_with_key("Game1");

        game.do_action(PacoAction::Lift(BoardPosition(10))).unwrap();
        let current_state = game
            .do_action(PacoAction::Place(BoardPosition(18)))
            .unwrap();

        // recalculating the current state does not lead to surprises.
        let current_state_2 = game.current_state().unwrap();
        assert_eq!(current_state.key, current_state_2.key);
        assert_eq!(current_state.actions, current_state_2.actions);
        assert_eq!(current_state.legal_actions, current_state_2.legal_actions);

        // there are two moves in the state and 16 possible actions.
        assert_eq!(current_state.actions.len(), 2);
        assert_eq!(current_state.legal_actions.len(), 16);
    }

    /// Tests setting the timer before and after the game starts
    #[test]
    fn test_setting_timer() -> Result<(), PacoError> {
        let mut game = SyncronizedMatch::new_with_key("Game1");

        // This should be allowed. (Assert via ?)
        game.set_timer(TimerConfig {
            time_budget_white: Duration::seconds(100),
            time_budget_black: Duration::seconds(100),
        })?;

        // This should be allowed. (Assert via ?)
        game.set_timer(TimerConfig {
            time_budget_white: Duration::seconds(200),
            time_budget_black: Duration::seconds(150),
        })?;

        // Start the game, then changing should no longer be allowed.
        game.start_timer();
        let match_state = game.set_timer(TimerConfig {
            time_budget_white: Duration::seconds(100),
            time_budget_black: Duration::seconds(100),
        });
        assert!(match_state.is_err());

        Ok(())
    }
}
