use std::ops::DerefMut;

use super::{ServerError, User};
use crate::db::Connection;

pub async fn get_user(username: String, conn: &mut Connection) -> Result<User, ServerError> {
    Ok(sqlx::query_as!(
        User,
        "SELECT id as user_id, username FROM user WHERE username = ?1",
        username
    )
    .fetch_one(conn.deref_mut())
    .await?)
}
