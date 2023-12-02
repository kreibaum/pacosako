
"""
Module that wraps the rust pacosako library and makes it accessible to Jtac,
which is Alpha Zero inspired boardgame training package.

!!! To use this package, you currently have to manually run
!!! `cargo build --release` in the folder `../lib`.
"""
module JtacPacoSako

import Libdl: dlopen, RTLD_GLOBAL

using Jtac
import Jtac.Training: DataSet

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

# TODO: Replace this via the artifact system
const lib = joinpath(dirname(@__DIR__), "../lib/target/release/libpacosako.so")

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

end # module JtacPacoSako
