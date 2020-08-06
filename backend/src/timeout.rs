use chrono::{DateTime, Duration, Utc};
use crossbeam_channel::{unbounded, Receiver, Sender};
use std::collections::HashMap;
use std::thread;
/// This module implements a timeout functionality. You can register timeouts on
/// a string key and will be notified when it runs out.

/// Timeout manager
pub struct Timeout {
    receiver: Receiver<(String, DateTime<Utc>)>,
    callback: Box<dyn Callback>,
    timeouts: HashMap<String, DateTime<Utc>>,
}

pub trait Callback: Send {
    fn on_timeout(&self, key: String, now: DateTime<Utc>);
}

enum Instruction {
    Schedule { key: String, when: DateTime<Utc> },
    TriggerCallback,
    Shutdown,
}

impl Timeout {
    /// Create a new timeout thread running in the background.
    /// Use the returned sender to request timeout callbacks.
    pub fn spawn(callback: Box<dyn Callback>) -> Sender<(String, DateTime<Utc>)> {
        let (sender, receiver) = unbounded();

        let data = Timeout {
            receiver,
            callback,
            timeouts: HashMap::new(),
        };

        thread::spawn(move || data.run());

        sender
    }

    /// Runs inside the new thread already
    fn run(mut self) {
        loop {
            let wakeup_time = self.determine_wakeup_time();

            match self.sleep(wakeup_time) {
                Instruction::Schedule { key, when } => {
                    self.schedule(key, when);
                }
                Instruction::TriggerCallback => {
                    self.trigger_callbacks();
                }
                Instruction::Shutdown => {
                    return;
                }
            }
        }
    }

    /// The wakeup time is just the minimum time that is scheduled.
    fn determine_wakeup_time(&self) -> Option<DateTime<Utc>> {
        self.timeouts.values().min().cloned()
    }

    fn sleep(&mut self, wakeup_time: Option<DateTime<Utc>>) -> Instruction {
        // Do we have a timer we are waiting for?
        if let Some(wakeup_time) = wakeup_time {
            self.sleep_for(wakeup_time - Utc::now())
        } else {
            self.sleep_indefinitely()
        }
    }

    /// Call this one to sleep when a timeout is scheduled. The duration is the
    /// amount of time the thread should listen for messages before handing back controll.
    fn sleep_for(&self, duration: Duration) -> Instruction {
        let duration: Result<std::time::Duration, time::OutOfRangeError> = duration.to_std();

        match duration {
            Ok(duration) => match self.receiver.recv_timeout(duration) {
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
    fn sleep_indefinitely(&self) -> Instruction {
        match self.receiver.recv() {
            Ok((key, when)) => Instruction::Schedule { key, when },
            Err(_) => Instruction::Shutdown,
        }
    }

    /// Figure out which callback are up and trigger them.
    /// This also removes them from the map.
    fn trigger_callbacks(&mut self) {
        let now = Utc::now();

        // Find out which keys timed out
        let timed_out: Vec<String> = self
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
            self.callback.on_timeout(key, now);
        }
    }

    fn schedule(&mut self, key: String, when: DateTime<Utc>) {
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
