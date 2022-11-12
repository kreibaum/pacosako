# A simple handwritten AI. Our first one. It is a rating function to be used
# in the MCST algorithm.

using .Game: AbstractGame, policy_length
using .Model: AbstractModel, uniform_policy

"""
This model returns the value from the rating function and a uniform distribution
on the actions (unless a paco sequence is determined).
"""
struct Luna <: AbstractModel{PacoSako,false} end

function Model.assist(model :: Luna, game :: PacoSako)

    if Game.is_over(game)
        value = Game.status(game)
        return (; value)
    end

    seqs = find_paco_sequences(game)
    if length(seqs) > 0
        value = 1
        actions = [s[1] for s in seqs]

        policy = zeros(policy_length(game))
        policy[actions] .= 1 / length(actions)

        return (; value, policy)
    end

    if is_sako_for_other_player(game)
      return (value = -0.5, )
    end

    (;)
end

function Model.apply(model::Luna, game::PacoSako)

    hint = Model.assist(model, game)
    value = get(hint, :value, 0)
    policy = get(hint, :policy, uniform_policy(policy_length(game)))

    # See how many tiles we can attack
    # Doesn't seem to help at all.
    # value += 0.4 * my_threat_count(game) / 64.0

    return (; value, policy)
end

Base.copy(m::Luna) = m

Base.show(io::IO, m::Luna) = print(io, "Luna()")

