-- OAuth & User database structure.
-- User table.
create table user (
    id integer not null primary key autoincrement unique,
    username text not null,
    avatar blob,
    -- For now we only support discord auth.
    discord_id text not null unique
);

-- Keeps the connection between a user and a discord account
create table oauth_token (
    user_id integer not null,
    access_token text not null,
    refresh_token text not null,
    expires_at integer not null,
    foreign key (user_id) references user(id)
);

-- Tracks user sessions.
create table user_session (
    user_id integer not null,
    session_id text not null,
    expires_at integer not null,
    foreign key (user_id) references user(id)
);