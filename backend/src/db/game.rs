use pacosako::setup_options::SetupOptionsAllOptional;

use crate::db::Connection;
use crate::login::UserId;
use crate::timer::Timer;
use crate::{sync_match::SynchronizedMatch, ServerError};

/// Stores the game in the database as a new entry and updates the id
pub async fn insert(
    game: &mut SynchronizedMatch,
    conn: &mut Connection,
) -> Result<(), ServerError> {
    let action_history = serde_json::to_string(&game.actions)?;

    let timer = if let Some(ref timer) = game.timer {
        Some(serde_json::to_string(timer)?)
    } else {
        None
    };
    let setup = serde_json::to_string(&game.setup_options)?;

    let white_player = game.white_player.map(|u| u.0);
    let black_player = game.black_player.map(|u| u.0);

    let id = sqlx::query!(
        "insert into game (action_history, timer, safe_mode, setup, white_player, black_player) values (?, ?, 1, ?, ?, ?)",
        action_history,
        timer,
        setup,
        white_player,
        black_player
    )
    .execute(conn)
    .await?
    .last_insert_rowid();

    game.key = format!("{id}");

    Ok(())
}

/// Updates the game in the database.
pub async fn update(game: &SynchronizedMatch, conn: &mut Connection) -> Result<(), ServerError> {
    let id: i64 = game.key.parse()?;

    let action_history = serde_json::to_string(&game.actions)?;

    let timer = if let Some(ref timer) = game.timer {
        Some(serde_json::to_string(timer)?)
    } else {
        None
    };

    let white_player = game.white_player.map(|u| u.0);
    let black_player = game.black_player.map(|u| u.0);

    sqlx::query!(
        r"update game
        set action_history = ?, timer = ?, white_player = ?, black_player = ?
        where id = ?",
        action_history,
        timer,
        white_player,
        black_player,
        id
    )
    .execute(conn)
    .await?;

    Ok(())
}

pub async fn select(
    id: i64,
    conn: &mut Connection,
) -> Result<Option<SynchronizedMatch>, ServerError> {
    let raw_game = sqlx::query_as!(
        RawGame,
        "select id, action_history, timer, setup, white_player, black_player from game where id = ?",
        id
    )
    .fetch_optional(conn)
    .await?;

    if let Some(raw_game) = raw_game {
        Ok(Some(raw_game.into_match()?))
    } else {
        Ok(None)
    }
}

pub async fn latest(conn: &mut Connection) -> Result<Vec<SynchronizedMatch>, ServerError> {
    let raw_games = sqlx::query_as!(
        RawGame,
        r"select id, action_history, timer, setup, white_player, black_player from game
        order by id desc
        limit 5"
    )
    .fetch_all(conn)
    .await?;

    raw_games.into_iter().map(|raw| raw.into_match()).collect()
}

pub async fn for_player(
    user_id: i64,
    offset: i64,
    limit: i64,
    conn: &mut Connection,
) -> Result<Vec<SynchronizedMatch>, ServerError> {
    let raw_games = sqlx::query_as!(
        RawGame,
        r"select id, action_history, timer, setup, white_player, black_player from game
        where white_player = ? or black_player = ?
        order by id desc
        limit ? offset ?",
        user_id,
        user_id,
        limit,
        offset,
    )
    .fetch_all(conn)
    .await?;

    raw_games.into_iter().map(|raw| raw.into_match()).collect()
}

pub async fn count_for_player(user_id: i64, conn: &mut Connection) -> Result<i32, ServerError> {
    Ok(sqlx::query!(
        r"select count(*) as count from game
            where white_player = ? or black_player = ?",
        user_id,
        user_id
    )
    .fetch_one(conn)
    .await?
    .count
    .unwrap_or(0))
}

// Database representation of a sync_match::SynchronizedMatch
// We don't fully normalize the data, instead we just dump JSON into the db.
struct RawGame {
    id: i64,
    action_history: String,
    timer: Option<String>,
    setup: String,
    white_player: Option<i64>,
    black_player: Option<i64>,
}

impl RawGame {
    fn into_match(self) -> Result<SynchronizedMatch, ServerError> {
        let mut timer = if let Some(ref timer) = self.timer {
            let timer: Timer = serde_json::from_str(timer)?;
            Some(timer.sanitize())
        } else {
            None
        };

        if timer.as_ref().is_some_and(|t| !t.config.is_legal()) {
            timer = None;
        }

        let setup_options: SetupOptionsAllOptional = serde_json::from_str(&self.setup)?;

        Ok(SynchronizedMatch {
            key: format!("{}", self.id),
            actions: serde_json::from_str(&self.action_history)?,
            timer,
            setup_options: setup_options.into(),
            white_player: self.white_player.map(UserId),
            black_player: self.black_player.map(UserId),
        })
    }
}
