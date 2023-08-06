use std::sync::atomic;

use axum::{
    extract::{
        ws::{Message, WebSocket},
        WebSocketUpgrade,
    },
    response::Response,
    Error,
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

pub async fn websocket_handler(ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(handle_socket)
}

// All Sockets must be stored in this structure so everyone can send messages to
// everyone else.
struct AllSockets {
    map: DashMap<SocketId, SocketData>,
    next_id: atomic::AtomicUsize,
}

impl AllSockets {
    pub fn generate_id() -> SocketId {
        SocketId(ALL_SOCKETS.next_id.fetch_add(1, atomic::Ordering::Relaxed))
    }
    // Insert a new socket into the map
    pub fn insert_new(id: SocketId, data: SocketData) {
        ALL_SOCKETS.map.insert(id, data);
    }
    // If there is a socket registered with this id, return a Sender that can be
    // used to send messages to it. This sender puts messages into a mpsc queue
    // that is processed by the socket's task.
    pub fn sender(id: SocketId) -> Option<Sender<Message>> {
        let entry = ALL_SOCKETS.map.get(&id)?;
        Some(entry.to_client.clone())
    }
    // Send a message to a given socket id. This is fire and forget. If the
    // message can't be sent, it is silently dropped. Use sender(id) for more
    // control.
    pub async fn send(id: SocketId, msg: Message) {
        if let Some(sender) = Self::sender(id) {
            if let Err(e) = sender.send(msg).await {
                error!(
                    "Internal error queuing message for websocket {}: {}",
                    id.0, e
                );
            }
        }
    }
    // Remove a socket from the map. This aborts the socket's tasks.
    pub fn remove(id: SocketId) {
        if let Some((_, data)) = ALL_SOCKETS.map.remove(&id) {
            info!("Removing websocket {} and aborting tasks", id.0);
            data.writer_task_abort_handle.abort();
            data.reader_task_abort_handle.abort();
        }
    }
}

// Global AllSockets instance:
lazy_static! {
    static ref ALL_SOCKETS: AllSockets = AllSockets {
        map: DashMap::new(),
        next_id: atomic::AtomicUsize::new(1)
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct SocketId(usize);

struct SocketData {
    to_client: Sender<Message>,
    writer_task_abort_handle: AbortHandle,
    reader_task_abort_handle: AbortHandle,
}

pub async fn handle_socket(socket: WebSocket) {
    let (sender, receiver) = socket.split();

    let (tx, rx) = tokio::sync::mpsc::channel(32);

    let id = AllSockets::generate_id();

    let writer_task_abort_handle = tokio::spawn(write(sender, rx, id)).abort_handle();
    let reader_task_abort_handle = tokio::spawn(read(receiver, id)).abort_handle();

    let socket_data = SocketData {
        to_client: tx,
        writer_task_abort_handle,
        reader_task_abort_handle,
    };

    AllSockets::insert_new(id, socket_data);
}

async fn read(mut receiver: SplitStream<WebSocket>, id: SocketId) -> Result<(), Error> {
    while let Some(msg) = receiver.next().await {
        AllSockets::send(id, msg?).await;
    }
    info!("Websocket receiver task finished.");
    AllSockets::remove(id);
    Ok(())
}

// Copies messages from the receiver mpsc to the sender websocket sink.
async fn write(mut sender: SplitSink<WebSocket, Message>, mut rx: Receiver<Message>, id: SocketId) {
    while let Some(msg) = rx.recv().await {
        let Ok(()) = sender.send(msg).await else {
            break;
        };
    }
    info!("Websocket sender task finished. Aborting connection.");
    AllSockets::remove(id);
}
