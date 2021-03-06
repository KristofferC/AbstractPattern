using AbstractPattern
using AbstractPattern.BasicPatterns

const backend = MK(RedyFlavoured)
"""
[a, b..., c] -> :vec3 => [a], b, [c]
[a, b, c]    -> :vec => [a, b, c]
"""
function ellipsis_split(args::AbstractArray{T, 1}) where T
    ellipsis_index = findfirst(args) do arg
        Meta.isexpr(arg, :...)
    end
    if isnothing(ellipsis_index)
        Val(:vec) => args
    else
        Val(:vec3) => (
            args[1:ellipsis_index-1],
            args[ellipsis_index].args[1],
            args[ellipsis_index+1:end]
        )
    end
end

function P_partial_struct_decons(t, partial_fields, ps, prepr::AbstractString="$t")
    function tcons(_...)
        t
    end
    comp = PComp(
        prepr, tcons;
    )
    function extract(sub, i::Int)
        :($sub.$(partial_fields[i]))
    end
    decons(comp, extract, ps)
end

basic_ex2tf(eval::Function, a) =
    isprimitivetype(typeof(a)) ? literal(a) : error("invalid literal $a")
basic_ex2tf(eval::Function, l::LineNumberNode) = wildcard
basic_ex2tf(eval::Function, q::QuoteNode) = literal(q)
basic_ex2tf(eval::Function, s::String) = literal(s)
basic_ex2tf(eval::Function, n::Symbol) =
    n === :_ ?  wildcard : P_capture(n)

Base.@pure function qt2ex(ex::Any)
    if ex isa Expr
        Meta.isexpr(ex, :$) && return ex.args[1]
        Expr(:call, Expr, QuoteNode(ex.head), Expr(:vect, (qt2ex(e) for e in ex.args)...))
    elseif ex isa Symbol
        QuoteNode(ex)
    else
        ex
    end
end

function basic_ex2tf(eval::Function, ex::Expr)
    !(x) = basic_ex2tf(eval, x)
    hd = ex.head; args = ex.args; n_args = length(args)
    if hd === :||
        @assert n_args === 2
        l, r = args
        or(!l, !r)
    elseif hd === :&&
        @assert n_args === 2
        l, r = args
        and(!l, !r)

    elseif hd === :if
        @assert n_args === 2
        cond = args[1]
        guard() do _, scope, _
            see_captured_vars(cond, scope)
        end
    elseif hd === :&
        @assert n_args === 1
        val = args[1]
        guard() do target, scope, _
            see_captured_vars(:($target == $val), scope)
        end
    elseif hd === :let
        bind = args[1]
        @assert bind isa Expr
        if bind.head === :(=)
            @assert bind.args[1] isa Symbol
            P_bind(bind.args[1], bind.args[2], see_capture=true)
        else
            @assert bind.head === :block
            binds = Function[P_bind(arg.args[1], arg.args[2], see_capture=true) for arg in bind.args]
            push!(binds, wildcard)
            and(binds)
        end
    elseif hd === :(::)
        if n_args === 2
            p, ty = args
            ty = eval(ty)::TypeObject
            and(P_type_of(ty), !p)
        else
            @assert n_args === 1
            p = args[1]
            ty = eval(ty)::TypeObject
            P_type_of(ty)
        end
    elseif hd === :vect
        tag, split = ellipsis_split(args)
        return tag isa Val{:vec} ?
            P_vector([!e for e in split]) :
            let (init, mid, tail) = split
                P_vector3(
                    [!e for e in init],
                    !mid,
                    [!e for e in tail]
                )
            end
    elseif hd === :tuple
        P_tuple([!e for e in args])
    elseif hd === :call
        let f = args[1],
            args′ = view(args, 2:length(args))
            n_args′ = n_args - 1
            t = eval(f)
            if t === Core.svec
                tag, split = ellipsis_split(args′ )
                return tag isa Val{:vec} ?
                    P_svec([!e for e in split]) :
                    let (init, mid, tail) = split
                        P_svec3(
                            [!e for e in init],
                            !mid,
                            [!e for e in tail]
                        )
                    end
            end
            all_field_ns = fieldnames(t)
            partial_ns = Symbol[]
            patterns = Function[]
            if n_args′ >= 1 && Meta.isexpr(args′[1], :parameters)
                kwargs = args′[1].args
                args′ = view(args′, 2:length(args′))
            else
                kwargs = []
            end
            if length(all_field_ns) === length(args′)
                append!(patterns, [!e for e in args′])
                append!(partial_ns, all_field_ns)
            elseif length(all_field_ns) !== 0
                error("count of positional fields should be 0 or the same as the fields($all_field_ns)")
            end
            for e in kwargs
                if e isa Symbol
                    e in all_field_ns || error("unknown field name $e for $t when field punnning.")
                    push!(partial_ns, e)
                    push!(patterns, P_capture(e))
                elseif Meta.isexpr(e, :kw)
                    key, value = e.args
                    key in all_field_ns || error("unknown field name $key for $t when field punnning.")
                    @assert key isa Symbol
                    push!(partial_ns, key)
                    push!(patterns, and(P_capture(key), !value))
                end
            end
            P_partial_struct_decons(t, partial_ns, patterns)
        end
    elseif hd === :quote
        !qt2ex(args[1])
    else
        error("not implemented expr=>pattern rule for '($hd)' Expr.")
    end
end

const case_sym = Symbol("@case")
"""a minimal implementation of switch
"""
macro switch(val, ex)
    @assert Meta.isexpr(ex, :block)
    clauses = Union{LineNumberNode, Pair{<:Function, Symbol}}[]
    body = Expr(:block)
    alphabeta = 'a':'z'
    base = gensym()
    k = 0
    for i in eachindex(ex.args)
        stmt = ex.args[i]
        if Meta.isexpr(stmt, :macrocall) &&
           stmt.args[1] === case_sym &&
           length(stmt.args) == 3

            pattern = basic_ex2tf(__module__.eval, stmt.args[3])
            br :: Symbol = Symbol(alphabeta[i % 26], i <= 26 ? "" : string(i), base)
            push!(clauses,  pattern => br)
            push!(body.args, :(@label $br))
        else
            if stmt isa LineNumberNode
                push!(clauses, stmt)
            end
            push!(body.args, stmt)
        end
    end
    
    match_logic = backend(val, clauses, __source__)
    esc(Expr(
        :block,
        match_logic,
        body
    ))
end


val = 1
@switch val begin
    @case 1
        println("case 1!")
        return
    @case _
        println("case 2!")
        return
end

val = [1, 2, 3, 4]
@switch val begin
    @case (1, 2, a)
        println("emmmm")
        return
    @case [1, (b::AbstractArray{Int, 1})..., 4]
        println("b:", b, " sum(b):", sum(b))
        return
end


@switch :(a = (1, 2, 3)) begin
    @case :(a = (1, $(b...)))
        println(b)
        return
end

@switch (1, 5) begin
    @case (1, 2)
        println(b)
        return
    @case (a, &(a + 4)) && let x = Int[a, 1], x = x .+ a end
        println("this run ", x)
        return
end

@switch Tuple{Int, Int}.parameters begin
    @case Core.svec(a, b)
        println(a, b)
        return
end


@switch :(&ooo) begin
    @case :(&$a)
        println(a)
        return
end



# import MLStyle
# import Match
# import Rematch

# function f_rematch(value)
#     Rematch.@match value begin    
#         _::String => :string
#         (2, a, 3) => (:some_tuple, a)
#         [1, a..., 3, 4] => (:some_vector, a)
#     end
# end

# function f_match(value)
#     Match.@match value begin    
#         _::String => :string
#         (2, a, 3) => (:some_tuple, a)
#         [1, a..., 3, 4] => (:some_vector, a)
#     end
# end

# function f_mlstyle(value)
#     Rematch.@match value begin    
#         _::String => :string
#         (2, a, 3) => (:some_tuple, a)
#         [1, a..., 3, 4] => (:some_vector, a)
#     end
# end

# function f_this(value)
#     @switch value begin
#     @case _::String
#         return :string
#     @case (2, a, 3) 
#         return (:some_tuple, a)
#     @case [1, a..., 3, 4]
#         return (:some_vector, a)
#     end
# end

# using BenchmarkTools
# data = [
#     "asda",
#     (2, 1 ,3),
#     [1, 2, 2, 3, 4]
# ]

# fs = [f_rematch, f_match, f_mlstyle, f_this]

# for datum in data
#     for f in fs
#         @info :testing f datum
#         println(@btime $f($datum))
#     end
#     println("===================")
# end
