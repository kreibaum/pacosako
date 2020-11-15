//! Setting up a paralell websocket server. This should help me integrate
//! the new tungstenite server and work on features for it.

use async_std::net::{TcpListener, TcpStream};
use async_std::task;
use async_tungstenite::tungstenite::protocol::Message;
use async_tungstenite::{self, WebSocketStream};
use futures::{
    channel::mpsc::{unbounded, UnboundedSender},
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
struct PeerMap(Arc<Mutex<HashMap<SocketAddr, Tx>>>);

impl PeerMap {
    fn broadcast(&self, msg: Message) {
        info!("Broadcasting message to all connected clients.");

        let peers = self.0.lock().unwrap();

        // We want to broadcast the message to everyone except ourselves.

        for (peer_addr, recp) in peers.iter() {
            if let Err(_) = recp.unbounded_send(msg.clone()) {
                warn!(
                    "Closed Receiver not properly removed from map: {}",
                    peer_addr
                );
            }
        }
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
    let (tx, rx) = unbounded();
    peer_map.0.lock().unwrap().insert(addr, tx);

    let connection_count = peer_map.0.lock().unwrap().len();
    peer_map.broadcast(Message::Text(format!(
        "There are currently {} connected sockets.",
        connection_count
    )));

    let receive_from_others = rx.map(Ok).forward(write);
    pin_mut!(receive_from_others);

    info!("New WebSocket connection: {}", addr);
    // handle_connection(ws_stream).await?;

    let broadcast_incoming = broadcast_incoming(peer_map.clone(), addr, read);

    pin_mut!(broadcast_incoming);
    // Wait for one of the futures to complete. The receive_from_others should
    // stay available all the time, so I expect this to only resolve when
    // broadcast_incoming resolves.
    future::select(broadcast_incoming, receive_from_others).await;

    info!("Connection closed: {}", addr);
    peer_map.0.lock().unwrap().remove(&addr);

    let connection_count = peer_map.0.lock().unwrap().len();
    peer_map.broadcast(Message::Text(format!(
        "There are currently {} connected sockets.",
        connection_count
    )));

    // Websocket terminated successfully.
    Ok(())
}

fn broadcast_incoming(
    peer_map: PeerMap,
    addr: SocketAddr,
    read: SplitStream<WebSocketStream<TcpStream>>,
) -> impl Future {
    read.try_filter(|msg| {
        // Broadcasting a Close message from one client
        // will close the other clients.
        future::ready(!msg.is_close())
    })
    .try_for_each(move |msg| {
        info!(
            "Received a message from {}: {}",
            addr,
            msg.to_text().unwrap(),
        );
        let peers = peer_map.0.lock().unwrap();

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

        future::ok(())
    })
}

pub fn spawn(port: u16) {
    thread::spawn(move || task::block_on(run(port)));
}
