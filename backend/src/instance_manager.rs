use crate::timeout;
use chrono::{DateTime, Duration, Utc};
use rand::{thread_rng, Rng};
use std::collections::{HashMap, HashSet};
use std::fmt::Debug;
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
pub trait Instance: Sized + Send {
    /// The type of messages send by the client to the server.
    type ClientMessage: ClientMessage;
    type ServerMessage: ServerMessage;
    type InstanceParameters;
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String>;
    /// Create a new instance and make it store the key.
    fn new_with_key(key: &str, params: Self::InstanceParameters) -> Self;
    /// Accept a client message and possibly send messages back.
    fn handle_message(&mut self, message: Self::ClientMessage, ctx: &mut Context<Self>);
    /// Called, when the instance set a timout itself and this timeout has passed
    fn handle_timeout(&mut self, now: DateTime<Utc>, ctx: &mut Context<Self>);
}

pub trait ProvidesKey {
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String>;
}

pub trait ClientMessage: ProvidesKey + Clone + Debug {
    /// Create a client messsage that represents a client subscribing.
    fn subscribe(key: String) -> Self;
}

pub trait ServerMessage: Into<String> + Clone + Debug {
    /// Allows us to send messages to the client without knowing about the
    /// server message type in detail.
    fn error(message: Cow<String>) -> Self;
}

/// Represents the client which send a message to the game. You can send server
/// messages back to the client. The messages will be buffered and send out
/// later. This means technical error handling can be hidden from the business
/// logic.
/// The context gives the ability to broadcast messages to all clients that are
/// connected to the same instance.
pub struct Context<T: Instance> {
    reply_queue: Vec<T::ServerMessage>,
    broadcast_queue: Vec<T::ServerMessage>,
    new_timeout: Option<DateTime<Utc>>,
}

impl<T: Instance> Context<T> {
    fn new() -> Self {
        Context {
            reply_queue: vec![],
            broadcast_queue: vec![],
            new_timeout: None,
        }
    }
    pub fn reply(&mut self, message: T::ServerMessage) {
        self.reply_queue.push(message)
    }
    pub fn broadcast(&mut self, message: T::ServerMessage) {
        self.broadcast_queue.push(message)
    }
    /// Request that the on_timeout method of this instance will be called at
    /// the given DateTime. If this is called multiple times, the earliest
    /// timeout will be used. This also applies for calls to set_timeout over
    /// different handle_message calls.
    pub fn set_timeout(&mut self, when: DateTime<Utc>) {
        self.new_timeout = Some(Self::min_time(when, self.new_timeout));
    }
    /// Returns the minimum time of the two given times. Returns the first value
    /// If the second one is None.
    fn min_time(a: DateTime<Utc>, b: Option<DateTime<Utc>>) -> DateTime<Utc> {
        if let Some(b) = b {
            if a < b {
                a
            } else {
                b
            }
        } else {
            a
        }
    }
}

/// As an implementation detail for now, we lock the Manager on every access.
/// This is of course not a good implementation and we should switch over to
/// some kind of concurrent hashmap in the future.
pub struct Manager<T: Instance> {
    sync: Arc<Mutex<SyncManager<T>>>,
}

/// Inner Manager, locked before access.
struct SyncManager<T: Instance> {
    instances: HashMap<String, InstanceMetadata<T>>,
    clients: HashMap<Sender, ClientData>,
    timeout_sender: crossbeam_channel::Sender<(String, DateTime<Utc>)>,
    /// Keeps a log of the last few games that were created.
    /// This is not really great, we'll eventually pull this directly from the
    /// DB as needed, as we don't want last_created for all types of instances.
    last_created: Vec<(String, DateTime<Utc>)>,
}

struct ClientData {
    connected_to: HashSet<String>,
}

impl ClientData {
    fn new() -> Self {
        ClientData {
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
        &mut *($server.sync.lock().unwrap())
    }};
}

impl<T: Instance> Clone for Manager<T> {
    fn clone(&self) -> Self {
        Manager {
            sync: self.sync.clone(),
        }
    }
}

impl<T: Instance + 'static> Default for Manager<T> {
    fn default() -> Self {
        Manager::new()
    }
}

impl<T: Instance + 'static> Manager<T> {
    /// Creates an empty manager that does not contain any games yet.
    pub fn new() -> Self {
        let new_instance = Manager {
            sync: Arc::from(Mutex::from(SyncManager::default())),
        };

        // The Manager and the timeout thread need to know each other, as they
        // communicate in both directions. I break this dependency loop by
        // first creating the manager with a dead end channel, setting up the
        // timeout thread and then replacing the sender with the new one.
        lock!(new_instance).timeout_sender = new_instance.spawn_timeout_thread();

        new_instance
    }
    /// Creates a new instance and returns its key.
    pub fn new_instance(&self, params: T::InstanceParameters) -> String {
        lock!(self).new_instance(params)
    }
    /// Routes a message to the corresponding instance
    pub fn handle_message(&self, message: T::ClientMessage, sender: Sender) {
        lock!(self).handle_message(message, sender)
    }
    /// Subscribes a sender to the instance with the given key.
    pub fn subscribe(&self, key: Cow<String>, sender: Sender) {
        lock!(self).subscribe(key, sender)
    }
    /// Spawns a thread in the background that is required to set and receive timeouts
    fn spawn_timeout_thread(&self) -> crossbeam_channel::Sender<(String, DateTime<Utc>)> {
        let m: Manager<T> = self.clone();
        timeout::Timeout::spawn(Box::new(m))
    }
    /// Runs a function on the instance assocciated with the key
    pub fn run<A, F: FnOnce(&T) -> A>(&self, key: String, f: F) -> Option<A> {
        lock!(self).run(key, f)
    }
    pub fn recently_created_games(&self) -> Vec<String> {
        lock!(self).recently_created_games()
    }
}

impl<T: Instance> timeout::Callback for Manager<T> {
    fn on_timeout(&self, key: String, now: DateTime<Utc>) {
        // TODO: This should use std::sync::Weak instead of std::sync::Arc,
        // because it will enable a clean shutdown of the timeout thread.
        // Currently the reference loop will keep the Manager and thread alive.
        lock!(self).on_timeout(key, now);
    }
}

impl<T: Instance> Default for SyncManager<T> {
    /// Creates an empty manager that does not contain any instances yet.
    fn default() -> Self {
        SyncManager {
            instances: HashMap::new(),
            clients: HashMap::new(),
            timeout_sender: crossbeam_channel::bounded(0).0,
            last_created: Vec::with_capacity(5),
        }
    }
}

impl<T: Instance> SyncManager<T> {
    fn new_instance(&mut self, params: T::InstanceParameters) -> String {
        let key = generate_unique_key(&self.instances);

        let new_instance = T::new_with_key(&key, params);
        self.instances
            .insert(key.clone(), InstanceMetadata::new(new_instance));
        self.remember_creation(key.clone(), Utc::now());

        info!("Created new instance with key {}", key);
        key
    }

    /// Stores the game in a short list of recently created games.
    fn remember_creation(&mut self, key: String, now: DateTime<Utc>) {
        // We never store more than 5 recently created games.
        if self.last_created.len() >= 5 {
            self.last_created.remove(0);
        }
        self.last_created.push((key, now));
    }

    /// Shows newest instaces up to five from the last five minutes
    pub fn recently_created_games(&mut self) -> Vec<String> {
        self.last_created
            .iter()
            .filter(|&t| t.1 > Utc::now() - Duration::minutes(5))
            .map(|t| t.0.clone())
            .collect()
    }

    fn handle_message(&mut self, message: T::ClientMessage, sender: Sender) {
        debug!("Handling client message {:?}", message);
        let key = message.key();
        if let Some(instance) = self.instances.get_mut(&*key) {
            Self::handle_message_for_instance(&self.timeout_sender, message, &sender, instance)
        } else {
            warn!("Got a client message with no assocciated : {:?}", message);
            Self::send_message(&sender, Self::error_no_instance(key));
        }
    }

    fn handle_message_for_instance(
        timeout_sender: &crossbeam_channel::Sender<(String, DateTime<Utc>)>,
        message: T::ClientMessage,
        sender: &Sender,
        instance: &mut InstanceMetadata<T>,
    ) {
        let mut context = Context::new();
        let key = message.key().into_owned();
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

        if let Some(when) = context.new_timeout {
            match timeout_sender.send((key, when)) {
                Ok(()) => { /* This is good*/ }
                Err(e) => error!("Timer thread is dead: {:?}", e),
            }
        }
    }

    fn send_message(sender: &Sender, message: T::ServerMessage) {
        match sender.send(ws::Message::text(message)) {
            Ok(()) => { /* Nothing to do, we are happy. */ }
            Err(e) => error!("Websocket send error: {:?}", e),
        }
    }

    fn subscribe(&mut self, key: Cow<String>, sender: Sender) {
        debug!("A client is subscribing to the instance {}.", key);
        // Check if an instance with this key exists
        if let Some(instance) = self.instances.get_mut(&*key) {
            let mut client_already_connected = false;

            // Check if we already track this client
            let client = self.clients.get_mut(&sender);
            if let Some(client) = client {
                // If the set did have this value present, false is returned.
                client_already_connected = !client.connected_to.insert(key.clone().into_owned());
            } else {
                let mut client = ClientData::new();
                client.connected_to.insert(key.clone().into_owned());
                self.clients.insert(sender.clone(), client);
            }

            if client_already_connected {
                warn!("The client is already connected to the instance {}.", key);
                Self::send_message(
                    &sender,
                    T::ServerMessage::error(Cow::Owned(format!(
                        "Client is already connected to {}.",
                        key
                    ))),
                );
            } else {
                debug!(
                    "Subscribing to the instance {} by a client was successful.",
                    key
                );
                instance.clients.insert(sender.clone());
                Self::handle_message_for_instance(
                    &self.timeout_sender,
                    T::ClientMessage::subscribe(key.into_owned()),
                    &sender,
                    instance,
                );
            }
        } else {
            warn!("The instance {} does not exist.", key);
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

    fn on_timeout(&mut self, key: String, now: DateTime<Utc>) {
        debug!("The timer thread reported a potential timeout for {}.", key);
        if let Some(instance) = self.instances.get_mut(&key) {
            let mut context = Context::new();

            instance.instance.handle_timeout(now, &mut context);

            if !context.reply_queue.is_empty() {
                // TODO: Ideally we would have a second context type that did
                // not even offer the .reply( .. ) method.
                error!(
                    "The instance with key {} called .reply( .. ) in a timeout handler.",
                    key
                );
            }

            // Broadcast messages to all connected clients
            for msg in context.broadcast_queue {
                for client in &instance.clients {
                    Self::send_message(client, msg.clone());
                }
            }

            if let Some(when) = context.new_timeout {
                match self.timeout_sender.send((key, when)) {
                    Ok(()) => { /* This is good*/ }
                    Err(e) => error!("Timer thread is dead: {:?}", e),
                }
            }
        }
    }

    /// Runs a function on the instance assocciated with the key
    fn run<A, F: FnOnce(&T) -> A>(&mut self, key: String, f: F) -> Option<A> {
        self.instances.get(&key).map(|meta| f(&meta.instance))
    }
}

/// Returns a number key that is not yet used in the map.
pub fn generate_unique_key<T>(map: &HashMap<String, T>) -> String {
    generate_unique_key_generic(map, || generate_key())
}

/// Returns an alphabetic key that is not yet used in the map.
pub fn generate_unique_key_alphabetic<T>(map: &HashMap<String, T>) -> String {
    generate_unique_key_generic(map, || alphabetic_key(3))
}

fn generate_unique_key_generic<T, F: Fn() -> String>(
    map: &HashMap<String, T>,
    generator: F,
) -> String {
    let rand_string = generator();
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
/// Generates a key consisting of only letters. We do this to differentiate the
/// designer keys from the game keys.
fn alphabetic_key(length: usize) -> String {
    use rand::seq::SliceRandom;

    // Here we exclude I, J and O because they can be easily mistaken.
    let letters: Vec<_> = "ABCDEFGHKLMNPQRSTUVWXYZ".chars().collect();

    letters
        .choose_multiple(&mut rand::thread_rng(), length)
        .collect()
}

#[cfg(test)]
mod test {
    use super::*;
    use chrono::Duration;

    /// This intstance manager is pretty tricky to get right, so I define a
    /// simple test instance type to test it.
    /// We need to implement all message types for this as well as an Instance
    /// stucture, so the setup is rather involved.
    /// Each instance is simply a i64 number that you can get or set by sending
    /// a message. Setting the value will broadcast to all other subscribers.

    struct TestInstance {
        key: String,
        value: i64,
    }

    #[derive(Clone, Debug)]
    enum TestClientMsg {
        Set { key: String, value: i64 },
        Get { key: String },
    }

    impl ProvidesKey for TestClientMsg {
        fn key(&self) -> Cow<String> {
            match self {
                TestClientMsg::Set { key, .. } => Cow::Borrowed(key),
                TestClientMsg::Get { key } => Cow::Borrowed(key),
            }
        }
    }

    impl ClientMessage for TestClientMsg {
        fn subscribe(key: String) -> Self {
            TestClientMsg::Get { key }
        }
    }

    #[derive(Clone, Debug)]
    enum TestServerMsg {
        IsNow { key: String, value: i64 },
        Oups { error: String },
    }

    impl From<TestServerMsg> for String {
        fn from(msg: TestServerMsg) -> Self {
            match msg {
                TestServerMsg::IsNow { key, value } => format!("{}: {}", key, value),
                TestServerMsg::Oups { error } => error,
            }
        }
    }

    impl ServerMessage for TestServerMsg {
        fn error(message: Cow<String>) -> Self {
            TestServerMsg::Oups {
                error: message.into_owned(),
            }
        }
    }

    impl Instance for TestInstance {
        type ClientMessage = TestClientMsg;
        type ServerMessage = TestServerMsg;
        type InstanceParameters = ();
        fn key(&self) -> Cow<String> {
            Cow::Borrowed(&self.key)
        }
        fn new_with_key(key: &str, _: ()) -> Self {
            TestInstance {
                key: key.to_owned(),
                value: 0,
            }
        }
        fn handle_message(&mut self, message: Self::ClientMessage, ctx: &mut Context<Self>) {
            match message {
                TestClientMsg::Set { key, value, .. } => {
                    self.value = value;
                    ctx.broadcast(TestServerMsg::IsNow { key, value });
                }
                TestClientMsg::Get { key } => {
                    ctx.reply(TestServerMsg::IsNow {
                        key,
                        value: self.value,
                    });
                }
            }
        }

        fn handle_timeout(&mut self, _now: DateTime<Utc>, _ctx: &mut Context<Self>) {
            // No timeouts used in the test.
        }
    }

    #[allow(deprecated)]
    fn new_mock_sender(id: u32) -> (Sender, impl FnMut() -> String) {
        // Yes, this is deprecated. But ws is using it, so I need it for testing.
        let (sender, receiver) = mio::channel::sync_channel(100);

        // This constructor is #[doc(hidden)], but still public.
        let sender = Sender::new(mio::Token(id as usize), sender, id);

        // The type ws::..::Command is private, so I can't talk about it and I am
        // unable to return any parameters which have this in its type parameter.
        let f = move || format!("{:?}", receiver.try_recv());

        (sender, Box::new(f))
    }

    /// Tries to connect to an instance that does not exist and fails.
    #[test]
    fn test_subscription_to_non_existing_game_fails() {
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);

        m.subscribe(Cow::Owned("Game1".to_owned()), s1);

        // We expect that there is exacty one message in the replies and that
        // it is about Game1 not existing.
        assert!(r1().contains("There is no instance with key Game1."));
        assert!(r1().starts_with("Err("));
    }

    /// Creates an instance and connects to it.
    /// Tests that we recieve the state as a response.
    /// Also checks that connecting twice does work.
    #[test]
    fn test_subscription_works() {
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);

        // Set up instance and connect.
        let key = m.new_instance(());
        m.subscribe(Cow::Owned(key.clone()), s1.clone());

        assert!(r1().contains(&format!("{}: {}", key, 0)));
        assert_eq!(r1(), "Err(Empty)");

        m.subscribe(Cow::Owned(key.clone()), s1);

        assert!(r1().contains(&format!("Client is already connected to {}.", key)));
        assert_eq!(r1(), "Err(Empty)");

        // Check that we are still only connected once.
        assert_eq!(lock!(m).clients.len(), 1);
    }

    /// Checks that Set and Get messages are handled correctly.
    #[test]
    fn test_reply_to_get() {
        // Set up instance and connect.
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);
        let key = m.new_instance(());
        m.subscribe(Cow::Owned(key.clone()), s1.clone());

        // Clean channel.
        assert!(r1().contains(&format!("{}: {}", key.clone(), 0)));
        assert_eq!(r1(), "Err(Empty)");

        m.handle_message(
            TestClientMsg::Set {
                key: key.clone(),
                value: 42,
            },
            s1.clone(),
        );

        assert!(r1().contains(&format!("{}: {}", key.clone(), 42)));
        assert_eq!(r1(), "Err(Empty)");

        m.handle_message(TestClientMsg::Get { key: key.clone() }, s1.clone());

        assert!(r1().contains(&format!("{}: {}", key.clone(), 42)));
        assert_eq!(r1(), "Err(Empty)");
    }

    /// Connect two clients and check that messages get passed as expected.
    #[test]
    fn test_message_passing() {
        // Set up instance and connect.
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);
        let (s2, mut r2) = new_mock_sender(2);
        let key = m.new_instance(());
        m.subscribe(Cow::Owned(key.clone()), s1.clone());
        m.subscribe(Cow::Owned(key.clone()), s2.clone());

        // Clean channels
        assert!(r1().contains(&format!("{}: {}", key.clone(), 0)));
        assert_eq!(r1(), "Err(Empty)");
        assert!(r2().contains(&format!("{}: {}", key.clone(), 0)));
        assert_eq!(r2(), "Err(Empty)");

        // Update the value from client 1 and check that it arrives in client 2.
        m.handle_message(
            TestClientMsg::Set {
                key: key.clone(),
                value: 42,
            },
            s1.clone(),
        );

        assert!(r2().contains(&format!("{}: {}", key.clone(), 42)));
        assert_eq!(r2(), "Err(Empty)");
    }

    #[test]
    fn test_set_timeout() {
        let now = Utc::now();

        let ctx: Context<TestInstance> = Context::new();
        assert_eq!(ctx.new_timeout, None);

        let mut ctx: Context<TestInstance> = Context::new();
        ctx.set_timeout(now);
        ctx.set_timeout(now + Duration::seconds(2));
        assert_eq!(ctx.new_timeout.unwrap(), now);

        let mut ctx: Context<TestInstance> = Context::new();
        ctx.set_timeout(now);
        ctx.set_timeout(now - Duration::seconds(2));
        assert_eq!(ctx.new_timeout.unwrap(), now - Duration::seconds(2));
    }
}
