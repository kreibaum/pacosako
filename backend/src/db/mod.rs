/// Everything related to the play page.
pub mod game;
// pub(crate) mod puzzle;

use std::ops::{Deref, DerefMut};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

use axum::{
    async_trait,
    extract::{FromRequestParts, Request, State},
    http::{request::Parts, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
/// All database logic for the pacosako game server lives in this project.
/// We are using sqlx to talk to an sqlite database.
use sqlx::pool::PoolConnection;
use sqlx::sqlite::{Sqlite, SqlitePool};

use crate::AppState;

pub type Connection = PoolConnection<Sqlite>;

/// A request-scoped database connection, shared across the whole request.
///
/// The database middleware checks a connection out of the pool before the
/// handler runs and inserts a `Conn` handle into the request's extension map.
/// `Conn` extractors clone the handle, take the connection out of it for
/// exclusive use, and put it back when they are done. The transaction is begun
/// on first use and the middleware commits or rolls it back based on the
/// response status. The connection is released to the pool once the last clone
/// of the handle is dropped.
///
/// Note that a handler must extract this *after* any other extractor that also
/// uses the request connection (such as `SessionData`), because only one
/// `Conn` may own the connection at a time.
pub struct Conn {
    inner: Arc<Mutex<Option<Connection>>>,
    in_transaction: Arc<AtomicBool>,
    conn: Option<Connection>,
}

impl Clone for Conn {
    /// Clones the shared handle. The clone never carries the owned connection;
    /// only a `Conn` that was created by the `FromRequestParts` extractor does.
    fn clone(&self) -> Self {
        Self {
            inner: Arc::clone(&self.inner),
            in_transaction: Arc::clone(&self.in_transaction),
            conn: None,
        }
    }
}

impl Conn {
    /// Checks a connection out of the pool and wraps it in a handle.
    pub async fn acquire(pool: &SqlitePool) -> Result<Self, sqlx::Error> {
        let conn = pool.acquire().await?;
        Ok(Self {
            inner: Arc::new(Mutex::new(Some(conn))),
            in_transaction: Arc::new(AtomicBool::new(false)),
            conn: None,
        })
    }

    /// Takes the connection out of the handle. Returns `None` if a `Conn`
    /// extractor currently has exclusive ownership of it.
    fn take(&self) -> Option<Connection> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take()
    }

    /// Puts the connection back into the handle.
    fn put(&self, conn: Connection) {
        *self
            .inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(conn);
    }

    /// Begins a transaction on the connection. This only happens on the first
    /// use within a request; all later uses reuse the already-open transaction.
    async fn begin(&self, conn: &mut Connection) -> Result<(), sqlx::Error> {
        if !self.in_transaction.load(Ordering::SeqCst) {
            sqlx::query("BEGIN").execute(&mut **conn).await?;
            self.in_transaction.store(true, Ordering::SeqCst);
        }
        Ok(())
    }

    /// Commits or rolls back the transaction that was opened for the request.
    ///
    /// The decision is derived purely from the HTTP response status: successful
    /// responses (2xx and redirects) are committed, everything else is rolled
    /// back. Errors while finishing the transaction are logged but do not
    /// change the response that is sent to the client.
    pub async fn finish(&self, status: StatusCode) {
        if !self.in_transaction.load(Ordering::SeqCst) {
            return;
        }
        let Some(mut conn) = self.take() else {
            return;
        };
        let result = if status.as_u16() < 400 {
            sqlx::query("COMMIT").execute(&mut *conn).await
        } else {
            sqlx::query("ROLLBACK").execute(&mut *conn).await
        };
        if let Err(e) = result {
            error!("Error when finishing the database transaction: {e}");
        }
        self.in_transaction.store(false, Ordering::SeqCst);
        self.put(conn);
    }
}

#[async_trait]
impl FromRequestParts<AppState> for Conn {
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(
        parts: &mut Parts,
        _state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let handle = parts.extensions.get::<Conn>().cloned().ok_or((
            StatusCode::INTERNAL_SERVER_ERROR,
            "No database connection available for this request",
        ))?;
        let mut extracted = handle.clone();
        let mut conn = extracted.take().ok_or((
            StatusCode::INTERNAL_SERVER_ERROR,
            "The database connection for this request is already in use",
        ))?;
        extracted.begin(&mut conn).await.map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Could not start transaction",
            )
        })?;
        extracted.conn = Some(conn);
        Ok(extracted)
    }
}

impl Deref for Conn {
    type Target = Connection;

    fn deref(&self) -> &Self::Target {
        self.conn
            .as_ref()
            .expect("Connection was already returned to the pool")
    }
}

impl DerefMut for Conn {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.conn
            .as_mut()
            .expect("Connection was already returned to the pool")
    }
}

impl Drop for Conn {
    fn drop(&mut self) {
        if let Some(conn) = self.conn.take() {
            self.put(conn);
        }
        if Arc::strong_count(&self.inner) == 1 && self.in_transaction.load(Ordering::SeqCst) {
            error!(
                "Dropping a request connection while a transaction is still open. \
                 This usually means a handler panicked before the transaction could be finished."
            );
        }
    }
}

/// Middleware that lends a single database connection to every request.
///
/// A connection is checked out of the pool before the handler runs and a
/// handle to it is stashed in the request's extension map, where `Conn`
/// extractors can pick it up. No transaction is started here. After the
/// handler has finished, the transaction (if any) is committed for successful
/// responses and rolled back for error responses.
pub async fn conn_middleware(
    State(pool): State<SqlitePool>,
    mut request: Request,
    next: Next,
) -> Response {
    let conn = match Conn::acquire(&pool).await {
        Ok(conn) => conn,
        Err(e) => {
            error!("Could not check out a database connection: {e}");
            return (StatusCode::INTERNAL_SERVER_ERROR, "Database error").into_response();
        }
    };
    request.extensions_mut().insert(conn.clone());
    let response = next.run(request).await;
    conn.finish(response.status()).await;
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, extract::Request};

    /// Creates a request connection over an in-memory database that already
    /// contains a single table. SQLite keeps one private in-memory database per
    /// connection, so the schema is created on the very connection that the
    /// handle lends out. As long as the handle stays alive the same connection
    /// is reused and the data persists across `take`/`put` cycles.
    async fn test_handle() -> Conn {
        let pool = SqlitePool::connect("sqlite::memory:").await.unwrap();
        let handle = Conn::acquire(&pool).await.unwrap();
        let mut conn = handle.take().unwrap();
        sqlx::query("CREATE TABLE test_rows (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
            .execute(&mut *conn)
            .await
            .unwrap();
        handle.put(conn);
        handle
    }

    async fn insert_row(handle: &Conn, value: &str) {
        let mut conn = handle.take().unwrap();
        sqlx::query("INSERT INTO test_rows (value) VALUES (?)")
            .bind(value)
            .execute(&mut *conn)
            .await
            .unwrap();
        handle.put(conn);
    }

    async fn count_rows(handle: &Conn) -> i64 {
        let mut conn = handle.take().unwrap();
        let count: i64 = sqlx::query_scalar("SELECT count(*) FROM test_rows")
            .fetch_one(&mut *conn)
            .await
            .unwrap();
        handle.put(conn);
        count
    }

    #[tokio::test]
    async fn success_response_commits_the_transaction() {
        let handle = test_handle().await;

        // Simulate a handler: take the connection, begin lazily, write.
        let mut conn = handle.take().unwrap();
        handle.begin(&mut conn).await.unwrap();
        handle.put(conn);
        insert_row(&handle, "a").await;

        // The middleware would now decide based on a 2xx response.
        handle.finish(StatusCode::OK).await;

        assert_eq!(count_rows(&handle).await, 1);
    }

    #[tokio::test]
    async fn error_response_rolls_back_the_transaction() {
        let handle = test_handle().await;

        let mut conn = handle.take().unwrap();
        handle.begin(&mut conn).await.unwrap();
        handle.put(conn);
        insert_row(&handle, "a").await;

        // A non-2xx response must discard all writes of the request.
        handle.finish(StatusCode::INTERNAL_SERVER_ERROR).await;

        assert_eq!(count_rows(&handle).await, 0);
    }

    #[tokio::test]
    async fn begin_is_lazy_and_reused() {
        let handle = test_handle().await;

        // Without a first use, nothing is committed or rolled back.
        handle.finish(StatusCode::OK).await;

        // The first use begins a transaction and later uses reuse it.
        let mut conn = handle.take().unwrap();
        handle.begin(&mut conn).await.unwrap();
        handle.begin(&mut conn).await.unwrap(); // does not begin a second transaction
        handle.put(conn);
        insert_row(&handle, "a").await;
        insert_row(&handle, "b").await;

        handle.finish(StatusCode::OK).await;
        assert_eq!(count_rows(&handle).await, 2);
    }

    #[tokio::test]
    async fn conn_extractor_reuses_the_request_connection() {
        let pool = SqlitePool::connect("sqlite::memory:").await.unwrap();
        let handle = Conn::acquire(&pool).await.unwrap();
        let mut request = Request::builder().uri("/").body(Body::empty()).unwrap();
        request.extensions_mut().insert(handle);

        let app_state = crate::AppState {
            config: crate::config::EnvironmentConfig {
                dev_mode: false,
                database_path: String::new(),
                bind: String::new(),
                secret_key: String::new(),
                grafana_password: String::new(),
                server_url: String::new(),
                discord_client_id: String::new(),
                secrets_file: String::new(),
                discord_client_secret: String::new(),
            },
            pool,
        };

        let (mut parts, _) = request.into_parts();
        let conn = Conn::from_request_parts(&mut parts, &app_state)
            .await
            .unwrap();
        // The extractor has taken exclusive ownership of the pooled connection.
        assert!(parts.extensions.get::<Conn>().unwrap().take().is_none());
        drop(conn);
        // Dropping the extractor returns the connection to the request handle.
        assert!(parts.extensions.get::<Conn>().unwrap().take().is_some());
    }
}
