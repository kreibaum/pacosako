-- Extension table on game table to store AI config.

create table game_aiConfig (
  game_id integer not null,
  player_color TEXT CHECK(player_color in ('w', 'b')),
  model_name text not null,
  model_strength integer not null,
  model_temperature REAL not null,
  FOREIGN KEY (game_id) REFERENCES game(id),
  UNIQUE(game_id, player_color)
);