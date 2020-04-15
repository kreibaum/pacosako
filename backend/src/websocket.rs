use rand::distributions::Alphanumeric;
use rand::{thread_rng, Rng};
use serde::{Deserialize, Serialize};
use serde_json::de::from_str;
use serde_json::ser::to_string;
use std::collections::HashMap;
use std::convert::TryFrom;
use std::result::Result as StdResult;
use std::sync::{Arc, Mutex};
use std::thread;
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

struct Connection {
    sender: Sender,
    game_key: String,
}

#[derive(Default)]
struct SyncServer {
    games: HashMap<String, SyncronizedBoard>,
    connections: Vec<Connection>,
}

#[derive(Default, Clone)]
pub struct WebsocketServer(Arc<Mutex<SyncServer>>);

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

/// This can't be a function because a function would have its own stack frame
/// and would need to drop the result of server.lock() before returning. This
/// is impossible if it wants to return a mutable reference to the droped data.
///
///     lock!(server: WebsocketServer) -> &mut SyncServer
macro_rules! lock {
    ( $server:expr ) => {{
        &mut *($server.0.lock().unwrap())
    }};
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
    let key = generate_key(server);
    let board = SyncronizedBoard {
        key: key.clone(),
        steps,
    };
    // Add the board to the list of games
    server.games.insert(key.clone(), board);
    key
}

fn generate_key(server: &SyncServer) -> String {
    let code: usize = thread_rng().gen_range(0, 9000);
    let rand_string: String = format!("{}", code + 1000);
    if server.games.contains_key(&rand_string) {
        generate_key(server)
    } else {
        rand_string
    }
}

fn find_connection_by_sender_mut<'a>(
    connections: &'a mut Vec<Connection>,
    sender: &'a Sender,
) -> Option<&'a mut Connection> {
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
    match client_message {
        ClientMessage::Subscribe { game_key } => subscribe(lock!(server), sender, game_key),
        ClientMessage::NextStep { index, step } => next_step(lock!(server), sender, index, step),
    }
}
