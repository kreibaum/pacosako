//! Rust module for handling permissions.
//!
//! The related database table is `user_permission`.
//! This table is maintained in this module.

use sqlx::query;

use crate::db::Connection;
use crate::login::UserId;

pub const BACKDATED_USER_ASSIGNMENT: &str = "backdated_user_assignment";

/// Checks if a user has a certain permission.
pub async fn is_allowed(user_id: UserId, permission: &str, conn: &mut Connection) -> Result<bool, sqlx::Error> {
    let result = query!(
        r#"
        SELECT EXISTS (
            SELECT 1
            FROM user_permission
            WHERE user_id = $1 AND permission = $2
        ) AS permission_exists
        "#,
        user_id.0,
        permission
    )
        .fetch_one(conn)
        .await?;

    Ok(result.permission_exists.is_positive())
}
