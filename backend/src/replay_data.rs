//! Module for managing `ReplayMetaInformation` in the backend

use axum::{Json, extract::Path};
use serde::Serialize;

#[derive(Serialize)]
pub struct ReplayMetaData {
    game: String,
    action_index: i64,
    category: String,
    /// data holds a json encoded payload to render the object.
    data: String,
}



// Get the replay information
pub async fn get_metadata(Path(key): Path<String>) -> Json<Vec<ReplayMetaData>> {
    Json(vec![
        ReplayMetaData {
            game : key.clone(),
            action_index : 2,
            category: "Example Arrow".to_owned(),
            data: r#"{"type":"arrow", "start":11, "end":27 }"#.to_owned()
        },
        ReplayMetaData {
            game : key,
            action_index : 2,
            category: "Example Arrow".to_owned(),
            data: r#"{"type":"arrow", "start":1, "end":18 }"#.to_owned()
        }
    ])
}
