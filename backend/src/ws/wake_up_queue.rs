//! Implements a wake-up queue that is used to coordinate wake-up.
//! The timers can be cancelled by sending a new shorter delay to the queue for
//! the same key.

use chrono::Utc;
use once_cell::sync::OnceCell;
use std::{
    collections::{BTreeMap, BTreeSet},
    time::Instant,
};

use crate::ws::{to_logic, LogicMsg};

pub fn spawn_sleeper_thread() {
    std::thread::spawn(move || {
        let sleeper = sleeper_task();
        tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .expect("Failed to create tokio runtime for wake up queue")
            .block_on(sleeper);
    });
}

pub fn put_utc(key: impl Into<String>, wake_up: chrono::DateTime<Utc>) {
    let wake_up = wake_up - Utc::now();
    let wake_up = std::time::Instant::now() + wake_up.to_std().unwrap();

    put(key, wake_up);
}

pub fn put(key: impl Into<String>, wake_up: Instant) {
    if let Err(e) = WAKE_UP_SENDER
        .get()
        .expect("WAKE_UP_SENDER not initialized")
        .send(WakeUpEntry {
            key: key.into(),
            wake_up,
        })
    {
        warn!("Failed to send wake up entry: {}", e)
    }
}

/// Returns a future that sleeps until the given wake up time.
async fn sleep_until(entry: WakeUpEntry) {
    let now = Instant::now();
    if entry.wake_up > now {
        tokio::time::sleep(entry.wake_up - now).await;
    }
}

static WAKE_UP_SENDER: OnceCell<kanal::Sender<WakeUpEntry>> = OnceCell::new();

/// Runs the wake up queue as a tokio task.
async fn sleeper_task() {
    let (sender, receiver) = kanal::bounded_async(20);

    let mut wake_ups: BTreeSet<WakeUpEntry> = BTreeSet::new();
    let mut wake_up_for_key: BTreeMap<String, WakeUpEntry> = BTreeMap::new();

    WAKE_UP_SENDER
        .set(sender.clone_sync())
        .expect("Failed to set wake up sender");

    loop {
        // Check if there is a wake up
        let first = wake_ups.iter().next().cloned();
        if let Some(entry) = first {
            // Sleep until the wake up time is reached or a new wake up is requested.
            let sleep = sleep_until(entry);
            let new_wake_up = receiver.recv();
            tokio::select! {
                _ = sleep => {
                    trigger_up_wake_ups(&mut wake_ups, &mut wake_up_for_key);
                }
                new_wake_up = new_wake_up => {
                    let new_wake_up = new_wake_up.expect("Wake up receiver closed");
                    update_wake_up(&mut wake_ups, &mut wake_up_for_key, new_wake_up);
                }
            }
        } else {
            let new_wake_up = receiver.recv().await.expect("Wake up receiver closed");
            update_wake_up(&mut wake_ups, &mut wake_up_for_key, new_wake_up);
        }
    }
}

/// A new wake up was requested. Remove the old one and add the new one.
fn update_wake_up(
    wake_ups: &mut BTreeSet<WakeUpEntry>,
    wake_up_for_key: &mut BTreeMap<String, WakeUpEntry>,
    new_wake_up: WakeUpEntry,
) {
    if let Some(old_wake_up) = wake_up_for_key.remove(&new_wake_up.key) {
        wake_ups.remove(&old_wake_up);
    }
    wake_ups.insert(new_wake_up.clone());
    wake_up_for_key.insert(new_wake_up.key.clone(), new_wake_up);
}

fn trigger_up_wake_ups(
    wake_ups: &mut BTreeSet<WakeUpEntry>,
    wake_up_for_key: &mut BTreeMap<String, WakeUpEntry>,
) {
    println!("Triggering up wake ups. Current size: {}", wake_ups.len());

    loop {
        // Get the first wake up and check if is is already due.
        let first = wake_ups.iter().next().cloned();
        if let Some(entry) = first {
            if entry.wake_up > Instant::now() {
                // The first wake up is not due yet. We are done.
                break;
            } else {
                // The first wake up is due. Remove it.
                wake_ups.remove(&entry);
                wake_up_for_key.remove(&entry.key);
                to_logic(LogicMsg::Timeout {
                    key: entry.key,
                    timestamp: Utc::now(),
                });
            }
        } else {
            // There are no more wake ups. We are done.
            break;
        }
    }
    println!("Wake ups triggered. Current size: {}", wake_ups.len());
}

#[derive(Debug, PartialEq, Eq, Clone)]
struct WakeUpEntry {
    key: String,
    wake_up: Instant,
}

/// Implement Ord on WakeUpEntry so that it can be used in a BTreeSet.
/// The ordering is reversed so that the smallest wake_up time is at the front.
/// If the wake_up times are equal, the key is used to break the tie.
/// This is needed to make the ordering total.
impl Ord for WakeUpEntry {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        match self.wake_up.cmp(&other.wake_up) {
            std::cmp::Ordering::Equal => self.key.cmp(&other.key),
            std::cmp::Ordering::Less => std::cmp::Ordering::Greater,
            std::cmp::Ordering::Greater => std::cmp::Ordering::Less,
        }
    }
}

impl PartialOrd for WakeUpEntry {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
