
"""
Module that wraps the rust pacosako dynamic library and makes it accessible
to the Jtac boardgame training package.

!!! To use this package, you currently have to manually run
!!! `cargo build --release` in `../lib`.

It provides the type `PacoSako`, which implements the `Jtac.Game.AbstractGame`
interface. This enables Jtac support for creating classical or neural network
based AIs, improving neural AIs via self-play (in an Alpha Zero inspired way),
benchmarking their performance, or playing against them. One classical AI
model, `Luna`, which relies on a strict analysis for possible checks and uses a
simple heuristic to propose state values and action policies, is implemented in
this package.

The submodule `PacoPlay` bridges this package to the pacoplay webpage, and
exports utility function for playing against a Jtac AI on it.
"""
module JtacPacoSako

using Jtac

# re-export Jtac Modules
export Jtac,
       Util,
       Pack,
       Game,
       Target,
       Data,
       Model,
       Player,
       Training


export PacoSako, Luna
export fen, random_position

# TODO: Use the Artifact interface to store compiled versions of the library
# in the web?
const DYNLIB_PATH = joinpath(dirname(@__DIR__), "../lib/target/release/libpacosako.so")

"""
    libcall(name, args...) 

Wrapper around [`ccall`](@ref) that automatically inserts the pacosako shared
library.
"""
libcall(name, args...) = ccall((name, DYNLIB_PATH), args...)

# Jtac.Game.AbstractGame implementation of PacoSako
include("pacosako.jl")

# Luna ai model
include("luna.jl")


"""
Glue between the JtacPacoSako package and the pacoplay webpage.
"""
module PacoPlay

  using ..JtacPacoSako
  using HTTP, LazyJSON

  include("pacoplay.jl")

end # module PacoPlay

export PacoPlay

end
