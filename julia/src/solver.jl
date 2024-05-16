
"""
Jtac model that solves Paco in 1.

This model can only be used as an assistant for a proper model (see
[`Jtac.Model.Assisted`](@ref)).
"""
struct Paco1Solver <: AbstractModel{PacoSako} end

function Model.assist(model :: Paco1Solver, game :: PacoSako)
  chains = sakochains(game)
  if length(chains) > 0
    value = 1
    actions = [s[1] for s in chains]
    policy = zeros(Game.policylength(game))
    policy[actions] .= 1 / length(actions)
    (; value, policy)
  else
    (;)
  end
end
