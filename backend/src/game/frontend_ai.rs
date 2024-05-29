use crate::db::Connection;
use crate::login::UserId;

pub async fn find_user_for_model_name(model_name: &str, conn: &mut Connection) -> Result<Option<UserId>, sqlx::Error> {
    let res = sqlx::query!(
        "SELECT user_id from user_modelName where model_name = $1",
        model_name
    )
        .fetch_optional(&mut *conn)
        .await?;

    Ok(res.map(|x| UserId(x.user_id)))
}