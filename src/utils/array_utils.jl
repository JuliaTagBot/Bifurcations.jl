module ArrayUtils

using Base: typename

using LinearAlgebra
using LinearAlgebra: QRPackedQ, LQPackedQ, BlasFloat

using ForwardDiff: Dual
using StaticArrays: SVector, SMatrix, StaticArray, Size, similar_type
using ArrayInterface: ismutable

container_array_of(::SVector{S}) where {S} = SVector{S}
container_array_of(::SMatrix{S1, S2}) where {S1, S2} = SMatrix{S1, S2}
container_array_of(::Array{T, N}) where {T, N} = Array{<:Any, N}

cast_container(::Type{A}, v::A) where {A <: AbstractArray} = v

function cast_container(::Type{A}, v) where {A <: AbstractArray}
    constructor = typename(A).wrapper  # e.g., Array
    return constructor(v)
end

cast_container(::Type{<:SubArray{T, N, P}}, v) where {T, N, P} =
    cast_container(P, v)

@generated function cast_container(::Type{<: SVector{S}},
                                   v::AbstractArray{T},
                                   ) where {S, T}
    values = [:(v[$i]) for i in 1:S]
    quote
        SVector{$S, $T}($(values...))
    end
end

_eigvals(A) = eigvals(A)
_eigvals(A::SMatrix) = eigvals(Array(A))
# Workaround: Only hermitian matrices are diagonalizable by *StaticArrays*.

_eig(A) = eigen(A)
_eig(A::SMatrix) = eigen(Array(A))
_eig(A::Adjoint) = eigen(Array(A))

function _similar(x::AbstractArray, dims...)
    y = parent(x)
    if typeof(x) === typeof(y)
        return similar(x, dims)
    else
        return _similar(y, dims...)
    end
end
_similar(x::LinearAlgebra.AbstractQ, dims...) = _similar(x.factors, dims...)
_similar(x::StaticArray, dims...) = _zeros(x, dims...)
_zeros(x::AbstractArray{T}, dims...) where T = fill!(similar(x, T, dims), zero(T))
_zeros(x::StaticArray, dims...) = zeros(similar_type(x, Size(dims)))

const AnyDual = Dual{T, V, N} where {T, V, N}

badeltype(::AbstractArray{T}) where {T} = T in (Any, AnyDual)

fixeltype(::Type{T}, v::AbstractArray{T}) where {T} = v

@generated function fixeltype(::Type{E},
                              v::SVector{S, Any},
                              ) where {E, S}
    values = [:(v[$i]) for i in 1:S]
    quote
        SVector{$S, $E}($(values...))
    end
end

#=
@generated function fixeltype(::Type{E}, M::SMatrix) where {E}
    s = Size(M)
    S1 = s[1]
    S2 = s[2]
    L = S1 * S2
    values = [:(M[$i]) for i in 1:L]
    quote
        SMatrix{$S1, $S2, $E}($(values...))
    end
end
=#

isalmostzero(xs::AbstractArray, atol) = all(x -> isalmostzero(x, atol), xs)
isalmostzero(x, atol) = abs(x) < atol

zero_if_nan(x) = isnan(x) ? zero(x) : x

@inline function eye!(A)
    A .= 0
    for i in 1:min(size(A)...)
        @inbounds A[i, i] = 1
    end
    A
end

function _lq!(A::SMatrix)
    Q, R = qr(A')
    return (LowerTriangular(R'), Q')
end

function _lq!(A)  # for CuAarray
    Q, R = qr(A')
    return (UpperTriangular(R)', Q')
end

function _lq!(A::Matrix{<:BlasFloat})
    L, Q = lq!(A)
    return (LowerTriangular(L), Q)
end

_det(Q) = det(Q)
# https://github.com/JuliaLang/julia/pull/32887
_det(Q::Union{QRPackedQ{T}, LQPackedQ{T}}) where {T <: Real} =
    isodd(count(!iszero, Q.τ)) ? -1 : 1
_det(Q::Transpose) = _det(Q.parent)
_det(Q::Adjoint) = adjoint(_det(Q.parent))

@inline foldlargs(op, x) = x
@inline foldlargs(op, x1, x2, xs...) = foldlargs(op, op(x1, x2), xs...)

bottomrow(M::AbstractArray) = @view M[end:end, :]
bottomrow(M::SMatrix{S1, S2}) where {S1, S2} =
    SMatrix{1, S2}(
        foldlargs((), ntuple(identity, S2)...) do xs, i
            (xs..., @inbounds M[S1, i])
        end
    )

popbottomright(A) = A[1:end-1, 1:end-1]
popbottomright(A::Adjoint) = popbottomright(A')'
popbottomright(A::LowerTriangular) = LowerTriangular(popbottomright(parent(A)))
popbottomright(A::UpperTriangular) = UpperTriangular(popbottomright(parent(A)))

function popbottomright(A::SMatrix{S1,S2}) where {S1,S2}
    xs = foldlargs((), ntuple(identity, S2 - 1)...) do xs, j
        foldlargs(xs, ntuple(identity, S1 - 1)...) do xs, i
            (xs..., @inbounds A[i, j])
        end
    end
    return SMatrix{S1 - 1,S2 - 1}(xs)
end

function _normalize!(x)
    normalize!(x)
    return x
end

_normalize!(x::SVector) = x ./ norm(x)

canonicalize(x::AbstractVector{<: Real}) = normalize(x)

"""
    canonicalize(x::AbstractVector) -> y

Normalize `x` then rotate the complex phase so that `real(y)` and
`imag(y)` are orthogonal.  It is equivalent to `normalize(x)` if `x`
is a real vector.
"""
function canonicalize(x::AbstractVector{<: Complex};
                      atol = eps(real(eltype(x))))
    x = normalize(x)
    num = x ⋅ conj(x)
    if abs(num) < atol
        return x
    end
    r = num / conj(num)
    return r^(1/4) .* x
end

# TODO: use \ instead of A_ldiv_B!
_A_ldiv_B!(A, B::T) where T = _A_ldiv_B!(T, A, B)
_A_ldiv_B!(Y, A, B::T) where T = _A_ldiv_B!(T, Y, A, B)

_A_ldiv_B!(::Type{<: SubArray{T, N, P}}, args...) where {T, N, P} =
    _A_ldiv_B!(P, args...)
_A_ldiv_B!(::Type{<: LowerTriangular{T, P}}, args...) where {T, P} =
    _A_ldiv_B!(P, args...)
_A_ldiv_B!(::Type{<: UpperTriangular{T, P}}, args...) where {T, P} =
    _A_ldiv_B!(P, args...)

_A_ldiv_B!(::Type{<:AbstractArray}, A, B) = A_ldiv_B!(A, B)
_A_ldiv_B!(::Type{<:StaticArray}, A, B) = A \ B
_A_ldiv_B!(::Type{<:Vector}, A::SubArray, B) =  A \ B # TODO: make it in-place
_A_ldiv_B!(::Type{<:AbstractArray}, Y, A, B) = A_ldiv_B!(Y, A, B)
_A_ldiv_B!(::Type{<:StaticArray}, _, A, B) = A \ B

"""
    nan_(aggregator, v[, region])
    nan_(aggregator, f::Function, v)

Example: `nan_(mean, v)` computes the average of `v` ignoring all `NaN` values.

* https://discourse.julialang.org/t/nanmean-options/4994/2
* https://discourse.julialang.org/t/nanmean-options/4994/6
"""
nan_(aggregator, v::AbstractArray) = aggregator(filter(!isnan, v))
nan_(aggregator, v) = aggregator(Iterators.filter(!isnan, v))
nan_(aggregator, f::Function, v) = nan_(x -> aggregator(f, x), v)
nan_(aggregator, v, region) = mapslices(v -> nan_(aggregator, v), v,
                                        dims = region)

end  # module
