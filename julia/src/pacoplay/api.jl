"""
    requestmatch(; domain = :dev)

Request a new match from the pacoplay subdomain `domain`.
"""
function requestmatch(; domain = :dev) :: Int
  url = PacoPlay.Url.server(; domain)
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
  url = PacoPlay.Url.server(; domain) * "/api/username_password"
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

"""
    submitaction(match_id, player, action; domain, uuid, session)
    submitaction(match_id, game, action; kwargs...)

Submit the action `action` to the match with id `match_id`. The active `player`
or current game state `game` is needed to convert from Jtac action indices to
pacoplay actions.
"""
function submitaction( match :: Integer
                     , player :: Integer
                     , action :: Game.ActionIndex
                     ; domain = :dev
                     , session = nothing
                     , uuid = "lpdyrmi3m3e1txe09dh" )

  url = PacoPlay.Url.server(; domain) * "/api/ai/game/$(match)?uuid=$uuid"
  action = Json.action(action, player) 
  headers = Dict(
    "Content-Type" => "application/json",
    "Cookie" => "session=$session",
  )
  HTTP.post(url, headers, action)
end

function submitaction(match, game :: PacoSako, action; kwargs...)
  submitaction(match, Player.activeplayer(game), action; kwargs...)
end

# TODO: Functionality to query the current game in a match
