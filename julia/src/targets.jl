
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

Target.defaultlossfunction(:: SakoTarget) = :sumabs2

function blockedpawns(ps:: PacoSako) :: Vector{Float32}
    buf = zeros(Float32, 128)
    @pscall(
        :blocked_pawns_target,
        Int64,
        (Ptr{Nothing}, Ptr{Float32}, Int64),
        ps.ptr,
        buf,
        length(buf)
    )

   buf
end

struct BlockedPawnsTarget <: AbstractTarget{PacoSako} end

Base.length(:: BlockedPawnsTarget) = 128

function Target.label(:: BlockedPawnsTarget, ctx :: LabelContext{PacoSako})
    blockedpawns(ctx.game)
end

Target.defaultactivation(:: BlockedPawnsTarget) = :sigmoid

Target.defaultlossfunction(:: BlockedPawnsTarget) = :sumabs2