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
            data: r##"{"type":"arrow", "tail":11, "head":27, "color": "#ffc80080", "width" : 20 }"##.to_owned()
        },
        ReplayMetaData {
            game : key.clone(),
            action_index : 2,
            category: "Example Arrow".to_owned(),
            data: r##"{"type":"arrow", "tail":1, "head":18, "color": "#ff0000A0", "width" : 7  }"##.to_owned()
        },
        ReplayMetaData {
            game : key.clone(),
            action_index : 4,
            category: "Weight Arrow".to_owned(),
            data: r##"{"type":"arrow", "tail":13, "head":21, "weight" : 1 }"##.to_owned()
        },
        ReplayMetaData {
            game : key.clone(),
            action_index : 4,
            category: "Weight Arrow".to_owned(),
            data: r##"{"type":"arrow", "tail":14, "head":22, "weight" : 2 }"##.to_owned()
        },
        ReplayMetaData {
            game : key.clone(),
            action_index : 4,
            category: "Weight Arrow".to_owned(),
            data: r##"{"type":"arrow", "tail":15, "head":23, "weight" : 3 }"##.to_owned()
        }
    ])
}
