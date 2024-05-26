-- Adds  a flag to the aiConfig table to indicate if the ai is a frontend ai
-- The frontend will then run the model in the browser, if the connected user
-- has control over the ai side. (The have control if they control the other side).
alter table game_aiConfig add column is_frontend_ai INTEGER DEFAULT 0;

