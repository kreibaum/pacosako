/// Everything related to the play page.
pub(crate) mod game;

use super::{LoginRequest, Position, SavePositionRequest, SavePositionResponse, ServerError, User};
/// All database logic for the pacosako game server lives in this project.
/// We are using sqlx to talk to an sqlite database.
use sqlx::sqlite::SqlitePool;

#[derive(Clone)]
pub struct Pool(pub SqlitePool);

struct PositionRaw {
    id: i64,
    owner: i64,
    data: Option<String>,
}

impl From<sqlx::Error> for ServerError {
    fn from(db_error: sqlx::Error) -> Self {
        ServerError::DatabaseError {
            message: db_error.to_string(),
        }
    }
}

impl Pool {
    pub async fn new(database_path: &str) -> Result<Self, sqlx::Error> {
        let pool = SqlitePool::connect(database_path).await?;

        Ok(Pool(pool))
    }

    pub(crate) async fn position_create(
        &self,
        request: SavePositionRequest,
        user: User,
    ) -> Result<SavePositionResponse, sqlx::Error> {
        let mut conn = self.0.acquire().await?;

        let request_data = request.data.to_string();

        let board_id = sqlx::query!(
            "INSERT INTO position (owner, data) VALUES (?1, ?2)",
            user.user_id,
            request_data,
        )
        .execute(&mut conn)
        .await?
        .last_insert_rowid();

        Ok(SavePositionResponse { id: board_id })
    }

    pub(crate) async fn position_update(
        &self,
        board_id: i64,
        request: SavePositionRequest,
    ) -> Result<SavePositionResponse, sqlx::Error> {
        let mut conn = self.0.acquire().await?;

        let request_data = request.data.to_string();

        sqlx::query!(
            "UPDATE position SET data = ?1 WHERE id = ?2",
            board_id,
            request_data
        )
        .execute(&mut conn)
        .await?;

        Ok(SavePositionResponse { id: board_id })
    }

    pub(crate) async fn position_get(&self, id: i64) -> Result<Position, ServerError> {
        let rec: Option<PositionRaw> = sqlx::query_as!(
            PositionRaw,
            "SELECT id, owner, data FROM position WHERE id = ?",
            id
        )
        .fetch_optional(&self.0)
        .await?;

        if let Some(rec) = rec {
            rec.into_position()
        } else {
            Err(ServerError::NotFound)
        }
    }

    pub(crate) async fn position_get_list(
        &self,
        user_id: i64,
    ) -> Result<Vec<Position>, ServerError> {
        let recs: Vec<PositionRaw> = sqlx::query_as!(
            PositionRaw,
            "SELECT id, owner, data FROM position WHERE owner = ?1",
            user_id
        )
        .fetch_all(&self.0)
        .await?;

        recs.iter().map(PositionRaw::into_position).collect()
    }

    pub(crate) async fn get_user(&self, username: String) -> Result<User, ServerError> {
        Ok(sqlx::query_as!(
            User,
            "SELECT id as user_id, username FROM user WHERE username = ?1",
            username
        )
        .fetch_one(&self.0)
        .await?)
    }

    pub(crate) async fn check_password(&self, login: &LoginRequest) -> Result<bool, ServerError> {
        use pbkdf2::pbkdf2_check;

        let rec = sqlx::query!(
            "SELECT password FROM user WHERE username = ?1",
            login.username,
        )
        .fetch_one(&self.0)
        .await?;

        if let Some(hash) = rec.password {
            Ok(pbkdf2_check(&login.password, &hash).is_ok())
        } else {
            // If the user has no password, they can't log in ever.
            Ok(false)
        }
    }
}

impl PositionRaw {
    fn into_position(&self) -> Result<Position, ServerError> {
        Ok(Position {
            id: self.id,
            owner: self.owner,
            data: json_parse(&self.data)?,
        })
    }
}

fn json_parse(raw: &Option<String>) -> Result<serde_json::Value, ServerError> {
    if let Some(raw) = raw {
        serde_json::from_str(raw).map_err(|_| ServerError::DeserializationFailed)
    } else {
        Err(ServerError::DeserializationFailed)
    }
}
