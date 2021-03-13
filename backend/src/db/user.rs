use std::ops::DerefMut;

use super::{LoginRequest, ServerError, User};
use crate::db::Connection;

pub async fn get_user(conn: &mut Connection, username: String) -> Result<User, ServerError> {
    Ok(sqlx::query_as!(
        User,
        "SELECT id as user_id, username FROM user WHERE username = ?1",
        username
    )
    .fetch_one(conn.deref_mut())
    .await?)
}

pub async fn check_password(
    conn: &mut Connection,
    login: &LoginRequest,
) -> Result<bool, ServerError> {
    use pbkdf2::pbkdf2_check;

    let rec = sqlx::query!(
        "SELECT password FROM user WHERE username = ?1",
        login.username,
    )
    .fetch_one(conn.deref_mut())
    .await?;

    if let Some(hash) = rec.password {
        Ok(pbkdf2_check(&login.password, &hash).is_ok())
    } else {
        // If the user has no password, they can't log in ever.
        Ok(false)
    }
}
