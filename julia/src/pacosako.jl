"""This module wraps the rust pacosako dynamic library"""

using Jtac

# To build this, run `cargo build` in ../lib
# const DYNLIB_PATH = "../lib/target/debug/libpacosako.so"
# To build this, run `cargo build --release` in ../lib
const DYNLIB_PATH = "../lib/target/release/libpacosako.so"

mutable struct PacoSako <: Game.AbstractGame
    ptr::Ptr{Nothing}
    cache::Union{Nothing,Vector{UInt8}} # store serialized game when frozen
    forfeit_by::Int64
end


"""Initializer and general memory management"""
function PacoSako()::PacoSako
    ptr = ccall((:new, DYNLIB_PATH), Ptr{Nothing}, ())
    wrap_pacosako_ptr(ptr)
end

function wrap_pacosako_ptr(ptr::Ptr{Nothing})::PacoSako
    ps = PacoSako(ptr, nothing, 0)
    finalizer(destroy!, ps)
    ps
end

"""Destructor. Never call that manually, or you'll double free / use after free."""
function destroy!(ps::PacoSako)
    # ccall to rust to tell it to release the object.
    ccall((:drop, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end


################################################################################
## Implementation of the Game interface. #######################################
################################################################################

function Base.copy(ps::PacoSako)::PacoSako
    @assert !Game.is_frozen(ps)
    ptr = ccall((:clone, DYNLIB_PATH), Ptr{Nothing}, (Ptr{Nothing},), ps.ptr)
    ps2 = wrap_pacosako_ptr(ptr)
    ps2.forfeit_by = ps.forfeit_by
    ps2
end

function Game.status(ps::PacoSako)::Int64
    @assert !Game.is_frozen(ps)
    if ps.forfeit_by != 0
        -ps.forfeit_by
    else
        ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
    end
end

Game.current_player(ps::PacoSako)::Int64 = ccall((:current_player, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)

function Game.legal_actions(ps::PacoSako)
    @assert !Game.is_frozen(ps)
    # While there are 132 possible actions (64+64+4) there can be at most 64
    # actions that are legal at any point.
    out = zeros(UInt8, 64)
    ccall((:legal_actions, DYNLIB_PATH), Nothing, (Ptr{Nothing}, Ptr{UInt8}), ps.ptr, out)
    Int.(collect(Iterators.takewhile(x -> x > 0, out)))
end

function Game.apply_action!(ps::PacoSako, action::Int)::PacoSako
    @assert !Game.is_frozen(ps)
    status_code = ccall((:apply_action_bang, DYNLIB_PATH), Int64, (Ptr{Nothing}, UInt8), ps.ptr, UInt8(action))
    if length(Game.legal_actions(ps)) == 0 && ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr) == 42
        ps.forfeit_by = Game.current_player(ps)
    end
    @assert status_code == 0 "Error during apply_action! of PacoSako game!"
    ps
end

function Game.array(ps::PacoSako)::Array{Float32,3}
    size = Base.size(ps)
    memory = zeros(Float32, prod(size))
    status_code = ccall((:repr, DYNLIB_PATH), Int64, (Ptr{Nothing}, Ptr{Float32}, Int64), ps.ptr, memory, length(memory))
    @assert status_code == 0 "Error while determining the game representation"
    reshape(memory, size)
end

function Base.size(:: Type{PacoSako})
    layer_count = ccall((:repr_layer_count, DYNLIB_PATH), Int64, ())
    @assert layer_count > 0 "Layer count must be positive"
    (8, 8, layer_count)
end

Game.policy_length(:: Type{PacoSako})::Int = 132

# Only when a human player wants to play
# draw(io :: IO, game :: PacoSako) :: Nothing = error("drawing $(typeof(game)) not implemented.")

# For performance:
# function is_action_legal(game :: PacoSako, action :: ActionIndex)

################################################################################
## (De-)Serialization ##########################################################
################################################################################

function serialize(ps::PacoSako)::Vector{UInt8}
    @assert !Game.is_frozen(ps)
    length = ccall((:serialize_len, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
    out = zeros(UInt8, length)
    status_code = ccall((:serialize, DYNLIB_PATH), Int64, (Ptr{Nothing}, Ptr{UInt8}, Int64), ps.ptr, out, length)
    @assert status_code == 0 "Error during serialization of PacoSako game!"
    out
end

function deserialize(bincode::Vector{UInt8})::PacoSako
    ptr = ccall((:deserialize, DYNLIB_PATH), Ptr{Nothing}, (Ptr{UInt8}, Int64), bincode, length(bincode))
    @assert ptr != C_NULL "Deserialization error for PacoSako game!"
    ps = wrap_pacosako_ptr(ptr)
    if length(Game.legal_actions(ps)) == 0 && ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr) == 42
        ps.forfeit_by = Game.current_player(ps)
    end
    ps
end

function Game.is_frozen(ps::PacoSako)::Bool
    !isnothing(ps.cache)
end

function Game.freeze(ps::PacoSako)::PacoSako
    @assert !Game.is_frozen(ps)
    PacoSako(C_NULL, serialize(ps), ps.forfeit_by)
end

function Game.unfreeze(ps::PacoSako)::PacoSako
    @assert Game.is_frozen(ps)
    deserialize(ps.cache)
end

################################################################################
## Helpers #####################################################################
################################################################################

function println(ps::PacoSako)
    @assert !Game.is_frozen(ps)
    ccall((:print, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end
