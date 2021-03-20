/// Handles all the websocket client logic.
pub mod client_connector;

use crate::ServerError;
use async_channel::{Receiver, Sender};
use async_std::task;
use async_std::{
    net::{TcpListener, TcpStream},
    sync::RwLock,
};
use async_tungstenite::{
    accept_async,
    tungstenite::{Error, Message},
};
use client_connector::{PeerMap, WebsocketOutMsg};
use futures::future::{select, Either};
use futures::prelude::*;
use log::*;
use std::{collections::HashMap, net::SocketAddr, sync::Arc};

pub fn run_server(port: u16) -> Result<(), ServerError> {
    let (to_logic, message_queue) = async_channel::unbounded();

    let all_peers = client_connector::run_websocket_connector(port, to_logic);

    run_logic_server(all_peers, message_queue);

    Ok(())
}

/// A message that is send to the logic where the logic has then to react.
enum LogicMsg {
    Websocket { data: Message, source: SocketAddr },
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

/// Spawn a thread that handles the server logic.
fn run_logic_server(all_peers: PeerMap, message_queue: Receiver<LogicMsg>) {
    std::thread::spawn(move || task::block_on(loop_logic_server(all_peers, message_queue)));
}

/// Simple loop that reacts to all the messages.
async fn loop_logic_server(all_peers: PeerMap, message_queue: Receiver<LogicMsg>) {
    while let Ok(msg) = message_queue.recv().await {
        handle_message(msg, &all_peers).await;
    }
}

async fn handle_message(msg: LogicMsg, ws: &PeerMap) {
    info!("Handling message!");

    match msg {
        LogicMsg::Websocket { data, source } => {
            info!("Data is: {:?}", data);
            // Just echo:
            if let Some(target) = ws.get(&source).await {
                target.send(data).await;
            }
        }
    }
}
