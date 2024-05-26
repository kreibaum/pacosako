
"""
Module that wraps the rust pacosako library and makes it accessible to Jtac,
which is Alpha Zero inspired boardgame training package.
"""
module JtacPacoSako

using Artifacts, LazyArtifacts
import Libdl

using Reexport

@reexport using Jtac
@reexport using Jtac.Common

export PacoSako, PacoSakoTensorizor

export Paco1Solver, Luna, Ludwig, Hedwig

export SakoTarget, BlockedPawnsTarget, ThreatenedSquaresTarget

"""
Reference to the currently loaded instance of libpacosako.
"""
const LIBPACOSAKO = Ref{Ptr{Nothing}}()

"""
    @pscall(symbol, args...)

Convenient way to run `ccall(ptr, args...)`, where `ptr` is the resolved
function pointer `ptr = Libdl.dlsym(LIBPACOSAKO[], symbol)`.

Has to be a macro since `ccall` is syntax and not a normal julia function.
"""
macro pscall(symbol, return_type, signature, args...)
  ptr = :(Libdl.dlsym(LIBPACOSAKO[], $symbol))
  Expr(:call, :ccall, ptr, return_type, signature, args...) |> esc
end

# Jtac.Game.AbstractGame implementation of PacoSako
include("pacosako.jl")

# Additional training targets
include("targets.jl")

# Classical AI models and assistants
include("solver.jl")
include("luna.jl")

# Pretrained models that are downloaded on demand via the artifact system
include("pretrained.jl")

"""
Glue between the JtacPacoSako package and the pacoplay webpage.
"""
module PacoPlay

  using ..JtacPacoSako
  using HTTP, JSON
  using DelimitedFiles

  module Url
    using ..JtacPacoSako
    include("pacoplay/url.jl")
  end

  module Json
    using ..JtacPacoSako
    import JSON
    include("pacoplay/json.jl")
  end

  module Api
    using HTTP, URIs
    using ..JtacPacoSako
    import ..PacoPlay
    import ..Json
    include("pacoplay/api.jl")
  end

  include("pacoplay/log.jl")
  include("pacoplay/upload.jl")
  include("pacoplay/play.jl")
  include("pacoplay/parsedb.jl")

end # module PacoPlay

export PacoPlay

function __init__()
  dynlib_path = if haskey(ENV, "LIBPACOSAKO")
    ENV["LIBPACOSAKO"]
  else
    joinpath(dirname(@__DIR__), "../lib/target/release/libpacosako.so")
  end

  if isfile(dynlib_path)
    LIBPACOSAKO[] = Libdl.dlopen(dynlib_path)
    @info "Using local copy of libpacosako at $dynlib_path"
  else
    path = joinpath(artifact"libpacosako", "libpacosako")
    LIBPACOSAKO[] = Libdl.dlopen(path)
  end
end

end # module JtacPacoSako
