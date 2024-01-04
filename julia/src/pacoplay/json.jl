
const PROMOTE_OPTIONS = ["Rook", "Knight", "Bishop", "Queen"]

"""
    adaptperspective(index, active_player)

Transform an absolute field index `index` on the chess board (always from
white's perspective) to the perspective of the current player `active_player`.
"""
function adaptperspective(index, active_player :: Int)
  if active_player == 1
    index
  else
    x = index % 8
    y = div(index, 8)
    x + 8 * (7 - y)
  end
end

# Convert pacoplay action json to action index
# Examples would be {"Lift" : 5}, {"Place" : 7} or {"Promote" : "Bishop"}
"""
    parseaction(json, active_player)

Parse the action in `json` from the perspective of `active_player`.
"""
function parseaction(json :: LazyJSON.Value, active_player :: Int) :: Int
  if "Lift" in keys(json)
    1 + adaptperspective(json["Lift"], active_player)
  elseif "Place" in keys(json)
    1 + 64 + adaptperspective(json["Place"], active_player)
  elseif "Promote" in keys(json)
    piece_type = json["Promote"]
    offset = findfirst(isequal(piece_type), PROMOTE_OPTIONS)
    if !isnothing(offset)
      2 * 64 + offset
    else
      msg = "Piece type '$piece_type' in JSON is not understood (promotion)."
      throw(ArgumentError(msg))
    end
  else
    throw(ArgumentError("Action in JSON is not understood."))
  end
end

function parseaction(json_str :: String, active_player :: Int)
  try 
    json = LazyJSON.parse(json_str)
  catch err
    throw(ArgumentError("Invalid json string: $err"))
  end
  parseaction(json, active_player)
end

"""
    action(action_id, active_player)

Returns a json string that corresponds to the action `action_id` from the
perspective of `active_player`.
"""
function action(id :: Int, active_player :: Int) :: String
  if 0 < id <= 64
    body = "{\"Lift\":$(adaptperspective(id - 1, active_player))}"
  elseif 64 < id <= 128
    body = "{\"Place\":$(adaptperspective(id - 1 - 64, active_player))}"
  elseif 128 < id <=132
    body = "{\"Promote\":\"$(PROMOTE_OPTIONS[id - 128])\"}"
  else
    throw(ArgumentError("Action index $id is not supported"))
  end
end


"""
    parsegame(json) -> (game, timeout)

Parses the provided json and returns a `game` instance of type `PacoSako`.
Additionally, it returns a `timeout` value that either has the value `0` (no
timeout), `-1` (black won by timeout), or `1` (white won by timeout).
"""
function parsegame(state_json :: LazyJSON.Value)
  if !("actions" in keys(state_json))
    throw(ArgumentError("Provided JSON has no field 'actions'"))
  end
  game = PacoSako()
  for pacoplay_action in state_json["actions"]
    action = parseaction(pacoplay_action, Game.activeplayer(game))
    Game.move!(game, action)
  end

  if "TimeoutVictory" in keys(state_json["victory_state"])
    winner = state_json["victory_state"]["TimeoutVictory"]
    timeout = winner == "White" ? 1 : -1
  else
    timeout = 0
  end

  game, timeout
end

function parsegame(json_str :: String)
  try 
    json = LazyJSON.parse(json_str)
  catch err
    throw(ArgumentError("Invalid json string: $err"))
  end
  parsegame(json)
end

