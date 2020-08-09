use pacosako::{PacoAction, PacoError};

use crate::{instance_manager, sync_match, timer};
use serde::{Deserialize, Serialize};
use serde_json::de::from_str;
use serde_json::ser::to_string;
use std::collections::HashMap;
use std::convert::TryFrom;
use std::result::Result as StdResult;
use std::sync::{Arc, Mutex};
use std::{borrow::Cow, thread};
use ws::listen;
use ws::{Message, Result, Sender};

/// A websocket for live game sync using websockets.
/// This is using the ws-rs library which seems to be in a reasonable state,
/// as the owner is willing to hand over maintainership and other people have
/// asked to step in. I think it is also mostly done, seeing as it passes the
/// Autobahn test suite, so I think the current state is ok.
///
/// https://github.com/housleyjk/ws-rs/issues/315
///
/// There is no dedicated websocket support in Rocket right now, but if it
/// lands, we will likely switch to that.
///
/// https://github.com/SergioBenitez/Rocket/issues/90

#[derive(Serialize)]
struct SyncronizedBoard {
    key: String,
    steps: Vec<serde_json::Value>,
}

/// All the errors that can be returned.
pub enum WebsocketError {
    PacoError(PacoError),
    MatchNotFound(String),
}

/// Make sure PacoError is ?-compatible
impl From<PacoError> for WebsocketError {
    fn from(e: PacoError) -> Self {
        WebsocketError::PacoError(e)
    }
}

struct Connection {
    sender: Sender,
    // Legacy: syncronized board designer
    game_key: String,
}

#[derive(Default)]
struct SyncServer {
    // This games variable is actually shared board designer states, so I want
    // rename them and somewhat change how they work.
    games: HashMap<String, SyncronizedBoard>,
    connections: Vec<Connection>,
}

#[derive(Default, Clone)]
pub struct WebsocketServer {
    inner: Arc<Mutex<SyncServer>>,
    matches: instance_manager::Manager<sync_match::SyncronizedMatch>,
}

/// This can't be a function because a function would have its own stack frame
/// and would need to drop the result of server.lock() before returning. This
/// is impossible if it wants to return a mutable reference to the droped data.
///
///     lock!(server: WebsocketServer) -> &mut SyncServer
macro_rules! lock {
    ( $server:expr ) => {{
        &mut *($server.inner.lock().unwrap())
    }};
}

impl WebsocketServer {
    pub fn new_match(&self, params: sync_match::MatchParameters) -> String {
        self.matches.new_instance(params)
    }
}

/// All allowed messages that may be send by the client to the server.
#[derive(Deserialize)]
enum ClientMessage {
    Subscribe {
        game_key: String,
    },
    NextStep {
        index: usize,
        step: serde_json::Value,
    },
    /// Send this, if you want to be informed about what happens in a match.
    SubscribeToMatch {
        key: String,
    },
    DoAction {
        key: String,
        action: PacoAction,
    },
    Rollback {
        key: String,
    },
    SetTimer {
        key: String,
        timer: timer::TimerConfig,
    },
    StartTimer {
        key: String,
    },
}

/// Filter the general websocket messages into ClientMatchMessages or return
/// Err(()) if the message is not a ClientMatchMessage.
impl TryFrom<&ClientMessage> for sync_match::ClientMatchMessage {
    type Error = ();
    fn try_from(value: &ClientMessage) -> StdResult<Self, Self::Error> {
        match value {
            ClientMessage::DoAction { key, action } => {
                Ok(sync_match::ClientMatchMessage::DoAction {
                    key: key.clone(),
                    action: action.clone(),
                })
            }
            ClientMessage::Rollback { key } => {
                Ok(sync_match::ClientMatchMessage::Rollback { key: key.clone() })
            }
            ClientMessage::SetTimer { key, timer } => {
                Ok(sync_match::ClientMatchMessage::SetTimer {
                    key: key.clone(),
                    timer: timer.clone(),
                })
            }
            ClientMessage::StartTimer { key } => {
                Ok(sync_match::ClientMatchMessage::StartTimer { key: key.clone() })
            }
            _ => Err(()),
        }
    }
}

/// All allowed messages that may be send by the server to the client.
#[derive(Serialize)]
enum ServerMessage<'a> {
    TechnicalError {
        error_message: String,
    },
    FullState {
        board: &'a SyncronizedBoard,
    },
    NextStep {
        index: usize,
        step: &'a serde_json::Value,
    },
}

impl TryFrom<Message> for ClientMessage {
    type Error = &'static str;
    fn try_from(message: Message) -> StdResult<Self, Self::Error> {
        if let Ok(text) = message.as_text() {
            if let Ok(client_message) = from_str(text) {
                Ok(client_message)
            } else {
                Err("Message could not be decoded.")
            }
        } else {
            Err("Message did not have a text body.")
        }
    }
}

impl<'a> ServerMessage<'a> {
    fn send_to(&'a self, sender: &Sender) -> Result<()> {
        sender.send(to_string(self).unwrap_or("null".to_owned()))
    }
}

/// Create a new Syncronized Board and connect the current user to this board.
/// The given list of states will be stored with the board.
pub fn share(
    server: &WebsocketServer,
    steps: Vec<serde_json::Value>,
) -> StdResult<String, &'static str> {
    if steps.is_empty() {
        Err("You need to have at least one step to share a board.")
    } else {
        Ok(share_(lock!(server), steps))
    }
}

/// Internal version of the share function that is called after the mutex is handled.
/// Returns the key that was assigned to the syncronized board.
fn share_(server: &mut SyncServer, steps: Vec<serde_json::Value>) -> String {
    // Get a unique id
    let key = generate_key(&server.games);
    let board = SyncronizedBoard {
        key: key.clone(),
        steps,
    };
    // Add the board to the list of games
    server.games.insert(key.clone(), board);
    key
}

/// Returns a key that is not yet used in the map.
fn generate_key<T>(map: &HashMap<String, T>) -> String {
    instance_manager::generate_unique_key_alphabetic(map)
}

fn find_connection_by_sender_mut<'a>(
    connections: &'a mut Vec<Connection>,
    sender: &Sender,
) -> Option<&'a mut Connection> {
    // This will quickly become inefficient, when more than a few player are
    // connected. I also have no way to evict old connections right now.
    // TODO: As Connection implements Hash, this should be a hash map instead.
    for connection in connections {
        if connection.sender == *sender {
            return Some(connection);
        }
    }
    None
}

/// Call this function to subscribe a websocket connection to a game board.
/// If the websocket is already connected to a syncronized board, the old
/// connection will be dropped.
fn subscribe(server: &mut SyncServer, sender: &Sender, game_key: String) -> Result<()> {
    if let Some(board) = server.games.get(&game_key) {
        let response = ServerMessage::FullState { board };

        // Find the connection of the current user and update the game key.
        // If the sender has not connected to any game, create a connection.
        if let Some(connection) = find_connection_by_sender_mut(&mut server.connections, &sender) {
            connection.game_key = game_key;
            response.send_to(sender)
        } else {
            let connection = Connection {
                sender: sender.clone(),
                game_key: game_key,
            };
            response.send_to(sender)?;
            server.connections.push(connection);
            Ok(())
        }
    } else {
        ServerMessage::TechnicalError {
            error_message: format!("There is no syncronized board with key='{}'.", game_key),
        }
        .send_to(sender)
    }
}

/// The client uploads a new state and indicates which index they believe it
/// should be at. They have to give the index to check that they don't try to do
/// an update based on an outdated state.
///
/// If this function detects that the client is out of sync, it will push the
/// full current state to the client.
fn next_step(
    server: &mut SyncServer,
    sender: &Sender,
    index: usize,
    step: serde_json::Value,
) -> Result<()> {
    let game_key =
        if let Some(connection) = find_connection_by_sender_mut(&mut server.connections, &sender) {
            &connection.game_key
        } else {
            return ServerMessage::TechnicalError {
                error_message: format!("This client is not subscribed to any game."),
            }
            .send_to(sender);
        }
        .clone();

    if let Some(board) = server.games.get_mut(&game_key) {
        if index != board.steps.len() {
            ServerMessage::TechnicalError {
                error_message: format!(
                    "Sync error: You are trying to add step {}, but you must add step {}.",
                    index,
                    board.steps.len()
                ),
            }
            .send_to(sender)?;
            return ServerMessage::FullState { board }.send_to(sender);
        }
        // Add step to the board
        board.steps.push(step.clone());

        // Broadcast to all subscribed connections.
        for connection in &server.connections {
            if connection.game_key == *game_key {
                ServerMessage::NextStep { index, step: &step }.send_to(&connection.sender)?;
            }
        }
    }

    Ok(())
}

////////////////////////////////////////////////////////////////////////////////
/// General Websocket infrastructure functions /////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/// Spawns a thread to run a websocket server.
pub fn run_websocket() -> WebsocketServer {
    let server = WebsocketServer::default();
    run_websocket_internal(server.clone());
    server
}

fn run_websocket_internal(server: WebsocketServer) {
    thread::spawn(move || {
        listen("0.0.0.0:3012", |sender| {
            // For each sender, we need to store an Arc to the SyncServer.
            let server = server.clone();
            move |msg| on_message(&server, &sender, msg)
        })
    });
}

/// Decodes the message from the client and handles errors if they occur.
/// After the message has been decoded, on_client_message is called.
fn on_message(server: &WebsocketServer, sender: &Sender, msg: Message) -> Result<()> {
    match ClientMessage::try_from(msg) {
        Ok(client_message) => on_client_message(server, sender, client_message),
        Err(error_message) => ServerMessage::TechnicalError {
            error_message: error_message.to_owned(),
        }
        .send_to(sender),
    }
}

/// Matches the client message and calls a function which handles it.
fn on_client_message(
    server: &WebsocketServer,
    sender: &Sender,
    client_message: ClientMessage,
) -> Result<()> {
    use std::convert::TryInto;
    if let Ok(msg) = (&client_message).try_into() {
        server.matches.handle_message(msg, sender.clone());
        return Ok(());
    }

    match client_message {
        ClientMessage::Subscribe { game_key } => subscribe(lock!(server), sender, game_key),
        ClientMessage::NextStep { index, step } => next_step(lock!(server), sender, index, step),
        ClientMessage::SubscribeToMatch { key } => {
            Ok(server.matches.subscribe(Cow::Owned(key), sender.clone()))
        }
        ClientMessage::DoAction { .. } => Ok(()), // Already handled earlier.
        ClientMessage::Rollback { .. } => Ok(()), // Already handled earlier.
        ClientMessage::SetTimer { .. } => Ok(()), // Already handled earlier.
        ClientMessage::StartTimer { .. } => Ok(()), // Already handled earlier.
    }
}
