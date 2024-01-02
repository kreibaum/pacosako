
"""
Module that wraps the rust pacosako library and makes it accessible to Jtac,
which is Alpha Zero inspired boardgame training package.

!!! To use this package, you currently have to manually run
!!! `cargo build --release` in the folder `../lib`.
"""
module JtacPacoSako

using Artifacts
import Libdl

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


function __init__()
  dynlib_path = if haskey(ENV, "LIBPACOSAKO")
    ENV["LIBPACOSAKO"]
  else
    joinpath(dirname(@__DIR__), "../lib/target/release/libpacosako.so")
  end

  if isfile(dynlib_path)
    LIBPACOSAKO[] = Libdl.dlopen(dynlib_path)
    @info "Using local copy of libpacosako: $dynlib_path"
  else
    path = joinpath(artifact"libpacosako", "libpacosako")
    LIBPACOSAKO[] = Libdl.dlopen(path)
  end

end


end # module JtacPacoSako
