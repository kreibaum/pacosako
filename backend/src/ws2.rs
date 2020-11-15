//! Setting up a paralell websocket server. This should help me integrate
//! the new tungstenite server and work on features for it.

use async_std::net::{TcpListener, TcpStream};
use async_std::task;
use async_tungstenite::{self, tungstenite::protocol::Message, WebSocketStream};
use futures::{
    channel::mpsc::{unbounded, UnboundedReceiver, UnboundedSender},
    future, pin_mut,
};
use futures::{prelude::*, stream::SplitStream};
use log::info;
use std::{
    collections::HashMap,
    io::Error as IoError,
    net::SocketAddr,
    sync::{Arc, Mutex},
    thread,
};

type Tx = UnboundedSender<Message>;
#[derive(Default, Clone, Debug)]
struct PeerMap {
    map: Arc<Mutex<HashMap<SocketAddr, Tx>>>,
}

impl PeerMap {
    /// Send a message to all connected clients. You should rarely use this.
    fn broadcast(&self, msg: impl Into<Message>) {
        self._broadcast(msg.into())
    }

    fn _broadcast(&self, msg: Message) {
        info!("Broadcasting message to all connected clients.");

        let peers = self.map.lock().expect("Mutex was poisoned");

        for (peer_addr, recp) in peers.iter() {
            Self::_send(peer_addr, recp, msg.clone());
        }
    }

    fn _send(addr: &SocketAddr, recp: &UnboundedSender<Message>, msg: Message) {
        if let Err(_) = recp.unbounded_send(msg) {
            warn!("Closed receiver not properly removed from map: {}", addr);
        }
    }

    /// Register a new websocket client into the map and get a Receiver that you
    /// need to hook up to your websocket write stream.
    fn insert(&self, addr: SocketAddr) -> UnboundedReceiver<Message> {
        let (tx, rx) = unbounded();

        self.map
            .lock()
            .expect("Mutex was poisoned")
            .insert(addr, tx);

        rx
    }

    fn remove(&self, addr: &SocketAddr) {
        self.map.lock().expect("Mutex was poisoned").remove(addr);
    }

    fn connection_count(&self) -> usize {
        self.map.lock().expect("Mutex was poisoned").len()
    }
}

async fn run(port: u16) -> Result<(), IoError> {
    let addr = format!("0.0.0.0:{}", port);

    // Create the event loop and TCP listener we'll accept connections on.
    let listener = TcpListener::bind(&addr).await?;
    info!("Ws2 is listening on: {}", addr);

    let state = PeerMap::default();

    while let Ok((stream, _)) = listener.accept().await {
        task::spawn(accept_connection(state.clone(), stream));
    }

    Ok(())
}

async fn accept_connection(
    peer_map: PeerMap,
    stream: TcpStream,
) -> async_tungstenite::tungstenite::Result<()> {
    let addr = stream.peer_addr()?;
    info!("Peer address: {}", addr);

    // Get the websocket stream and split it.
    let ws_stream = async_tungstenite::accept_async(stream)
        .await
        .expect("Error during the websocket handshake occurred");
    let (write, read) = ws_stream.split();

    // Create a channel that we can put into the peer map. When we receive
    // messages over this channel, we pass it to our client.
    // let (tx, rx) = unbounded();
    let rx = peer_map.insert(addr);

    peer_map.broadcast(Message::Text(format!(
        "There are currently {} connected sockets.",
        peer_map.connection_count()
    )));

    let receive_from_others = rx.map(Ok).forward(write);
    pin_mut!(receive_from_others);

    info!("New WebSocket connection: {}", addr);
    // handle_connection(ws_stream).await?;

    let broadcast_incoming = message_loop(peer_map.clone(), addr, read);
    pin_mut!(broadcast_incoming);

    // Wait for one of the futures to complete. The receive_from_others should
    // stay available all the time, so I expect this to only resolve when
    // broadcast_incoming resolves.
    future::select(broadcast_incoming, receive_from_others).await;

    info!("Connection closed: {}", addr);
    peer_map.remove(&addr);

    peer_map.broadcast(Message::Text(format!(
        "There are currently {} connected sockets.",
        peer_map.connection_count()
    )));

    // Websocket terminated successfully.
    Ok(())
}

async fn message_loop(
    peer_map: PeerMap,
    addr: SocketAddr,
    mut read: SplitStream<WebSocketStream<TcpStream>>,
) -> async_tungstenite::tungstenite::Result<()> {
    loop {
        match read.next().await {
            Some(msg) => {
                let msg = msg?;

                if msg.is_text() || msg.is_binary() {
                    info!(
                        "Received a message from {}: {}",
                        addr,
                        msg.to_text().unwrap(),
                    );

                    react_to_message(peer_map.clone(), addr, msg)?;
                } else if msg.is_close() {
                    return Ok(());
                }
            }
            None => return Ok(()), // terminated
        }
    }
}

fn react_to_message(
    peer_map: PeerMap,
    addr: SocketAddr,
    msg: Message,
) -> async_tungstenite::tungstenite::Result<()> {
    let peers = peer_map.map.lock().unwrap();

    // We want to broadcast the message to everyone except ourselves.
    let broadcast_recipients = peers.iter().filter(|(peer_addr, _)| peer_addr != &&addr);

    for (peer_addr, recp) in broadcast_recipients {
        if let Err(_) = recp.unbounded_send(msg.clone()) {
            warn!(
                "Closed Receiver not properly removed from map: {}",
                peer_addr
            );
        }
    }

    Ok(())
}

pub fn spawn(port: u16) {
    thread::spawn(move || task::block_on(run(port)));
}
