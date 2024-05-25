//! Helper functions around the permissions that a websocket connection holds.

use crate::db;
use crate::login::{session, SessionId, UserId};

/// Every websocket must have an uuid, otherwise the connection is refused.
/// They may also have a session token which is used to authenticate the user.
/// This session id is stored in the database and persists between server restarts.
/// The uuid is stored in local storage and persists as well.
///
/// This is how we allow people to play without an account without their games
/// getting "stolen" by someone else.
pub type SocketAuth = (String, Option<SessionId>);

/// You can resolve the session id of a socket to a user id.
pub struct SocketIdentity {
    pub uuid: String,
    pub user_id: Option<UserId>,
}

impl SocketIdentity {
    /// Checks the validity of the session and returns the user id.
    /// Do not store this, sessions may expire, or users may log out!
    pub async fn resolve_user((uuid, session_id): &SocketAuth, conn: &mut db::Connection) -> Result<SocketIdentity, anyhow::Error> {
        let user_id = if let Some(session_id) = session_id {
            let session_data = session::load_session(session_id, conn).await?;
            Some(session_data.user_id)
        } else {
            None
        };
        Ok(SocketIdentity {
            uuid: uuid.clone(),
            user_id,
        })
    }
}