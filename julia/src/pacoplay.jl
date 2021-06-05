
const PROMOTE_OPTIONS = ["Rook", "Knight", "Bishop", "Queen"]
const COLORS = Dict(1 => "White", -1 => "Black")


function log(msg)
  buf = IOBuffer()
  ctx = IOContext(buf, :color => true)
  printstyled(ctx, "pacoplay ", color = 245)
  println(String(take!(buf)) * msg)
end

function log(match :: Int, msg)
  buf = IOBuffer()
  ctx = IOContext(buf, :color => true)
  printstyled(ctx, "pacoplay:", color = 245)
  printstyled(ctx, "$match", color = 245)
  printstyled(ctx, " ", color = 245)
  println(String(take!(buf)) * msg)
end

function logerr(msg)
  buf = IOBuffer()
  ctx = IOContext(buf, :color => true)
  printstyled(ctx, "pacoplay ", color = 245)
  printstyled(ctx, "Error: $msg\n", color = red)
  println(stderr, String(take!(buf)) * msg)
end

gamehash(game) = "#" * string(Game.hash(game))[1:5]

# transform an absolute field index on the chess board (always from white's
# perspective) to the perspective of the current players
function adapt_perspective(index, current_player :: Int)
  if current_player == 1
    index
  else
    x = index % 8
    y = div(index, 8)
    x + 8 * (7 - y)
  end
end

# Convert pacoplay action json to action index
# Examples would be {"Lift" : 5}, {"Place" : 7} or {"Promote" : "Bishop"}
function parse_action(json, current_player) :: Int
  if "Lift" in keys(json)
    1 + adapt_perspective(json["Lift"], current_player)
  elseif "Place" in keys(json)
    1 + 64 + adapt_perspective(json["Place"], current_player)
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

function parse_game(state_json)
  if !("actions" in keys(state_json))
    throw(ArgumentError("Provided JSON has no field 'actions'"))
  end
  game = PacoSako()
  for pacoplay_action in state_json["actions"]
    action = parse_action(pacoplay_action, Game.current_player(game))
    Game.apply_action!(game, action)
  end
  victory_string = nothing
  if Game.is_over(game)
    if Game.status(game) in [-1, 1]
      victory_string = "Winner: $(COLORS[Game.status(game)])"
    else
      victory_string = "Draw"
    end
  elseif "TimeoutVictory" in keys(state_json["victory_state"])
    winner = state_json["victory_state"]["TimeoutVictory"]
    victory_string = "Winner: $winner (by timeout)"
  end
  game, victory_string
end

# Convert action index to pacoplay action json string
function action_string(id :: Int, current_player :: Int) :: String
  if 0 < id <= 64
    body = "{\"Lift\":$(adapt_perspective(id - 1, current_player))}"
  elseif 64 < id <= 128
    body = "{\"Place\":$(adapt_perspective(id - 1 - 64, current_player))}"
  elseif 128 < id <=132
    body = "{\"Promote\":\"$(PROMOTE_OPTIONS[id - 128])\"}"
  else
    throw(ArgumentError("Action index $id is not supported"))
  end
end

function do_action_string(match, id, current_player :: Int) :: String
  action = action_string(id, current_player)
  "{\"DoAction\":{\"key\":\"$match\",\"action\":$action}}"
end

function subscription_string(match :: Int) :: String
  "{\"SubscribeToMatch\":{\"key\":\"$match\"}}"
end

function websocket_url(server_url :: String)
  parts = splitpath(server_url)
  if parts[1] in ["ws:", "http:"]
    "ws://" * joinpath(parts[2:end]..., "websocket")
  elseif parts[1] in ["wss:", "https:"]
    "wss://" * joinpath(parts[2:end]..., "websocket")
  else
    "wss://" * joinpath(parts..., "websocket")
  end
end

function subscribe(ws, match :: Int)
  write(ws, subscription_string(match))
  response = readavailable(ws)
  json = nothing
  try
    json = LazyJSON.parse(String(response))
  catch _
    logerr("Could not parse server response")
    return nothing
  end
  if "MatchConnectionSuccess" in keys(json)
    return json["MatchConnectionSuccess"]
  else
    logerr("Could not understand server response")
    return nothing
  end
end

function check_updates(games :: Channel)
  new_victory = nothing
  new_state = nothing
  while isready(games)
    new_state, new_victory = take!(games)
  end
  new_state, new_victory
end

function wait_updates(games :: Channel)
  wait(games)
  check_updates(games)
end

function play_match( server_url :: String
                   , match :: Int
                   , color :: Int = 1
                   ; delay :: Float64 = 0.1
                   , player = Player.MCTSPlayer(power = 1000))

  @assert color in [-1, 1] "AI must either play as White (1) or Black (-1)"

  ws_url = websocket_url(server_url)

  log("Connecting...")
  HTTP.WebSockets.open(ws_url) do ws

    log("Subscribing...")
    # Try to connect to the websocket and hope that it responds as anticipated
    json = subscribe(ws, match)
    if isnothing(json) return end

    # We connected successfully
    log("Assuming color $(COLORS[color]) in match $match on $server_url")

    game, victory = parse_game(json["state"])
    games = Channel(100)
    log(match, "Received first state $(gamehash(game))")

    # Now we let the player play if it has the right color
    @sync begin

      exiting = false

      # listen to pacoplay changes of the game state and fill the games channel
      @async while true
        try
          msg = readavailable(ws)
          json = LazyJSON.parse(String(msg))
          state = parse_game(json["CurrentMatchState"])
          put!(games, state)
          log(match, "Received state $(gamehash(state[1]))")
        catch err
          if err isa EOFError && !exiting
            logerr("Websocket has closed")
          elseif err isa LazyJSON.ParseError
            logerr("Could not parse server message")
          elseif err isa KeyError
            logerr("Could not understand server message")
          elseif err isa ArgumentError
            logerr(err.msg)
          elseif err isa InvalidStateException && !exiting
            # the games channel has been closed
          end
          exiting = true
          close(ws)
          close(games)
          break
        end
      end

      # think about next action(s) to take and submit them
      @async while true

        if !isnothing(victory)
          log(match, "Match is over. " * victory)
          exiting = true
          close(ws)
          close(games)
          break
        end

        # the following could raise acceptions when waiting on games
        # or when trying to write to ws after it was closed
        try 
          if color != Game.current_player(game)
            log(match, "Waiting for opponent...")
            game, victory = wait_updates(games)
            continue
          end

          log(match, "Thinking...")
          actions = Player.decide_chain(player, game)

          # since finding the decision might have taken some time, we
          # check if the game state has changed by human intervention
          # before submitting
          sleep(delay)
          current_game, vs = check_updates(games)

          # the game has changed. don't submit
          if !isnothing(vs) || (!isnothing(current_game) && (current_game != game))
            log(match, "Info: Game state was changed while player was thinking")
            game = current_game
            victory = vs
            continue
          end

          # the game has not changed, and we try to submit all actions
          log(match, "Submitting actions $(join(actions, ", "))")
          for action in actions
            # do action
            write(ws, do_action_string(match, action, Game.current_player(game)))
            Game.apply_action!(game, action)
            # wait for feedback from the server
            sleep(delay)
            current_game, vs = wait_updates(games)
            if current_game != game
              # manual intervention changed the game, not our submitted action
              log(match, "Info: Game state was changed while player was acting")
              break
            end
            game = current_game
            victory = vs
          end
        catch err
          if err isa InvalidStateException && !exiting
            logerr("Games channel was closed unexpectedly")
          elseif !exiting
            logerr(err)
          end
          exiting = true
          close(ws)
          close(games)
          break
        end
      end
    end
  end
  log("Exiting...")
end

