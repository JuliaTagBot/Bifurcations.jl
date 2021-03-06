import ..BifurcationsBase


dim_ds_state(sweep::Codim1LCSweep) = length(sweep.eigvals[1])  # TODO: don't


abstract type AbstractLimitCycleData end

struct LimitCycleData{M, R, V, P} <: AbstractLimitCycleData
    state::M
    period::R
    param_value::V
    prob::P
end

BifurcationsBase.problem_of(lc::LimitCycleData) = lc.prob
BifurcationsBase.contkind(lc::LimitCycleData) = contkind(lc.prob)  # TODO: don't

LimitCycleData(u::AbstractVector, n::Integer, prob) =
    LimitCycleData(
        reshape((@view u[1:end-2]), n, :),
        u[end - 1],  # period
        u[end],      # param_value
        prob,
    )

function limitcycles(sweep::Codim1LCSweep)
    n = dim_ds_state(sweep)
    u_list = as(sweep, ContinuationSweep).u
    sol = as(sweep, ContinuationSweep).sol.value  # TODO: don't
    if sol !== nothing
        prob = sol.prob
    else
        prob = nothing
    end
    return LimitCycleData.(u_list, (n,), (prob,))
end

limitcycles(sol::Codim1LCSolution) = vcat(limitcycles.(sol.sweeps)...)
limitcycles(solver::Codim1LCSolver) = limitcycles(solver.sol)


function BifurcationsBase.measure(lc::AbstractLimitCycleData, i::Integer)
    state = @view lc.state[i, :]
    xs = similar(state, length(state) + 1)
    copyto!(xs, state)
    xs[end] = state[1]
    return xs
end

# TODO: make it more type-based
function BifurcationsBase.measure(lc::LimitCycleData, key::Symbol)
    if key in (:p1, :parameter)
        return lc.param_value
    elseif key == :period
        return lc.period
    end
    error("Unsupported key: $key")
end


abstract type LCMeasurement end

struct GenericMeasurement{F} <: LCMeasurement
    f
end

(key::GenericMeasurement)(lc::LimitCycleData) = key.f(lc)

"""
Coordinate-wise measurement of the state.
"""
struct CWStateMeasurement{F} <: LCMeasurement
    index::Int
    f::F
end

(key::CWStateMeasurement)(lc::LimitCycleData) =
    key.f(@view lc.state[key.index, :])

function BifurcationsBase.measure(sweep::Codim1LCSweep, key::LCMeasurement)
    return key.(limitcycles(sweep))
end

# TODO: make it more type-based
function BifurcationsBase.measure(sweep::Codim1LCSweep, key::Symbol)
    u_list = as(sweep, ContinuationSweep).u
    if key in (:p1, :parameter)
        return [u[end] for u in u_list]
    elseif key == :period
        return [u[end - 1] for u in u_list]
    end
    error("Unsupported key: $key")
end


#=
period_extrema(ctx) = nan_(extrema, lc.period for lc in limitcycles(ctx))
=#
