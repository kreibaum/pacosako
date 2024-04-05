-- To classify a game as "lightspeed" / "blitz" / "rapid" / "classic", we first
-- need to combine the initial time control and the increment. This is done by
-- a formula suggested by Bas, that he was also using for the earlier ELO
-- tracking table. The formula is:
--  2 * initial_time + increment * 40
-- That is assuming fair initial time. We don't have to do that and can just
-- add the time budgets of both players.


-- Unfortunately, this means we need to drop the whole table and recreate it.
-- This is because SQLite does not support adding a STORED generated column.

-- See https://sqlite.org/lang_altertable.html#otheralter for more information.

-- It also allows us to get rid of "safe_mode" which is redundant with the setup
-- column. See 20221221223545_game-setup-column.sql for the migration.

-- And 20231119110923_game_ownership.sql wanted to add additional foreign keys.
-- We add them as well.


-- Defer foreign key checks for this transaction
-- Does this look hacky? Yes. See:
-- https://github.com/launchbadge/sqlx/issues/2085

-- remove the original TRANSACTION
COMMIT TRANSACTION;
-- tweak config
PRAGMA foreign_keys=OFF;
-- start your own TRANSACTION
BEGIN TRANSACTION;


-- Drop the existing indices on the game table
DROP INDEX IF EXISTS idx_game_white_player;
DROP INDEX IF EXISTS idx_game_black_player;

-- Create a new table with the additional generated column and foreign keys
CREATE TABLE new_game (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
    action_history TEXT NOT NULL,
    timer TEXT,
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- safe_mode BOOLEAN DEFAULT 0 NOT NULL,
    setup TEXT NOT NULL DEFAULT '{}',
    white_player INTEGER,
    black_player INTEGER,
    expected_time_limit REAL GENERATED ALWAYS AS (
        json_extract(timer, '$.config.time_budget_white') + 
        json_extract(timer, '$.config.time_budget_black') + 
        40 * coalesce(json_extract(timer, '$.config.increment'), 0)
    ) STORED,
    FOREIGN KEY (white_player) REFERENCES user(id),
    FOREIGN KEY (black_player) REFERENCES user(id)
);

-- Copy data from the old table to the new table
INSERT INTO new_game (id, action_history, timer, created, setup, white_player, black_player)
SELECT id, action_history, timer, created, setup, white_player, black_player
FROM game;

-- Drop the old table
DROP TABLE game;

-- Rename the new table to the original name
ALTER TABLE new_game RENAME TO game;

-- Recreate indices on the new game table
CREATE INDEX idx_game_white_player ON game (white_player);
CREATE INDEX idx_game_black_player ON game (black_player);


-- check foreign key constraint still upholding.
PRAGMA foreign_key_check;


-- commit your own TRANSACTION
COMMIT TRANSACTION;
-- rollback all config you setup before.
PRAGMA foreign_keys=ON;
-- start a new TRANSACTION to let migrator commit it.
BEGIN TRANSACTION;