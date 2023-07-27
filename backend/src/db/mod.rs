/// Everything related to the play page.
pub mod game;
pub(crate) mod puzzle;

use super::ServerError;
use sqlx::pool::PoolConnection;
/// All database logic for the pacosako game server lives in this project.
/// We are using sqlx to talk to an sqlite database.
use sqlx::sqlite::{Sqlite, SqlitePool};

#[derive(Clone)]
pub struct Pool(pub sqlx::pool::Pool<Sqlite>);

pub type Connection = PoolConnection<Sqlite>;

struct PositionRaw {
    id: i64,
    owner: i64,
    data: Option<String>,
}

impl Pool {
    pub async fn new(database_path: &str) -> Result<Self, sqlx::Error> {
        let pool = SqlitePool::connect(database_path).await?;

        Ok(Pool(pool))
    }

    /// Get a connection from the database pool.
    pub async fn conn(&self) -> Result<Connection, sqlx::Error> {
        self.0.acquire().await
    }
}

fn json_parse(raw: &Option<String>) -> Result<serde_json::Value, ServerError> {
    if let Some(raw) = raw {
        serde_json::from_str(raw).map_err(|_| ServerError::DeserializationFailed)
    } else {
        Err(ServerError::DeserializationFailed)
    }
}
