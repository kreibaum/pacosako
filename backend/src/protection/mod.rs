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

use crate::login::UserId;

#[derive(Debug)]
pub enum SideProtection {
    Unlocked,         // No one moved yet, or we didn't persist the UUID.
    UuidLock(String), // A UUID has locked this side.
    UserLock(UserId), // A user has locked this side.
}

impl SideProtection {
    /// Checks if the side can be controlled by the given uuid / user. Locks it
    /// to this uuid/user if it is unlocked.
    ///
    /// If it can be controlled by the given uuid and a user is given, then the
    /// lock upgrades to a user lock.
    pub fn test_and_assign(&mut self, uuid: &str, user: Option<UserId>) -> bool {
        match self {
            Self::Unlocked => {
                if let Some(user) = user {
                    *self = Self::UserLock(user);
                } else {
                    *self = Self::UuidLock(uuid.to_owned());
                }
                true
            }
            Self::UuidLock(current_uuid) => {
                if current_uuid == uuid {
                    if let Some(user) = user {
                        *self = Self::UserLock(user);
                    }
                    true
                } else {
                    false
                }
            }
            Self::UserLock(current_user) => user == Some(*current_user),
        }
    }

    pub fn is_unclaimed(&self) -> bool {
        matches!(self, Self::Unlocked)
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
