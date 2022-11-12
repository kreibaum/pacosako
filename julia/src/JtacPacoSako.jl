"""This module wraps the rust pacosako dynamic library"""
module JtacPacoSako

using Jtac

# re-export Jtac Modules
export Jtac,
       Util,
       Pack,
       Game,
       Data,
       Model,
       Player,
       Training

include("pacosako.jl")

include("luna.jl")

# PacoSako game type and Luna Model
export PacoSako,
       Luna

export fen

function __init__()
    # We have to register the game in order to use all functionality of Jtac
    # (loading and saving datasets and models)
    Pack.register(PacoSako)
    Pack.register(Luna)
end

################################################################################
## PacoPlay module to interact with pacoplay servers ###########################
################################################################################

module PacoPlay

  using ..JtacPacoSako
  using HTTP, LazyJSON

  include("pacoplay.jl")

end # module PacoPlay

export PacoPlay

end
