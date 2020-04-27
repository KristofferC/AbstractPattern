@nospecialize
# term_position is from ./SourcePos.jl and,
# PatternCompilationError is from ../PatternSignature
"""the view point of the type tag for each term
"""
function tag_extract(points_of_view::Dict{Any, Int})
    viewpoint = points_of_view[tag_extract]
    viewpos = points_of_view[term_position]

    function and(me, many)
        @assert !isempty(many)
        ts = getindex.(many, viewpoint)
        t = reduce(typeintersect, ts)
        if t === Base.Bottom
            core_msg = "and patterns require an intersection of $(ts), which seems empty!"
            linenumbernode = me[viewpos]
            throw(PatternCompilationError(linenumbernode, core_msg))
        end
        t
    end

    function or(_, many)
        ts = getindex.(many, viewpoint)
        Union{ts...}
    end

    function literal(_, val)
        typeof(val)
    end

    wildcard(_) = Any
    capture(_, _) = Any

    function decons(me, recog, ns)
        args = getindex.(ns, viewpoint)
        try
            recog.tag(args...)
        catch e
            if e isa MethodError && e.f === recog.tag
                throw(PatternCompilationError(me[viewpos], "invalid arguments for deconstructor $recog"))
            end
            rethrow()
        end
    end

    guard(_, _) = Any
    effect(_, _) = Any
    metadata(_, term, _) = term[viewpoint]

    (
        and = and,
        or = or,
        literal = literal,
        wildcard = wildcard,
        capture = capture,
        decons = decons,
        guard = guard,
        effect = effect,
        metadata = metadata
    )
end
@specialize