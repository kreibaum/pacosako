-- Extension table on game table to store replay meta data.
create table game_replay_metadata (
    game_id integer not null,
    action_index integer not null,
    category text not null,
    metadata text not null,
    FOREIGN KEY (game_id) REFERENCES game(id)
);