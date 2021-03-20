/// This module implements a timeout functionality. You can register timeouts on
/// a string key and will be notified when it runs out.
use chrono::{DateTime, Duration, Utc};
use crossbeam_channel::{unbounded, Receiver, Sender};
use std::collections::HashMap;
use std::hash::Hash;
use std::thread;

type ChannelError<T> = crossbeam_channel::SendError<(T, DateTime<Utc>)>;

pub trait TimeoutOutMsg<T>: Sized + Send + Sync + 'static {
    fn from_ws_message(data: T, timestamp: DateTime<Utc>) -> Option<Self>;
}

/// Creates a timeout thread which works kind of like a channel, but all the
/// messages you put in get delayed. (Note that this channel is sync!)
pub fn run_timeout_thread<T>(
    to_logic: async_channel::Sender<impl TimeoutOutMsg<T>>,
) -> async_channel::Sender<(T, DateTime<Utc>)>
where
    T: Send + Sync + Eq + Hash + Clone + 'static,
{
    // We have a pair of channels and then do some logic inbetween.
    let (to_timeout, input) = unbounded();
    let (output, from_timeout) = unbounded();

    thread::spawn(move || {
        let data = Timeout {
            input,
            output,
            timeouts: HashMap::new(),
        };
        data.run()
    });

    let (result, to_timeout_async) = async_channel::unbounded();

    std::thread::spawn(move || async_std::task::block_on(read_async(to_timeout_async, to_timeout)));
    std::thread::spawn(move || async_std::task::block_on(forward_async(from_timeout, to_logic)));

    result
}

/// Ideally I should rewrite this connector to be async, then I can skip this
/// forwarding thread. But for now it is easier to forward then to convert this
/// into async properly.
async fn read_async<T>(
    to_timeout_async: async_channel::Receiver<(T, DateTime<Utc>)>,
    to_timeout: Sender<(T, DateTime<Utc>)>,
) -> () {
    while let Ok(pair) = to_timeout_async.recv().await {
        if to_timeout.send(pair).is_err() {
            break;
        }
    }
}

/// Ideally I should rewrite this connector to be async, then I can skip this
/// forwarding thread. But for now it is easier to forward then to convert this
/// into async properly.
async fn forward_async<T>(
    from_timeout: Receiver<(T, DateTime<Utc>)>,
    to_logic: async_channel::Sender<impl TimeoutOutMsg<T>>,
) -> () {
    while let Ok((data, timestamp)) = from_timeout.recv() {
        if let Some(msg) = TimeoutOutMsg::from_ws_message(data, timestamp) {
            if to_logic.send(msg).await.is_err() {
                break;
            }
        }
    }
}

/// Timeout manager
struct Timeout<T> {
    input: Receiver<(T, DateTime<Utc>)>,
    output: Sender<(T, DateTime<Utc>)>,
    timeouts: HashMap<T, DateTime<Utc>>,
}

pub trait Callback: Send {
    fn on_timeout(&self, key: String, now: DateTime<Utc>);
}

enum Instruction<T> {
    Schedule { key: T, when: DateTime<Utc> },
    TriggerCallback,
    Shutdown,
}

impl<T: Eq + Hash + Clone> Timeout<T> {
    /// Runs inside the new thread already
    fn run(mut self) -> Result<(), ChannelError<T>> {
        loop {
            let wakeup_time = self.determine_wakeup_time();

            match self.sleep(wakeup_time) {
                Instruction::Schedule { key, when } => {
                    self.schedule(key, when);
                }
                Instruction::TriggerCallback => {
                    self.trigger_callbacks()?;
                }
                Instruction::Shutdown => {
                    return Ok(());
                }
            }
        }
    }

    /// The wakeup time is just the minimum time that is scheduled.
    fn determine_wakeup_time(&self) -> Option<DateTime<Utc>> {
        self.timeouts.values().min().cloned()
    }

    fn sleep(&mut self, wakeup_time: Option<DateTime<Utc>>) -> Instruction<T> {
        // Do we have a timer we are waiting for?
        if let Some(wakeup_time) = wakeup_time {
            self.sleep_for(wakeup_time - Utc::now())
        } else {
            self.sleep_indefinitely()
        }
    }

    /// Call this one to sleep when a timeout is scheduled. The duration is the
    /// amount of time the thread should listen for messages before handing back controll.
    fn sleep_for(&self, duration: Duration) -> Instruction<T> {
        let duration: Result<std::time::Duration, time::OutOfRangeError> = duration.to_std();

        match duration {
            Ok(duration) => match self.input.recv_timeout(duration) {
                Ok((key, when)) => Instruction::Schedule { key, when },
                Err(error) => {
                    if error.is_timeout() {
                        Instruction::TriggerCallback
                    } else {
                        Instruction::Shutdown
                    }
                }
            },

            Err(_) => {
                // Out of range when converting from time to std can only happen
                // when the duration is negative. In this case we don't wait and
                // return immediately.
                Instruction::TriggerCallback
            }
        }
    }

    /// Call this one to sleep if no timeout is scheduled.
    fn sleep_indefinitely(&self) -> Instruction<T> {
        match self.input.recv() {
            Ok((key, when)) => Instruction::Schedule { key, when },
            Err(_) => Instruction::Shutdown,
        }
    }

    /// Figure out which callback are up and trigger them.
    /// This also removes them from the map.
    fn trigger_callbacks(&mut self) -> Result<(), ChannelError<T>> {
        let now = Utc::now();

        // Find out which keys timed out
        let timed_out: Vec<T> = self
            .timeouts
            .iter()
            .filter(|&(_, &v)| v < now)
            .map(|(k, _)| k.clone())
            .collect();

        // Remove them from the map
        for key in &timed_out {
            self.timeouts.remove(key);
        }

        // Trigger callbacks
        for key in timed_out {
            self.output.send((key.clone(), now))?;
        }
        Ok(())
    }

    fn schedule(&mut self, key: T, when: DateTime<Utc>) {
        match self.timeouts.entry(key) {
            std::collections::hash_map::Entry::Occupied(mut entry) => {
                // Check if the new timeout is earlier, replace the entry in that case.
                if when < *entry.get() {
                    entry.insert(when);
                }
            }
            std::collections::hash_map::Entry::Vacant(entry) => {
                // There is no entry in the HashMap yet, so we register the timeout.
                entry.insert(when);
            }
        }
    }
}
