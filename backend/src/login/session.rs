use super::{crypto, SessionId, UserId, SESSION_COOKIE};
use crate::{db::Connection, AppState};
use axum::{
    async_trait,
    extract::FromRequestParts,
    http::{request::Parts, StatusCode},
    Extension, RequestPartsExt,
};
use tower_cookies::Cookies;

/// An authenticated session. When you access this from an extractor, it has been
/// verified that the session is valid by checking against the database.
pub struct SessionData {
    pub user_id: UserId,
    pub session_id: SessionId,
}

#[async_trait]
impl FromRequestParts<AppState> for SessionData {
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        match get_session_from_request_parts(parts, state).await {
            Ok(session) => Ok(session),
            Err(_) => Err((StatusCode::UNAUTHORIZED, "User is not logged in.")),
        }
    }
}

pub async fn create_session(
    user_id: UserId,
    connection: &mut Connection,
) -> Result<SessionId, anyhow::Error> {
    let uuid = uuid::Uuid::new_v4().to_string();
    sqlx::query!(
        r"insert into session (id, user_id, expires_at) values (?, ?, datetime(CURRENT_TIMESTAMP, '+14 days'))",
        uuid,
        user_id.0
    )
    .execute(connection)
    .await?;

    Ok(SessionId(uuid))
}

pub async fn load_session(
    session_id: SessionId,
    connection: &mut Connection,
) -> Result<SessionData, anyhow::Error> {
    let res = sqlx::query!(r"select user_id from session where id = ?", session_id.0)
        .fetch_one(connection)
        .await;
    let res = res.map_err(|e| anyhow::anyhow!("Session not found: {:?}", e))?;
    res.user_id
        .map(|user_id| SessionData {
            user_id: UserId(user_id),
            session_id,
        })
        .ok_or_else(|| anyhow::anyhow!("Session not found"))
}

async fn get_session_from_request_parts(
    parts: &mut Parts,
    state: &AppState,
) -> Result<SessionData, anyhow::Error> {
    let Extension(cookies) = parts
        .extract::<Extension<Cookies>>()
        .await
        .expect("Missing the 'Cookies' extractor");

    let Some(session_cookie) = cookies.get(SESSION_COOKIE) else {
        anyhow::bail!("User is not logged in.")
    };

    let session_id = crypto::decrypt_session_key(session_cookie.value(), &state.config.secret_key)?;

    let mut connection = state.pool.conn().await?;
    load_session(session_id, &mut connection).await
}
