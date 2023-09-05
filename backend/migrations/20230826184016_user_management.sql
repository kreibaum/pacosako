DROP TABLE user_session;
DROP TABLE oauth_token;
DROP TABLE user;

PRAGMA foreign_keys = ON;

-- User detail table
CREATE TABLE user (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- Name may be null in case of anonymous users
    name TEXT NULL,
    -- Profile picture is an identifier for the user's profile picture
    -- This can be 'discord:8342729096ea3675442027381ff50dfe' with a discord avatar hash
    -- or 'identicon:204bedcd9a44b3e1db26e7619bca694d' with a generated identicon
    avatar TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Login table
CREATE TABLE login (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    -- type should be 'discord' or 'password'
    type TEXT NOT NULL CHECK (type IN ('discord', 'password')),
    -- identifier is the discord user id or login name (different from user name)
    identifier TEXT NOT NULL UNIQUE,
    hashed_password TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES user(id)
);

-- Properly working 'session' and 'oauth_token' tables require the secret_key
-- property to be set in the config file.
-- Session table
CREATE TABLE session (
    -- Randomly generated UUID, stored in the client encrypted with the secret key
    -- On the database side, this is stored in plaintext
    id TEXT PRIMARY KEY,
    user_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES user(id)
);

-- Oauth token table
CREATE TABLE oauth_token (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    login_id INTEGER NOT NULL,
    -- The access_token is encrypted in the database with the secret key
    -- from the config file. Accidentally leaking the database will not leak
    -- the access token this way.
    access_token TEXT NOT NULL,
    -- The refresh_token is encrypted in the same way.
    refresh_token TEXT,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (login_id) REFERENCES login(id)
);

CREATE INDEX idx_login_identifier ON login(identifier);
CREATE INDEX idx_session_user_id ON session(user_id);