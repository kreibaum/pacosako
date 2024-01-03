
module Urls

  import ...JtacPacoSako: PacoSako, fen

  function server(; domain = :dev)
    if domain in [:official, nothing]
      "https://pacoplay.com"
    elseif domain in [:localhost]
      "http://localhost:8000"
    else
      "https://$domain.pacoplay.com"
    end
  end

  function websocket(uuid :: String; domain = :dev)
    if domain in [:official, nothing]
      "wss://pacoplay.com/websocket?uuid=$uuid"
    elseif domain in [:localhost]
      "ws://localhost:8000/websocket?uuid=$uuid"
    else
      "wss://$domain.pacoplay.com/websocket?uuid=$uuid"
    end
  end

  editor(; domain = :dev) = server(; domain) * "/editor"

  editor(fen_string :: String; domain = :dev) =
    editor(; domain) * "?fen=" * replace(fen_string, " " => "%20")

  editor(ps :: PacoSako; domain = :dev) = editor(fen(ps); domain)

  game(; domain = :dev) = server(; domain) * "/game"
  game(match :: Int; domain = :dev) = game(; domain) * "/$match"

  replay(; domain = :dev) = server(; domain) * "/replay"
  replay(match :: Int; domain = :dev) = replay(; domain) * "/$match"

end # module Urls


module Json

  using ...JtacPacoSako
  import LazyJSON

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

end # module Json


module Api

  using HTTP
  using URIs

  using ...JtacPacoSako
  import ..PacoPlay
  import ..Json

  """
      requestmatch(; domain = :dev)

  Request a new match from the pacoplay subdomain `domain`.
  """
  function requestmatch(; domain = :dev) :: Int
    url = PacoPlay.Urls.server(; domain)
    body = "{\"timer\":null,\"safe_mode\":true}"
    resp = HTTP.post(url * "/api/create_game", Dict("Content-Type" => "application/json"); body)

    @assert resp.status == 200 "Creating game failed: $(resp.status)"
    parse(Int, String(resp.body))
  end

  """
      signin(username, password; domain = :dev)

  Sign in into the pacoplay subdomain `domain` with credentials `username` and
  `password`. Returns the session cookie.
  """
  function signin(username, password; domain = :dev)
    url = PacoPlay.Urls.server(; domain) * "/api/username_password"
    data = """{"username":"$username","password":"$password"}"""
    headers = ["Content-Type" => "application/json"]

    # With cookies = true, the cookies are stored in HTTP.COOKIEJAR
    response = HTTP.post(url, headers, data; cookies = true)

    # Check if the response status is successful
    if response.status != 200
        println("Error: Received status code $(response.status)")
        throw(ArgumentError("Could not sign in with the provided credentials"))
    end

    # Extract cookie from cookie jar
    uri = parse(URIs.URI, url)
    session_cookie = HTTP.Cookies.getcookies!(HTTP.COOKIEJAR, uri)[1].value
    session_cookie
  end

  function postaction( match
                     , game
                     , action
                     ; domain = :dev
                     , session = nothing
                     , uuid = "lpdyrmi3m3e1txe09dh" )

    url = PacoPlay.Urls.server(; domain) * "/api/ai/game/$(match)?uuid=$uuid"
    action = Json.action(action, Game.activeplayer(game)) 
    headers = Dict(
      "Content-Type" => "application/json",
      "Cookie" => "session=$session",
    )
    HTTP.post(url, headers, action)
  end

end # module Api


# ---------------- PacoPlay play function ------------------------------------ #

import ..JtacPacoSako: PacoSako, fen

function action_string(match, id, active_player :: Int) :: String
  action = Json.action(id, active_player)
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


"""
    check_updates(games :: Channel) :: (game, timeout)

Checks if we have received a new game state from the pacoplay server.
In addition to the game state, it also returns a timeout value that tells us
if either player has lost by timeout. The timeout value is either `0` (no
timeout), `-1` (black won by timeout), or `1` (white won by timeout).
"""
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

function uploadmatch(games :: Vector{PacoSako}; kwargs...)
  @assert isequal(games[1], PacoSako()) """
  Can only upload game sequences that start with a default initial state.
  """
  actions = Game.reconstructactions(games)
  uploadmatch(actions; kwargs...)
end

function uploadmatch( actions :: Vector{Game.ActionIndex}
                    ; domain = :dev
                    , uuid :: String = "lpdyrmi3m3e1txe09dh"
                    , username = nothing
                    , password = nothing )

  log("Uploading match with $(length(actions)) actions")
  game = PacoSako()
  match = Api.requestmatch(; domain)

  if !isnothing(username) && !isnothing(password)
    session = Api.signin(username, password; domain)
    log("Signed in with session cookie: $session")
  end

  for action in actions
    Api.postaction(match, game, action; domain, uuid, session)
    Game.move!(game, action)
  end

  url = Urls.replay(match; domain)
  log("Upload successful: $url")
end

"""
    play(player, [matchid]; kwargs...)

Let `player` play a paco sako match  on the pacoplay website under the id
`matchid`. By default, a new match is requested.

# Arguments
* `color = :white`: The color assumed by `player`.
* `domain = :dev`: The pacoplay domain the player is connected to. Setting \
  `domain = :official` will use the production server.
* `delay = 0.25`: Artificial delay in seconds between moves of `player`.
* `uuid`: The uuid sent to the pacoplay server when connecting.
* `username`: The username that `player` uses for login. If not `nothing`, \
  `password` also has to be specified.
* `password`: The password that `player` uses for login. If not `nothing`, \
  `username` also has to be specified.
"""
function play( player :: Player.AbstractPlayer
             , match :: Int = -1
             ; color = :white
             , domain = :dev
             , delay :: Float64 = 0.25
             , uuid :: String = "lpdyrmi3m3e1txe09dh"
             , username = nothing
             , password = nothing )

  if color in [:white, :White, :w, :W, "white", "White", "w", "W", 1]
    color = 1
  elseif color in [:black, :Black, :b, :B, "black", "Black", "b", "B", -1]
    color = -1
  else
    error("color $color not understood")
  end

  server_url = Urls.server(; domain)
  ws_url = Urls.websocket(uuid ; domain)

  if match <= 0
    log("Requesting new game from $server_url...")
    match = Api.requestmatch(;domain)
    url = Urls.game(match; domain)
    log("Created game: $url")
  end

  session_cookie = nothing
  if !isnothing(username) && !isnothing(password)
    session_cookie = Api.signin(username, password; domain)
    log("Signed in with session cookie: $session_cookie")
  end

  log("Connecting...")
  # HTTP.WebSockets.open does not properly use the CookieJar, so we manually
  # set the cookie header.
  headers = ["Cookie" => "session=$session_cookie"]
  HTTP.WebSockets.open(ws_url; headers) do ws

    log("Subscribing...")
    # Try to connect to the websocket and hope that it responds as anticipated
    json = subscribe(ws, match)
    if isnothing(json) return end

    # We connected successfully
    url = Urls.game(match; domain)
    log("Assuming color $(COLORS[color]) in $url")

    game, timeout = Json.parsegame(json)
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
          state = Json.parsegame(json["CurrentMatchState"])
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

        if timeout != 0 || Game.isover(game)
          if timeout != 0
            str = "Winner: $(COLORS[timeout]) (by timeout)"
          elseif Game.status(game) == Game.draw
            str = "Draw"
          else
            str = "Winner: $(COLORS[Int(Game.status(game))])"
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
          if color != Game.activeplayer(game)
            log(match, "Waiting for opponent...")
            game, timeout = wait_updates(games)
            continue
          end

          log(match, "Thinking...")
          chain = Player.decidechain(player, game)

          # since finding the decision might have taken some time, we
          # check if the game state has changed by human intervention
          # before submitting
          sleep(delay)
          new_game, tout = check_updates(games)

          # the game has changed. don't submit
          if (!isnothing(tout) && tout != 0) || (!isnothing(new_game) && (new_game != game))
            log(match, "Info: Game state has changed while player was thinking")
            game = new_game
            timeout = tout
            continue
          end

          # the game has not changed, and we try to submit all actions
          log(match, "Submitting actions $(join(chain, ", "))")
          for action in chain
            # do action
            HTTP.send(ws, action_string(match, action, Game.activeplayer(game)))
            Game.move!(game, action)
            # wait for feedback from the server
            sleep(delay)
            new_game, tout = wait_updates(games)
            if new_game != game
              # manual intervention changed the game, not our submitted action
              log(match, "Info: Game state has changed while player was acting")
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


