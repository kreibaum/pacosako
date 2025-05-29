//! Game Management API.

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};

use pacosako::PlayerColor;

use crate::protection::backdated_user_assignment::backdate_user_assignment;
use crate::{
    actors::websocket::UuidQuery,
    db::{self, Pool},
    login::{
        session::SessionData,
        user::{self, AiMetaData},
    },
    sync_match::{
        CompressedMatchStateClient, CurrentMatchStateClient, MatchParameters, SynchronizedMatch,
    },
    timer::TimerConfig,
    ws, AppState, ServerError,
};

mod frontend_ai;

/// Adds the game management API to the given router.
/// This is expected to be nested at "/api".
pub fn add_to_router(api_router: Router<AppState>) -> Router<AppState> {
    api_router
        .route("/create_game", post(create_game))
        .route("/game/:key", get(get_game))
        .route("/ai/game/:key", post(post_action_to_game))
        .route("/ai/game/:key/metadata/:color", post(post_ai_metadata))
        .route("/game/recent", get(recently_created_games))
        .route("/branch_game", post(branch_game))
        .route("/me/games", get(my_games))
        .route("/game/backdate", post(backdate_user_assignment))
}

/// Create a match on the database and return the id.
/// The Websocket will then have to load it on its own. While that is
/// mildly inefficient, it decouples the websocket server from the http
/// server a bit.
///
/// Also, this needs to write AI data to the database.
async fn create_game(
    pool: State<Pool>,
    session: Option<SessionData>,
    Json(game_parameters): Json<MatchParameters>,
) -> Result<String, ServerError> {
    if !game_parameters.is_legal() {
        return Err(ServerError::BadRequest);
    }

    info!("Creating a new game on client request.");
    let mut conn = pool.conn().await?;
    let mut game = SynchronizedMatch::new_with_key("0", game_parameters.sanitize());

    // Check if we also need to attach an AI to this game.
    if let Some(ai_side_request) = game_parameters.ai_side_request {
        let Some(ai) =
            frontend_ai::find_user_for_model_name(&ai_side_request.model_name, &mut conn).await?
        else {
            return Err(ServerError::BadRequest);
        };

        // Check who the requesting player is.
        let requesting_player = session.map(|s| s.user_id);

        // Replace None with a random color.
        let ai_color = ai_side_request.color.unwrap_or_else(|| {
            if rand::random() {
                PlayerColor::White
            } else {
                PlayerColor::Black
            }
        });

        if ai_color == PlayerColor::White {
            game.white_player = Some(ai);
            game.black_player = requesting_player;
        } else {
            game.white_player = requesting_player;
            game.black_player = Some(ai);
        }
        db::game::insert(&mut game, &mut conn).await?;
        let metadata = AiMetaData {
            model_name: ai_side_request.model_name,
            model_strength: ai_side_request.model_strength,
            model_temperature: ai_side_request.model_temperature,
            is_frontend_ai: true,
        };
        user::write_one_ai_config_for_game(&game.key, ai_color, &metadata, &mut conn).await?;
    } else {
        db::game::insert(&mut game, &mut conn).await?;
    }

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
        println!("loading game: {:?}", game.setup_options);
        Ok(Json(
            CurrentMatchStateClient::try_new_without_sender(game.current_state()?, &mut conn)
                .await?,
        ))
    } else {
        Err(ServerError::NotFound)
    }
}

async fn post_action_to_game(
    session: Option<SessionData>,
    Path(key): Path<String>,
    Query(params): Query<UuidQuery>,
    Json(action): Json<pacosako::PacoAction>,
) {
    ws::to_logic(ws::LogicMsg::AiAction {
        key,
        action,
        uuid: params.uuid,
        session_id: session.map(|s| s.session_id),
    })
    .await;
}

async fn post_ai_metadata(
    session: SessionData, // TODO: Verify that only AIs can call this.
    Path((key, player_color)): Path<(String, PlayerColor)>,
    pool: State<Pool>,
    Json(metadata): Json<AiMetaData>,
) -> Result<(), ServerError> {
    let mut conn = pool.conn().await?;
    user::write_one_ai_config_for_game(&key, player_color, &metadata, &mut conn).await?;

    // If this side of the game does not have player protection yet, we set it
    // to this AI player from the session.

    // update game set white_player = ? where id = ? // or black_player
    let key: i64 = key.parse()?;
    if let Some(game) = db::game::select(key, &mut conn).await? {
        if game.white_player.is_none() && player_color == PlayerColor::White {
            db::game::set_player(key, player_color, session.user_id, &mut conn).await?;
        } else if game.black_player.is_none() && player_color == PlayerColor::Black {
            db::game::set_player(key, player_color, session.user_id, &mut conn).await?;
        }
    }

    Ok(())
}

/// Returns the five most recently played games. It just returns each current state as fen.
async fn recently_created_games(
    pool: State<Pool>,
) -> Result<Json<Vec<CompressedMatchStateClient>>, ServerError> {
    let mut conn = pool.conn().await?;
    let games = db::game::latest(&mut conn).await?;

    let mut result = Vec::with_capacity(games.len());

    for game in games {
        result.push(CompressedMatchStateClient::try_new(&game, &game.project()?, &mut conn).await?);
    }

    Ok(Json(result))
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
    games: Vec<CompressedMatchStateClient>,
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

    let mut result = Vec::with_capacity(games.len());

    for game in games {
        result.push(CompressedMatchStateClient::try_new(&game, &game.project()?, &mut conn).await?);
    }

    Ok(Json(PagedGames {
        games: result,
        total_games,
    }))
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

        // Copy over AI configuration if it is present.
        // Shouldn't I then move the AI configuration to the SynchronizedMatch struct??
        // Some new GameDao struct to really hammer home the "This is a database object" point?
        // That would also lend itself to tracking who has won the game / is it over.

        Ok(game.key)
    } else {
        Err(ServerError::NotFound)
    }
}
