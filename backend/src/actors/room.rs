//! A room, or game room is an actor that manages a game. It reacts to game
//! events and updates other players of the latest state.
//!
//! The database is used as a backing storage at all times.

use super::{
    protection::{GameProtectionStrategy, NoProtectionStrategy},
    websocket::SocketId,
};
use dashmap::{mapref::entry::Entry, DashMap};
use lazy_static::lazy_static;
use std::collections::HashSet;

pub struct Room {
    key: String,
    connected: HashSet<SocketId>,
    /// The UUIDs that are allowed to make moves on this board.
    /// This is not persisted for now, so after a server restart the game
    /// can be hijacked in principle.
    protection: Box<dyn GameProtectionStrategy>,
    // TODO: Should the GameProtectionStrategy really be the responsibility of the room?
    // Or is this only in here, because the Room is the only thing that lives long enough?
    // Since the game state is loaded and destroyed on each action.
}

lazy_static! {
    /// Stores all rooms that are currently active.
    static ref ALL_ROOMS: DashMap<String, Room> = DashMap::new();
}

/// Tries to connect a socket to a room. If the room does not exist, it is created.
pub fn connect(key: String, client: SocketId) {
    let mut room = ALL_ROOMS.entry(key.clone()).or_insert_with(|| Room {
        key: key.clone(),
        connected: HashSet::new(),
        protection: Box::new(NoProtectionStrategy),
    });
    room.connected.insert(client);
}

/// Disconnects a socket from a room. If this was the last socket, the room
/// is deleted.
pub fn disconnect(key: String, client: SocketId) {
    // This must use the entry API to make sure there is no "gap" in holding the
    // lock. In such a gap, another connection may insert a new connection which
    // makes the room not empty anymore.
    // With this entry API, the lock is held until the entry is removed.
    // The other thread would then create a new room, which is fine.
    match ALL_ROOMS.entry(key) {
        Entry::Occupied(mut entry) => {
            entry.get_mut().connected.remove(&client);
            if entry.get().connected.is_empty() {
                entry.remove();
            }
        }
        Entry::Vacant(_) => {
            // Nothing to remove, somehow the room already doesn't exist.
        }
    }
}
