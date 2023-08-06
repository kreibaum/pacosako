use std::sync::atomic;

use axum::{
    extract::{
        ws::{Message, WebSocket},
        WebSocketUpgrade,
    },
    response::Response,
};
use dashmap::DashMap;
use futures_util::{
    sink::SinkExt,
    stream::{SplitSink, SplitStream, StreamExt},
};
use lazy_static::lazy_static;
use tokio::{
    sync::mpsc::{Receiver, Sender},
    task::AbortHandle,
};

use crate::ws::{to_logic, LogicMsg};

/// Identifies a websocket connection across the server.
/// This is used to send messages to a specific socket.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SocketId(usize);

/// Handler for websocket connections to be used in axum routes.
pub async fn websocket_handler(ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(handle_socket)
}

/// Lot's of static methods to interact with the AllSockets instance.
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
}

/// Handles a new websocket connection, setting up the tasks that read and
/// write to the socket. This also registers the socket on its id.
async fn handle_socket(mut socket: WebSocket) {
    // socket
    //     .send(Message::Text("Hello from the server!".to_string()))
    //     .await
    //     .unwrap();
    // // Sleep for 0.4 seconds
    // tokio::time::sleep(std::time::Duration::from_millis(400)).await;

    // socket
    //     .send(Message::Close(Some(axum::extract::ws::CloseFrame {
    //         code: 1000,
    //         reason: std::borrow::Cow::Borrowed(""),
    //     })))
    //     .await
    //     .unwrap();
    // socket.close().await.unwrap();
    let (sender, receiver) = socket.split();

    let (tx, rx) = tokio::sync::mpsc::channel(32);

    let id = SocketId::new();

    let writer_task_abort_handle = tokio::spawn(write(sender, rx, id)).abort_handle();
    let reader_task_abort_handle = tokio::spawn(read(receiver, id)).abort_handle();

    let socket_data = SocketData {
        to_client: tx,
        writer_task_abort_handle,
        reader_task_abort_handle,
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
                });
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
