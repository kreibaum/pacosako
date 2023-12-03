-- Add two new columns 'white_player' and 'black_player' to the 'game' table
-- Unfortunately SQLite does not support adding foreign keys to existing tables
-- https://www.sqlite.org/faq.html#q11
-- We'll just go without foreign keys on the new columns.
ALTER TABLE
    game
ADD
    COLUMN white_player INTEGER NULL;

ALTER TABLE
    game
ADD
    COLUMN black_player INTEGER NULL;