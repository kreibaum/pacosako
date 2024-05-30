//! Game Protection Module. Here we make sure that only people who own the game
//! can play it.
//!
//! Historically, I had introduced the "safe_mode" flag to games and a client
//! side UUID in local storage. These UUID work as ephemeral keys that can own
//! games as well. We never persist them, so a server restart will restart the
//! safe_mode assignments.
//!
//! We now support users as well. A side of a game can be owned by a user. This
//! allows them to play the game on any device. We still support anonymous
//! users, as before.
//!
//! We'll also assume safe_mode for all games. This is no longer optional.
//!
//! It is possible to lock both sides to the same user. This reduces complexity
//! and I don't believe this ever was very important.

use serde::Serialize;

use crate::login::UserId;
use crate::ws::socket_auth::SocketIdentity;

pub mod backdated_user_assignment;

#[derive(Debug)]
pub enum SideProtection {
    Unlocked,         // No one moved yet, or we didn't persist the UUID.
    UuidLock(String), // A UUID has locked this side.
    UserLock(UserId), // A user has locked this side.
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum ControlLevel {
    /// No one controls this side. Take an action to take control.
    Unlocked,
    /// You control this side.
    LockedByYou,
    /// Your browser is asked to run the AI for this side.
    LockedByYourFrontendAi,
    /// Someone else controls this side.
    LockedByOther,
}

impl ControlLevel {
    pub fn can_control_or_take_over(self) -> bool {
        matches!(self, Self::Unlocked | Self::LockedByYou)
    }
}

impl SideProtection {
    /// Checks if the side can be controlled by the given socket.
    /// This is for read-only access. This does not lock the side.
    ///
    /// This does mean that there now is a difference between "This is your side"
    /// and "This is unassigned; you can take it". That is why we don't return
    /// a `bool` but a `ControlLevel`.
    pub fn test(&self, SocketIdentity { uuid, user_id }: &SocketIdentity) -> ControlLevel {
        match self {
            Self::Unlocked => ControlLevel::Unlocked,
            Self::UuidLock(current_uuid) => {
                if current_uuid == uuid {
                    ControlLevel::LockedByYou
                } else {
                    ControlLevel::LockedByOther
                }
            }
            Self::UserLock(current_user) => {
                if Some(*current_user) == *user_id {
                    ControlLevel::LockedByYou
                } else {
                    ControlLevel::LockedByOther
                }
            }
        }
    }

    /// Checks if the side can be controlled by the given uuid / user. Locks it
    /// to this uuid/user if it is unlocked.
    ///
    /// If it can be controlled by the given uuid and a user is given, then the
    /// lock upgrades to a user lock.
    pub fn test_and_assign(&mut self, socket_identity: &SocketIdentity) -> bool {
        let SocketIdentity { uuid, user_id } = socket_identity;
        match self {
            Self::Unlocked => {
                *self = socket_identity.into();
                true
            }
            Self::UuidLock(current_uuid) => {
                if current_uuid == uuid {
                    if let Some(user_id) = user_id {
                        *self = Self::UserLock(*user_id);
                    }
                    true
                } else {
                    false
                }
            }
            Self::UserLock(current_user) => *user_id == Some(*current_user),
        }
    }

    pub fn get_user(&self) -> Option<UserId> {
        match self {
            Self::Unlocked => None,
            Self::UuidLock(_) => None,
            Self::UserLock(user) => Some(*user),
        }
    }

    pub fn for_user(player: Option<UserId>) -> SideProtection {
        if let Some(player) = player {
            SideProtection::UserLock(player)
        } else {
            SideProtection::Unlocked
        }
    }
}

impl From<&SocketIdentity> for SideProtection {
    fn from(SocketIdentity { uuid, user_id }: &SocketIdentity) -> Self {
        if let Some(user_id) = user_id {
            SideProtection::UserLock(user_id.clone())
        } else {
            SideProtection::UuidLock(uuid.clone())
        }
    }
}
