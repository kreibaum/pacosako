-- Extension table on user that allows each user to have one or more unique model names.
-- This is for AIs running in the browser. When they are requested by the frontend, the backend
-- must assign a user to the game it creates.

CREATE TABLE user_modelName (
  user_id INTEGER NOT NULL,
  model_name TEXT NOT NULL,
  PRIMARY KEY (user_id, model_name),
  FOREIGN KEY (user_id) REFERENCES user (id),
  UNIQUE (model_name)
);

-- INSERT INTO user_modelName (user_id, model_name) VALUES ('9', 'ludwig');
-- INSERT INTO user_modelName (user_id, model_name) VALUES ('15', 'hedwig');
-- -- Find all AIs
-- select * from user inner join user_modelname on user_id = user.id;
