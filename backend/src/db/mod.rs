/// Everything related to the play page.
pub mod game;
// pub(crate) mod puzzle;

use sqlx::pool::PoolConnection;
/// All database logic for the pacosako game server lives in this project.
/// We are using sqlx to talk to an sqlite database.
use sqlx::sqlite::{Sqlite, SqlitePool};

#[derive(Clone)]
pub struct Pool(pub sqlx::pool::Pool<Sqlite>);

pub type Connection = PoolConnection<Sqlite>;

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
