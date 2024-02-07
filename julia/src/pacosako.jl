
"""
PacoSako game state. Wrapper of a rust pacosako state object.
"""
mutable struct PacoSako <: Game.AbstractGame
  ptr :: Ptr{Nothing}
  forfeit_by :: Int64
end

function Pack.pack(io :: IO, ps :: PacoSako) :: Nothing
  Pack.pack(io, serialize(ps), Pack.BinaryFormat()) 
end

function Pack.unpack(io :: IO, :: Type{PacoSako}) :: PacoSako
  bytes = Pack.unpack(io, Pack.BinaryFormat())
  deserialize(bytes)
end

"""
    destroy!(ps)

Destroy the paco sako game state `ps`. Afterwards, `ps` must not be used
anymore.

!!! This function is part of the finalizer of `PacoSako` values and should not
!!! be called manually.
"""
function destroy!(ps :: PacoSako)
  @pscall(:drop, Nothing, (Ptr{Nothing},), ps.ptr)
end

"""
    PacoSako(ptr) 

Wrap the pointer `ptr`, which must point to a valid pacosako object, and return
a [`PacoSako`](@ref) object.
"""
function PacoSako(ptr :: Ptr{Nothing})
  @assert ptr != C_NULL "Cannot accept null pointer as PacoSako state"
  ps = PacoSako(ptr, 0)
  finalizer(destroy!, ps)
  status = @pscall(:status, Int64, (Ptr{Nothing}, ), ps.ptr)
  if length(Game.legalactions(ps)) == 0 && status == 42
      ps.forfeit_by = Game.mover(ps)
  end
  ps
end

"""
    PacoSako()
    PacoSako(fen)

Create a new [`PacoSako`](@ref) instance. If no fen-notated string `fen` is
provided, the returned game is in the default initial state.
"""
function PacoSako() :: PacoSako
  ptr = @pscall(:new, Ptr{Nothing}, ())
  PacoSako(ptr)
end

function PacoSako(fen :: String) :: PacoSako
  bytes = Vector{UInt8}(fen)
  ptr = @pscall(
    :parse_fen,
    Ptr{Nothing},
    (Ptr{UInt8}, Int64),
    bytes,
    length(bytes),
  )
  @assert ptr != C_NULL "Invalid fen string"
  PacoSako(ptr)
end

function Game.status(ps :: PacoSako) :: Game.Status
  if ps.forfeit_by != 0
    Game.Status(-ps.forfeit_by)
  else
    s = @pscall(:status, Int64, (Ptr{Nothing},), ps.ptr)
    Game.Status(s)
  end
end

function Game.mover(ps :: PacoSako) :: Int64
  @pscall(:current_player, Int64, (Ptr{Nothing},), ps.ptr)
end

function Game.moverlabel(ps :: PacoSako) :: String
  Game.mover(ps) == 1 ? "WHITE" : "BLACK"
end


"""
    movelabel(game, action)

Return a string representation of the action `action` at game state `game`.
"""
function Game.movelabel(ps :: PacoSako, action :: Int) :: String
  tmp = zeros(UInt8, 2)
  len = @pscall(
    :movelabel,
    Int64,
    (Ptr{Nothing}, UInt8, Ptr{UInt8}, Int64),
    ps.ptr,
    UInt8(action),
    tmp,
    length(tmp)
  )
  @assert len != 0 && len <= length(tmp) """
  Label string did not fit in allocated memory. This should be impossible.
  """
  String(@view tmp[1:len])
end

Game.policylength(:: Type{PacoSako}) :: Int = 132

function Game.legalactions(ps :: PacoSako)
  # While there are 132 possible actions (64+64+4) there can be at most 64
  # actions that are legal at any point.
  out = zeros(UInt8, 64)
  @pscall(:legal_actions, Nothing, (Ptr{Nothing}, Ptr{UInt8}), ps.ptr, out)
  actions = Iterators.takewhile(x -> x > 0, out)
  [Int(a) for a in actions]
end

function dumpgame(game :: PacoSako)
  fname = "$(time_ns()).pacosako"
  open(f -> Pack.pack(f, game), fname, "w")
  fname
end

function Game.move!(ps :: PacoSako, action :: Int) :: PacoSako
  status_code = @pscall(
    :apply_action_bang,
    Int64,
    (Ptr{Nothing}, UInt8),
    ps.ptr,
    UInt8(action)
  )
  if status_code != 0
    fname = dumpgame(ps)
    error("Error while moving with action $action (game dump: $fname)")
  end

  actions = Game.legalactions(ps)
  raw_status = @pscall(:status, Int64, (Ptr{Nothing},), ps.ptr)
  if length(actions) == 0 && raw_status == 42
      ps.forfeit_by = Game.mover(ps)
  end

  ps
end

function Game.array(pss :: Vector{PacoSako})
  batchsize = length(pss)
  buf = Game.arraybuffer(PacoSako, batchsize)
  Game.array!(buf, pss)
  buf
end

function Game.array(ps :: PacoSako)
  reshape(Game.array([ps]), 8, 8, 30)
end

function Game.array!(buf, games :: Vector{PacoSako})
  @assert size(buf)[1:3] == size(PacoSako)
  @assert size(buf, 4) >= length(games)

  batchsize = length(games)
  game_length = prod(size(PacoSako))

  # Reset the buffer that will carry the array representation of the games
  buf[:, :, :, 1:batchsize] .= 0

  # Buffer for storing the index representation of a single game state.
  #
  # The index representation is a sparse representation of a paco sako board
  # via 38 UInt32 values. The first 33 values are used as indices that identify
  # which entries of the dense game array should be set to 1 (we call this
  # operation "scattering"). The final 5 values correspond to the values of the
  # final 5 layers of the dense game array, all of which are constant.
  #
  # The crucial advantage of this representation is that only 38*8 bytes have to
  # be uploaded to the GPU per game state evaluation. Therefore, the amount of
  # data transfer between the CPU and GPU drops significantly.
  tmp = zeros(UInt32, 38)

  # Scatter indices that determine the location of 1s in the array representation
  scatter_indices = zeros(UInt32, 33, batchsize)

  # Values for the final 5 layers in the array representation
  layer_values = zeros(Float32, 5, batchsize)

  for (index, ps) in enumerate(games)

    # Get the index representation of this game
    @pscall(
      :get_idxrepr,
      Int64,
      (Ptr{Nothing}, Ptr{Nothing}, Int64),
      ps.ptr,
      tmp,
      length(tmp)
    )

    # Extract scatter indices and layer values for this game
    offset = (index - 1) * game_length
    scatter_indices[:, index] .= 1 .+ tmp[1:33] .+ offset
    layer_values[:, index] .= tmp[34:38]
  end

  # Set the buffer to 1 at the 33 scatter index locations
  scatter_indices = reshape(scatter_indices, :)
  buf[scatter_indices] .= 1

  # Set the 5 constant layers
  T = Model.arraytype(buf)
  layer_values = convert(T, layer_values)
  buf[:, :, 26:30, 1:batchsize] .= reshape(layer_values, 1, 1, 5, :)

  # Scale the final layer
  buf[:, :, 30, 1:batchsize] ./= 100

  nothing
end

function Game.randominstance(:: Type{PacoSako})
  ptr = @pscall(:random_position, Ptr{Nothing}, ())
  @assert ptr != C_NULL "Error in the random generator for PacoSako"
  PacoSako(ptr)
end

function Game.visualize(ps::PacoSako)
  @pscall(:print, Nothing, (Ptr{Nothing},), ps.ptr)
end

function Base.:(==)(ps1 :: PacoSako, ps2 :: PacoSako) :: Bool
  @pscall(:equals, Int64, (Ptr{Nothing}, Ptr{Nothing}), ps1.ptr, ps2.ptr) == 0
end

function Base.hash(ps :: PacoSako) :: UInt64
  @pscall(:hash, UInt64, (Ptr{Nothing},), ps.ptr)
end

function Base.isequal(a :: PacoSako, b :: PacoSako)
  Base.hash(a) == Base.hash(b)
end

"""
    serialize(ps) 

Serialize the paco sako game state `ps`. Returns a byte vector.
"""
function serialize(ps :: PacoSako) :: Vector{UInt8}
  len = @pscall(:serialize_len, Int64, (Ptr{Nothing},), ps.ptr)
  out = zeros(UInt8, len)
  status_code = @pscall(
    :serialize,
    Int64,
    (Ptr{Nothing}, Ptr{UInt8}, Int64),
    ps.ptr,
    out,
    len
  )
  @assert status_code == 0 "Error during serialization of PacoSako game"
  out
end

"""
    deserialize(bytes) 

Deserialize a paco sako game state from the byte vector `bytes`.
"""
function deserialize(bincode :: Vector{UInt8}) :: PacoSako
  ptr = @pscall(
    :deserialize,
    Ptr{Nothing},
    (Ptr{UInt8}, Int64),
    bincode,
    length(bincode)
  )
  @assert ptr != C_NULL "Deserialization error for PacoSako game"
  PacoSako(ptr)
end

function statusmsg(game)
  if Game.isover(game)
    s = Game.status(game)
    if s == Game.draw
      "draw"
    elseif s == Game.win
      "white won"
    elseif s == Game.loss
      "black won"
    end
  else
    if Game.mover(game) == 1
      "white moving"
    else
      "black moving"
    end
  end
end

function Base.show(io :: IO, game :: PacoSako)
  print(io, "PacoSako($(statusmsg(game)))")
end

function Base.show(io :: IO, :: MIME"text/plain", game :: PacoSako)
  pacoplay_editor_url = PacoPlay.Url.editor(game)
  println(io, "PacoSako($(statusmsg(game)))")
  print(io, "  link: $pacoplay_editor_url")
end

function Base.size(:: Type{PacoSako})
  layer_count = @pscall(:repr_layer_count, Int64, ())
  @assert layer_count > 0 "Layer count must be positive"
  (8, 8, layer_count)
end

function Base.copy(ps :: PacoSako) :: PacoSako
  ptr = @pscall(:clone, Ptr{Nothing}, (Ptr{Nothing},), ps.ptr)
  PacoSako(ptr)
end

#
# Paco sako specific functionality
#

"""
    fen(ps)

Returns the fen notation string of the [`PacoSako`](@ref) game state `ps`.
"""
function fen(ps::PacoSako)
  tmp = zeros(UInt8, 100)
  len = @pscall(
    :write_fen,
    Int64,
    (Ptr{Nothing}, Ptr{UInt8}, Int64),
    ps.ptr,
    tmp,
    length(tmp)
  )
  @assert len != 0 && len <= length(tmp) """
  Fen string did not fit in allocated memory. This should be impossible.
  """
  String(@view tmp[1:len])
end

"""
    sako(ps)

Returns whether the [`PacoSako`](@ref) game state `ps` can be finished within
the next chain of the currently active player.
"""
sako(ps :: PacoSako) :: Bool = !isempty(sakochains(ps))

"""
    sakothreat(ps)

Returns whether the [`PacoSako`](@ref) game state `ps` can be finished with one
the next chain of the currently inactive player
"""
function sakothreat(ps :: PacoSako)
  @pscall(:is_sako_for_other_player, Bool, (Ptr{Nothing},), ps.ptr)
end

"""
    attackcount(ps)

Count how many tiles can be attacked by the current player in a [`PacoSako`]
(@ref) game state `ps`.
"""
function attackcount(ps :: PacoSako) :: Int64
  @pscall(:my_threat_count, Int64, (Ptr{Nothing},), ps.ptr)
end


"""
    sakochains(ps)

Given the [`PacoSako`](@ref) game state `ps`, return all possible action
sequences for the current player to unite with the opponent king.

Only direct chains are found, so "Sako in two" is not included. Returns
at most 30 chains, and does not return chains that are longer than 30 actions.
"""
function sakochains(ps :: PacoSako) :: Vector{Vector{Int64}}
  buffer = zeros(UInt8, 1000)
  status_code = @pscall(
    :find_paco_sequences,
    Int64,
    (Ptr{Nothing}, Ptr{UInt8}, Int64),
    ps.ptr,
    buffer,
    length(buffer),
  )
  if status_code != 0
    fname = dumpgame(game)
    error("Error while trying to find sako chains (game dump: $fname)")
  end

  # Split the result at each returned 0s
  chains = Vector{Int64}[]
  chain = Int64[]
  for action in buffer
    if action != 0
      push!(chain, action)
    elseif length(chain) > 0
      push!(chains, chain)
      chain = Int64[]
    end
  end
  chains
end


"""
    sakodata(; tries = 100)

Return a [`DataSet`](@ref) of [`PacoSako`](@ref) game states equipped with
corresponding value and policy labels that are known to be optimal.

May return the same game state twice if there is more than one optimal action
(i.e. several ways to capture the king).
"""
function sakodata(; tries=100) :: DataSet{PacoSako}
  ds = DataSet(PacoSako, Target.defaulttargets(PacoSako))
  for _ in 1:tries
    ps = Game.randominstance(PacoSako)
    for chain in sakochains(ps)
      ps2 = copy(ps)
      for action in chain
        push!(ds.games, copy(ps2))
        plabel = zeros(Float32, Game.policylength(ps2))
        plabel[action] = 1
        vlabel = Float32[1]
        push!(ds.target_labels[1], vlabel)
        push!(ds.target_labels[2], plabel)
        Game.move!(ps2, action)
      end
    end
  end
  @assert Training.isconsistent(ds) """Dataset consistency check failed"""
  ds
end


""" 
    halfmovecount(ps)

Returns the halfmove count of the [`PacoSako`](@ref) game state `ps`.
"""
function halfmovecount(ps::PacoSako)
  @pscall(:half_move_count, Int64, (Ptr{Nothing},), ps.ptr)
end


"""
    movecount(ps)

Returns the fullmove count of the [`PacoSako`](@ref) game state `ps`.
"""
function movecount(ps::PacoSako)
  @pscall(:move_count, Int64, (Ptr{Nothing},), ps.ptr)
end

"""
    actioncount(ps)

Returns the number of actions that have been played in the [`PacoSako`](@ref)
game state `ps`.
"""
function actioncount(ps::PacoSako)
  @pscall(:action_count, Int64, (Ptr{Nothing},), ps.ptr)
end