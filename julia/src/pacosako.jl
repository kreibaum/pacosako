"""This module wraps the rust pacosako dynamic library"""

using Jtac

# To build this, run `cargo build` in ../lib
# const DYNLIB_PATH = "../lib/target/debug/libpacosako.so"
# To build this, run `cargo build --release` in ../lib
const DYNLIB_PATH = "../lib/target/release/libpacosako.so"

mutable struct PacoSako <: Game.AbstractGame
    ptr::Ptr{Nothing}
    forfeit_by::Int64
end


"""Initializer and general memory management"""
function PacoSako()::PacoSako
    ptr = ccall((:new, DYNLIB_PATH), Ptr{Nothing}, ())
    wrap_pacosako_ptr(ptr)
end

function wrap_pacosako_ptr(ptr::Ptr{Nothing})::PacoSako
    ps = PacoSako(ptr, 0)
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
    ptr = ccall((:clone, DYNLIB_PATH), Ptr{Nothing}, (Ptr{Nothing},), ps.ptr)
    ps2 = wrap_pacosako_ptr(ptr)
    ps2.forfeit_by = ps.forfeit_by
    ps2
end

function Game.status(ps::PacoSako)::Int64
    if ps.forfeit_by != 0
        -ps.forfeit_by
    else
        ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)
    end
end

Game.current_player(ps::PacoSako)::Int64 = ccall((:current_player, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)

function Game.legal_actions(ps::PacoSako)
    out = zeros(UInt8, 128)
    ccall((:legal_actions, DYNLIB_PATH), Nothing, (Ptr{Nothing}, Ptr{UInt8}), ps.ptr, out)
    Int.(collect(Iterators.takewhile(x -> x > 0, out)))
end

function Game.apply_action!(ps::PacoSako, action::Int)::PacoSako
    status_code = ccall((:apply_action_bang, DYNLIB_PATH), Int64, (Ptr{Nothing}, UInt8), ps.ptr, UInt8(action))
    if length(Game.legal_actions(ps)) == 0
        ps.forfeit_by = Game.current_player(ps)
    end
    ps
end

## TODOS:

# Only when we want to to use neuronal network models
# Game.array(:: AbstractGame) = error("unimplemented")

Game.policy_length(:: Type{PacoSako})::Int = 132

# Only when a human player wants to play
# draw(io :: IO, game :: AbstractGame) :: Nothing = error("drawing $(typeof(game)) not implemented.")

# For performance:
# function is_action_legal(game :: AbstractGame, action :: ActionIndex)

################################################################################
## Helpers #####################################################################
################################################################################

function println(ps::PacoSako)
    ccall((:print, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end
