
"""
Target which labels if [`issako`](@ref) evaluates to `true`.
"""
struct SakoTarget <: AbstractTarget{PacoSako} end

Base.length(:: SakoTarget) = 1

function Target.label(:: SakoTarget, ctx :: LabelContext{PacoSako})
  sako = issako(ctx.game)
  Float32[sako]
end

Target.defaultactivation(:: SakoTarget) = :tanh
