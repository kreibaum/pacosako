use crate::instance_manager::{ClientMessage, Instance, ProvidesKey, ServerMessage};
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
}

/// Message that may be send by the client to the server.
#[derive(Clone)]
pub enum ClientMatchMessage {
    GetCurrentState { key: String },
    DoAction { key: String, action: PacoAction },
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

        board.execute(new_action)?;
        self.actions.push(new_action);

        Ok(CurrentMatchState {
            key: self.key.clone(),
            actions: self.actions.clone(),
            legal_actions: board.actions()?,
        })
    }

    /// Gets the current state and the currently available legal actions.
    fn current_state(&self) -> Result<CurrentMatchState, PacoError> {
        let board = self.project()?;
        Ok(CurrentMatchState {
            key: self.key.clone(),
            actions: self.actions.clone(),
            legal_actions: board.actions()?,
        })
    }
}

#[cfg(test)]
mod test {
    use super::*;
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
}
