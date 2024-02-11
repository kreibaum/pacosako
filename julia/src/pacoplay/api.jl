"""
    requestmatch(; domain = :dev)

Request a new match from the pacoplay subdomain `domain`.
"""
function requestmatch(; domain=:dev)::Int
  url = PacoPlay.Url.server(; domain)
  body = "{\"timer\":null,\"safe_mode\":true}"
  resp = HTTP.post(url * "/api/create_game", Dict("Content-Type" => "application/json"); body)

  @assert resp.status == 200 "Creating game failed: $(resp.status)"
  parse(Int, String(resp.body))
end

function downloadmatch(match_id; domain=:dev)
  url = PacoPlay.Url.server(; domain)
  resp = HTTP.get(url * "/api/game/$match_id")
  @assert resp.status == 200 "Download of match $match_id failed: $(resp.status)"
  body = String(resp.body)
  Json.parsematch(body)
end

function submitmatchanalysis(match_id, matchanalysis::Jtac.Analysis.MatchAnalysis, session_cookie::String; domain=:dev)

  # meta_data = replayjson.(matchanalysis.turn_analyses)
  action_index = 0
  meta_data = []
  for turnanalysis in matchanalysis.turn_analyses
    action_index += length(turnanalysis.actions)
    append!(meta_data, replayjson(match_id, action_index, turnanalysis))
  end
  @show meta_data
  submitmetadata(match_id, meta_data, session_cookie; domain)
end

function replayjson(match_id, action_index, turnanalysis::Jtac.Analysis.TurnAnalysis)::Vector{String}
  good = Jtac.Analysis.goodturns(turnanalysis)[1][1]
  from = tile(good[1], turnanalysis.mover)
  start = 2
  if from == -1 # Promotion, there won't be two subsequent actions that promote.
    from = tile(good[2], turnanalysis.mover)
    start = 3
  end
  result = []
  for i in start:length(good)
    to = tile(good[i], turnanalysis.mover)
    if to == -1
      continue
    end
    inner = """{\\"type\\":\\"arrow\\", \\"tail\\":$from, \\"head\\":$to, \\"color\\":\\"#5050ff80\\" }"""

    outer = """{"game":$match_id, "action_index":$action_index, "category":"Analysis", "data":"$inner"}"""
    push!(result, outer)
    from = to
  end

  result
end

function tile(tile::Int, mover::Int)::Int
  t = if tile <= 64
    tile
  elseif tile <= 128
    tile - 64
  else
    return -1 # Promotion
  end
  if mover == -1
    mirror_tile(t) - 1
  else
    t - 1
  end
end

"""
    mirror_tile(tile::Int)::Int

Return the tile index of the mirrored tile of `tile`.
We need this, because we flip the board in the board rotation.
"""
function mirror_tile(tile::Int)::Int
  mirrored = [
    57, 58, 59, 60, 61, 62, 63, 64,
    49, 50, 51, 52, 53, 54, 55, 56,
    41, 42, 43, 44, 45, 46, 47, 48,
    33, 34, 35, 36, 37, 38, 39, 40,
    25, 26, 27, 28, 29, 30, 31, 32,
    17, 18, 19, 20, 21, 22, 23, 24,
    9, 10, 11, 12, 13, 14, 15, 16,
    1, 2, 3, 4, 5, 6, 7, 8
  ]
  mtile = mirrored[tile]
  @assert mirrored[mtile] == tile
  mtile
end

function submitmetadata(match_id, meta_data::Vector, session_cookie::String; domain=:dev)
  url = PacoPlay.Url.server(; domain) * "/api/replay_meta_data/$match_id"
  data = "[" * join(meta_data, ",") * "]"
  headers = Dict(
    "Content-Type" => "application/json",
    "Cookie" => "session=$session_cookie",
  )
  HTTP.post(url, headers, data)
end

"""
    signin(username, password; domain = :dev)

Sign in into the pacoplay subdomain `domain` with credentials `username` and
`password`. Returns the session cookie.
"""
function signin(username, password; domain=:dev)
  url = PacoPlay.Url.server(; domain) * "/api/username_password"
  data = """{"username":"$username","password":"$password"}"""
  headers = ["Content-Type" => "application/json"]

  # With cookies = true, the cookies are stored in HTTP.COOKIEJAR
  response = HTTP.post(url, headers, data; cookies=true)

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

"""
    setaimetadata(match_id, color, session_cookie, model_name, model_strength, model_temperature; domain = :dev)

Set the AI metadata for the match with id `match_id` and color `color` to the
values `model_name`, `model_strength` and `model_temperature`. The session
cookie `session_cookie` is needed to authenticate the request.
"""
function setaimetadata(match_id::Int, color::Int, session_cookie::String, model_name::String
  ; model_strength::Int=0, model_temperature=0.0, domain=:dev)

  color_name = color == 1 ? "White" : "Black"

  url = PacoPlay.Url.server(; domain) * "/api/ai/game/$(match_id)/metadata/$(color_name)"
  data = """{"model_name":"$model_name","model_strength":$model_strength,"model_temperature":$model_temperature}"""
  headers = Dict(
    "Content-Type" => "application/json",
    "Cookie" => "session=$session_cookie",
  )
  HTTP.post(url, headers, data)
end


"""
    submitaction(match_id, player, action; domain, uuid, session)
    submitaction(match_id, game, action; kwargs...)

Submit the action `action` to the match with id `match_id`. The active `player`
or current game state `game` is needed to convert from Jtac action indices to
pacoplay actions.
"""
function submitaction(match::Integer, player::Integer, action::Game.ActionIndex
  ; domain=:dev, session=nothing, uuid="lpdyrmi3m3e1txe09dh")

  url = PacoPlay.Url.server(; domain) * "/api/ai/game/$(match)?uuid=$uuid"
  action = Json.action(action, player)
  headers = Dict(
    "Content-Type" => "application/json",
    "Cookie" => "session=$session",
  )
  HTTP.post(url, headers, action)
end

function submitaction(match, game::PacoSako, action; kwargs...)
  submitaction(match, Player.mover(game), action; kwargs...)
end

# TODO: Functionality to query the current game in a match
