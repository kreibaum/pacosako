-- Creates a game table to store games.
-- This now also means that the game id is no longer a string but an integer.
-- However, this is only an implementation detail on the server and won't be
-- provided to the client.
CREATE TABLE `game` (
    `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
    `action_history` TEXT NOT NULL,
    `timer` TEXT,
    `created` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)