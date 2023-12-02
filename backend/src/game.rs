//! Game Management API.

use crate::{
    db::{self, Pool},
    login::session::SessionData,
    sync_match::{CurrentMatchStateClient, MatchParameters, SynchronizedMatch},
    timer::TimerConfig,
    ws, AppState, ServerError,
};
use axum::{
    extract::{Path, Query, State},
    response::Response,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};

/// Adds the game management API to the given router.
/// This is expected to be nested at "/api".
pub fn add_to_router(api_router: Router<AppState>) -> Router<AppState> {
    api_router
        .route("/create_game", post(create_game))
        .route("/game/:key", get(get_game))
        .route("/ai/game/:key", post(post_action_to_game))
        .route("/game/recent", get(recently_created_games))
        .route("/branch_game", post(branch_game))
        .route("/me/games", get(my_games))
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
) -> Result<Json<CurrentMatchStateClient>, ServerError> {
    let key: i64 = key.parse()?;
    let mut conn = pool.conn().await?;

    if let Some(game) = db::game::select(key, &mut conn).await? {
        Ok(Json(
            CurrentMatchStateClient::try_new(game.current_state()?, &mut conn).await?,
        ))
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
) -> Result<Json<Vec<CurrentMatchStateClient>>, ServerError> {
    let mut conn = pool.conn().await?;
    let games = db::game::latest(&mut conn).await?;

    Ok(Json(add_metadata_for_client(games, conn).await?))
}

/// Essentially this is just a specific `map`, but I need to be able to await and use `?`.
async fn add_metadata_for_client(
    games: Vec<SynchronizedMatch>,
    mut conn: sqlx::pool::PoolConnection<sqlx::Sqlite>,
) -> Result<Vec<CurrentMatchStateClient>, ServerError> {
    let mut result = Vec::with_capacity(games.len());
    for game in games {
        result.push(CurrentMatchStateClient::try_new(game.current_state()?, &mut conn).await?);
    }

    Ok(result)
}

#[derive(Deserialize)]
struct PagingQuery {
    /// Offset must be >= 0.
    offset: u32,
    /// Limit must be between 1 and 100.
    limit: u32,
}

#[derive(Serialize)]
struct PagedGames {
    games: Vec<CurrentMatchStateClient>,
    total_games: usize,
}

async fn my_games(
    State(pool): State<Pool>,
    session: SessionData,
    Query(params): Query<PagingQuery>,
) -> Result<Json<PagedGames>, ServerError> {
    let mut conn = pool.conn().await?;

    if params.limit < 1 || params.limit > 100 {
        return Err(ServerError::BadRequest);
    }

    let games: Vec<SynchronizedMatch> = db::game::for_player(
        session.user_id.0,
        params.offset as i64,
        params.limit as i64,
        &mut conn,
    )
    .await?;

    let total_games = db::game::count_for_player(session.user_id.0, &mut conn).await? as usize;

    let games = add_metadata_for_client(games, conn).await?;

    Ok(Json(PagedGames { games, total_games }))
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
