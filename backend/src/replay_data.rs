//! Module for managing `ReplayMetaInformation` in the backend

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};

use crate::{db::Pool, login::session::SessionData, ServerError};

#[derive(Serialize)]
pub struct ReplayMetaData {
    game: String,
    action_index: i64,
    category: String,
    /// data holds a json encoded payload to render the object.
    data: String,
}

#[derive(Serialize, Deserialize)]
pub struct ReplayMetaDataInput {
    action_index: i64,
    category: String,
    /// data holds a json encoded payload to render the object.
    data: String,
}

pub async fn post_metadata(
    _session: SessionData, // TODO: Verify that only AIs can call this.
    Path(key): Path<String>,
    pool: State<Pool>,
    Json(data): Json<Vec<ReplayMetaDataInput>>,
) -> Result<(), ServerError> {
    let mut conn = pool.conn().await?;

    for ele in data {
        sqlx::query!(
            r"INSERT INTO game_replay_metadata
        (game_id, action_index, category, metadata)
        VALUES (?, ?, ?, ?)",
            key,
            ele.action_index,
            ele.category,
            ele.data
        )
        .execute(&mut conn)
        .await?;
    }

    Ok(())
}

// Get the replay information
pub async fn get_metadata(
    pool: State<Pool>,
    Path(key): Path<String>,
) -> Result<Json<Vec<ReplayMetaData>>, ServerError> {
    let mut conn = pool.conn().await.unwrap();
    let data = sqlx::query!(
        r"SELECT action_index, category, metadata
        FROM game_replay_metadata
        WHERE game_id = ?",
        key
    )
    .fetch_all(&mut conn)
    .await?;

    let mut result = Vec::new();
    for ele in data {
        result.push(ReplayMetaData {
            game: key.clone(),
            action_index: ele.action_index,
            category: ele.category,
            data: ele.metadata,
        });
    }
    Ok(Json(result))
}
