//! Game Management API.

use crate::{
    db::{self, Pool},
    sync_match::{CurrentMatchState, MatchParameters, SynchronizedMatch},
    timer::TimerConfig,
    ws, AppState, ServerError,
};
use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;

/// Adds the game management API to the given router.
/// This is expected to be nested at "/api".
pub fn add_to_router(api_router: Router<AppState>) -> Router<AppState> {
    api_router
        .route("/create_game", post(create_game))
        .route("/game/:key", get(get_game))
        .route("/ai/game/:key", post(post_action_to_game))
        .route("/game/recent", get(recently_created_games))
        .route("/branch_game", post(branch_game))
}

/// Create a match on the database and return the id.
/// The Websocket will then have to load it on its own. While that is
/// mildly inefficient, it decouples the websocket server from the http
/// server a bit.
async fn create_game(
    pool: State<Pool>,
    game_parameters: Json<MatchParameters>,
) -> Result<String, ServerError> {
    info!("Creating a new game on client request.");
    let mut conn = pool.conn().await?;
    let mut game = SynchronizedMatch::new_with_key("0", game_parameters.0.sanitize());
    db::game::insert(&mut game, &mut conn).await?;

    info!("Game created with id {}.", game.key);
    Ok(game.key.to_string())
}

/// Returns the current state of the given game. This is intended for use by the
/// replay page.
async fn get_game(
    Path(key): Path<String>,
    pool: State<Pool>,
) -> Result<Json<CurrentMatchState>, ServerError> {
    let key: i64 = key.parse()?;
    let mut conn = pool.conn().await?;

    if let Some(game) = db::game::select(key, &mut conn).await? {
        Ok(Json(game.current_state()?))
    } else {
        Err(ServerError::NotFound)
    }
}

async fn post_action_to_game(Path(key): Path<String>, action: Json<pacosako::PacoAction>) {
    ws::to_logic(ws::LogicMsg::AiAction {
        key,
        action: action.0,
    })
    .await;
}

async fn recently_created_games(
    pool: State<Pool>,
) -> Result<Json<Vec<CurrentMatchState>>, ServerError> {
    let games = db::game::latest(&mut pool.conn().await?).await?;

    let vec: Result<Vec<CurrentMatchState>, _> = games.iter().map(|m| m.current_state()).collect();

    Ok(Json(vec?))
}

#[derive(Deserialize, Clone)]
struct BranchParameters {
    source_key: String,
    action_index: usize,
    timer: Option<TimerConfig>,
}

/// Create a match from an existing match
async fn branch_game(
    pool: State<Pool>,
    game_branch_parameters: Json<BranchParameters>,
) -> Result<String, ServerError> {
    info!("Creating a new game on client request.");
    let mut conn = pool.conn().await?;

    let game = db::game::select(game_branch_parameters.source_key.parse()?, &mut conn).await?;

    if let Some(mut game) = game {
        game.actions.truncate(game_branch_parameters.action_index);

        game.timer = game_branch_parameters.timer.clone().map(|o| o.into());

        db::game::insert(&mut game, &mut conn).await?;

        Ok(game.key)
    } else {
        Err(ServerError::NotFound)
    }
}
