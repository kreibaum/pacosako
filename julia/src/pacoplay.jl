
module Url

  using ...JtacPacoSako

  function server(; domain = :dev)
    if domain in [:official, nothing]
      "https://pacoplay.com"
    else
      "https://$domain.pacoplay.com"
    end
  end

  editor(; domain = :dev) = server(; domain) * "/editor"

  editor(fen_string :: String; domain = :dev) =
    editor(; domain) * "?fen=" * replace(fen_string, " " => "%20")

  editor(ps :: PacoSako; domain = :dev) = editor(fen(ps); domain)

  game(; domain = :dev) = server(; domain) * "/game"
  game(match :: Int; domain = :dev) = game(; domain) * "/$match"

  function websocket(; domain = :dev)
    base = server(; domain)[9:end]
    "wss://" * base * "/websocket"
  end

end # module Url

module Api

  using HTTP

  using ...JtacPacoSako
  import ..PacoPlay

  function create_game(; domain = :dev) :: Int
    url = PacoPlay.Url.server(; domain)
    body = "{\"timer\":null,\"safe_mode\":true}"
    resp = HTTP.post(url * "/api/create_game", Dict("Content-Type" => "application/json"); body)

    @assert resp.status == 200 "Creating game failed: $(resp.status)"
    parse(Int, String(resp.body))
  end

end # module Api

module Json

  using ...JtacPacoSako
  import LazyJSON

  const PROMOTE_OPTIONS = ["Rook", "Knight", "Bishop", "Queen"]

  # Transform an absolute field index on the chess board (always from white's
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
  """
      parse_action(json, current_player)

  Parse the action in `json` from the perspective of `current_player`.
  """
  function parse_action(json :: LazyJSON.Value, current_player :: Int) :: Int
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

  function parse_action(json_str :: String, current_player :: Int)
    try 
      json = LazyJSON.parse(json_str)
    catch err
      throw(ArgumentError("Invalid json string: $err"))
    end
    parse_action(json, current_player)
  end

  """
      action(action_id, current_player)

  Returns a json string that corresponds to the action `action_id` from the
  perspective of `current_player`.
  """
  function action(id :: Int, current_player :: Int) :: String
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


  """
      parse_game(json) -> (game, timeout)

  Parses the provided json and returns a `game` instance of type `PacoSako`.
  Additionally, it returns a `timeout` value that either has the value `0` (no
  timeout), `-1` (black won by timeout), or `1` (white won by timeout).
  """
  function parse_game(state_json :: LazyJSON.Value)
    if !("actions" in keys(state_json))
      throw(ArgumentError("Provided JSON has no field 'actions'"))
    end
    game = PacoSako()
    for pacoplay_action in state_json["actions"]
      action = parse_action(pacoplay_action, Game.current_player(game))
      Game.apply_action!(game, action)
    end

    if "TimeoutVictory" in keys(state_json["victory_state"])
      winner = state_json["victory_state"]["TimeoutVictory"]
      timeout = winner == "White" ? 1 : -1
    else
      timeout = 0
    end

    game, timeout
  end

  function parse_game(json_str :: String)
    try 
      json = LazyJSON.parse(json_str)
    catch err
      throw(ArgumentError("Invalid json string: $err"))
    end
    parse_game(json)
  end

end


# ---------------- PacoPlay play function ------------------------------------ #


function action_string(match, id, current_player :: Int) :: String
  action = Json.action(id, current_player)
  "{\"DoAction\":{\"key\":\"$match\",\"action\":$action}}"
end

function subscription_string(match :: Int) :: String
  "{\"type\":\"subscribeToMatchSocket\",\"data\":\"{\\\"key\\\":\\\"$match\\\"}\"}"
end

function subscribe(ws, match :: Int)
  HTTP.send(ws, subscription_string(match))
  response = HTTP.receive(ws)
  json = nothing
  try
    json = LazyJSON.parse(String(response))
  catch _
    logerr("Could not parse server response")
    return nothing
  end
  if "CurrentMatchState" in keys(json)
    return json["CurrentMatchState"]
  else
    logerr("Could not understand server response: " * String(response))
    return nothing
  end
end

function check_updates(games :: Channel)
  timeout = nothing
  state = nothing
  while isready(games)
    state, timeout = take!(games)
  end
  state, timeout
end

function wait_updates(games :: Channel)
  wait(games)
  check_updates(games)
end

const COLORS = Dict(1 => "white", -1 => "black")

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
  printstyled(ctx, "Error: $msg\n", color = :red)
  println(stderr, String(take!(buf)) * msg)
end

"""
    play(player, match = -1; color = :white, domain = :dev, delay = 0.25)

Let `player` play a `match` on the pacoplay website, assuming `color`. If `match < 0`, a new game
is created and the corresponding link is printed to stdout.

Setting `domain = :official` will use the production server.
"""
function play( player :: Player.AbstractPlayer
             , match :: Int = -1
             ; color = :white
             , domain = :dev
             , delay :: Float64 = 0.25 )

  if color in [:white, :White, :w, :W, "white", "White", "w", "W", 1]
    color = 1
  elseif color in [:black, :Black, :b, :B, "black", "Black", "b", "B", -1]
    color = -1
  else
    error("color $color not understood")
  end

  server_url = Url.server(; domain)
  ws_url = Url.websocket(; domain)

  if match <= 0
    log("Requesting new game from $server_url...")
    match = Api.create_game(;domain)
    url = Url.game(match; domain)
    log("Created game: $url")
  end

  log("Connecting...")
  HTTP.WebSockets.open(ws_url) do ws

    log("Subscribing...")
    # Try to connect to the websocket and hope that it responds as anticipated
    json = subscribe(ws, match)
    if isnothing(json) return end

    # We connected successfully
    url = Url.game(match; domain)
    log("Assuming color $(COLORS[color]) in $url")

    game, timeout = Json.parse_game(json)
    games = Channel(100)
    log(match, "Received first state $(fen(game))")

    # Now we let the player play if it has the right color
    @sync begin

      exiting = false

      # listen to pacoplay changes of the game state and fill the games channel
      @async while true
        try
          msg = HTTP.receive(ws)
          json = LazyJSON.parse(String(msg))
          state = Json.parse_game(json["CurrentMatchState"])
          put!(games, state)
          log(match, "Received state $(fen(state[1]))")
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

        if timeout != 0 || Game.is_over(game)
          if timeout != 0
            str = "Winner: $(COLORS[timeout]) (by timeout)"
          elseif Game.status(game) == 0
            str = "Draw"
          else
            str = "Winner: $(COLORS[Game.status(game)])"
          end
          log(match, "Match is over. " * str)
          exiting = true
          close(ws)
          close(games)
          break
        end

        # the following could raise exceptions when waiting on games
        # or when trying to write to ws after it was closed
        try 
          if color != Game.current_player(game)
            log(match, "Waiting for opponent...")
            game, timeout = wait_updates(games)
            continue
          end

          log(match, "Thinking...")
          actions = Player.decide_chain(player, game)

          # since finding the decision might have taken some time, we
          # check if the game state has changed by human intervention
          # before submitting
          sleep(delay)
          new_game, tout = check_updates(games)

          # the game has changed. don't submit
          if (!isnothing(tout) && tout != 0) || (!isnothing(new_game) && (new_game != game))
            log(match, "Info: Game state was changed while player was thinking")
            game = new_game
            timeout = tout
            continue
          end

          # the game has not changed, and we try to submit all actions
          log(match, "Submitting actions $(join(actions, ", "))")
          for action in actions
            # do action
            HTTP.send(ws, action_string(match, action, Game.current_player(game)))
            Game.apply_action!(game, action)
            # wait for feedback from the server
            sleep(delay)
            new_game, tout = wait_updates(games)
            if new_game != game
              # manual intervention changed the game, not our submitted action
              log(match, "Info: Game state was changed while player was acting")
              break
            end
            game = new_game
            timeout = tout
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

