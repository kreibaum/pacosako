
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

  server_url = Url.server(; domain)
  ws_url = Url.websocket(uuid ; domain)

  if match <= 0
    log("Requesting new game from $server_url...")
    match = Api.requestmatch(;domain)
    url = Url.game(match; domain)
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
    url = Url.game(match; domain)
    log("Assuming color $(COLORS[color]) in $url")

    game, timeout = Json.parsegame(json)
    games = Channel(100)
    log(match, "Received first state $(JtacPacoSako.fen(game))")

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
          log(match, "Received state $(JtacPacoSako.fen(state[1]))")
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
            logerr("Game channel was closed unexpectedly")
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


