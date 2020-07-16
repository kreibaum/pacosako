use rand::{thread_rng, Rng};
use std::collections::{HashMap, HashSet};
use std::{
    borrow::Cow,
    sync::{Arc, Mutex},
};
use ws::Sender;

/// The instance manager makes sure you can have multiple instances of a thing
/// in a websocket service. This class will take care of message passing and
/// session management.
///
/// When we eventually add persistence to the instances, this will also be the
/// responsibility of the instance manager.

/// An instance is the type managed by the instance manager.
pub trait Instance: Sized {
    /// The type of messages send by the client to the server.
    type ClientMessage: ClientMessage;
    type ServerMessage: ServerMessage;
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String>;
    /// Create a new instance and make it store the key.
    fn new_with_key(key: &str) -> Self;
    /// Accept a client message and possibly send messages back.
    fn handle_message(&mut self, message: Self::ClientMessage, ctx: &mut Context<Self>);
}

pub trait ProvidesKey {
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String>;
}

pub trait ClientMessage: ProvidesKey + Clone {
    /// Create a client messsage that represents a client subscribing.
    fn subscribe() -> Self;
}

pub trait ServerMessage: Into<ws::Message> + Clone {
    /// Allows us to send messages to the client without knowing about the
    /// server message type in detail.
    fn error(message: Cow<String>) -> Self;
}

/// Represents the client which send a message to the game. You can send server
/// messages back to the client. The messages will be buffered and send out
/// later. This means technical error handling can be hidden from the business
/// logic.
/// The context gives the ability to broadcast messages to all clients that are
/// connected to the
pub struct Context<T: Instance> {
    reply_queue: Vec<T::ServerMessage>,
    broadcast_queue: Vec<T::ServerMessage>,
}

impl<T: Instance> Context<T> {
    pub fn reply(&mut self, message: T::ServerMessage) {
        self.reply_queue.push(message)
    }
    pub fn broadcast(&mut self, message: T::ServerMessage) {
        self.broadcast_queue.push(message)
    }
    fn new() -> Self {
        Context {
            reply_queue: vec![],
            broadcast_queue: vec![],
        }
    }
}

/// As an implementation detail for now, we lock the Manager on every access.
/// This is of course not a good implementation and we should switch over to
/// some kind of concurrent hashmap in the future.
pub struct Manager<T: Instance>(Arc<Mutex<SyncManager<T>>>);

/// Inner Manager, locked before access.
struct SyncManager<T: Instance> {
    instances: HashMap<String, InstanceMetadata<T>>,
    clients: HashMap<Sender, ClientData>,
}

struct ClientData {
    sender: Sender,
    connected_to: HashSet<String>,
}

impl ClientData {
    fn new(sender: Sender) -> Self {
        ClientData {
            sender,
            connected_to: HashSet::new(),
        }
    }
}

struct InstanceMetadata<T: Instance> {
    instance: T,
    clients: HashSet<Sender>,
}

impl<T: Instance> InstanceMetadata<T> {
    fn new(instance: T) -> Self {
        InstanceMetadata {
            instance,
            clients: HashSet::new(),
        }
    }
}

/// This can't be a function because a function would have its own stack frame
/// and would need to drop the result of server.lock() before returning. This
/// is impossible if it wants to return a mutable reference to the droped data.
///
///     lock!(server: WebsocketServer) -> &mut SyncServer
macro_rules! lock {
    ( $server:expr ) => {{
        &mut *($server.0.lock().unwrap())
    }};
}

impl<T: Instance> Manager<T> {
    /// Creates a new instance and returns its key.
    pub fn new(&self) -> String {
        lock!(self).new()
    }
    /// Routes a message to the corresponding instance
    pub fn handle_message(&self, message: T::ClientMessage, sender: Sender) {
        lock!(self).handle_message(message, sender)
    }
    /// Subscribes a sender to the instance with the given key.
    pub fn subscribe(&self, key: Box<dyn ProvidesKey>, sender: Sender) {
        lock!(self).subscribe(key.key(), sender)
    }
}

impl<T: Instance> SyncManager<T> {
    fn new(&mut self) -> String {
        let key = generate_unique_key(&self.instances);

        let new_instance = T::new_with_key(&key);
        self.instances
            .insert(key.clone(), InstanceMetadata::new(new_instance));

        key
    }

    fn handle_message(&mut self, message: T::ClientMessage, sender: Sender) {
        let key = message.key();
        if let Some(instance) = self.instances.get_mut(&*key) {
            Self::handle_message_for_instance(message, &sender, instance)
        } else {
            Self::send_message(&sender, Self::error_no_instance(key));
        }
    }

    fn handle_message_for_instance(
        message: T::ClientMessage,
        sender: &Sender,
        instance: &mut InstanceMetadata<T>,
    ) {
        let mut context = Context::new();
        instance.instance.handle_message(message, &mut context);

        // Send messages back to client
        for msg in context.reply_queue {
            Self::send_message(sender, msg);
        }

        // Broadcast messages to all connected clients
        for msg in context.broadcast_queue {
            for client in &instance.clients {
                Self::send_message(client, msg.clone());
            }
        }
    }

    fn send_message(sender: &Sender, message: T::ServerMessage) {
        match sender.send(message) {
            Ok(()) => { /* Nothing to do, we are happy. */ }
            Err(_) => todo!("handle ws send errors"),
        }
    }

    fn subscribe(&mut self, key: Cow<String>, sender: Sender) {
        // Check if an instance with this key exists
        if let Some(instance) = self.instances.get_mut(&*key) {
            let mut client_already_connected = false;

            // Check if we already track this client
            let client = self.clients.get_mut(&sender);
            if let Some(client) = client {
                // If the set did have this value present, false is returned.
                client_already_connected = !client.connected_to.insert(key.clone().into_owned());
            } else {
                let mut client = ClientData::new(sender.clone());
                client.connected_to.insert(key.clone().into_owned());
                self.clients.insert(sender.clone(), client);
            }

            if client_already_connected {
                Self::send_message(
                    &sender,
                    T::ServerMessage::error(Cow::Owned(format!(
                        "Client is already connected to {}.",
                        key
                    ))),
                );
            } else {
                instance.clients.insert(sender.clone());
                Self::handle_message_for_instance(T::ClientMessage::subscribe(), &sender, instance);
            }
        } else {
            Self::send_message(&sender, Self::error_no_instance(key));
        }
    }

    /// Creates the error that is send to the client of they try to interact
    /// with an instance that does not exist.
    fn error_no_instance(key: Cow<String>) -> T::ServerMessage {
        T::ServerMessage::error(Cow::Owned(format!(
            "There is no instance with key {}.",
            key
        )))
    }
}

/// Returns a key that is not yet used in the map.
pub fn generate_unique_key<T>(map: &HashMap<String, T>) -> String {
    let rand_string = generate_key();
    if map.contains_key(&rand_string) {
        generate_unique_key(map)
    } else {
        rand_string
    }
}

fn generate_key() -> String {
    let code: usize = thread_rng().gen_range(0, 9000);
    format!("{}", code + 1000)
}
