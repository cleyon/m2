#!/usr/bin/awk -f
#*****************************************************************************
#
# NAME
#       m2 - Line oriented macro processor
#
# USAGE
#       m2 [NAME=VAL] [file...]
#       awk -f m2 [file...]
#
# DESCRIPTION
#       M2 copies its input file(s) to its output unchanged except as
#       modified by certain "macro expressions."  The following lines
#       define macros for subsequent processing:
#
#           @comment ...           Comment - line is ignored
#           @@.../@#.../@rem ...   Same as @comment
#           @define NAME VALUE     Set NAME to VALUE
#           @default NAME VALUE    As @define, but only if NAME not already defined
#           @longdef NAME          Define NAME to <lines> until @longend
#             ...                    Don't use other @ commands inside def!
#           @longend                 But simple @VAR@ references should be okay
#           @append NAME MORE      Add to the body of an already defined macro
#           @undefine NAME         Remove definition of NAME
#           @include FILENAME      Read and process FILENAME
#           @paste FILENAME        Read FILENAME literally, do not process any macros
#           @if NAME               Include subsequent text if NAME != 0
#           @unless NAME           Include subsequent text if NAME == 0 (or undefined)
#           @if NAME OP OTHER      Test if NAME compares to OTHER (names or values)
#           @if(not)env ENV        Test if ENV is defined in the environment (or not)
#           @if(not)exists PATH    Test if PATH exists (or not)
#           @if(not)in KEY ARR     Test if symbol ARR[KEY] is defined
#           @else                  Switch to the other branch of an @if statement
#           @fi/@endif             Terminate @if or @unless
#           @incr/@decr NAME [N]   Add or subtract 1 (or N) from an already defined NAME
#           @input [NAME]          Read a single line from keyboard and define NAME
#           @ignore DELIM          Ignore input until line that begins with DELIM
#           @shell DELIM [SHELL]   Read input until DELIM, send to SHELL (default /bin/sh)
#                                    Note: input data is evaluated before being sent to shell
#           @typeout               Print entire remainder of input literally,
#           @warn/@echo STUFF      Send STUFF to standard error, continue
#           @error STUFF           Send STUFF to standard error, exit 2
#           @exit [CODE]           Stop parsing input immediately, exit CODE (default 0)
#           @dump [FILE]           Print defined NAMEs and their definitions
#
#       A definition may extend across many lines by ending each line
#       with a backslash, thus quoting the following newline.
#       Alternatively, use @longdef.  Short macros can be defined on the
#       command line by using the form "NAME=VAL" (or "NAME=" to define
#       with empty value)
#
#       Any occurrence of @name@ in the input is replaced in the output
#       by the corresponding value.  Specifying more than one word in a
#       @aaa bbb ...@ form is used as a crude form of function invocation.
#
#       Macros can expand positional parameters whose actual values will be
#       supplied when the macro is called.  The definition should refer to
#       $1, $2, etc; $0 refers to the name of the macro name itself.
#       Example:
#           @define greet Hello, $1!  I send you $0ings.
#           @greet world@
#               => Hello, world!  I send you greetings.
#       You may supply more parameters than needed, but it is an error
#       for a definition to refer to a parameter which is not supplied.
#
#       The following built-in definitions are recognized:
#           @basename SYM@         Return base name of SYM
#           @boolval SYM@          Return 1 if symbol is true, else 0
#           @dirname SYM@          Return directory name of SYM
#           @gensym@               Generate symbol: <prefix><counter>
#             @gensym 42@            Set counter; prefix unchanged
#             @gensym pre 0@         Set prefix and counter
#           @getenv VAR@           Get environment variable [*]
#           @lc SYM@               Lower case
#           @len SYM@              Number of characters in symbol
#           @substr SYM BEG [LEN]  Substring
#           @trim SYM@             Remove leading and trailing whitespace
#           @uc SYM@               Upper case
#           @uuid@                 Generate something that resembles a UUID:
#                                    C3525388-E400-43A7-BC95-9DF5FA3C4A52
#
#       [*] @getenv VAR@ will be replaced by the value of the
#       environment variable VAR.  If VAR is not defined, nothing is
#       output (i.e., the replacement text is the empty string) and no
#       error is generated.  (Depending on __STRICT__.)
#
#       The following symbols are pre-defined:
#           __DATE__               Current date (19450716)
#           __FILE__               Current file name
#           __GENSYMPREFIX__       Prefix for generated symbols ("g")
#           __GENSYMCOUNT__        Count for generated symbols (0)
#           __GID__                (effective) Groupd id
#           __HOST__               Short host name
#           __HOSTNAME__           FQDN host name
#           __INPUT__              The characters read by @input
#           __LINE__               Current line number in file
#           __NFILE__              Number of files processed (0)
#           __STRICT__             Strict mode (TRUE)
#           __TIME__               Current time (053000)
#           __TIMESTAMP__          ISO 8601 timestamp (1945-07-16T05:30:00-0600)
#           __UID__                (effective) User id
#           __USER__               Username
#           __VERSION__            m2 version
#
#       Except for __INPUT__ and __STRICT__, these built-in symbols
#       cannot be modified by the user.  The values of __DATE__,
#       __TIME__, and __TIMESTAMP__ are fixed at the start of the
#       program and do not change.
#
# ERROR MESSAGES
#       Bad parameters [in 'XXX']
#           - A command was not given the expected number of parameters.
#
#       Cannot recursively read 'XXX'
#           - Attempt to @include the same file multiple times.
#
#       Comparison operator 'XXX' invalid
#           - An @if expression with an invalid comparison operator.
#
#       Delimiter 'XXX' not found
#           - A multi-line read (@ignore, @longdef, @shell) did not find
#             its terminating delimiter line.
#           - An @if block was not properly terminated before end of input.
#
#       Duplicate 'XXX' not allowed
#           - More than one @else found in a single @if block.
#
#       Environment variable 'XXX' not defined
#           - Attempt to getenv an undefined environment variable
#             while __STRICT__ is in effect.
#
#       Error reading file 'XXX'
#           - Read error on file.
#
#       File 'XXX' does not exist
#           - Attempt to @include a non-existent file.
#
#       No corresponding 'XXX'
#           - An @else or @endif was seen without a matching @if.
#           - A @longend was seen without a matching @longdef.
#
#       Parameter NN not supplied in 'XXX'
#           - A macro referred to a parameter (such as $1) for which
#             no value was supplied.
#
#       Symbol 'XXX' already defined
#           - A @default attempted to define a previously defined symbol.
#
#       Symbol 'XXX' not defined
#           - A symbol name without a value was passed to a function
#           - An undefined macro was referenced and __STRICT__ is true.
#
#       Symbol 'XXX' protected
#           - Attempt to modify a protected symbol (__XXX__).
#             (__STRICT__ is an exception and can be modified.)
#
#       Too many parameters in 'XXX'
#           - More than nine parameters were supplied to a macro.
#
#       Unexpected end of macro definition
#           - Input ended before macro definition was complete.
#
#       Value 'XXX' must be numeric
#           - Something expected to be a number was not.
#
# EXIT CODES
#       0   Normal process completion, or @exit command
#       1   Internal error generated by error()
#       2   @error command
#
# BUGS
#       M2 is two steps lower than m4.  You'll probably miss something
#       you have learned to expect.
#
#       Positional parameters are parsed by splitting on white space.
#               @foo "aaa bbb" ccc
#       contains 3 arguments ('"aaa', 'bbb"', and 'ccc'), not two.
#
# EXAMPLE
#       @define Condition under
#          ...
#       You are clearly @Condition@worked.
#
# AUTHOR
#       Jon L. Bentley, jlb@research.bell-labs.com
#
# SEE ALSO
#       http://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791
#
#*****************************************************************************

BEGIN {
    version = "2.0.0"
}


function format_message(text, line, file)
{
    if (line == "")
        line = get_symbol("__LINE__")
    if (file == "")
        file = get_symbol("__FILE__")
    if (file == "/dev/stdin" || file == "-")
        file = "<STDIN>"

    return file ":" line  ":" text
}


function print_stderr(text)
{
    print text | "cat 1>&2"
}


function error(text, line, file)
{
    print_stderr(format_message(text, line, file))
    exit 1
}


# Return s but with last character removed (usually '\n')
function chop(s)
{
    return substr(s, 1, length(s)-1)
}


# x[y]  =>  x <SUBSEP> y
function remove_brackets(sym,    lbracket, rbracket)
{
    if (sym !~ /^.+\[.+\]$/)
        return sym

    lbracket = index(sym, "[")
    rbracket = index(sym, "]")
    return substr(sym, 1,          lbracket-1) \
           SUBSEP \
           substr(sym, lbracket+1, rbracket-lbracket-1)
}


# x <SUBSEP> y  =>  x[y]
function restore_brackets(sym,    idx)
{
    idx = index(sym, SUBSEP)
    if (idx == 0)
        return sym
    return substr(sym, 1, idx-1) "[" substr(sym, idx+1) "]"
}


function integerp(pat)
{
    return pat ~ /^-?[0-9]+$/
}


# Protected symbols cannot be changed by the user.
function symbol_protected_p(sym)
{
    if (sym == "__STRICT__" || sym == "__INPUT__")
        return FALSE
    return sym ~ /^__.*__$/
}


function symbol_defined_p(sym)
{
    return remove_brackets(sym) in symtab
}


function symbol_true_p(sym)
{
    return (symbol_defined_p(sym) && get_symbol(sym) != 0)
}


function get_symbol(sym)
{
    return symtab[remove_brackets(sym)]
}


function set_symbol(sym, val)
{
    symtab[remove_brackets(sym)] = val
}


function incr_symbol(sym, incr)
{
    if (incr == "")
        incr = 1
    symtab[remove_brackets(sym)] += incr
}


function delete_symbol(sym)
{
    # It is legal to delete an array key that does not exist
    delete symtab[remove_brackets(sym)]
}


function currently_active()
{
    return active[ifdepth]
}


function strictp()
{
    return symbol_true_p("__STRICT__")
}


function path_exists_p(path)
{
    return (system("/usr/bin/stat " path " >/dev/null 2>/dev/null") == 0)
}


function hex_digits(n,    i, s)
{
    s = ""
    for (i = 0; i < n; i++)
        s = s sprintf("%X", int(16*rand()))
    return s
}


# KIRK:  Mr. Spock, have you accounted for the variable mass of whales
#        and water in your time re-entry program?
# SPOCK: Mr. Scott cannot give me exact figures, Admiral, so...
#        I will make a guess.
# KIRK:  A guess?  You, Spock?  That's extraordinary.
# SPOCK: [to McCOY] I don't think he understands.
# McCOY: No, Spock.  He means that he feels safer about your guesses
#        than most other people's facts.
# SPOCK: Then you're saying...  it is a compliment?
# McCOY: It is.
# SPOCK: Ah.  Then I will try to make the best guess I can.
function uuid()
{
    return hex_digits(8) "-" hex_digits(4) "-" hex_digits(4) "-" hex_digits(4) "-" hex_digits(12)
}


# Quicksort - from "The AWK Programming Language", p.161
# Used in builtin_dump() to sort the symbol table.
function qsort(A, left, right,    i, last)
{
    if (left >= right)          # Do nothing if array contains
        return                  # less than two elements
    swap(A, left, left + int((right-left+1)*rand()))
    last = left                 # A[left] is now partition element
    for (i = left+1; i <= right; i++)
        if (less_than(A[i], A[left]))
            swap(A, ++last, i)
    swap(A, left, last)
    qsort(A, left,   last-1)
    qsort(A, last+1, right)
}

# Special comparison used to sort leading underscores after all other values
function less_than(s1, s2,    s1_underscore, s2_underscore)
{
    s1_underscore = substr(s1, 1, 1) == "_"
    s2_underscore = substr(s2, 1, 1) == "_"
    if (s1_underscore && !s2_underscore)
        return FALSE
    else if (s2_underscore && !s1_underscore)
        return TRUE
    else
        return s1 < s2
}

function swap(A, i, j,    t)
{
    t = A[i];  A[i] = A[j];  A[j] = t
}


function builtin_default(    sym)
{
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active())
        return
    if (symbol_defined_p(sym))
        print_stderr(format_message("Symbol '" sym "' already defined:" $0))
    else
        dodef(FALSE)
}


# @define, @append
function builtin_define(    append_flag, sym)
{
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active())
        return
    append_flag = ($1 == "@append")
    dodef(append_flag)
}


function builtin_dump(    buf, cnt, definition, dumpfile, i, key, keys, sym_name)
{
    if (! currently_active())
        return
    dumpfile = (NF >= 2) ? $2 : ""

    # Count and sort the symbol table keys
    cnt = 0
    for (key in symtab) {
        keys[++cnt] = key
    }
    qsort(keys, 1, cnt)

    # Format definitions
    buf = ""
    for (i = 1; i <= cnt; i++) {
        key = keys[i]
        sym_name = restore_brackets(key)
        definition = get_symbol(key)
        if (index(definition, "\n") == 0)
            buf = buf "@define " sym_name "\t" definition "\n"
        else {
            buf = buf "@longdef " sym_name "\n"
            buf = buf definition           "\n"
            buf = buf "@longend"           "\n"
        }
    }
    buf = chop(buf)

    # Print them
    if (dumpfile)
        print buf > dumpfile
    else
        print_stderr(buf)
}


function builtin_else()
{
    if (ifdepth == 0)
        error("No corresponding '@if':" $0)
    if (seen_else[ifdepth])
        error("Duplicate '@else' not allowed:" $0)
    seen_else[ifdepth] = TRUE
    active[ifdepth] = active[ifdepth-1] ? ! currently_active() : FALSE
}


function builtin_endif()
{
    if (ifdepth-- == 0)
        error("No corresponding '@if':" $0)
}


# @error, @warn, @echo
function builtin_error(    exit_flag, message)
{
    if (! currently_active())
        return
    exit_flag = ($1 == "@error")
    if (NF == 1) {
        message = format_message($1)
    } else {
        $1 = ""
        sub("^[ \t]*", "")
        message = dosubs($0)
    }
    print_stderr(message)
    if (exit_flag)
        exit 2
}


function builtin_exit()
{
    if (! currently_active())
        return
    exit (NF > 1 && integerp($2)) ? $2 : 0
}


# @if, et al
function builtin_if(    cond, op, val2, val4)
{
    sub(/^@/, "")               # Remove leading @ otherwise dosubs($0) loses
    $0 = dosubs($0)

    if ($1 == "if") {
        if (NF == 2) {
            # @if [!]FOO
            if (substr($2, 1, 1) == "!")
                cond = ! symbol_true_p(substr($2, 2))
            else
                cond = symbol_true_p($2)
        } else if (NF == 3 && $2 == "!")
            # @if ! FOO
            cond = ! symbol_true_p($3)
        else if (NF == 4) {
            # @if FOO <op> BAR
            val2 = symbol_defined_p($2) ? get_symbol($2) : $2
            op   = $3
            val4 = symbol_defined_p($4) ? get_symbol($4) : $4

            if      (op == "<")                 cond = val2 <  val4
            else if (op == "<=")                cond = val2 <= val4
            else if (op == "="  || op == "==")  cond = val2 == val4
            else if (op == "!=" || op == "<>")  cond = val2 != val4
            else if (op == ">=")                cond = val2 >= val4
            else if (op == ">")                 cond = val2 >  val4
            else
                error("Comparison operator '" op "' invalid:" $0)
        } else
            error("Bad parameters:" $0)
    } else if ($1 == "ifdef") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = symbol_defined_p($2)
    } else if ($1 == "ifnotdef" || $1 == "ifndef") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = ! symbol_defined_p($2)
    } else if ($1 == "ifenv") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = $2 in ENVIRON
    } else if ($1 == "ifnotenv") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = ! ($2 in ENVIRON)
    } else if ($1 == "ifexists") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = path_exists_p($2)
    } else if ($1 == "ifnotexists") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = ! path_exists_p($2)
    } else if ($1 == "ifin") {   # @ifin us-east-1 VALID_REGIONS
        if (NF < 3)
            error("Bad parameters:" $0)
        cond = symbol_defined_p($3 "[" $2 "]")
    } else if ($1 == "ifnotin") {
        if (NF < 3)
            error("Bad parameters:" $0)
        cond = ! symbol_defined_p($3 "[" $2 "]")
    } else if ($1 == "ifnot" || $1 == "unless") {
        if (NF < 2)
            error("Bad parameters:" $0)
        cond = ! symbol_true_p($2)
    } else
        # Should not happen
        error("builtin_if(): '" $1 "' not matched:" $0)

    active[++ifdepth] = currently_active() ? cond : FALSE
    seen_else[ifdepth] = FALSE
}


# Read multiple lines until delim is seen as first characters on a line.
# If delimiter is not found, return EOF marker.  Intermediate lines are
# terminated with a newline character, but last line has it stripped
# away.  The lines read are NOT macro-expanded; if desired, the caller
# can invoke dosubs() on the returned buffer.  Special case if delim is
# "" - read until end of file and return whatever is found, without error.
function read_lines_until(delim,    buf, delim_len)
{
    buf = ""
    delim_len = length(delim)
    while (TRUE) {
        if (readline() == EOF)
            if (delim_len == 0)
                break
            else
                return EOF
        if (delim_len > 0 && substr($0, 1, delim_len) == delim)
            break
        buf = buf $0 "\n"
    }
    return chop(buf)
}


# Ignore input until line starts with $2.  This means
#     @ignore Foo
#     ...
#     Foobar
# works.
function builtin_ignore(    buf, delim, save_line, save_lineno)
{
    if (NF != 2)
        error("Bad parameters:" $0)
    if (! currently_active())
        return
    save_line = $0
    save_lineno = get_symbol("__LINE__")
    delim = $2
    buf = read_lines_until(delim)
    if (buf == EOF)
        error("Delimiter '" delim "' not found:" save_line, save_lineno)
}


# @include, @paste
function builtin_include(    error_text, filename, read_literally)
{
    if (NF != 2)
        error("Bad parameters:" $0)
    if (! currently_active())
        return
    read_literally = ($1 == "@paste")   # @paste does not process macros
    filename = dosubs($2)
    if (! dofile(filename, read_literally)) {
        error_text = "File '" filename "' does not exist:" $0
        if (strictp())
            error(error_text)
        else
            print_stderr(format_message(error_text))
    }
}


# @incr, @decr
function builtin_incr(    incr, sym)
{
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (NF >= 3 && !integerp($3))
        error("Value '" $3 "' must be numeric:" $0)
    if (! currently_active())
        return
    if (! symbol_defined_p(sym))
        error("Symbol '" sym "' not defined:" $0)
    incr = (NF >= 3) ? $3 : 1
    incr_symbol(sym, ($1 == "@incr") ? incr : -incr)
}


# Read a single line from /dev/tty.  No prompt is issued; if you want
# one, use @echo.  Specify the symbol you want to receive the input.  If
# no symbol is specified, a default name of __INPUT__ is used.
function builtin_input(    getstat, input, sym)
{
    sym = (NF < 2) ? "__INPUT__" : $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active())
        return
    getstat = getline input < "/dev/tty"
    if (getstat < 0)
        error("Error reading file '/dev/tty':" $0)
    set_symbol(sym, input)
}


function builtin_longdef(    buf, save_line, save_lineno, sym)
{
    if (NF != 2)
        error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active())
        return
    save_line = $0
    save_lineno = get_symbol("__LINE__")
    buf = read_lines_until("@longend")
    if (buf == EOF)
        error("Delimiter '@longend' not found:" save_line, save_lineno)
    set_symbol(sym, buf)
}


# @longend should never be encountered alone because builtin_longdef()
# consumes any matching @longend.
function builtin_longend()
{
    error("No corresponding '@longdef':" $0)
}


function builtin_shell(    buf, delim, save_line, save_lineno, shell)
{
    if (NF == 2) {              # @shell EOD@
        delim = $2
        shell = "/bin/sh"
    } else if (NF == 3) {       # @shell EOD /bin/bash@
        delim = $2
        shell = $3
    } else
        error("Bad parameters:" $0)
    if (! currently_active())
        return
    save_line = $0
    save_lineno = get_symbol("__LINE__")
    buf = read_lines_until(delim)
    if (buf == EOF)
        error("Delimiter '" delim "' not found:" save_line, save_lineno)
    print buf | shell
    close(shell)
}


function builtin_typeout(    buf)
{
    if (! currently_active())
        return
    buf = read_lines_until("")
    if (length(buf) > 0)
        print buf
}


function builtin_undefine(    sym)
{
    if (NF != 2)
        error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active())
        return
    delete_symbol(sym)
}


function dofile(filename, read_literally,    savefile, saveline, savebuffer)
{
    if (filename == "-")
        filename = "/dev/stdin"
    if (! path_exists_p(filename))
        return FALSE

    if (filename in activefiles)
        error("Cannot recursively read '" filename "':" $0)

    # Save old file context
    savefile   = get_symbol("__FILE__")
    saveline   = get_symbol("__LINE__")
    savebuffer = buffer

    # Set up new file context
    activefiles[filename] = TRUE
    buffer = ""
    set_symbol("__FILE__", filename)
    set_symbol("__LINE__", 0)
    incr_symbol("__NFILE__")

    while (readline() != EOF)
        process_line(read_literally)

    # Reached end of file
    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != "-" && filename != "/dev/stdin")
        close(filename)
    if (ifdepth > 0)
        error("Delimiter '@endif' not found")
    delete activefiles[filename]

    # Restore previous file context
    set_symbol("__FILE__", savefile)
    set_symbol("__LINE__", saveline)
    buffer = savebuffer

    return TRUE
}


function process_line(read_literally,    newstring)
{
    # Short circuit if we're not processing macros, or no @ found
    if (read_literally ||
        (currently_active() && index($0, "@") == 0)) {
        print $0
        return
    }

    # Look for built-in commands
    if      (/^@(@|#)/)                      { } # Comments are ignored
    else if (/^@append([ \t]|$)/)            { builtin_define()   }
    else if (/^@(c(omment)|rem)([ \t]|$)/)   { } # Comments are ignored
    else if (/^@default([ \t]|$)/)           { builtin_default()  }
    else if (/^@define([ \t]|$)/)            { builtin_define()   }
    else if (/^@dump([ \t]|$)/)              { builtin_dump()     }
    else if (/^@else([ \t]|$)/)              { builtin_else()     }
    else if (/^@(endif|fi)([ \t]|$)/)        { builtin_endif()    }
    else if (/^@error([ \t]|$)/)             { builtin_error()    }
    else if (/^@exit([ \t]|$)/)              { builtin_exit()     }
    else if (/^@(if(not)?|unless)([ \t]|$)/) { builtin_if()       }
    else if (/^@if(n(ot)?)?def([ \t]|$)/)    { builtin_if()       }
    else if (/^@if(not)?env([ \t]|$)/)       { builtin_if()       }
    else if (/^@if(not)?exists([ \t]|$)/)    { builtin_if()       }
    else if (/^@if(not)?in([ \t]|$)/)        { builtin_if()       }
    else if (/^@ignore([ \t]|$)/)            { builtin_ignore()   }
    else if (/^@include([ \t]|$)/)           { builtin_include()  }
    else if (/^@(incr|decr)([ \t]|$)/)       { builtin_incr()     }
    else if (/^@input([ \t]|$)/)             { builtin_input()    }
    else if (/^@longdef([ \t]|$)/)           { builtin_longdef()  }
    else if (/^@longend([ \t]|$)/)           { builtin_longend()  }
    else if (/^@paste([ \t]|$)/)             { builtin_include()  }
    else if (/^@shell([ \t]|$)/)             { builtin_shell()    }
    else if (/^@typeout([ \t]|$)/)           { builtin_typeout()  }
    else if (/^@undef(ine)?([ \t]|$)/)       { builtin_undefine() }
    else if (/^@(warn|echo)([ \t]|$)/)       { builtin_error()    }

    # Process @
    else {
        newstring = dosubs($0)
        if ($0 == newstring || index(newstring, "@") == 0) {
            if (currently_active())
                print newstring
        } else {
            buffer = newstring "\n" buffer
        }
    }
}


# Put next input line into global string "buffer"
# Return EOF or "" (null string)
function readline(    getstat, i, status)
{
    status = ""
    if (buffer != "") {
        i = index(buffer, "\n")
        $0 = substr(buffer, 1, i-1)
        buffer = substr(buffer, i+1)
    } else {
        getstat = getline < get_symbol("__FILE__")
        if (getstat < 0)        # Error
            error("Error reading file '" get_symbol("__FILE__") "'")
        else if (getstat == 0)  # End of file
            status = EOF
        else                    # Read a line
            incr_symbol("__LINE__")
    }
    # # Kludge: allow @Mname at start of line without closing @
    # if ($0 ~ /^@[A-Z][a-zA-Z0-9_]*[ \t]*$/)
    #     sub(/[ \t]*$/, "@")
    return status
}


# M2 uses a fast substitution function.  The idea is to process the
# string from left to right, searching for the first substitution to be
# made.  We then make the substitution, and rescan the string starting
# at the fresh text.  We implement this idea by keeping two strings: the
# text processed so far is in L (for Left), and unprocessed text is in
# R (for Right).
#
# Here is the pseudocode for dosubs:
#     L = Empty
#     R = Input String
#     while R contains an "@" sign do
#         let R = A @ B; set L = L A and R = B
#         if R contains no "@" then
#             L = L "@"
#             break
#         let R = A @ B; set M = A and R = B
#         if M is in SymTab then
#             R = SymTab[M] R
#         else
#             L = L "@" M
#             R = "@" R
#         return L R
function dosubs(s,    expand, i, j, l, m, nparam, p, params, r, sym)
{
    if (index(s, "@") == 0)
        return s
    l = ""                   # Left of current pos; ready for output
    r = s                    # Right of current; unexamined at this time
    while ((i = index(r, "@")) != 0) {
        l = l substr(r, 1, i-1)
        r = substr(r, i+1)      # Currently scanning @
        i = index(r, "@")
        if (i == 0) {
            l = l "@"
            break
        }
        m = substr(r, 1, i-1)
        r = substr(r, i+1)

        nparam = split(m, params) - 1
        sym = params[1]
        if (nparam > 9)
            error("Too many parameters in '" m "':" $0)

        # basename : Return base name of file
        if (sym == "basename") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (symbol_defined_p(p))
                p = get_symbol(p)
            "/usr/bin/basename " p | getline expand
            r = expand r

        # boolval : Return 1 if symbol is true, else 0
        #   @boolval SYM@ => 0 or 1
        } else if (sym == "boolval") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            r = (symbol_true_p(params[2]) ? "1" : "0") r

        # dirname : Return directory name of file
        } else if (sym == "dirname") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (symbol_defined_p(p))
                p = get_symbol(p)
            "/usr/bin/dirname " p | getline expand
            r = expand r

        # gensym : Generate symbol
        #   @gensym@ => g66
        #   @gensym 42@ (prefix unchanged, counter now 42) => g42
        #   @gensym foo 42@ => (prefix now "foo", counter now 42) => foo42
        } else if (sym == "gensym") {
            if (nparam == 1) {
                if (! integerp(params[2]))
                    error("Value '" m "' must be numeric:" $0)
                set_symbol("__GENSYMCOUNT__", params[2])
            } else if (nparam == 2) {
                if (! integerp(params[3]))
                    error("Value '" m "' must be numeric:" $0)
                set_symbol("__GENSYMPREFIX__", params[2])
                set_symbol("__GENSYMCOUNT__",  params[3])
            } else if (nparam > 2)
                error("Bad parameters in '" m "':" $0)
            # 0, 1, or 2 params
            r = get_symbol("__GENSYMPREFIX__") get_symbol("__GENSYMCOUNT__") r
            incr_symbol("__GENSYMCOUNT__")

        # getenv : Get environment variable
        #   @getenv HOME@ => /home/user
        } else if (sym == "getenv") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            env = params[2]
            if (env in ENVIRON)
                r = ENVIRON[env] r
            else if (strictp())
                error("Environment variable '" env "' not defined:" $0)

        # lc : Lower case
        } else if (sym == "lc") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = tolower(get_symbol(p)) r

        # len : Length
        #   @len SYM@ => N
        } else if (sym == "len") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = length(get_symbol(p)) r

        # substr : Substring ...  SYMBOL, START[, LENGTH]
        #   @substr FOO 3@
        #   @substr FOO 2 2@
        } else if (sym == "substr") {
            if (nparam != 2 && nparam != 3)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            if (! integerp(params[3]))
                error("Value '" m "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(get_symbol(p), params[3]+1) r
            } else if (nparam == 3) {
                if (! integerp(params[4]))
                    error("Value '" m "' must be numeric:" $0)
                r = substr(get_symbol(p), params[3]+1, params[4]) r
            }

        # trim : Remove leading and trailing whitespace
        } else if (sym == "trim") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            expand = get_symbol(p)
            sub(/^[ \t]+/, "", expand)
            sub(/[ \t]+$/, "", expand)
            r = expand r

        # uc : Upper case
        } else if (sym == "uc") {
            if (nparam != 1)
                error("Bad parameters in '" m "':" $0)
            p = params[2]
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = toupper(get_symbol(p)) r

        # uuid : Generate something that resembles a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (sym == "uuid") {
            r = uuid() r

        } else if (symbol_defined_p(sym)) {
            expand = get_symbol(sym)
            # Expand $N parameters (includes $0 for macro name)
            for (j = 0; j <= 9; j++)
                if (index(expand, "$" j) > 0) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$" j, params[j+1], expand)
                }
            r = expand r

        } else if (strictp()) {
            error("Symbol '" m "' not defined:" $0)

        } else {
            l = l "@" m
            r = "@" r
        }
    }
    return l r
}


# Caller is responsible for checking NF, so we don't check here.
# Caller is also responsible for ensuring name is not protected.
function dodef(append_flag,    name, str, x)
{
    name = $2
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")  # OLD BUG: last * was +
    str = $0
    while (str ~ /\\$/) {
        if (readline() == EOF)
            error("Unexpected end of macro definition")
        # OLD BUG: sub(/\\$/, "\n" $0, str)
        x = $0
        sub(/^[ \t]+/, "", x)
        str = chop(str) "\n" x
    }

    # If the definition text looks like an expansion request, do a preliminary
    # expansion; then see if the result might be a symbol which we could
    # possibly use; then do a final substitution.  This makes possible:
    #      @define AMI  @ami-list[@my-region@]@
    # This is a terrible**2 kludge....
    if (str ~ /^@.+@$/) {
        x = dosubs(substr(str, 2, length(str)-2))
        if (symbol_defined_p(x))
            str = get_symbol(x)
        str = dosubs(str)
    }
    set_symbol(name, append_flag ? get_symbol(name) str : str)
}


function initialize(    d, dateout, egid, euid, host, hostname, user)
{
    TRUE            = 1
    FALSE           = 0
    EOF             = "EOF" SUBSEP "EOF" # Unlikely to occur in normal text
    ifdepth         = 0
    active[ifdepth] = TRUE
    buffer          = ""

    srand()                     # Seed random number generator
    "date +'%Y %m %d %H %M %S %z'" | getline dateout;   split(dateout, d)
    "id -g"                        | getline egid
    "id -u"                        | getline euid
    "hostname -s"                  | getline host
    "hostname"                     | getline hostname
    "id -un"                       | getline user

    set_symbol("__DATE__",         d[1] d[2] d[3])
    set_symbol("__GENSYMPREFIX__", "g")
    set_symbol("__GENSYMCOUNT__",  0)
    set_symbol("__GID__",          egid)
    set_symbol("__HOST__",         host)
    set_symbol("__HOSTNAME__",     hostname)
    set_symbol("__NFILE__",        0)
    set_symbol("__STRICT__",       TRUE)
    set_symbol("__TIME__",         d[4] d[5] d[6])
    set_symbol("__TIMESTAMP__",    d[1] "-" d[2] "-" d[3] "T" \
                                   d[4] ":" d[5] ":" d[6] d[7])
    set_symbol("__UID__",          euid)
    set_symbol("__USER__",         user)
    set_symbol("__VERSION__",      version)
}


BEGIN {
    initialize()

    if (ARGC == 1)
        dofile("-")
    else {
        for (i = 1; i < ARGC; i++) {
            # print_stderr("Debug: ARGV[" i "]='" ARGV[i] "'")
            if (ARGV[i] ~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)/) {
                eq = index(ARGV[i], "=")
                name = substr(ARGV[i], 1, eq-1)
                val  = substr(ARGV[i], eq+1)
                if (symbol_protected_p(name)) {
                    print_stderr("Symbol '" name "' protected")
                    exit 1
                }
                set_symbol(name, val)
            } else if (! dofile(ARGV[i]))
                print_stderr("File '" ARGV[i] "' does not exist")
        }
    }
}
