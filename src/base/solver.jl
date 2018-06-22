import ..Continuations: step!, new_sweep!
using ..Continuations: AbstractContinuationSolver, ContinuationOptions,
    SweepSetup

abstract type BifurcationCache{PC} <: AbstractContinuationCache{PC} end

struct BifurcationSolver{
        R <: ContinuationSolver,
        P <: BifurcationProblem,
        C <: BifurcationCache,
        S <: BifurcationSolution,
        } <: AbstractContinuationSolver
    super::R
    prob::P
    opts::ContinuationOptions
    cache::C
    sol::S
end

function BifurcationSolver(prob::BifurcationProblem,
                           opts::ContinuationOptions)
    super = ContinuationSolver(prob, opts)
    cache = BifurcationCache(prob, super.cache)
    sol = BifurcationSolution(super.sol, sweeptype(prob, super))
    return BifurcationSolver(super, prob, opts, cache, sol)
end


function step!(solver::BifurcationSolver)
    step!(solver.super)
    # calling [[../continuations/solver.jl::step!]]

    analyze!(solver.cache, solver.opts)
    record!(solver.sol, solver.cache)
    check_sweep_length(solver.sol.sweeps[end])
end


function new_sweep!(solver::BifurcationSolver, setup::SweepSetup)
    new_sweep!(solver.super, setup)
    # calling [[../continuations/solver.jl::new_sweep!]]

    allocate_sweep!(solver.sol, as(solver, ContinuationSolver))

    for u in setup.past_points
        re_analyze!(solver, u)
    end
    re_analyze!(solver, setup.u0)
    check_sweep_length(solver.sol.sweeps[end])
end
# TODO: `new_sweep!(solver.super, setup)` sets up `solver.super.cache`
# but `re_analyze!(solver, u)` rewrites the cache.  It causes no
# problem at the moment since the last `re_analyze!(solver, setup.u0)`
# set the cache back to the first state.


function allocate_sweep!(sol::BifurcationSolution, solver::ContinuationSolver)
    super = as(sol, ContinuationSolution)
    sweep = BifurcationSweep(super.sweeps[end], solver)
    push!(sol.sweeps, sweep)
end


function push_special_point!(sweep::BifurcationSweep,
                             cache::BifurcationCache)
    push_special_point!(sweep,
                        cache.point_type,
                        as(cache, ContinuationCache).J)
end

function push_special_point!(sweep::BifurcationSweep,
                             point_type,
                             J1)
    super = as(sweep, ContinuationSweep)
    point = SpecialPointInterval(
        timekind(sweep),
        point_type,
        length(sweep),
        super.u[end - 1],
        super.u[end],
        J1,
        WeakRef(sweep),
    )
    push!(sweep.special_points, point)
end

"""
    is_special(point_type) :: Bool
"""
is_special(point_type::T) where T = point_type != regular_point(T)

function record!(sol::BifurcationSolution, cache::BifurcationCache)
    super = as(cache, ContinuationCache)
    sweep = sol.sweeps[end]
    push!(sweep.jacobians, copy(super.J))
    push!(sweep.eigvals, copy(cache.eigvals))

    if is_special(cache.point_type)
        push_special_point!(sweep, cache)
    end
end