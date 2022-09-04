use crate::db::Connection;
use crate::ServerError;

// Required for SQLX query_as! support.
struct FenWrapper {
    fen: String,
}

pub async fn get(id: i64, conn: &mut Connection) -> Result<Option<String>, ServerError> {
    Ok(
        sqlx::query_as!(FenWrapper, "select fen from puzzle where id = ?", id)
            .fetch_optional(conn)
            .await?
            .map(|w| w.fen),
    )
}
