"""This module wraps the rust pacosako dynamic library"""
module JtacPacoSako

using Jtac

# PacoSako game type
export PacoSako

# export Jtac interface
export Jtac,
       Util,
       Game,
       Model,
       Player,
       Training,
       Bench

# To build this, run `cargo build` in ../lib
# const DYNLIB_PATH = "../lib/target/debug/libpacosako.so"
# To build this, run `cargo build --release` in ../lib
const DYNLIB_PATH = joinpath(dirname(@__DIR__), "../lib/target/release/libpacosako.so")

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

function Base.show(io::IO, game::PacoSako)
  if Game.is_over(game)
    print(io, "PacoSako($(Game.status(game)) won)")
  else
    print(io, "PacoSako($(Game.current_player(game)) moving)")
  end
end

function Base.show(io::IO, :: MIME"text/plain", game::PacoSako)
  if Game.is_over(game)
    print(io, "PacoSako game with result $(Game.status(game))")
  else
    print(io, "PacoSako game with player $(Game.current_player(game)) moving")
  end
end

function Game.draw(ps::PacoSako)
    @assert !Game.is_frozen(ps)
    ccall((:print, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end

function Base.:(==)(ps1::PacoSako, ps2::PacoSako)::Bool
    ccall((:equals, DYNLIB_PATH), Int64, (Ptr{Nothing}, Ptr{Nothing}), ps1.ptr, ps2.ptr) == 0
end

function Game.hash(ps::PacoSako)::UInt64
    @assert !Game.is_frozen(ps)
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
function find_sako_sequences(ps::PacoSako)::Vector{Vector{Int64}}
    memory = zeros(UInt8, 1000)
    
    status_code = ccall((:find_sako_sequences, DYNLIB_PATH), Int64,
        (Ptr{Nothing}, Ptr{UInt8}, Int64),
        ps.ptr, memory, length(memory))
    @assert status_code == 0 "Error when trying to find sequences"

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

################################################################################
## Generates states where the best policy is known. ############################
################################################################################

"""
Returns a vector of positions together with a single action that is optimal
in this situation. This may return the same position twice if there is more than
one optimal action. (i.e. two ways to capture the king.)
"""
function find_simple_positions(; tries=100)::Training.Dataset{PacoSako}
    result = Training.Dataset{PacoSako}()
    for _ in 1:tries
        ps = random_position()
        solutions = find_sako_sequences(ps)
        for chain in solutions
            ps2 = copy(ps)
            for action in chain
                push!(result.games, copy(ps2))
                label = Util.one_hot(1 + 132, 1 + action)
                label[1] = 1
                push!(result.label, label)
                push!(result.flabel, Vector())

                Game.apply_action!(ps2, action)
            end
        end
    end
    result
end

function __init__()
  # We have to register the game in order to use all functionality of Jtac
  # (loading and saving datasets and models)
  Game.register!(PacoSako)
end

################################################################################
## PacoPlay module to interact with pacoplay servers ###########################
################################################################################

export PacoPlay

include("pacoplay.jl")

end
