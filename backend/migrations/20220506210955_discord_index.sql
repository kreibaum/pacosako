-- Add indices for the colums we search by.
create index index_user_discord_id on user (discord_id);

create index index_session_id on user_session (session_id);