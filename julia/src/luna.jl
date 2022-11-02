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

function luna_rating(game::PacoSako)
    if Game.is_over(game)
        return Game.status(game)
    end

    return 0
end

function Model.apply(model::RatingModel, game::PacoSako)
    (value=luna_rating(game), policy=uniform_policy(policy_length(game)))
end

Base.copy(m::RatingModel) = m

Base.show(io::IO, m::RatingModel) = print(io, "RatingModel()")
