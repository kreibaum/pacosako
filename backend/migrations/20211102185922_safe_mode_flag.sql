-- Add migration script here
alter table
    game
add
    safe_mode BOOLEAN default 0 not null;