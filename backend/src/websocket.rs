use pacosako::{PacoAction, PacoBoard, PacoError};

use crate::instance_manager;
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

type R<T> = StdResult<T, WebsocketError>;

/// A match is a recording of actions taken in it together with a unique
/// identifier that can be used to connect to the game.
/// It also takes care of tracking the timing and ensures actions are legal.
struct SyncronizedMatch {
    key: String,
    actions: Vec<PacoAction>,
}

#[derive(Serialize)]
pub struct CurrentMatchState {
    key: String,
    actions: Vec<PacoAction>,
    legal_actions: Vec<PacoAction>,
}

/// This implementation contains most of the "Business Logic" of the match.
impl SyncronizedMatch {
    fn with_key(key: String) -> Self {
        SyncronizedMatch {
            key,
            actions: Vec::default(),
        }
    }

    /// Reconstruct the board state
    fn project(&self) -> R<pacosako::DenseBoard> {
        // Here we don't need to validate the move, this was done before they
        // have been added to the action list.
        let mut board = pacosako::DenseBoard::new();
        for action in &self.actions {
            board.execute_trusted(action.clone())?;
        }
        Ok(board)
    }

    /// Validate and execute an action.
    fn do_action(&mut self, new_action: PacoAction) -> R<CurrentMatchState> {
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
    fn current_state(&self) -> R<CurrentMatchState> {
        let board = self.project()?;
        Ok(CurrentMatchState {
            key: self.key.clone(),
            actions: self.actions.clone(),
            legal_actions: board.actions()?,
        })
    }
}

struct Connection {
    sender: Sender,
    // Legacy: syncronized board designer
    game_key: String,
    // Going forward, this one is used for real games.
    match_key: String,
}

#[derive(Default)]
struct SyncServer {
    // This games variable is actually shared board designer states, so I want
    // rename them and somewhat change how they work.
    games: HashMap<String, SyncronizedBoard>,
    matches: HashMap<String, SyncronizedMatch>,
    connections: Vec<Connection>,
}

pub struct MatchMoveInstruction {
    key: String,
    action: PacoAction,
}

#[derive(Default, Clone)]
pub struct WebsocketServer(Arc<Mutex<SyncServer>>);

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

impl WebsocketServer {
    pub fn create_game(&self) -> String {
        lock!(self).create_game()
    }

    pub fn do_move(&self, instruction: MatchMoveInstruction) -> R<CurrentMatchState> {
        lock!(self)
            .get_match(&instruction.key)
            .ok_or_else(|| WebsocketError::MatchNotFound(instruction.key.clone()))?
            .do_action(instruction.action)
    }

    pub fn current_state(&self, key: &str) -> R<CurrentMatchState> {
        lock!(self)
            .get_match(&key)
            .ok_or_else(|| WebsocketError::MatchNotFound(key.into()))?
            .current_state()
    }
}

impl SyncServer {
    fn create_game(&mut self) -> String {
        // Get a unique id
        let key = generate_key(&self.matches);
        let board = SyncronizedMatch::with_key(key.clone());
        // Add the board to the list of games
        self.matches.insert(key.clone(), board);

        println!("Created game with key {}", key);

        key
    }

    fn get_match(&mut self, key: &str) -> Option<&mut SyncronizedMatch> {
        self.matches.get_mut(key)
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
    CurrentMatchState(CurrentMatchState),
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

// Create a new Syncronized Match. This will return the string identifier of
// the match and the client can then subscribe on the websocket.
pub fn create_match(server: &WebsocketServer) -> String {
    _create_match(lock!(server))
}

fn _create_match(server: &mut SyncServer) -> String {
    let key = generate_key(&server.matches);
    let s_match = SyncronizedMatch::with_key(key.clone());
    server.matches.insert(key.clone(), s_match);
    key
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
    instance_manager::generate_unique_key(map)
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
                match_key: "".to_owned(),
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

/// Call this function to subscribe a websocket connection to a match.
/// This does not look great right now, definitely needs a refactoring.
fn subscribe_match(server: &mut SyncServer, sender: &Sender, match_key: String) -> Result<()> {
    if let Some(s_match) = server.matches.get(&match_key) {
        let current_state = s_match.current_state();
        match current_state {
            Ok(current_state) => subscribe_match_2(server, sender, current_state),
            Err(e) => ServerMessage::TechnicalError {
                error_message: "error while subscribing to match".to_owned(),
            }
            .send_to(sender),
        }
    } else {
        ServerMessage::TechnicalError {
            error_message: format!("There is no match with key='{}'.", match_key),
        }
        .send_to(sender)
    }
}

fn subscribe_match_2(
    server: &mut SyncServer,
    sender: &Sender,
    current_state: CurrentMatchState,
) -> Result<()> {
    // Find the connection of the current user and update the game key.
    // If the sender has not connected to any game, create a connection.
    if let Some(connection) = find_connection_by_sender_mut(&mut server.connections, &sender) {
        connection.game_key = current_state.key.clone();
        // Send the current state of the match the client just subscribed to.
        ServerMessage::CurrentMatchState(current_state).send_to(sender)
    } else {
        let connection = Connection {
            sender: sender.clone(),
            game_key: "".to_owned(),
            match_key: current_state.key.clone(),
        };
        // Send the current state of the match the client just subscribed to.
        ServerMessage::CurrentMatchState(current_state).send_to(sender)?;
        server.connections.push(connection);
        Ok(())
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

fn do_action(
    server: &mut SyncServer,
    sender: &Sender,
    key: String,
    action: PacoAction,
) -> Result<()> {
    if let Some(connection) = find_connection_by_sender_mut(&mut server.connections, sender) {
        if connection.match_key != key {
            return ServerMessage::TechnicalError {
                error_message: "You must be connected to the match.".to_owned(),
            }
            .send_to(sender);
        }

        if let Some(s_match) = server.matches.get_mut(&key) {
            let new_state = s_match.do_action(action);
            let message = match new_state {
                Ok(s) => ServerMessage::CurrentMatchState(s),
                Err(_) => ServerMessage::TechnicalError {
                    error_message: "Step did not work.".to_owned(),
                },
            };

            message.send_to(sender)?;
        }
    } else {
        ServerMessage::TechnicalError {
            error_message: "You must be connected to the match.".to_owned(),
        }
        .send_to(sender)?;
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
        ClientMessage::SubscribeToMatch { key } => subscribe_match(lock!(server), sender, key),
        ClientMessage::DoAction { key, action } => do_action(lock!(server), sender, key, action),
    }
}
