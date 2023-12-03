
using .Game: AbstractGame
using .Model: AbstractModel

"""
Model that returns the value obtained via a simple rating function that takes
sako sequences into account. Always returns a uniform policy distribution unless
a paco sequence is determined.
"""
struct Luna <: AbstractModel{PacoSako} end

function Model.assist(model :: Luna, game :: PacoSako)
  if Game.isover(game)
    value = Game.status(game)
    return (value = Float32(value))
  end

  chains = sakochains(game)
  if length(chains) > 0
    value = 1
    actions = [s[1] for s in chains]
    policy = zeros(Game.policylength(game))
    policy[actions] .= 1 / length(actions)
    return (; value, policy)
  end

  if sakothreat(game)
    return (value = -0.5, )
  end

  # If we arrive here, Luna can say nothing useful about the game state
  (;)
end

function Model.apply(model :: Luna, game :: PacoSako; targets = (:value, :policy))
  @assert issubset(targets, [:value, :policy]) """
  Luna model can only evaluate targets :value and :policy.
  """
  hint = Model.assist(model, game)
  value = get(hint, :value, 0)

  if haskey(hint, :policy)
    policy = hint.policy
  else
    policy = ones(Float32, Game.policylength(game))
    policy ./= length(policy)
  end

  # See how many tiles we can attack
  # Doesn't seem to help at all.
  # value += 0.4 * attackcount(game) / 64.0

  return (; value, policy)
end

Base.copy(m::Luna) = m

Base.show(io::IO, m::Luna) = print(io, "Luna()")

