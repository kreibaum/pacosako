//! Setting up a paralell websocket server. This should help me integrate
//! the new tungstenite server and work on features for it.

use async_std::net::{TcpListener, TcpStream};
use async_std::task;
use async_tungstenite;
use async_tungstenite::tungstenite::protocol::Message;
use futures::prelude::*;
use futures::{
    channel::mpsc::{unbounded, UnboundedSender},
    future, pin_mut,
};
use log::info;
use std::{
    collections::HashMap,
    io::Error as IoError,
    net::SocketAddr,
    sync::{Arc, Mutex},
    thread,
};

type Tx = UnboundedSender<Message>;
type PeerMap = Arc<Mutex<HashMap<SocketAddr, Tx>>>;

async fn run(port: u16) -> Result<(), IoError> {
    let addr = format!("0.0.0.0:{}", port);

    // Create the event loop and TCP listener we'll accept connections on.
    let listener = TcpListener::bind(&addr).await?;
    info!("Ws2 is listening on: {}", addr);

    let state = PeerMap::new(Mutex::new(HashMap::new()));

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
    peer_map.lock().unwrap().insert(addr, tx);

    let receive_from_others = rx.map(Ok).forward(write);
    pin_mut!(receive_from_others);

    info!("New WebSocket connection: {}", addr);
    // handle_connection(ws_stream).await?;

    let broadcast_incoming = read
        .try_filter(|msg| {
            // Broadcasting a Close message from one client
            // will close the other clients.
            future::ready(!msg.is_close())
        })
        .try_for_each(|msg| {
            info!(
                "Received a message from {}: {}",
                addr,
                msg.to_text().unwrap(),
            );
            let peers = peer_map.lock().unwrap();

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
        });

    pin_mut!(broadcast_incoming);
    // Wait for one of the futures to complete. The receive_from_others should
    // stay available all the time, so I expect this to only resolve when
    // broadcast_incoming resolves.
    future::select(broadcast_incoming, receive_from_others).await;

    info!("Connection closed: {}", addr);
    peer_map.lock().unwrap().remove(&addr);

    // Websocket terminated successfully.
    Ok(())
}

pub fn spawn(port: u16) {
    thread::spawn(move || task::block_on(run(port)));
}
