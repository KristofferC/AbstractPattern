@nospecialize
export TagfulPattern, And, Or,
       Literal, Wildcard, Capture,
       Deconstrucution, Guard, Effect,
       untagless, TagfulPattern,
       PatternInfo

abstract type TagfulPattern end


struct PatternInfo
    pattern ::TagfulPattern
    metatag :: Union{Nothing, LineNumberNode}
    typetag :: TypeObject
end

struct And <: TagfulPattern
    ps :: Vector{PatternInfo}
end

struct Or <: TagfulPattern
    ps :: Vector{PatternInfo}
end

struct Literal{T} <: TagfulPattern
    val :: T
end

struct Wildcard <: TagfulPattern
end

struct Capture <: TagfulPattern
    n :: Union{String, Symbol}
end

struct Deconstrucution <: TagfulPattern
    recog :: Recogniser
    params :: Vector{PatternInfo}
end

struct Guard <: TagfulPattern
    predicate :: Any
end

struct Effect <: TagfulPattern
    perform :: Any
end

@specialize
function _uncurry_call_argtail(f)
    function (_, args...)
        f(args...)
    end
end
@nospecialize

function untagless(points_of_view::Dict{Any, Int})
    myviewpoint = points_of_view[untagless]
    metaviewpoint = points_of_view[term_position]
    typetag_viewpoint = points_of_view[tag_extract]
    mk_info(all_info)::PatternInfo = PatternInfo(
        all_info[[myviewpoint, metaviewpoint, typetag_viewpoint]]...
    )
    ! = mk_info
    (
        and = (_, ps) -> And(PatternInfo[!e for e in ps]),
        or= (_, ps) -> Or(PatternInfo[!e for e in ps]),
        literal = _uncurry_call_argtail(Literal),
        wildcard = _uncurry_call_argtail(Wildcard),
        capture = _uncurry_call_argtail(Capture),
        decons = (_, recog, ps) -> Deconstrucution(recog, PatternInfo[!p for p in ps]),
        guard = _uncurry_call_argtail(Guard),
        effect = _uncurry_call_argtail(Effect),
        metadata = (_, term, _) -> term[myviewpoint]
    )
end
@specialize    