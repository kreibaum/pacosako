/// Handles all the websocket client logic.
pub mod client_connector;
pub mod timeout_connector;

use crate::{
    db,
    sync_match::{CurrentMatchState, SyncronizedMatch},
    ServerError,
};
use async_channel::{Receiver, Sender};
use async_std::task;
use async_tungstenite::tungstenite::Message;
use chrono::{DateTime, Utc};
use client_connector::{PeerMap, WebsocketOutMsg};
use log::*;
use pacosako::PacoAction;
use serde::{Deserialize, Serialize};
use serde_json::de::from_str;
use serde_json::ser::to_string;
use std::{
    collections::{HashMap, HashSet},
    net::SocketAddr,
};

use self::timeout_connector::TimeoutOutMsg;

pub fn run_server(port: u16, pool: db::Pool) -> Result<(), ServerError> {
    let (to_logic, message_queue) = async_channel::unbounded();

    let all_peers = client_connector::run_websocket_connector(port, to_logic.clone());
    let to_timeout = timeout_connector::run_timeout_thread(to_logic);

    run_logic_server(all_peers, to_timeout, message_queue, pool);

    Ok(())
}

/// A message that is send to the logic where the logic has then to react.
enum LogicMsg {
    Websocket {
        data: Message,
        source: SocketAddr,
    },
    Timeout {
        key: String,
        timestamp: DateTime<Utc>,
    },
}

impl WebsocketOutMsg for LogicMsg {
    fn from_ws_message(
        data: async_tungstenite::tungstenite::Message,
        source: std::net::SocketAddr,
    ) -> std::option::Option<Self> {
        if data.is_text() || data.is_binary() {
            Some(LogicMsg::Websocket { data, source })
        } else {
            None
        }
    }
}

impl TimeoutOutMsg<String> for LogicMsg {
    fn from_ws_message(data: String, timestamp: DateTime<Utc>) -> Option<Self> {
        Some(LogicMsg::Timeout {
            key: data,
            timestamp,
        })
    }
}

/// Spawn a thread that handles the server logic.
fn run_logic_server(
    all_peers: PeerMap,
    to_timeout: Sender<(String, DateTime<Utc>)>,
    message_queue: Receiver<LogicMsg>,
    pool: db::Pool,
) {
    std::thread::spawn(move || {
        task::block_on(loop_logic_server(
            all_peers,
            to_timeout,
            message_queue,
            pool,
        ))
    });
}

/// Simple loop that reacts to all the messages.
async fn loop_logic_server(
    all_peers: PeerMap,
    to_timeout: Sender<(String, DateTime<Utc>)>,
    message_queue: Receiver<LogicMsg>,
    pool: db::Pool,
) -> Result<(), ServerError> {
    let mut server_state = ServerState::default();

    while let Ok(msg) = message_queue.recv().await {
        let mut conn = pool.0.acquire().await?;
        handle_message(
            msg,
            to_timeout.clone(),
            &all_peers,
            &mut server_state,
            &mut conn,
        )
        .await;
    }
    Ok(())
}

#[derive(Debug, Default)]
struct ServerState {
    rooms: HashMap<String, GameRoom>,
}

impl ServerState {
    /// Returns a room, creating it if required. The socket that asked is added
    /// to the room automatically.
    fn room(&mut self, key: &String, asked_by: SocketAddr) -> &mut GameRoom {
        let room = self.rooms.entry(key.clone()).or_insert(GameRoom {
            key: key.clone(),
            connected: HashSet::new(),
        });
        room.connected.insert(asked_by);
        room
    }
    /// Call this method if we determine that a room is not backed by any game
    /// or if the last client disconnects.
    fn destroy_room(&mut self, key: &String) {
        self.rooms.remove(key);
    }
}

#[derive(Debug)]
struct GameRoom {
    key: String,
    connected: HashSet<SocketAddr>,
}

/// All allowed messages that may be send by the client to the server.
#[derive(Deserialize)]
enum ClientMessage {
    SubscribeToMatch { key: String },
    DoAction { key: String, action: PacoAction },
    Rollback { key: String },
}

/// Messages that may be send by the server to the client.
#[derive(Clone, Serialize, Debug)]
pub enum ServerMessage {
    CurrentMatchState(CurrentMatchState),
    MatchConnectionSuccess {
        key: String,
        state: CurrentMatchState,
    },
    Error(String),
}

/// This handle message is wired up, so that each message is handled separately.
/// What we likely actually want is to only run messages sequentially that
/// concern the same game key. So that is some possible performance improvement
/// that is still open here.
async fn handle_message(
    msg: LogicMsg,
    to_timeout: Sender<(String, DateTime<Utc>)>,
    ws: &PeerMap,
    server_state: &mut ServerState,
    conn: &mut db::Connection,
) {
    match msg {
        LogicMsg::Websocket { data, source } => {
            info!("Data is: {:?}", data);

            match data {
                Message::Text(ref text) => {
                    if let Ok(client_msg) = from_str(text) {
                        handle_client_message(
                            client_msg,
                            source,
                            to_timeout,
                            ws,
                            server_state,
                            conn,
                        )
                        .await;
                    }
                }
                Message::Binary(payload) => {
                    warn!("Binary message recieved: {:?}", payload);
                }
                Message::Ping(payload) => send_raw_msg(ws, &source, Message::Pong(payload)).await,
                Message::Pong(_) => {}
                Message::Close(_) => {
                    info!("Close message recieved. This is not implemented here.");
                }
            };
        }
        LogicMsg::Timeout { key, timestamp } => {
            info!("Timeout was called for game {} at {}", key, timestamp);

            let game = fetch_game(&key, conn).await;
            let mut game = match game {
                Some(game) => game,
                None => {
                    error!(
                        "Error when loading the game {} for which a timer expired",
                        key
                    );
                    server_state.destroy_room(&key);
                    return;
                }
            };

            match game.timer_progress() {
                Ok(state) => {
                    if let Some(ref timer) = state.timer {
                        if timer.get_state().is_finished() {
                            if store_game(&game, conn).await.is_some() {
                                if let Some(room) = server_state.rooms.get_mut(&game.key) {
                                    broadcast_state(room, &state, ws).await;
                                }
                            }
                        } else {
                            let next_reminder = timer.timeout(state.controlling_player);
                            to_timeout
                                .send((key, next_reminder))
                                .await
                                .expect("Timeout connector quit unexpectedly.");
                        }
                    }
                }
                Err(e) => {
                    error!("Error when progressing the timer: {}", e);
                    return;
                }
            }
        }
    }
}

async fn handle_client_message(
    msg: ClientMessage,
    sender: SocketAddr,
    to_timeout: Sender<(String, DateTime<Utc>)>,
    ws: &PeerMap,
    server_state: &mut ServerState,
    conn: &mut db::Connection,
) {
    match msg {
        ClientMessage::SubscribeToMatch { key } => {
            let room = server_state.room(&key, sender);

            let game = fetch_game(&room.key, conn).await;
            let game = if let Some(game) = game {
                game
            } else {
                server_state.destroy_room(&key);
                return send_error(format!("Game {} not found", key), &sender, ws).await;
            };

            let state = game.current_state();
            let state = match state {
                Ok(state) => state,
                Err(_) => {
                    server_state.destroy_room(&key);
                    return send_error(format!("Could not connect to game {}", key), &sender, ws)
                        .await;
                }
            };

            if let Some(ref timer) = state.timer {
                if !timer.get_state().is_finished() {
                    let next_reminder = timer.timeout(state.controlling_player);
                    to_timeout
                        .send((key.clone(), next_reminder))
                        .await
                        .expect("Timeout connector quit unexpectedly.");
                }
            }

            let response = ServerMessage::MatchConnectionSuccess { key, state };

            send_msg(response, &sender, ws).await;
        }
        ClientMessage::DoAction { key, action } => {
            let room = server_state.room(&key, sender);

            let game = fetch_game(&room.key, conn).await;
            let mut game = if let Some(game) = game {
                game
            } else {
                server_state.destroy_room(&key);
                return send_error(format!("Game {} not found", key), &sender, ws).await;
            };

            match game.timer_progress() {
                Ok(state) => {
                    if let Some(ref timer) = state.timer {
                        if timer.get_state().is_finished() {
                            if store_game(&game, conn).await.is_some() {
                                broadcast_state(room, &state, ws).await;
                            }
                            return;
                        }
                    }
                }
                Err(e) => {
                    error!("Error when progressing the timer: {}", e);
                    return;
                }
            }

            match game.do_action(action) {
                Ok(state) => {
                    if store_game(&game, conn).await.is_some() {
                        broadcast_state(room, &state, ws).await;
                    }
                }
                Err(error) => {
                    return send_error(
                        format!("Action could not be performed: {:?}", error),
                        &sender,
                        ws,
                    )
                    .await;
                }
            }
        }
        ClientMessage::Rollback { key } => {
            let room = server_state.room(&key, sender);

            let game = fetch_game(&room.key, conn).await;
            let mut game = if let Some(game) = game {
                game
            } else {
                server_state.destroy_room(&key);
                return send_error(format!("Game {} not found", key), &sender, ws).await;
            };

            match game.timer_progress() {
                Ok(state) => {
                    if let Some(ref timer) = state.timer {
                        if timer.get_state().is_finished() {
                            if store_game(&game, conn).await.is_some() {
                                broadcast_state(room, &state, ws).await;
                            }
                            return;
                        }
                    }
                }
                Err(e) => {
                    error!("Error when progressing the timer: {}", e);
                    return;
                }
            }

            match game.rollback() {
                Ok(state) => {
                    if store_game(&game, conn).await.is_some() {
                        broadcast_state(room, &state, ws).await;
                    }
                }
                Err(error) => {
                    return send_error(
                        format!("Action could not be performed: {:?}", error),
                        &sender,
                        ws,
                    )
                    .await;
                }
            }
        }
    }
}

async fn broadcast_state(room: &mut GameRoom, state: &CurrentMatchState, ws: &PeerMap) {
    for target in room.connected.iter() {
        send_msg(ServerMessage::CurrentMatchState(state.clone()), target, ws).await;
    }
}

async fn send_msg(message: ServerMessage, target: &SocketAddr, ws: &PeerMap) {
    match to_string(&message) {
        Ok(msg) => {
            let out_msg = Message::Text(msg);

            send_raw_msg(ws, target, out_msg).await;
        }
        Err(e) => {
            error!(
                "Error converting server message to json string: {:?}, {:?}",
                &message, e
            );
        }
    }
}

async fn send_raw_msg(ws: &PeerMap, target: &SocketAddr, out_msg: Message) {
    if let Some(target) = ws.get(target).await {
        match target.send(out_msg).await {
            Ok(_) => {}
            Err(e) => {
                warn!("Error sending a raw msg: {:?}", e)
            }
        };
    }
}

/// Helper message to make sending error messages easier.
async fn send_error(error_message: String, target: &SocketAddr, ws: &PeerMap) {
    send_msg(ServerMessage::Error(error_message), target, ws).await;
}

async fn fetch_game(key: &str, conn: &mut db::Connection) -> Option<SyncronizedMatch> {
    if let Ok(id) = key.parse() {
        match db::game::select(id, conn).await {
            Ok(game) => game,
            Err(load_error) => {
                error!("Error loading game {} with error {:?}.", id, load_error);
                None
            }
        }
    } else {
        info!("Trying to open game with key {} with is not a number", key);
        None
    }
}

async fn store_game(game: &SyncronizedMatch, conn: &mut db::Connection) -> Option<()> {
    match db::game::update(game, conn).await {
        Ok(_) => Some(()),
        Err(e) => {
            error!("Error saving game with key {} with error {:?}", game.key, e);
            None
        }
    }
}
