using DiffEqBase: numargs
using StaticArrays: SVector, push
using ForwardDiff


"""
Fixed point bifurcation problem.

See also: [`AbstractContinuationProblem`](@ref)

# Fields
* `homotopy::Function`:
  A function to compute ``H(x, t)`` where ``H`` is a homotopy
  ``H: \\mathbb R^N \\times \\mathbb R \\to \\mathbb R^N``.
  Function `homotopy` must be callable in one of the following form:
  `homotopy(x, p, t) ↦ H` (return `H`) for mutable state type or
  `homotopy(H, x, p, t)` (mutate `H`) for immutable state type.
* `homotopy_jacobian::Union{Function, Nothing}`:
  A function to compute ``H(x, t)`` and its Jacobian
  ``J = \\partial H / \\partial (x, t) \\in \\mathbb R^{N \\times (N+1)}``.
  Function `homotopy_jacobian` must be callable in one of the following form:
  `homotopy_jacobian(x, p, t) ↦ (H, J)` (return `(H, J)`) or
  `homotopy_jacobian(H, J, x, p, t)` (mutate `H` and `J`).
* `u0::Union{AbstractArray, Real}`: Initial state.
* `t0::Real`: Initial parameter.
* `t_domain::Tuple{<:Real, <:Real}`: Range of the parameter.
* `p`: Model parameter (constants).
"""
struct FixedPointBifurcationProblem{iip,
                                    tkind <: TimeKind,
                                    HJ, H, U, T, P,
                                    } <: AbstractContinuationProblem
    homotopy_jacobian::HJ
    homotopy::H
    u0::U
    t0::T
    t_domain::Tuple{T, T}
    p::P

    # TODO: Define domain for u.  Maybe use Domains.jl?

    function FixedPointBifurcationProblem{iip, tkind}(
            homotopy::H, u0::U, t0::Real, t_domain::Tuple,
            p::P = nothing;
            homotopy_jacobian::HJ = nothing,
            ) where{iip, tkind, HJ, H, U, P}
        T = promote_type(typeof(t0), map(typeof, t_domain)...)
        new{iip, tkind, HJ, H, U, T, P}(
            homotopy_jacobian, homotopy,
            u0, t0, t_domain, p)
    end
end

TimeKind(::Type{<: FixedPointBifurcationProblem{_, tkind}}) where {_, tkind} =
    tkind()

const FPBPWithHJac{iip, tkind} =
    FixedPointBifurcationProblem{iip, tkind, <: Function}
const FPBPNoHJac{iip, tkind} =
    FixedPointBifurcationProblem{iip, tkind, Void}
const FPBPScalar{tkind <: TimeKind} =
    FixedPointBifurcationProblem{false, tkind, HJ, H, <: Real} where {HJ, H}

function FixedPointBifurcationProblem(tkind::TimeKind,
                                      homotopy, args...; kwargs...)
    iip = numargs(homotopy) == 4
    return FixedPointBifurcationProblem{iip, tkind}(
        homotopy, args...; kwargs...)
end

as_immutable_state(x::Tuple) = SVector(x)
as_immutable_state(x::Number) = x

function FixedPointBifurcationProblem(tkind::TimeKind,
                                      homotopy,
                                      u0::Union{Tuple, Number},
                                      args...; kwargs...)
    return FixedPointBifurcationProblem{false, tkind}(
        homotopy,
        as_immutable_state(u0),
        args...; kwargs...)
end


struct FixedPointBifurcationCache{P, C} <: AbstractProblemCache{P}
    prob::P
    cfg::C

    FixedPointBifurcationCache(prob::P) where {P <: FPBPWithHJac} =
        new{P, Void}(prob)

    function FixedPointBifurcationCache(prob::P) where {P <: FPBPNoHJac{true}}
        x = get_u0(prob)
        y = similar(x, length(x) - 1)
        cfg = ForwardDiff.JacobianConfig((y, x) -> residual!(y, x, prob),
                                         y, x)
        return new{P, typeof(cfg)}(prob, cfg)
    end

    function FixedPointBifurcationCache(prob::P) where {P <: FPBPNoHJac{false}}
        x = get_u0(prob)
        cfg = ForwardDiff.JacobianConfig((x) -> residual!(nothing, x, prob),
                                         x)
        return new{P, typeof(cfg)}(prob, cfg)
    end
end

TimeKind(::Type{<: FixedPointBifurcationCache{P}}) where P = TimeKind(P)

get_prob_cache(prob::FixedPointBifurcationProblem) =
    FixedPointBifurcationCache(prob)

get_u0(prob::FixedPointBifurcationProblem) = _get_u0(prob, prob.u0)

function _get_u0(prob::FixedPointBifurcationProblem, ::AbstractVector)
    u0 = similar(prob.u0, length(prob.u0) + 1)
    u0[1:end-1] = prob.u0
    u0[end] = prob.t0
    return u0
end

function _get_u0(prob::FixedPointBifurcationProblem, ::Real)
    return SVector(prob.u0, prob.t0)
end

function _get_u0(prob::FixedPointBifurcationProblem, ::SVector)
    return push(prob.u0, prob.t0)
end

residual!(H, u, cache::_C{<: FixedPointBifurcationProblem}) =
    residual!(H, u, cache.prob)

function isindomain(u, cache::_C{<: FixedPointBifurcationProblem})
    t = u[end]
    tmin, tmax = cache.prob.t_domain
    return tmin <= t <= tmax
end

# ----------------------------------------------------------- inplace interface

function residual!(H, u, prob::FixedPointBifurcationProblem{true})
    x = @view u[1:end-1]
    t = u[end]
    prob.homotopy(H, x, prob.p, t)
    return H
end

function residual_jacobian!(H, J, u, cache::_C{<: FPBPWithHJac{true}})
    prob = cache.prob
    x = @view u[1:end-1]
    t = u[end]
    prob.homotopy_jacobian(H, J, x, prob.p, t)
    return (H, J)
end

function residual_jacobian!(H, J, u, cache::_C{<: FPBPNoHJac{true}})
    ForwardDiff.jacobian!(
        J,
        (y, x) -> residual!(y, x, cache),
        H,  # y
        u,  # x
        cache.cfg,
    )
    return (H, J)
end

# ------------------------------------------------------ out-of-place interface

function residual!(::Any, u, prob::FPBPScalar)
    x = u[1]
    t = u[end]
    return SVector(prob.homotopy(x, prob.p, t))
end

function residual!(::Any, u, prob::FixedPointBifurcationProblem{false})
    x = u[1:end-1]
    t = u[end]
    return prob.homotopy(x, prob.p, t)
end

function residual_jacobian!(_H, _J, u, cache::_C{<: FPBPWithHJac{false}})
    prob = cache.prob
    x = u[1:end-1]
    t = u[end]
    return prob.homotopy_jacobian(x, prob.p, t)
end

function residual_jacobian!(_H, _, u, cache::_C{<: FPBPNoHJac{false}})
    # TODO: Can I compute H and J in one go?  Or is it already
    # maximally efficient?
    H = residual!(_H, u, cache)
    J = ForwardDiff.jacobian(
        (x) -> residual!(_H, x, cache),
        u,  # x
        cache.cfg,
    )
    return (H, J)
end
