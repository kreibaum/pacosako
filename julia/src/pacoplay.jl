
module PacoPlay

using ..JtacPacoSako

using HTTP, LazyJSON

const PROMOTE_OPTIONS = ["Rook", "Knight", "Bishop", "Queen"]
const COLORS = Dict(1 => "WHITE", -1 => "BLACK")


function parse_action(json)::Int64
  if "Lift" in keys(json)
    1 + json["Lift"]
  elseif "Place" in keys(json)
    1 + json["Place"] + 64
  elseif "Promote" in keys(json)
    piece_type = json["Promote"]
    offset = findfirst(isequal(piece_type), PROMOTE_OPTIONS)
    if !isnothing(offset)
      2 * 64 + offset
    else
      ArgumentError("Piece type '$piece_type' is in JSON and not understood (promotion).") |> throw
    end
  else
    ArgumentError("There is an action in the JSON that is not understood.") |> throw
  end
end

function parse_actions(json) :: Vector{Int}
  if !("actions" in keys(json))
      ArgumentError("Provided JSON has no field 'actions'") |> throw
  end
  game = PacoSako()
  parse_action.(json["actions"])
end

function GET_actions(url) :: Vector{Int}
  r = HTTP.request("GET", url)
  json = LazyJSON.parse(String(r.body))
  parse_actions(json)
end

function GET_game_state(url) :: PacoSako
  game = PacoSako()
  Game.apply_actions!(game, GET_actions(url))
  game
end

function action_string(id) :: String
  if 0 < id <= 64
    body = "{\"Lift\":$(id - 1)}"
  elseif 64 < id <= 128
    body = "{\"Place\":$(id - 1 - 64)}"
  elseif 128 < id <=132
    body = "{\"Promote\":\"$(PROMOTE_OPTIONS[id - 128])\"}"
  else
    ArgumentError("Action index $id is not supported") |> throw
  end
end

function POST_action(url, id)
  body = action_string(id)
  HTTP.request("POST", url, ["Content-Type" => "application/json"], body)
end


function play_match(server_url :: String, match :: Int, color :: Int;
                    player = Player.MCTSPlayer(power = 1000), poll_interval :: Float64 = 1.0)

  @assert color in [-1, 1] "AI must either play WHITE (1) or BLACK (-1), given was $color"

  GET_url = joinpath(server_url, "api", "game", string(match))
  POST_url = joinpath(server_url, "api", "ai", "game", string(match))

  # number of actions leading to current game state
  l = -1

  get_state = () -> begin
    moves = GET_actions(GET_url)
    # check if we received the same game state before. If yes, we do not act
    if length(moves) <= l
      return nothing
    else
      l = length(moves)
    end
    # Print some information and construct the game
    if l == 0
      print("$l. WHITE moves first. ")
      game = PacoSako()
    else
      prev_game = Game.apply_actions!(PacoSako(), moves[1:end-1])
      prev_col = Game.current_player(prev_game)
      game = Game.apply_action!(prev_game, moves[end])
      if !Game.is_over(game)
        col = Game.current_player(game)
        if col != prev_col
          print("$l. $(COLORS[col]) to respond to $(action_string(moves[end])). ")
        else
          print("$l. $(COLORS[col]) to continue $(action_string(moves[end])). ")
        end
      end
    end
    game
  end

  println("Assuming color $(COLORS[color]) in match $match at $server_url")
  game = get_state()
  while !Game.is_over(game)
    if Game.current_player(game) == color
      print("Thinking... ")
      action_id = Player.decide(player, game)
      println("Decided on $(action_string(action_id))")
      POST_action(POST_url, action_id)
    else
      println("Waiting...")
    end
    sleep(poll_interval)
    g = get_state()
    while isnothing(g)
      sleep(poll_interval)
      g = get_state()
    end
    game = g
  end
  if Game.status(game) in [-1, 1]
    println("Match $match is over. Winner: $(COLORS[Game.status(game)])")
  else
    println("Match $match is over. Draw")
  end
end

export play_match,
       GET_actions,
       GET_game_state,
       POST_action

end # module PacoPlay
