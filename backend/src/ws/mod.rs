/// Handles all the websocket client logic.
pub mod client_connector;
pub mod timeout_connector;

use crate::{db, ServerError};
use async_channel::{Receiver, Sender};
use async_std::task;
use async_tungstenite::tungstenite::Message;
use chrono::{DateTime, Utc};
use client_connector::{PeerMap, WebsocketOutMsg};
use log::*;
use std::net::SocketAddr;

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
    while let Ok(msg) = message_queue.recv().await {
        let conn = pool.0.acquire().await?;
        handle_message(msg, to_timeout.clone(), &all_peers, conn).await;
    }
    Ok(())
}

/// This handle message is wired up, so that each message is handled separately.
/// What we likely actually want is to only run messages sequentially that
/// concern the same game key. So that is some possible performance improvement
/// that is still open here.
async fn handle_message(
    msg: LogicMsg,
    to_timeout: Sender<(String, DateTime<Utc>)>,
    ws: &PeerMap,
    conn: db::Connection,
) {
    info!("Handling message!");

    match msg {
        LogicMsg::Websocket { data, source } => {
            info!("Data is: {:?}", data);
            // Just echo:
            if let Some(target) = ws.get(&source).await {
                target.send(data).await;
            }
        }
        LogicMsg::Timeout { key, timestamp } => {
            info!("Timeout was called for game {} at {}", key, timestamp);
        }
    }
}
