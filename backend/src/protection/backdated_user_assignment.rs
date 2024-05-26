//! You are able to "backdate" user assignment on a game.
//! This can only happen when the game has already finished and requires special
//! permission from the user assigning the game's players.
//!
//! This is useful for assigning games to users that were not logged in at the time
//! the game was played.

use axum::extract::State;
use axum::Json;
use serde::Deserialize;

use pacosako::PlayerColor;

use crate::{db, ServerError};
use crate::db::{Connection, Pool};
use crate::login::permission::{BACKDATED_USER_ASSIGNMENT, is_allowed};
use crate::login::session::SessionData;
use crate::login::UserId;

/// This struct goes verbatim into `game_assignment_audit` table, so I have an idea
/// what was going on when there are arguments about misuse.
///
/// As far as rust is concerned, this is write-only.
/// It is only read manually.
#[derive(Debug)]
struct BackdatedUserAssignment {
    game_id: i64,
    white_assignee: Option<UserId>,
    black_assignee: Option<UserId>,
    assigned_by: UserId,
}

async fn perform_backdated_user_assignment(
    data: BackdatedUserAssignment, conn: &mut Connection,
) -> Result<(), ServerError> {
    info!("Backdating user assignment: {:#?}", data);

    // First, validate whether the user doing the assignment has the permission to do so.
    if !is_allowed(data.assigned_by, BACKDATED_USER_ASSIGNMENT, conn).await? {
        return Err(ServerError::NotAllowed("You do not have permission to backdate user assignment".to_string()));
    }

    // Load the current state of the game.
    let Some(game) = db::game::select(data.game_id, conn).await? else {
        return Err(ServerError::NotFound);
    };

    // Check if the game is over.
    if !game.current_state()?.victory_state.is_over() {
        return Err(ServerError::NotAllowed("Game is not over yet".to_string()));
    }

    // Check if any assignments that are getting made are incompatible with what is
    // already known about the game.
    if game.white_player.is_some() && data.white_assignee.is_some() && game.white_player != data.white_assignee {
        return Err(ServerError::NotAllowed(format!("White player is already assigned as {:?}", game.white_player)));
    }

    if game.black_player.is_some() && data.black_assignee.is_some() && game.black_player != data.black_assignee {
        return Err(ServerError::NotAllowed(format!("Black player is already assigned as {:?}", game.black_player)));
    }

    // Check if this actually adds any new information.
    let new_white_info = data.white_assignee.is_some() && game.white_player.is_none();
    let new_black_info = data.black_assignee.is_some() && game.black_player.is_none();
    if !new_white_info && !new_black_info {
        return Err(ServerError::NotAllowed("No new information to add".to_string()));
    }

    // Everything looks good, we can finally assign the players.
    // The audit log is written first.
    // "Temporary value dropped while borrowed" if we don't use those variables.
    let w = data.white_assignee.map(|u| u.0);
    let b = data.black_assignee.map(|u| u.0);
    sqlx::query!(
        "insert into game_assignment_audit (game_id, white_assignee, black_assignee, assigned_by) values (?, ?, ?, ?)",
        data.game_id, w, b, data.assigned_by.0,
    ).execute(&mut *conn).await?;

    // Now we can update the game.
    if let Some(white_assignee) = data.white_assignee {
        db::game::set_player(data.game_id, PlayerColor::White, white_assignee, &mut *conn).await?;
    }
    if let Some(black_assignee) = data.black_assignee {
        db::game::set_player(data.game_id, PlayerColor::Black, black_assignee, &mut *conn).await?;
    }

    Ok(())
}

#[derive(Deserialize, Debug)]
pub struct BackdatedUserAssignmentPostParameters {
    game_id: i64,
    white_assignee: Option<i64>,
    black_assignee: Option<i64>,
}

pub async fn backdate_user_assignment(
    session: SessionData,
    pool: State<Pool>,
    Json(params): Json<BackdatedUserAssignmentPostParameters>,
) -> Result<(), ServerError> {
    let mut conn = pool.conn().await?;
    perform_backdated_user_assignment(BackdatedUserAssignment {
        game_id: params.game_id,
        white_assignee: params.white_assignee.map(UserId),
        black_assignee: params.black_assignee.map(UserId),
        assigned_by: session.user_id,
    }, &mut conn).await
}