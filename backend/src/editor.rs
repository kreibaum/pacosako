//! Instance implementation for the editor share.
//! This is quite a simple definition, as any change will just be verifid and
//! then broadcasted to all connected clients.

use crate::instance_manager::{self, Context, Instance, ProvidesKey};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::from_str;
use std::{borrow::Cow, convert::TryFrom};

#[derive(Serialize, Clone, Debug)]
pub struct SyncronizedBoard {
    key: String,
    steps: Vec<serde_json::Value>,
}

impl Instance for SyncronizedBoard {
    /// The type of messages send by the client to the server.
    type ClientMessage = ClientMessage;
    type ServerMessage = ServerMessage;
    type InstanceParameters = ();
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String> {
        Cow::Borrowed(&self.key)
    }
    /// Create a new instance and make it store the key.
    fn new_with_key(key: &str, _params: ()) -> Self {
        SyncronizedBoard {
            key: key.to_string(),
            steps: Vec::new(),
        }
    }
    /// Accept a client message and possibly send messages back.
    fn handle_message(&mut self, message: Self::ClientMessage, ctx: &mut Context<Self>) {
        match message {
            ClientMessage::Subscribe { .. } => ctx.reply(ServerMessage::FullState {
                board: self.clone(),
            }),
            ClientMessage::NextStep { index, step, .. } => {
                if self.steps.len() != index {
                    ctx.reply(ServerMessage::TechnicalError {
                        error_message: format!(
                            "Sync error: You are trying to add step {}, but you must add step {}.",
                            index,
                            self.steps.len()
                        ),
                    });
                    ctx.reply(ServerMessage::FullState {
                        board: self.clone(),
                    });
                } else {
                    self.steps.push(step.clone());
                    ctx.broadcast(ServerMessage::NextStep { index, step });
                }
            }
        }
    }
    /// Called, when the instance set a timout itself and this timeout has passed
    fn handle_timeout(&mut self, _now: DateTime<Utc>, _ctx: &mut Context<Self>) {
        // We are not using timeouts.
    }

    fn load_from_db(key: &str, conn: crate::db::game::Conn) -> Result<Self, anyhow::Error> {
        Err(anyhow::anyhow!("Loading from db not imlemented."))
    }

    fn store_to_db(&self, conn: crate::db::game::Conn) -> Result<(), anyhow::Error> {
        Err(anyhow::anyhow!("Storing to db not imlemented."))
    }
}

/// All allowed messages that may be send by the client to the server.
#[derive(Deserialize, Clone, Debug)]
pub enum ClientMessage {
    Subscribe {
        game_key: String,
    },
    NextStep {
        game_key: String,
        index: usize,
        step: serde_json::Value,
    },
}

impl ProvidesKey for ClientMessage {
    fn key(&self) -> Cow<String> {
        match self {
            ClientMessage::Subscribe { game_key } => Cow::Borrowed(game_key),
            ClientMessage::NextStep { game_key, .. } => Cow::Borrowed(game_key),
        }
    }
}

impl instance_manager::ClientMessage for ClientMessage {
    fn subscribe(key: String) -> Self {
        ClientMessage::Subscribe { game_key: key }
    }
}

impl TryFrom<&str> for ClientMessage {
    type Error = &'static str;

    fn try_from(text: &str) -> Result<Self, Self::Error> {
        if let Ok(client_message) = from_str(text) {
            Ok(client_message)
        } else {
            Err("Message could not be decoded.")
        }
    }
}
/// All allowed messages that may be send by the server to the client.
#[derive(Serialize, Clone, Debug)]
pub enum ServerMessage {
    TechnicalError {
        error_message: String,
    },
    FullState {
        board: SyncronizedBoard,
    },
    NextStep {
        index: usize,
        step: serde_json::Value,
    },
}

impl instance_manager::ServerMessage for ServerMessage {
    fn error(message: Cow<String>) -> Self {
        ServerMessage::TechnicalError {
            error_message: message.to_string(),
        }
    }
}

/// This is for the old websocket server!
impl From<ServerMessage> for String {
    fn from(msg: ServerMessage) -> Self {
        use serde_json::ser::to_string;

        match to_string(&msg) {
            Ok(value) => value,
            Err(e) => format!(
                "An error occurred when serializing a websocket server message: {}",
                e
            ),
        }
    }
}
