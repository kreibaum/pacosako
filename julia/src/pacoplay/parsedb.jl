
function onehot(action)
  l = Game.policylength(PacoSako)
  vec = zeros(Float32, l)
  vec[action] = 1
  vec
end

"""
    parsedb(csv; seperator = ',', merge = true, match_ids = false, verbose = false)

Parse the csv file `csv` that contains exported matches from the pacoplay
webpage. Constructs a list of datasets (one for each match) which are merged if
`merge = true`. If `match_ids = true`, a vector of match ids is returned as
well.
"""
function parsedb( csv
                ; seperator :: Char = ','
                , merge = true
                , match_ids = false
                , verbose = false )

  data = readdlm(csv, seperator)
  n = size(data, 1) - 1

  if verbose
    println("Loaded $n action traces from csv file")
  end
  ids = Int[]

  dss = map(1:n) do index
    match_id = data[index+1, 1]

    ds = Training.DataSet(PacoSako)
    moves = LazyJSON.parse(data[index+1, 2])
    game = PacoSako()

    # Replay the game
    for move in moves
      action = PacoPlay.Json.parseaction(move, Game.activeplayer(game))
      policy = onehot(action)
      push!(ds.games, copy(game))
      push!(ds.target_labels[2].data, onehot(action)) # store policy targets
      try
        Game.move!(game, action)
      catch
        # This can happen when matches on the website follow old / alternative
        # rules or are malformed in other ways
        if verbose
          println("Match $match_id is invalid")
        end
        return nothing
      end
    end

    # Only accept matches that have been finished
    if !Game.isover(game)
      return nothing
    end

    # Use game result to provide value targets
    status = Game.status(game)
    for game in ds.games
      active = Game.activeplayer(game)
      value = Float32[active * Int(status)]
      push!(ds.target_labels[1].data, value)
    end
    @assert Training.isconsistent(ds)
    push!(ids, match_id)
    ds
  end

  dss = [ds for ds in dss if !isnothing(ds)]
  l = length(dss)

  if verbose 
    println("A total of $l out of $n traces have been loaded")
  end

  ds = merge ? Base.merge(dss) : dss
  match_ids ? (ds, ids) : ds
end
