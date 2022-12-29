use crate::ws::to_logic;
use crate::ServerError;
use async_std::task;
use async_std::{
    net::{TcpListener, TcpStream},
    sync::RwLock,
};
use async_tungstenite::WebSocketStream;
use async_tungstenite::{
    accept_async,
    tungstenite::{Error, Message},
};
use futures::stream::SplitSink;
use futures::{SinkExt, StreamExt};
use kanal::{AsyncReceiver, AsyncSender};
use log::*;
use std::{collections::HashMap, net::SocketAddr, sync::Arc};

#[derive(Default, Clone, Debug)]
pub struct PeerMap {
    map: Arc<RwLock<HashMap<SocketAddr, AsyncSender<Message>>>>,
}

pub trait WebsocketOutMsg: Sized + Send + Sync + 'static {
    fn from_ws_message(msg: Message, addr: SocketAddr) -> Option<Self>;
}

impl PeerMap {
    /// Register a new websocket client into the map and get a Receiver that you
    /// need to hook up to your websocket write stream.
    async fn add(&self, addr: SocketAddr) -> AsyncReceiver<Message> {
        let (tx, rx) = kanal::unbounded_async();

        self.map.write().await.insert(addr, tx);

        rx
    }

    pub async fn get(&self, addr: &SocketAddr) -> Option<AsyncSender<Message>> {
        self.map.read().await.get(addr).cloned()
    }

    async fn remove(&self, addr: &SocketAddr) {
        self.map.write().await.remove(addr);
    }
}

async fn accept_connection(
    peer: SocketAddr,
    stream: TcpStream,
    peer_receiver: AsyncReceiver<Message>,
    all_peers: PeerMap,
) {
    if let Err(e) = handle_connection(peer, stream, peer_receiver).await {
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
    peer_receiver: AsyncReceiver<Message>,
) -> Result<(), Error> {
    let ws_stream = accept_async(stream).await.expect("Failed to accept");
    info!("New WebSocket connection: {}", peer);
    let (ws_sender, mut ws_receiver) = ws_stream.split();

    // Forward messages from the logic to the websocket. This runs in its own
    // task.
    task::spawn(forward_messages_to_ws(peer, peer_receiver, ws_sender));

    while let Some(msg) = ws_receiver.next().await {
        let msg = msg?;
        if let Some(out_msg) = WebsocketOutMsg::from_ws_message(msg, peer) {
            to_logic(out_msg);
        }
    }

    Ok(())
}

async fn forward_messages_to_ws(
    peer: SocketAddr,
    source: AsyncReceiver<Message>,
    mut target: SplitSink<WebSocketStream<TcpStream>, Message>,
) -> Result<(), Error> {
    info!("Forwarding messages to websocket: {}", peer);
    while let Ok(msg) = source.recv().await {
        target.send(msg).await?;
    }
    info!("Stopped forwarding messages to websocket: {}", peer);

    Ok(())
}

async fn run(port: u16, all_peers: PeerMap) -> Result<(), ServerError> {
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await?;
    info!("The websocket server is listening on: {}", addr);

    while let Ok((stream, _)) = listener.accept().await {
        let peer = stream
            .peer_addr()
            .expect("connected streams should have a peer address");
        info!("Peer address: {}", peer);

        let peer_receiver = all_peers.add(peer).await;

        task::spawn(accept_connection(
            peer,
            stream,
            peer_receiver,
            all_peers.clone(),
        ));
    }

    Ok(())
}

/// Start a thread for the websocket connector and get a sender.
pub fn run_websocket_connector(port: u16) -> PeerMap {
    let all_peers = PeerMap::default();
    let result = all_peers.clone();

    std::thread::spawn(move || task::block_on(run(port, all_peers)));

    result
}
