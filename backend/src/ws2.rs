//! Setting up a paralell websocket server. This should help me integrate
//! the new tungstenite server and work on features for it.

use std::thread;

use async_std::net::{TcpListener, TcpStream};
use async_std::task;
use async_tungstenite;
use async_tungstenite::WebSocketStream;
use futures::prelude::*;
use log::info;

async fn run(port: u16) -> Result<(), std::io::Error> {
    let addr = format!("0.0.0.0:{}", port);

    // Create the event loop and TCP listener we'll accept connections on.
    let try_socket = TcpListener::bind(&addr).await;
    let listener = try_socket.expect("Failed to bind");
    info!("Ws2 is listening on: {}", addr);

    while let Ok((stream, _)) = listener.accept().await {
        task::spawn(accept_connection(stream));
    }

    Ok(())
}

async fn accept_connection(stream: TcpStream) {
    let addr = stream
        .peer_addr()
        .expect("connected streams should have a peer address");
    info!("Peer address: {}", addr);

    let ws_stream = async_tungstenite::accept_async(stream)
        .await
        .expect("Error during the websocket handshake occurred");

    info!("New WebSocket connection: {}", addr);
    echo_connection(ws_stream).await;
    info!("Connection closed: {}", addr);
}

async fn echo_connection(
    ws_stream: WebSocketStream<TcpStream>,
) -> async_tungstenite::tungstenite::Result<()> {
    let (mut write, mut read) = ws_stream.split();

    loop {
        match read.next().await {
            Some(msg) => {
                let msg = msg?;
                if msg.is_text() || msg.is_binary() {
                    info!("msg: {:?}", msg);
                    write.send(msg).await?;
                } else if msg.is_close() {
                    break;
                }
            }
            None => break, // terminated
        }
    }

    Ok(())
}

pub fn spawn(port: u16) {
    thread::spawn(move || task::block_on(run(port)));
}
