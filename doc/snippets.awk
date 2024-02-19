# Parse a string str as a possible symbol name and return number of matches.
# 1. If string is invalid, return -1 to indicate an error.
# 2. If string looks like a plain symbol name (e.g., "foo"):
#      part[1] := symbol name (root)
#      part[2] := ""
#      Return 1
# 3. If string looks like a symbol with an index (e.g., "foo[bar]"):
#      part[1] := symbol root
#      part[2] := index
#      Return 2
function name_S_parse(str, part,    cnt, i)
{
    if (str !~ /^[^[\]]+(\[[^[\]]+\])?$/) {
        # print("Name '" str "' not valid")
        return ERROR            # -1
    }
    cnt = split(str, part, "(\\[|\\])")
    # print("'" str "' ==> " cnt " fields:")
    # for (i = 1 ; i <= cnt; i++)
    #     print(i " = '" part[i] "'")
    return (cnt == 1) ? 1 : 2
}



## HOWTO Instantiate arguments

    # TODO Instantiate args
    dbg_print(cmd, 5, "NF=" NF)
    for (i = 1; i < NF; i++) {
        dbg_print("cmd", 1, sprintf("(docommand:" dolev ") Binding param %s (in fp %d) to value '%s'",
                                    nametab[cmdname, "", cmd_frame, "param", i],
                                    dolev, $(i+1)))
        name_2_store_sym_value(nametab[cmdname, "", cmd_frame, "param", i], "",
                               dolev, $(i+1))
    }



function ceil(x,    t)
{
    t = int(x)
    return x > t ? t+1 : t
}

function floor(x,    t)
{
    t = int(x)
    return x < t ? t-1 : t
}

function sign(x)
{
    return (x > 0) - (x < 0)
}

function min(m, n)
{
    return m < n ? m : n
}

function max(m, n)
{
    return m > n ? m : n
}

function asin(x)
{
    # untested
    return atan2(x, (1-x^2)^0.5)
}

function acos(x)
{
    # untested
    return atan2((1-x^2)^0.5, x)
}


# TRUE  if name is defined in at least one of the components (logical OR, not sure which)
# FALSE if name is not defined in any of the components at all
function name_defined_in_any_p(name, components,    def)
{
    if (first(name) == "@")
        name = substr(name, 2)
    if (length(name) == 0)
        return FALSE
    def = FALSE
    if (components == TYPE_ANY || index(components, TYPE_CMD))
        def = def || cmd_defined_p(name)
    if (components == TYPE_ANY || index(components, TYPE_FUNCTION))
        def = def || (name in functab)
    if (components == TYPE_ANY || index(components, TYPE_SEQUENCE))
        def = def || seq_defined_p(name)
    if (components == TYPE_ANY || index(components, TYPE_SYMBOL))
        def = def || sym_defined_p(name)
    return def
}



function dbg_message(key, lev, text, file, line)
{
    if (dbg(key, lev))
        print_stderr(format_message(text, file, line))
}
