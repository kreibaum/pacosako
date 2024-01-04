
"""
    upload(games; domain, uuid, username, password)
    upload(actions; domain, uuid, username, password)

Upload a series of actions as new match on pacoplay. If a vector of games is
provided, the corresponding actions are reconstructed.
"""
function upload( actions :: Vector{Game.ActionIndex}
               ; domain = :dev
               , uuid :: String = "lpdyrmi3m3e1txe09dh"
               , username = nothing
               , password = nothing )

  @assert !isempty(actions) "Cannot upload empty action sequence"
  log("Uploading match with $(length(actions)) actions")
  game = PacoSako()
  match = Api.requestmatch(; domain)

  if !isnothing(username) && !isnothing(password)
    session = Api.signin(username, password; domain)
    log("Signed in with session cookie: $session")
  else
    session = nothing
  end

  for action in actions
    Api.submitaction(match, game, action; domain, uuid, session)
    Game.move!(game, action)
  end

  url = Url.replay(match; domain)
  log("Upload successful: $url")
end

function upload(games :: Vector{PacoSako}; kwargs...)
  @assert !isempty(games) "Cannot upload empty game sequence"
  @assert isequal(games[1], PacoSako()) """
  Can only upload game sequences that start with a default initial state.
  """
  actions = Game.reconstructactions(games)
  upload(actions; kwargs...)
end

