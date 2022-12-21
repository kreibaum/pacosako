use pacosako::setup_options::SetupOptionsAllOptional;

use crate::db::Connection;
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

    let id = sqlx::query!(
        "insert into game (action_history, timer, safe_mode, setup) values (?, ?, 1, ?)",
        action_history,
        timer,
        setup,
    )
    .execute(conn)
    .await?
    .last_insert_rowid();

    game.key = format!("{}", id);

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

    sqlx::query!(
        r"update game 
        set action_history = ?, timer = ?
        where id = ?",
        action_history,
        timer,
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
        "select id, action_history, timer, setup from game where id = ?",
        id
    )
    .fetch_optional(conn)
    .await?;

    if let Some(raw_game) = raw_game {
        Ok(Some(raw_game.to_match()?))
    } else {
        Ok(None)
    }
}

pub async fn latest(conn: &mut Connection) -> Result<Vec<SynchronizedMatch>, ServerError> {
    let raw_games = sqlx::query_as!(
        RawGame,
        r"select id, action_history, timer, setup from game
        order by id desc
        limit 5"
    )
    .fetch_all(conn)
    .await?;

    let mut result = Vec::with_capacity(raw_games.len());
    for raw_game in raw_games {
        result.push(raw_game.to_match()?);
    }

    Ok(result)
}

// Database representation of a sync_match::SynchronizedMatch
// We don't fully normalize the data, instead we just dump JSON into the db.
struct RawGame {
    id: i64,
    action_history: String,
    timer: Option<String>,
    setup: String,
}

impl RawGame {
    fn to_match(self) -> Result<SynchronizedMatch, ServerError> {
        let timer = if let Some(ref timer) = self.timer {
            let timer: Timer = serde_json::from_str(timer)?;
            Some(timer.sanitize())
        } else {
            None
        };

        let setup_options: SetupOptionsAllOptional = serde_json::from_str(&self.setup)?;

        Ok(SynchronizedMatch {
            key: format!("{}", self.id),
            actions: serde_json::from_str(&self.action_history)?,
            timer,
            setup_options: setup_options.into(),
        })
    }
}
