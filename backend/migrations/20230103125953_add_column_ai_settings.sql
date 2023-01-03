-- This script adds a column to the game table to store the AI settings.
-- This is stored as a JSON string.
ALTER TABLE
    game
ADD
    COLUMN ai_settings TEXT;