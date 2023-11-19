use std::sync::atomic;

use axum::{
    extract::{
        ws::{Message, WebSocket},
        Query, WebSocketUpgrade,
    },
    response::Response,
};
use dashmap::DashMap;
use futures_util::{
    sink::SinkExt,
    stream::{SplitSink, SplitStream, StreamExt},
};
use lazy_static::lazy_static;
use serde::Deserialize;
use tokio::{
    sync::mpsc::{Receiver, Sender},
    task::AbortHandle,
};

use crate::{
    login::{session::SessionData, SessionId},
    ws::{to_logic, LogicMsg},
};

/// Identifies a websocket connection across the server.
/// This is used to send messages to a specific socket.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SocketId(usize);

#[derive(Deserialize)]
pub struct UuidQuery {
    uuid: String,
}

/// Handler for websocket connections to be used in axum routes.
pub async fn websocket_handler(
    session: Option<SessionData>,
    Query(params): Query<UuidQuery>,
    ws: WebSocketUpgrade,
) -> Response {
    let session_id = session.map(|s| s.session_id);

    ws.on_upgrade(move |websocket| handle_socket(websocket, params.uuid, session_id))
}

/// Lots of static methods to interact with the AllSockets instance.
impl SocketId {
    /// Generates a new unique socket id to be used to refer to a socket.
    pub fn new() -> SocketId {
        SocketId(NEXT_ID.fetch_add(1, atomic::Ordering::Relaxed))
    }
    /// Calling this method makes the socket callable by it's id.
    fn with_data(self, data: SocketData) {
        ALL_SOCKETS.insert(self, data);
    }
    pub fn is_alive(self) -> bool {
        ALL_SOCKETS.contains_key(&self)
    }
    /// If there is a socket registered with this id, return a Sender that can
    /// be used to send messages to it. This sender puts messages into a mpsc
    /// queue that is processed by the socket's task.
    pub fn sender(self) -> Option<Sender<Message>> {
        let entry = ALL_SOCKETS.get(&self)?;
        Some(entry.to_client.clone())
    }
    /// Send a message to a given socket id. This is fire and forget. If the
    /// message can't be sent, it is silently dropped. Use sender(id) for more
    /// control.
    pub async fn send(self, msg: Message) {
        if let Some(sender) = self.sender() {
            if let Err(e) = sender.send(msg).await {
                error!(
                    "Internal error queuing message for websocket {}: {}",
                    self.0, e
                );
            }
        }
    }
    /// Remove a socket from the map. This aborts the socket's tasks.
    pub fn remove(self) {
        if let Some((_, data)) = ALL_SOCKETS.remove(&self) {
            let remaining_sockets = ALL_SOCKETS.len();
            info!(
                "Removing websocket {} and aborting tasks. There are {} remaining connections.",
                self.0, remaining_sockets
            );
            data.writer_task_abort_handle.abort();
            data.reader_task_abort_handle.abort();
        }
    }

    /// Returns the number of currently connected websockets.
    pub fn count_connections() -> usize {
        ALL_SOCKETS.len()
    }

    /// Gets the owner from the data
    pub fn get_owner(self) -> Option<(String, Option<SessionId>)> {
        let entry = ALL_SOCKETS.get(&self)?;
        Some((entry.uuid.clone(), entry.session_id.clone()))
    }
}

lazy_static! {
    /// All Sockets must be stored in this map so everyone can send messages to
    /// everyone else.
    static ref ALL_SOCKETS: DashMap<SocketId, SocketData> = DashMap::new();
    static ref NEXT_ID: atomic::AtomicUsize = atomic::AtomicUsize::new(1);
}

struct SocketData {
    to_client: Sender<Message>,
    writer_task_abort_handle: AbortHandle,
    reader_task_abort_handle: AbortHandle,
    uuid: String,
    session_id: Option<SessionId>,
}

/// Handles a new websocket connection, setting up the tasks that read and
/// write to the socket. This also registers the socket on its id.
async fn handle_socket(socket: WebSocket, uuid: String, session_id: Option<SessionId>) {
    let (sender, receiver) = socket.split();

    let (tx, rx) = tokio::sync::mpsc::channel(32);

    let id = SocketId::new();

    let writer_task_abort_handle = tokio::spawn(write(sender, rx, id)).abort_handle();
    let reader_task_abort_handle = tokio::spawn(read(receiver, id)).abort_handle();

    let socket_data = SocketData {
        to_client: tx,
        writer_task_abort_handle,
        reader_task_abort_handle,
        uuid,
        session_id,
    };

    id.with_data(socket_data);
}

/// Reads all incoming messages from the websocket and delegates them.
async fn read(mut receiver: SplitStream<WebSocket>, id: SocketId) {
    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(msg) => {
                //id.send(msg).await
                to_logic(LogicMsg::Websocket {
                    data: msg,
                    source: id,
                })
                .await;
            }
            Err(e) => {
                error!("Error reading from websocket {}: {}", id.0, e);
                id.remove();
                return;
            }
        }
    }
    info!(
        "Websocket (id={}) receiver task finished without error.",
        id.0
    );
    id.remove();
}

/// Copies messages from the receiver mpsc to the sender websocket sink.
async fn write(mut sender: SplitSink<WebSocket, Message>, mut rx: Receiver<Message>, id: SocketId) {
    while let Some(msg) = rx.recv().await {
        if let Err(e) = sender.send(msg).await {
            error!("Error writing to websocket {}: {}", id.0, e);
            id.remove();
            return;
        };
    }
    info!(
        "Websocket (id={}) sender task finished without error.",
        id.0
    );
    id.remove();
}
