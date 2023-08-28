//! Module to load user information from the database

use crate::db::Connection;

use super::UserId;

pub struct PublicUserData {
    pub name: String,
    pub avatar: String,
}

pub async fn load_public_user_data(
    user_id: UserId,
    connection: &mut Connection,
) -> Result<PublicUserData, anyhow::Error> {
    let res = sqlx::query!("select name, avatar from user where id = ?", user_id.0)
        .fetch_one(connection)
        .await?;

    Ok(PublicUserData {
        name: res.name.unwrap_or("Anonymous".to_string()),
        avatar: res.avatar,
    })
}
