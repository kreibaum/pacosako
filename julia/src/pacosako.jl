
"""
PacoSako game state. Wrapper around the rust type TODO:???.
"""
mutable struct PacoSako <: Game.AbstractGame
  ptr :: Ptr{Nothing}
  forfeit_by :: Int64
end

function Pack.pack(io :: IO, ps :: PacoSako) :: Nothing
  Pack.pack(io, Pack.Bytes(serialize(ps))) 
end

function Pack.unpack(io :: IO, :: Type{PacoSako}) :: PacoSako
  bytes = Pack.unpack(io, Pack.Bytes)
  deserialize(bytes.data)
end


"""
    destroy!(ps)

Destructor function for a paco sako game state `ps`. After `destroy!` has been
called, `ps` must not be used anymore.

This function should never be called manually.
"""
function destroy!(ps :: PacoSako)
  libcall(:drop, Nothing, (Ptr{Nothing},), ps.ptr)
end

"""
    wrap_pacosako_ptr(ptr) 

Wrap the pointer `ptr`, which must point to a valid pacosako object, as
[`PacoSako`](@ref) struct.
"""
function wrap_pacosako_ptr(ptr :: Ptr{Nothing}) :: PacoSako
  @assert ptr != C_NULL "Cannot wrap a nullpointer as PacoSako state"
  ps = PacoSako(ptr, UInt8[], 0)
  finalizer(destroy!, ps)
  status = libcall(:status, Int64, (Ptr{Nothing},), ps.ptr)
  if length(Game.legalactions(ps)) == 0 && status == 42
      ps.forfeit_by = Game.activeplayer(ps)
  end
  ps
end

"""
    PacoSako()
    PacoSako(fen)

Create a new `PacoSako` instance. If no fen-notated string `fen` is provided,
the returned game is in the default initial state.
"""
function PacoSako() :: PacoSako
  ptr = libcall(:new, Ptr{Nothing}, ())
  wrap_pacosako_ptr(ptr)
end

function PacoSako(fen :: String) :: PacoSako
  bytes = Vector{UInt8}(fen)
  ptr = libcall(
    :parse_fen,
    Ptr{Nothing},
    (Ptr{UInt8}, Int64),
    bytes,
    length(bytes)
  )
  @assert ptr != C_NULL "invalid fen string"
  wrap_pacosako_ptr(ptr)
end

function Game.status(ps :: PacoSako) :: Int64
  if ps.forfeit_by != 0
    -ps.forfeit_by
  else
    libcall(:status, Int64, (Ptr{Nothing},), ps.ptr)
  end
end

function Game.activeplayer(ps :: PacoSako) :: Int64
  libcall(:current_player, Int64, (Ptr{Nothing},), ps.ptr)
end

Game.policylength(::Type{PacoSako})::Int = 132

function Game.legalactions(ps :: PacoSako)
  # While there are 132 possible actions (64+64+4) there can be at most 64
  # actions that are legal at any point.
  out = zeros(UInt8, 64)
  libcall(:legal_actions, Nothing, (Ptr{Nothing}, Ptr{UInt8}), ps.ptr, out)
  # TODO: this is not particularly nice code...
  Int.(collect(Iterators.takewhile(x -> x > 0, out)))
end

function Game.move!(ps :: PacoSako, action :: Int) :: PacoSako

  status_code = libcall(
    :apply_action_bang,
    Int64,
    (Ptr{Nothing}, UInt8),
    ps.ptr,
    UInt8(action)
  )
  @assert status_code == 0 "Error during move!"

  actions = Game.legalactions(ps)
  raw_status = libcall(:status, Int64, (Ptr{Nothing},), ps.ptr)
  if length(actions) == 0 && raw_status == 42
      ps.forfeit_by = Game.activeplayer(ps)
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
    libcall(
      :get_idxrepr,
      Int64,
      (Ptr{Nothing}, Ptr{Nothing}, Int64),
      ps.ptr,
      tmp,
      length(tmp)
    )

    # Extract scatter indices and layer values for this game
    offset = (index - 1) * game_length
    scatter_indices[:, i] .= 1 .+ tmp[1:33] .+ offset
    layer_values[:, i] .= tmp[34:38]
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

"""
    random_position()

Returns a random Paco Sako game state that is legal and not yet over.
"""
function random_position() :: PacoSako
  ptr = libcall(:random_position, Ptr{Nothing}, ())
  @assert ptr != C_NULL "Error in the random generator for PacoSako"
  wrap_pacosako_ptr(ptr)
end

Game.randominstance(:: Type{PacoSako}) = random_position()

"""
    serialize(ps) 

Serialize the paco sako game state `ps`. Returns a byte vector.
"""
function serialize(ps :: PacoSako) :: Vector{UInt8}
  len = libcall(:serialize_len, Int64, (Ptr{Nothing},), ps.ptr)
  out = zeros(UInt8, len)
  status_code = libcall(
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
  ptr = libcall(
    :deserialize,
    Ptr{Nothing},
    (Ptr{UInt8}, Int64),
    bincode,
    length(bincode)
  )
  @assert ptr != C_NULL "Deserialization error for PacoSako game"
  wrap_pacosako_ptr(ptr)
end

################################################################################
## Helpers #####################################################################
################################################################################

function Game.hash(ps :: PacoSako) :: UInt64
  libcall(:hash, UInt64, (Ptr{Nothing},), ps.ptr)
end

function Game.draw(ps::PacoSako)
  libcall(:print, Nothing, (Ptr{Nothing},), ps.ptr)
end


function Base.:(==)(ps1 :: PacoSako, ps2 :: PacoSako) :: Bool
  libcall(:equals, Int64, (Ptr{Nothing}, Ptr{Nothing}), ps1.ptr, ps2.ptr) == 0
end

function Base.show(io :: IO, game :: PacoSako)
  if Game.isover(game)
    print(io, "PacoSako($(Game.status(game)) won)")
  else
    print(io, "PacoSako($(Game.activeplayer(game)) moving)")
  end
end

function Base.show(io :: IO, :: MIME"text/plain", game :: PacoSako)
  pacoplay_editor_url = PacoPlay.Url.editor(game)
  if Game.isover(game)
    println(io, "PacoSako($(Game.status(game)) won)")
    print(io, "  link: $pacoplay_editor_url")
  else
    println(io, "PacoSako($(Game.activeplayer(game)) moving)")
    print(io, "  link: $pacoplay_editor_url")
  end
end

function Base.size(:: Type{PacoSako})
  layer_count = libcall(:repr_layer_count, Int64, ())
  @assert layer_count > 0 "Layer count must be positive"
  (8, 8, layer_count)
end

function Base.copy(ps :: PacoSako) :: PacoSako
  ptr = libcall(:clone, Ptr{Nothing}, (Ptr{Nothing},), ps.ptr)
  wrap_pacosako_ptr(ptr)
end

"""
Given a Paco Ŝako position, this returns a vector that contains all possible
chains for the current player to unite with the opponents king. (Only direct
chains, no "Paco in 2").

A chain has type Vector{Int64}, so we return Vector{"Chain"}.

If there are more than 30 chains or they are longer than 30 actions, these are
not returned.
"""
function find_paco_sequences(ps::PacoSako)::Vector{Vector{Int64}}
    memory = zeros(UInt8, 1000)

    status_code = libcall(:find_paco_sequences, Int64,
        (Ptr{Nothing}, Ptr{UInt8}, Int64),
        ps.ptr, memory, length(memory))
    @assert status_code == 0 "Error when trying to find sequences $(fen(ps))"

    # Now we need to split this along the 0
    out = Vector()
    chain = Vector()
    for action in memory
        if action != 0
            push!(chain, action)
        elseif length(chain) > 0
            push!(out, chain)
            chain = Vector()
        end
    end
    out
end

"""
Given a Paco Ŝako position, this finds out if the current player is in Ŝako and
needs to defend.
"""
function is_sako_for_other_player(ps::PacoSako)::Bool
    libcall(:is_sako_for_other_player, Bool, (Ptr{Nothing},), ps.ptr)
end

"""
Given a Paco Ŝako position, count how many tiles can be attacked by the
current player.
"""
function my_threat_count(ps::PacoSako)::Int64
    libcall(:my_threat_count, Int64, (Ptr{Nothing},), ps.ptr)
end

"""
    fen(pacosako)

Returns the fen string of the `PacoSako` game state `pacosako`.
"""
function fen(ps::PacoSako)
    tmp = zeros(UInt8, 100)
    len = libcall(:write_fen, Int64, (Ptr{Nothing}, Ptr{UInt8}, Int64), ps.ptr, tmp, length(tmp))
    @assert len != 0 && len <= length(tmp) "fen string did not fit in allocated memory"
    String(@view tmp[1:len])
end



################################################################################
## Generates states where the best policy is known. ############################
################################################################################

"""
Returns a vector of positions together with a single action that is optimal
in this situation. This may return the same position twice if there is more than
one optimal action. (i.e. two ways to capture the king.)
"""
function find_simple_positions(; tries=100)::Data.DataSet{PacoSako}
    result = Data.DataSet(PacoSako, Target.defaults(PacoSako))
    for _ in 1:tries
        ps = random_position()
        solutions = find_paco_sequences(ps)
        for chain in solutions
            ps2 = copy(ps)
            for action in chain
                push!(result.games, copy(ps2))
                plabel = zeros(Float32, Game.policy_length(ps2))
                plabel[action] = 1
                vlabel = Float32[1]
                push!(result.labels[1], vlabel)
                push!(result.labels[2], plabel)

                Game.apply_action!(ps2, action)
            end
        end
    end
    result
end

