"""This module wraps the rust pacosako dynamic library"""

# using Jtac

const DYNLIB_PATH = "../lib/target/debug/libpacosako.so"

mutable struct PacoSako # <: Game # We need to be using Jtac to subtype Game.
    ptr::Ptr{Nothing}
end


"""Initializer and general memory management"""
function PacoSako()::PacoSako
    ptr = ccall((:new, DYNLIB_PATH), Ptr{Nothing}, ())
    wrap_pacosako_ptr(ptr)
end

function wrap_pacosako_ptr(ptr::Ptr{Nothing})::PacoSako
    ps = PacoSako(ptr)
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
    wrap_pacosako_ptr(ptr)
end

# TODO: this one next.
# status(ps::PacoSako) = ccall((:status, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)

current_player(ps::PacoSako)::Int64 = ccall((:current_player, DYNLIB_PATH), Int64, (Ptr{Nothing},), ps.ptr)

function legal_actions(ps::PacoSako)
    out = zeros(UInt8, 128)
    ccall((:legal_actions, DYNLIB_PATH), Nothing, (Ptr{Nothing}, Ptr{UInt8}), ps.ptr, out)
    Int.(collect(Iterators.takewhile(x -> x > 0, out)))
end

function apply_action!(ps::PacoSako, action::Int)::PacoSako
    status_code = ccall((:apply_action_bang, DYNLIB_PATH), Int64, (Ptr{Nothing}, UInt8), ps.ptr, UInt8(action))
    ps
end

################################################################################
## Helpers #####################################################################
################################################################################

function println(ps::PacoSako)
    ccall((:print, DYNLIB_PATH), Nothing, (Ptr{Nothing},), ps.ptr)
end
