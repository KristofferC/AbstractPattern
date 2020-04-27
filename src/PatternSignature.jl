struct PatternCompilationError <: Exception
    line::Union{LineNumberNode,Nothing}
    msg::AbstractString
end


PatternImpl = NamedTuple{
    (:and, :or, :literal, :wildcard, :decons, :guard, :effect, :metadata),
}


PatternImpls = Vector{PatternImpl}

@nospecialize
and(args...) = and(collect(args))
and(ps::Vector) = function apply(impls::PatternImpls)
    xs = [p(impls) for p in ps]
    me = Vector{Any}(undef, length(impls))
    for i in eachindex(me)
        me[i] = impls[i].and(me, xs)
    end
    me
end

or(args...) = or(collect(args))
or(ps::Vector) = function apply(impls::PatternImpls)
    xs = [p(impls) for p in ps]
    me = Vector{Any}(undef, length(impls))
    for i in eachindex(me)
        me[i] = impls[i].or(me, xs)
    end
    me
end
literal(val) = function apply(impls::PatternImpls)
    me = Vector{Any}(undef, length(impls))
    for i in eachindex(me)
        me[i] = impls[i].literal(me, val)
    end
    me
end
function wildcard(impls::PatternImpls)
    me = Vector{Any}(undef, length(impls))
    for i in eachindex(me)
        me[i] = impls[i].wildcard(me)
    end
    me
end

guard(pred) = function apply(impls::PatternImpls)
    me = Vector{Any}(undef, length(impls))
    for i in eachindex(me)
        me[i] = impls[i].guard(me, pred)
    end
    me
end

@specialize
identity_view(target, scope, ln) = target
const no_guard = guard((target, scope, ln) -> true)
invalid_extract(_, _) = error("impossible")

function decons(tcons; guard1=no_guard, view=identity_view, guard2=no_guard, extract=invalid_extract, ps=[])
    decons(tcons, guard1, view, guard2, extract, ps)
end
@nospecialize
decons(tcons, guard1, view, guard2, extract, ps) = function apply(impls::PatternImpls)
    xs = [p(impls) for p in ps]
    me = Vector{Any}(undef, length(impls))
    guard1′ = guard1(impls)
    guard2′ = guard2(impls)

    for i in eachindex(me)
        me[i] = impls[i].decons(me, tcons, guard1′, view, guard2′, extract, xs)
    end
    me
end



effect(ctx_perf) = function apply(impls::PatternImpls)
    me = Vector{Any}(undef, length(impls))
    for i in eachindex(me)
        me[i] = impls[i].effect(me, ctx_perf)
    end
    me
end

function metadata(term, location)
    function apply(impls::PatternImpls)
        x = term(impls)
        me = Vector{Any}(undef, length(impls))
        for i in eachindex(me)
            me[i] = impls[i].metadata(me, x, location)
        end
        me
    end
end
@specialize

const self = (
    and = and,
    or = or,
    literal = literal,
    wildcard = wildcard,
    decons = decons,
    guard = guard,
    effect = effect,
    metadata = metadata,
)
