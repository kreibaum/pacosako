//! Module for managing `ReplayMetaInformation` in the backend

use axum::{extract::Path, Json};
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
    // Disabled for now to make it easy to merge this into the main branch
    if 2 * 2 > 3 {
        return Json(vec![]);
    }
    Json(vec![
        // If several arrows with the same game, action_index and category are
        // posted, then all of them are drawn
        ReplayMetaData {
            game: key.clone(),
            action_index: 2,
            category: "Example Arrow".to_owned(),
            data:
                r##"{"type":"arrow", "tail":11, "head":27, "color": "#ffc80080", "width" : 20 }"##
                    .to_owned(),
        },
        ReplayMetaData {
            game: key.clone(),
            action_index: 2,
            category: "Example Arrow".to_owned(),
            data: r##"{"type":"arrow", "tail":1, "head":18, "color": "#ff0000A0", "width" : 7  }"##
                .to_owned(),
        },
        ReplayMetaData {
            game: key.clone(),
            action_index: 4,
            category: "Weight Arrow".to_owned(),
            data: r#"{"type":"arrow", "tail":13, "head":21, "weight" : 1 }"#.to_owned(),
        },
        ReplayMetaData {
            game: key.clone(),
            action_index: 4,
            category: "Weight Arrow".to_owned(),
            data: r#"{"type":"arrow", "tail":14, "head":22, "weight" : 2 }"#.to_owned(),
        },
        ReplayMetaData {
            game: key.clone(),
            action_index: 4,
            category: "Weight Arrow".to_owned(),
            data: r#"{"type":"arrow", "tail":15, "head":23, "weight" : 3 }"#.to_owned(),
        },
        // If several values with the same game, action_index and category are
        // posted, then one of them is drawn
        ReplayMetaData {
            game: key.clone(),
            action_index: 4,
            category: "Value".to_owned(),
            // evaluation of the game state between -1 and 1, shown via a vertical
            // bar next to the board
            data: r#"{"type":"value", "value":0.15}"#.to_owned(),
        },
        ReplayMetaData {
            game: key.clone(),
            action_index: 6,
            category: "Value".to_owned(),
            // if uncertainty is associated to the value, a range can be provided
            data: r#"{"type":"value", "value":[0.15, 0.25]}"#.to_owned(),
        },
    ])
}
