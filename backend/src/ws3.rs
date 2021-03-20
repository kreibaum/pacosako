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
use futures::future::{select, Either};
use futures::prelude::*;
use log::*;
use std::{collections::HashMap, net::SocketAddr, sync::Arc};

#[derive(Default, Clone, Debug)]
pub(crate) struct PeerMap {
    map: Arc<RwLock<HashMap<SocketAddr, Sender<Message>>>>,
}

pub(crate) trait WebsocketOutMsg: Sized {
    fn from_ws_message(msg: Message) -> Option<Self>;
}

impl PeerMap {
    /// Register a new websocket client into the map and get a Receiver that you
    /// need to hook up to your websocket write stream.
    async fn add(&self, addr: SocketAddr) -> Receiver<Message> {
        let (tx, rx) = async_channel::unbounded();

        self.map.write().await.insert(addr, tx);

        rx
    }

    async fn get(&self, addr: &SocketAddr) -> Option<Sender<Message>> {
        if let Some(tx) = self.map.read().await.get(addr) {
            Some(tx.clone())
        } else {
            None
        }
    }

    async fn remove(&self, addr: &SocketAddr) {
        self.map.write().await.remove(addr);
    }
}

async fn accept_connection(
    peer: SocketAddr,
    stream: TcpStream,
    to_logic: Sender<LogicMsg>,
    peer_reciever: Receiver<Message>,
    all_peers: PeerMap,
) {
    if let Err(e) = handle_connection(peer, stream, to_logic, peer_reciever).await {
        match e {
            Error::ConnectionClosed | Error::Protocol(_) | Error::Utf8 => (),
            err => error!("Error processing connection: {}", err),
        }
    }
    // After the connection is fully handled, we remove it from the map again
    // otherwise we would leak memory.
    all_peers.remove(&peer).await;
}

async fn handle_connection(
    peer: SocketAddr,
    stream: TcpStream,
    to_logic: Sender<LogicMsg>,
    peer_reciever: Receiver<Message>,
) -> Result<(), Error> {
    let ws_stream = accept_async(stream).await.expect("Failed to accept");
    info!("New WebSocket connection: {}", peer);
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();

    let mut msg_fut = ws_receiver.next();

    let mut logic_fut = peer_reciever.recv();

    loop {
        match select(msg_fut, logic_fut).await {
            Either::Left((msg, logic_fut_continue)) => {
                match msg {
                    Some(msg) => {
                        let msg = msg?;
                        if msg.is_text() || msg.is_binary() {
                            let send_result = to_logic
                                .send(LogicMsg::Websocket {
                                    data: msg,
                                    source: peer.clone(),
                                })
                                .await;

                            if send_result.is_err() {
                                info!("Websocket client connection task terminated because to_logic died.");
                                break;
                            }
                        }
                        logic_fut = logic_fut_continue; // Continue waiting for tick.
                        msg_fut = ws_receiver.next(); // Receive next WebSocket message.
                    }
                    None => break, // WebSocket stream terminated.
                };
            }
            Either::Right((outbound_msg, msg_fut_continue)) => {
                if let Ok(outbound_msg) = outbound_msg {
                    ws_sender.send(outbound_msg).await?;
                }

                msg_fut = msg_fut_continue; // Continue receiving the WebSocket message.
                logic_fut = peer_reciever.recv(); // Wait for next tick.
            }
        }
    }

    Ok(())
}

async fn run(port: u16, to_logic: Sender<LogicMsg>, all_peers: PeerMap) -> Result<(), ServerError> {
    let addr = format!("127.0.0.1:{}", port);
    let listener = TcpListener::bind(&addr).await?;
    info!("The websocket server is listening on: {}", addr);

    while let Ok((stream, _)) = listener.accept().await {
        let peer = stream
            .peer_addr()
            .expect("connected streams should have a peer address");
        info!("Peer address: {}", peer);

        let peer_reciever = all_peers.add(peer).await;

        task::spawn(accept_connection(
            peer,
            stream,
            to_logic.clone(),
            peer_reciever,
            all_peers.clone(),
        ));
    }

    Ok(())
}

/// Start a thread for the websocket connector and get a sender.
fn run_websocket_connector(port: u16, to_logic: Sender<LogicMsg>) -> PeerMap {
    let all_peers = PeerMap::default();
    let result = all_peers.clone();

    std::thread::spawn(move || task::block_on(run(port, to_logic, all_peers)));

    result
}

pub fn run_server(port: u16) -> Result<(), ServerError> {
    let (to_logic, message_queue) = async_channel::unbounded();

    let all_peers = run_websocket_connector(port, to_logic);

    run_logic_server(all_peers, message_queue);

    Ok(())
}

/// A message that is send to the logic where the logic has then to react.
enum LogicMsg {
    Websocket { data: Message, source: SocketAddr },
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
