
# To build this, run `cargo build` in ../lib
# const DYNLIB_PATH = "../lib/target/debug/libpacosako.so"
# To build this, run `cargo build --release` in ../lib
const DYNLIB_PATH = joinpath(dirname(@__DIR__), "../lib/target/release/libpacosako.so")

mutable struct PacoSako <: Game.AbstractGame
    ptr #::Ptr{Nothing}
    bin::Pack.Bytes # store binary representation if frozen
    forfeit_by::Int64
end

"""Initializer and general memory management"""
function PacoSako()::PacoSako
    ptr = ccall((:new, DYNLIB_PATH), Ptr{Nothing}, ())
    wrap_pacosako_ptr(ptr)
end

function PacoSako(fen::String)::PacoSako
    bytes = Vector{UInt8}(fen)
    ptr = ccall((:parse_fen, DYNLIB_PATH), Ptr{Nothing}, (Ptr{UInt8}, Int64), bytes, length(bytes))
    @assert ptr != C_NULL "invalid fen string"
    wrap_pacosako_ptr(ptr)
end

function wrap_pacosako_ptr(ptr::Ptr{Nothing})::PacoSako
    @assert ptr != C_NULL
    ps = PacoSako(ptr, UInt8[], 0)
    finalizer(destroy!, ps)
    status = ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
    if length(Game.legal_actions(ps)) == 0 && status == 42
        ps.forfeit_by = Game.current_player(ps)
    end
    ps
end

"""Destructor. Never call that manually, or you'll double free use after free."""
function destroy!(ps::PacoSako)
    # ccall to rust to tell it to release the object.
    ccall((:drop, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end


################################################################################
## Implementation of the Game interface. #######################################
################################################################################

function Base.copy(ps::PacoSako)::PacoSako
    @assert !is_frozen(ps)
    ptr = ccall((:clone, DYNLIB_PATH), Ptr{Nothing}, (Ptr{Nothing},), ps.ptr)
    wrap_pacosako_ptr(ptr)
end

function Game.status(ps::PacoSako)::Int64
    @assert !is_frozen(ps)
    if ps.forfeit_by != 0
        -ps.forfeit_by
    else
        ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
    end
end

Game.current_player(ps::PacoSako)::Int64 = ccall((:current_player, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)

function Game.legal_actions(ps::PacoSako)
    @assert !is_frozen(ps)
    # While there are 132 possible actions (64+64+4) there can be at most 64
    # actions that are legal at any point.
    out = zeros(UInt8, 64)
    ccall((:legal_actions, DYNLIB_PATH), Nothing, (Ptr{Nothing}, Ptr{UInt8}), ps.ptr, out)
    Int.(collect(Iterators.takewhile(x -> x > 0, out)))
end

function Game.apply_action!(ps::PacoSako, action::Int)::PacoSako
    @assert !is_frozen(ps)
    status_code = ccall((:apply_action_bang, DYNLIB_PATH), Int64, (Ptr{Nothing}, UInt8), ps.ptr, UInt8(action))
    if length(Game.legal_actions(ps)) == 0 && ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr) == 42
        ps.forfeit_by = Game.current_player(ps)
    end
    @assert status_code == 0 "Error during apply_action! of PacoSako game"
    ps
end

function Game.array(pss::Vector{PacoSako})
    batchsize = length(pss)
    buf = Game.array_buffer(PacoSako, batchsize)
    Game.array!(buf, pss)
    buf
end

function Game.array(ps::PacoSako)
    reshape(Game.array([ps]), 8, 8, 30)
end

function Game.array!(buf, pss :: Vector{PacoSako})
    # do arguments make sense?
    batchsize = length(pss)
    batchsize > 0 || return

    @assert size(buf)[1:3] == size(PacoSako)
    @assert size(buf, 4) >= batchsize

    # some working memory
    idxrepr = zeros(UInt32, 38)
    one_indices = zeros(UInt32, 33, batchsize)
    layer_vals = zeros(Float32, 5, batchsize)

    for (i, ps) in enumerate(pss)
        # set idxrepr via call to rust
        ccall( (:get_idxrepr, DYNLIB_PATH)
             , Int64, (Ptr{Nothing}, Ptr{Nothing}, Int64)
             , ps.ptr, idxrepr, length(idxrepr) )

        one_indices[:, i] .= 1 .+ idxrepr[1:33] .+ (i-1) * prod(size(PacoSako))
        layer_vals[:, i] .= idxrepr[34:38]
    end

    # reset buffer
    buf[:, :, :, 1:batchsize] .= 0

    # set one_indices in buffer to ... one!
    one_indices = reshape(one_indices, :)
    buf[one_indices] .= 1

    # set layer values of buffer
    layer_vals = Model.adapt_atype(buf, layer_vals) # maybe load it to GPU
    layer_vals = reshape(layer_vals, 1, 1, 5, batchsize) # makes broadcasting work
    buf[:, :, 26:30, 1:batchsize] .= layer_vals

    # scale final layer
    buf[:, :, 30, 1:batchsize] ./= 100

    nothing
end

function Base.size(::Type{PacoSako})
    layer_count = ccall((:repr_layer_count, DYNLIB_PATH), Int64, ())
    @assert layer_count > 0 "Layer count must be positive"
    (8, 8, layer_count)
end

Game.policy_length(::Type{PacoSako})::Int = 132

# Only when a human player wants to play
# draw(io :: IO, game :: PacoSako) :: Nothing = error("drawing $(typeof(game)) not implemented.")

# For performance:
# function is_action_legal(game :: PacoSako, action :: ActionIndex)

################################################################################
## (De-)Serialization ##########################################################
################################################################################

function serialize(ps::PacoSako)::Vector{UInt8}
    @assert !is_frozen(ps)
    length = ccall((:serialize_len, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
    out = zeros(UInt8, length)
    status_code = ccall((:serialize, DYNLIB_PATH), Int64, (Ptr{Nothing}, Ptr{UInt8}, Int64), ps.ptr, out, length)
    @assert status_code == 0 "Error during serialization of PacoSako game!"
    out
end

function deserialize(bincode::Vector{UInt8})::PacoSako
    ptr = ccall((:deserialize, DYNLIB_PATH), Ptr{Nothing}, (Ptr{UInt8}, Int64), bincode, length(bincode))
    @assert ptr != C_NULL "Deserialization error for PacoSako game!"
    wrap_pacosako_ptr(ptr)
end

is_frozen(ps::PacoSako)::Bool = !isempty(ps.bin.data)

function Pack.freeze(ps::PacoSako)::PacoSako
    @assert !is_frozen(ps)
    PacoSako(0, serialize(ps), ps.forfeit_by)
end

function Pack.unfreeze(ps::PacoSako)::PacoSako
    @assert is_frozen(ps)
    deserialize(ps.bin.data)
end


################################################################################
## Helpers #####################################################################
################################################################################

function Base.show(io::IO, game::PacoSako)
    if Game.is_over(game)
        print(io, "PacoSako($(Game.status(game)) won)")
    else
        print(io, "PacoSako($(Game.current_player(game)) moving)")
    end
end

function Base.show(io::IO, ::MIME"text/plain", game::PacoSako)
    fen_string = PacoPlay.Url.editor(game)
    if Game.is_over(game)
        println(io, "PacoSako game with result $(Game.status(game))")
        print(io, "  link: $fen_string")
    else
        println(io, "PacoSako game with player $(Game.current_player(game)) moving")
        print(io, "  link: $fen_string")
    end
end

function Game.draw(ps::PacoSako)
    @assert !is_frozen(ps)
    ccall((:print, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end

function Base.:(==)(ps1::PacoSako, ps2::PacoSako)::Bool
    ccall((:equals, DYNLIB_PATH), Int64, (Ptr{Nothing}, Ptr{Nothing}), ps1.ptr, ps2.ptr) == 0
end

function Game.hash(ps::PacoSako)::UInt64
    @assert !is_frozen(ps)
    ccall((:hash, DYNLIB_PATH), UInt64, (Ptr{Nothing},), ps.ptr)
end

"""
Returns a random Paco Ŝako position that is legal and still running.
"""
function random_position()::PacoSako
    ptr = ccall((:random_position, DYNLIB_PATH), Ptr{Nothing}, ())
    @assert ptr != C_NULL "Error in the random generator for PacoSako"
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

    status_code = ccall((:find_paco_sequences, DYNLIB_PATH), Int64,
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
    ccall((:is_sako_for_other_player, DYNLIB_PATH), Bool, (Ptr{Nothing},), ps.ptr)
end

"""
Given a Paco Ŝako position, count how many tiles can be attacked by the
current player.
"""
function my_threat_count(ps::PacoSako)::Int64
    ccall((:my_threat_count, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
end

"""
    fen(pacosako)

Returns the fen string of the `PacoSako` game state `pacosako`.
"""
function fen(ps::PacoSako)
    tmp = zeros(UInt8, 100)
    len = ccall((:write_fen, DYNLIB_PATH), Int64, (Ptr{Nothing}, Ptr{UInt8}, Int64), ps.ptr, tmp, length(tmp))
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

