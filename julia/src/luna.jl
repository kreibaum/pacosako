# A simple handwritten AI. Our first one. It is a rating function to be used
# in the MCST algorithm.

# This implements a Model.

using JtacPacoSako

using .Game: AbstractGame, policy_length
using .Model: AbstractModel, uniform_policy

"""
This model returns the value from the rating function and a uniform distribution on the actions.
"""
struct RatingModel <: AbstractModel{PacoSako,false} end

function Model.apply(model::RatingModel, game::PacoSako)
    value = 0
    policy = uniform_policy(policy_length(game))

    if Game.is_over(game)
        value = Game.status(game)
        return (; value, policy)
    end

    # Check if we can Paco the opponent
    seq = find_sako_sequences(game)
    if length(seq) > 0
        value = 1
        action = seq[1][1]

        policy = zeros(Game.policy_length(game))
        policy[action] = 1

        return (; value, policy)
    end

    # Check if we are in Ŝako
    if is_sako_for_other_player(game)
        value = -0.3
        return (; value, policy)
    end

    return (; value, policy)
end

Base.copy(m::RatingModel) = m

Base.show(io::IO, m::RatingModel) = print(io, "RatingModel()")
