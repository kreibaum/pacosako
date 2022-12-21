-- Add a new column 'setup' to the 'game' table
ALTER TABLE game ADD COLUMN setup TEXT not null default '{}';

-- Update the 'setup' column for all rows in the 'game' table
-- If 'safe_mode' is true, set 'setup' to '{"safe_mode":true}'
-- If 'safe_mode' is false, set 'setup' to '{"safe_mode":false}'
UPDATE game
SET setup = (CASE
    WHEN safe_mode = 1 THEN '{"safe_mode":true}'
    ELSE '{"safe_mode":false}'
END)

-- Drop the 'safe_mode' column
--ALTER TABLE game DROP COLUMN safe_mode;

