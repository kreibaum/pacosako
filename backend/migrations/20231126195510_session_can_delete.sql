-- Indices which I forgot in the last script:
CREATE INDEX idx_game_white_player ON game (white_player);

-- And for black as well:
CREATE INDEX idx_game_black_player ON game (black_player);

-- New field session.can_delete
ALTER TABLE
    session
ADD
    COLUMN can_delete BOOLEAN NOT NULL DEFAULT FALSE;