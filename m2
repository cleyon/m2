#!/usr/bin/awk -f
#*****************************************************************************
#
# NAME
#       m2 - Line-oriented macro processor
#
# USAGE
#       m2 [NAME=VAL] [file...]
#       awk -f m2 [file...]
#
# DESCRIPTION
#       The m1 program is a "little brother" to the m4 macro processor
#       found on UNIX systems.  M2 is a line-oriented macro processor
#       which copies its input file(s) to its output.  It can perform
#       several tasks, including:
#
#       1. Define and expand macros.  Macros have two parts, a name and
#          a body.  All occurrences of a macro's name are replaced with
#          the macro's body.
#
#       2. Include files.  Special include directives in a data file are
#          replaced with the contents of the named file.  Includes can
#          usually be nested, with one included file including another.
#          Included files are processed for macros.
#
#       3. Conditional text inclusion and exclusion.  Different parts of
#          the text can be included in the final output, often based
#          upon whether a macro is or isn't defined.
#
#       4. Depending on the macro processor, comment lines can appear
#          that will be removed from the final output.
#
#       Macro expressions lines are distinguished with a "@" character.
#       The following lines define or control macros for subsequent
#       processing:
#
#           @append NAME MORE      Add to the body of an already defined macro
#           @capture NAME ...      Pass ... to shell, capture output in NAME
#                                    Note: ... data is evaluated before being sent to shell
#           @comment ...           Comment -- line is ignored
#           @decr NAME [N]         Subtract 1 (or N) from an already defined NAME
#           @default NAME VALUE    As @define, but no-op if NAME already defined
#           @define NAME VALUE     Set NAME to VALUE
#           @dump(all) [FILE]      Output symbol names & definitions to FILE (stderr)
#           @echo STUFF            Same as @warn
#           @else                  Switch to the other branch of an @if statement
#           @endif                 Terminate @if or @unless
#           @error STUFF           Send STUFF to standard error, exit 2
#           @exit [CODE]           Stop parsing input immediately, exit CODE (default 0)
#           @fi                    Same as @endif
#           @if NAME               Include subsequent text if NAME is true (!= 0)
#           @if NAME <OP> AAA      Test if NAME compares to AAA (names or values)
#           @if(_not)_defined NAME Test if NAME is defined
#           @if(_not)_env ENV      Test if ENV is defined in the environment (or not)
#           @if(_not)_exists PATH  Test if PATH exists (or not)
#           @if(_not)_in KEY ARR   Test if symbol ARR[KEY] is defined
#           @if(n)def NAME         Same as @if_defined/@if_not_defined
#           @ignore DELIM          Ignore input until line that begins with DELIM
#           @include FILENAME      Read and process contents of FILENAME
#           @incr NAME [N]         Add 1 (or N) from an already defined NAME
#           @initialize NAME VALUE As @default, but errors if NAME already defined
#           @input [NAME]          Read a single line from keyboard and define NAME
#           @longdef NAME          Define NAME to <...> lines until @longend
#             ...                    Don't use other @ commands inside def!
#           @longend                 But simple @VAR@ references should be okay
#           @paste FILENAME        Read FILENAME literally, do not process any macros
#           @print SYM             Ship out value of SYM without evaluation (use with @capture)
#           @read SYM FILE         Read FILE contents into SYM
#           @rem ...               Same as @comment
#           @shell DELIM [PROG]    Evaluate input until DELIM, send raw data to PROG
#                                    Output from prog is captured in output stream.
#           @typeout               Ship out remainder of input file literally, no processing
#           @undef(ine) NAME       Remove definition of NAME
#           @unless NAME           Include subsequent text if NAME == 0 (or undefined)
#           @warn STUFF            Send STUFF to standard error, continue
#           @@.../@#...            Same as @comment
#
#       A definition may extend across many lines by ending each line
#       with a backslash, thus quoting the following newline.
#       (Alternatively, use @longdef.)  Short macros can be defined on
#       the command line by using the form "NAME=VAL" (or "NAME=" to
#       define with empty value)
#
#       Any occurrence of @name@ in the input is replaced in the output
#       by the corresponding value.  Specifying more than one word in a
#       @aaa bbb ...@ form is used as a crude form of function invocation.
#
#       Macros can expand positional parameters whose actual values will be
#       supplied when the macro is called.  The definition should refer to
#       $1, $2, etc; $0 refers to the name of the macro name itself.
#       Example:
#           @define greet Hello, $1!  m2 sends you $0ings.
#           @greet world@
#               => Hello, world!  m2 sends you greetings.
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
#       Symbols that start and end with "__" (like __FOO__) are called
#       "internal" symbols.  The following internal symbols are pre-defined;
#       example values or defaults are shown:
#           __DATE__               Current date (19450716)
#           __FILE__               Current file name
#           __GENSYMCOUNT__        Count for generated symbols (0)
#           __GENSYMPREFIX__       Prefix for generated symbols (_gen)
#           __GID__                [effective] Group id
#           __HOST__               Short host name (myhost)
#           __HOSTNAME__           FQDN host name (myhost.example.com)
#           __INPUT__              The characters read by @input
#           __LINE__               Current line number in __FILE__
#           __NFILE__              Number of files processed (0)
#           __STRICT__             Strict mode (TRUE)
#           __TIME__               Current time (053000)
#           __TIMESTAMP__          ISO 8601 timestamp (1945-07-16T05:30:00-0600)
#           __UID__                [effective] User id
#           __USER__               Username
#           __VERSION__            m2 version
#
#       Except for __INPUT__ and __STRICT__, internal symbols cannot be
#       modified by the user.  The values of __DATE__, __TIME__, and
#       __TIMESTAMP__ are fixed at the start of the program and do not
#       change.
#
# ERROR MESSAGES
#       Bad parameters [in 'XXX']
#           - A command was not provided the expected number of parameters.
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
#           - @initialize attempted to define a previously defined symbol.
#
#       Symbol name 'XXX' invalid
#           - A symbol name does not pass validity check.  In __STRICT__
#             mode (the default), a symbol name may only contain letters,
#             digits, #, $, or _ characters.
#
#       Symbol 'XXX' not defined
#           - A symbol name without a value was passed to a function
#           - An undefined macro was referenced and __STRICT__ is true.
#
#       Symbol 'XXX' protected
#           - Attempt to modify a protected symbol (__XXX__).
#             (__STRICT__ is an exception and can be modified.)
#
#       Unexpected end of definition
#           - Input ended before macro definition was complete.
#
#       Value 'XXX' must be numeric
#           - Something expected to be a number was not.
#
# EXIT CODES
#       0   Normal process completion, or @exit command
#       1   Internal error generated by error()
#       2   @error command
#       64  Usage error
#       66  A file specified on command line could not be read
#
# BUGS
#       M2 is two steps lower than m4.  You'll probably miss something
#       you have learned to expect.
#
#       Positional parameters are parsed by splitting on white space.
#               @foo "aaa bbb" ccc
#       has 3 arguments ('"aaa', 'bbb"', 'ccc') not 2.
#
# EXAMPLE
#       @define Condition under
#          ...
#       You are clearly @Condition@worked.
#
# FILES
#       $HOME/.m2rc
#           - Init file automatically read if available.
#
#       /dev/stdin, /dev/stderr, /dev/tty
#           - I/O is performed on these paths.
#
# AUTHOR(S)
#       Jon L. Bentley, jlb@research.bell-labs.com.  Original author.
#       Christopher Leyon, cleyon@gmail.com.
#
# SEE ALSO
#       "m1: A Mini Macro Processor", Computer Language, June 1990,
#          Volume 7, Number 6, pages 47-61.
#
#       http://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791
#
#       https://docstore.mik.ua/orelly/unix3/sedawk/ch13_10.htm
#
#*****************************************************************************

BEGIN {
    version = "2.1.2"
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


function flush_stdout()
{
    # One of these should work, right?
    system("")
    fflush("/dev/stdout")
}


function print_stderr(text)
{
    flush_stdout()
    print text > "/dev/stderr"
    # More portable:
    # print text | "cat 1>&2"
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


function chomp(s,    last)
{
    last = substr(s, length(s), 1)
    return (last == "\n") ? chop(s) : s
}


# x[y]  =>  x <SUBSEP> y
function remove_brackets(sym,    lbracket, rbracket, x, y)
{
    lbracket = index(sym, "[")
    if (lbracket == 0)
        return sym
    if (sym !~ /^.+\[.+\]$/)
        return sym
    rbracket = index(sym, "]")
    x = substr(sym, 1, lbracket-1)
    y = substr(sym, lbracket+1, rbracket-lbracket-1)
    return x SUBSEP y
}


# x <SUBSEP> y  =>  x[y]
function restore_brackets(sym,    idx, x, y)
{
    idx = index(sym, SUBSEP)
    if (idx == 0)
        return sym
    x = substr(sym, 1, idx-1)
    y = substr(sym, idx+1)
    return x "[" y "]"
}


function integerp(pat)
{
    return pat ~ /^[-+]?[0-9]+$/
}


# Internal symbols start and end with double underscores
function symbol_internal_p(sym)
{
    return sym ~ /^__.*__$/
}


# In strict mode, a symbol must match the followiong regexp:
#       /^[A-Za-z#$_][A-Za-z#$_0-9]*$/
# In non-strict mode, any non-empty string is valid.
function symbol_valid_p(sym,    lbracket)
{
    # These are the ways a symbol is not valid:
    # 1. Empty string is never a valid symbol name
    if (length(sym) == 0)
        return FALSE

    # Half remove brackets
    if (sym ~ /^.+\[.+\]$/) {
        # Part to check for validity is the "x" part (think array name)
        # The "subscript" party can be anything at all.
        lbracket = index(sym, "[")
        sym = substr(sym, 1, lbracket-1)
    }

    # 2. We're in strict mode and the name doesn't pass regexp check
    if ((strictp()) && (sym !~ /^[A-Za-z#$_][A-Za-z#$_0-9]*$/))
        return FALSE

    return TRUE
}


# This function throws an error if the symbol is not valid
function validate_symbol(sym)
{
    if (symbol_valid_p(sym))
        return TRUE
    else
        error("Symbol name '" sym "' invalid:" $0)
}


# Protected symbols cannot be changed by the user.
function symbol_protected_p(sym)
{
    if (sym in unprotected_symbols)
        # Whitelist of known safe symbols
        return FALSE
    return symbol_internal_p(sym)
}


function symbol_defined_p(sym)
{
    return remove_brackets(sym) in symtab
}


function symbol_true_p(sym)
{
    return (symbol_defined_p(sym) &&
            get_symbol(sym) != 0  &&
            get_symbol(sym) != "")
}


function get_symbol(sym)
{
    return symtab[remove_brackets(sym)]
}


function set_symbol(sym, val)
{
    if (symbol_true_p("__DEBUG__"))
        print_stderr("set_symbol(" sym "," val ")")
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
    if (symbol_true_p("__DEBUG__"))
        print_stderr("delete_symbol(" sym ")")
    # It is legal to delete an array key that does not exist
    delete symtab[remove_brackets(sym)]
}


function currently_active_p()
{
    return active[ifdepth]
}


function strictp()
{
    return symbol_true_p("__STRICT__")
}


function default_shell()
{
    if (symbol_defined_p("SHELL"))
        return get_symbol("SHELL")
    else if ("SHELL" in ENVIRON)
        return ENVIRON["SHELL"]
    else
        return get_symbol("__SHELL__")
}


function path_exists_p(path)
{
    return (system("/usr/bin/stat " path " >/dev/null 2>/dev/null") == 0)
}


# Return a string of N random hex digits [0-9A-F].
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


function shipout_printf(s)
{
    printf("%s", s)
}


# @default, @initialize
function builtin_default(    sym)
{
    if (NF < 2) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
    if (symbol_defined_p(sym)) {
        if ($1 == "@init" || $1 == "@initialize")
            error("Symbol '" sym "' already defined:" $0)
    } else
        dodef(FALSE)
}


# @define, @append
function builtin_define(    append_flag, sym)
{
    if (NF < 2) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
    append_flag = ($1 == "@append")
    dodef(append_flag)
}


# @dump, @dumpall
function builtin_dump(    buf, cnt, definition, dumpfile, i, key, keys, sym_name, all_flag)
{
    if (! currently_active_p())
        return
    all_flag = ($1 == "@dumpall")
    dumpfile = (NF >= 2) ? $2 : "/dev/stderr"

    # Count and sort the symbol table keys
    cnt = 0
    for (key in symtab) {
        if (all_flag || ! symbol_internal_p(key))
            keys[++cnt] = key
    }
    qsort(keys, 1, cnt)

    # Format definitions
    buf = ""
    for (i = 1; i <= cnt; i++) {
        key = keys[i]
        definition = get_symbol(key)
        sym_name = restore_brackets(key)
        if (index(definition, "\n") == 0)
            buf = buf "@define " sym_name "\t" definition "\n"
        else {
            buf = buf "@longdef " sym_name "\n"
            buf = buf definition           "\n"
            buf = buf "@longend"           "\n"
        }
    }
    buf = chop(buf)
    print buf > dumpfile
    # More portable:
    # print_stderr(buf)
}


function builtin_else()
{
    if (ifdepth == 0)
        error("No corresponding '@if':" $0)
    if (seen_else[ifdepth])
        error("Duplicate '@else' not allowed:" $0)
    seen_else[ifdepth] = TRUE
    active[ifdepth] = active[ifdepth-1] ? ! currently_active_p() : FALSE
}


function builtin_endif()
{
    if (ifdepth-- == 0)
        error("No corresponding '@if':" $0)
}


# @error, @warn, @echo
function builtin_error(    exit_flag, message)
{
    if (! currently_active_p())
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
    if (! currently_active_p())
        return
    exit (NF > 1 && integerp($2)) ? $2 : 0
}


# @if, et al
function builtin_if(    sym, cond, op, val2, val4)
{
    sub(/^@/, "")          # Remove leading @ otherwise dosubs($0) loses
    $0 = dosubs($0)

    if ($1 == "if") {
        if (NF == 2) {
            # @if [!]FOO
            if (substr($2, 1, 1) == "!") {
                sym = substr($2, 2)
                validate_symbol(sym)
                cond = ! symbol_true_p(sym)
            } else {
                validate_symbol($2)
                cond = symbol_true_p($2)
            }
        } else if (NF == 3 && $2 == "!") {
            # @if ! FOO
            validate_symbol($3)
            cond = ! symbol_true_p($3)
        } else if (NF == 4) {
            # @if FOO <op> BAR
            val2 = (symbol_valid_p($2) && symbol_defined_p($2)) ? get_symbol($2) : $2
            op   = $3
            val4 = (symbol_valid_p($2) && symbol_defined_p($4)) ? get_symbol($4) : $4

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

    } else if ($1 == "if_not" || $1 == "unless") {
        if (NF < 2) error("Bad parameters:" $0)
        validate_symbol($2)
        cond = ! symbol_true_p($2)

    } else if ($1 == "if_defined" || $1 == "ifdef") {
        if (NF < 2) error("Bad parameters:" $0)
        validate_symbol($2)
        cond = symbol_defined_p($2)

    } else if ($1 == "if_not_defined" || $1 == "ifndef") {
        if (NF < 2) error("Bad parameters:" $0)
        validate_symbol($2)
        cond = ! symbol_defined_p($2)

    } else if ($1 == "if_env") {
        if (NF < 2) error("Bad parameters:" $0)
        cond = $2 in ENVIRON

    } else if ($1 == "if_not_env") {
        if (NF < 2) error("Bad parameters:" $0)
        cond = ! ($2 in ENVIRON)

    } else if ($1 == "if_exists") {
        if (NF < 2) error("Bad parameters:" $0)
        cond = path_exists_p($2)

    } else if ($1 == "if_not_exists") {
        if (NF < 2) error("Bad parameters:" $0)
        cond = ! path_exists_p($2)

    } else if ($1 == "if_in") {   # @if_in us-east-1 VALID_REGIONS
        if (NF < 3) error("Bad parameters:" $0)
        validate_symbol($3)
        cond = symbol_defined_p($3 "[" $2 "]")

    } else if ($1 == "if_not_in") {
        if (NF < 3) error("Bad parameters:" $0)
        validate_symbol($3)
        cond = ! symbol_defined_p($3 "[" $2 "]")

    } else
        # Should not happen
        error("builtin_if(): '" $1 "' not matched:" $0)

    active[++ifdepth] = currently_active_p() ? cond : FALSE
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


# @capture SYM CMD...
# In general, the only thing you can safely to with symbols defined here
# is to @print them.
function builtin_capture(    sym, val, cmd)
{
    if (symbol_true_p("__DEBUG__"))
        print_stderr("@capture: \$0='" $0 "'")
    if (NF < 3) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)

    val = ""
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")
    cmd = dosubs($0)
    if (symbol_true_p("__DEBUG__"))
        print_stderr("@capture: cmd='" cmd "'")
    while ((cmd | getline) > 0) {
        if ($0 !~ /^[ \t]*$/)
            val = val $0 "\n"
    }
    if (symbol_true_p("__DEBUG__"))
        print_stderr("@capture: val='" val "'")
    set_symbol(sym, chop(val))
}


# Ignore input until line starts with $2.  This means
#     @ignore Foo
#     ...
#     Foobar
# works.
function builtin_ignore(    buf, delim, save_line, save_lineno)
{
    if (NF != 2) error("Bad parameters:" $0)
    if (! currently_active_p())
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
    if (NF != 2) error("Bad parameters:" $0)
    if (! currently_active_p())
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
    if (NF < 2) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (NF >= 3 && !integerp($3))
        error("Value '" $3 "' must be numeric:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
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
    if (! currently_active_p())
        return
    validate_symbol(sym)
    getstat = getline input < "/dev/tty"
    if (getstat < 0)
        error("Error reading file '/dev/tty':" $0)
    set_symbol(sym, input)
}


function builtin_longdef(    buf, save_line, save_lineno, sym)
{
    if (NF != 2) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
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


# @print
function builtin_print(    sym, r)
{
    if (NF != 2) error("Bad parameters:" $0)
    sym = $2
    if (! currently_active_p())
        return
    validate_symbol(sym)
    if (! symbol_defined_p(sym))
        error("Symbol '" sym "' not defined:" $0)
    # We want @print to end cleanly
    if (dostr(get_symbol(sym)) == 0)
        shipout_printf("\n")
}


# @read
# As usual, multiline values are accepted but the final trailing \n (if
# any) is stripped.
function builtin_read(    sym, file, line, val, getstat)
{
    if (symbol_true_p("__DEBUG__"))
        print_stderr("@read: \$0='" $0 "'")
    if (NF == 3) {       # @read SYM FILE
        sym = $2
        file = $3
    } else
        error("Bad parameters:" $0)
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)

    val = ""
    while (TRUE) {
        getstat = getline line < file
        if (getstat < 0)        # Error
            error("Error reading file '" file "'")
        else if (getstat == 0)  # End of file
            break
        else                    # Read a line
            val = val line "\n"
    }
    close(file)
    set_symbol(sym, chomp(val))
}


# @shell DELIM [shell]@
# The sendto program defaults to a reasonable shell but you can specify
# where you want to send your data.  Possibly useful choices would be a
# non-standard shell, a message emailer, or /usr/bin/bc.
#
#       @define NUM   355
#       @define DENOM 113
#       Here is a pretty good approximation of pi followed by the standard value:
#       @shell EOD /usr/bin/bc -l
#       scale=10
#       @NUM@/@DENOM@
#       4*a(1)
#       EOD
function builtin_shell(    buf, delim, save_line, save_lineno, sendto)
{
    if (NF < 2)
        error("Bad parameters:" $0)
    if (! currently_active_p())
        return
    delim = $2
    $1 = ""; $2 = ""
    if (NF == 2) {              # @shell DELIM
        sendto = default_shell()
    } else {       # @shell DELIM /bin/bash
        sub("^[ \t]*", "")
        sendto = dosubs($0)
    }

    save_line = $0
    save_lineno = get_symbol("__LINE__")
    buf = read_lines_until(delim)
    if (buf == EOF)
        error("Delimiter '" delim "' not found:" save_line, save_lineno)
    print dosubs(buf) | sendto
    close(sendto)
}


function builtin_typeout(    buf)
{
    if (! currently_active_p())
        return
    buf = read_lines_until("")
    if (length(buf) > 0)
        shipout_printf(buf "\n")
}


function builtin_undefine(    sym)
{
    if (NF != 2) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
    delete_symbol(sym)
}


# Sets $0 so dostr() can process it.  Returns
#  1 if a newline was found; there's potentially more data.
#  0 if no newline was found so that empties the strbuf.
# -1 on empty strbuf - end of data
function readline_from_string(    i, status)
{
    if (strbuf == "") {
        $0 = ""
        return -1
    }
    i = index(strbuf, "\n")
    if (i == 0) {
        $0 = strbuf
        strbuf = ""
        return 0
    }
    $0 = substr(strbuf, 1, i-1)
    strbuf = substr(strbuf, i+1)
    return 1
}


# Return value as from readline_from_string: 1 if a newline was included
# last, 0 if the cursor is stuck and needs a newline.
function dostr(s,    r, rprev)
{
    if (symbol_true_p("__DEBUG__"))
        print_stderr("dostr(" s ")")
    flush_stdout()
    strbuf = s
    rprev = -1
    while (TRUE) {
        r = readline_from_string()
        if (r == -1)
            break
        shipout_printf("%s", $0)
        if (r == 1)
            shipout_printf("\n")
        rprev = r
    }
    flush_stdout()
    return rprev
}


# The high-level processing happens in the dofile() function, which
# reads one line at a time, and decides what to do with each line.  The
# activefiles array keeps track of open files.  The symbol __FILE__
# stores the current file to read data from.  When an "@include"
# directive is seen, dofile() is called recursively on the new file.
# Interestingly, the included filename is first processed for macros.
# Read this function carefully--there are some nice tricks here.
function dofile(filename, read_literally,    savefile, saveline, savebuffer)
{
    if (symbol_true_p("__DEBUG__"))
        print_stderr("dofile(" filename \
                     (read_literally ? ", read_literally=TRUE" : "") \
                     ")")
    if (filename == "-")
        filename = "/dev/stdin"
    if (! path_exists_p(filename))
        return FALSE

    if (filename in activefiles)
        error("Cannot recursively read '" filename "':" $0)

    # Save old file context
    flush_stdout()
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
    flush_stdout()
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
        (currently_active_p() && index($0, "@") == 0)) {
        shipout_printf($0 "\n")
        return
    }

    # Look for built-in commands.  Note, these only match
    # at beginning of line.
    if      (/^@(@|#)/)                  { } # Comments are ignored
    else if (/^@append([ \t]|$)/)        { builtin_define() }
    else if (/^@c([ \t]|$)/)             { } # Comments are ignored
    else if (/^@capture([ \t]|$)/)       { builtin_capture() }
    else if (/^@comment([ \t]|$)/)       { } # Comments are ignored
    else if (/^@decr([ \t]|$)/)          { builtin_incr() }
    else if (/^@default([ \t]|$)/)       { builtin_default() }
    else if (/^@define([ \t]|$)/)        { builtin_define() }
    else if (/^@dump(all)?([ \t]|$)/)    { builtin_dump() }
    else if (/^@echo([ \t]|$)/)          { builtin_error() }
    else if (/^@else([ \t]|$)/)          { builtin_else() }
    else if (/^@endif([ \t]|$)/)         { builtin_endif() }
    else if (/^@error([ \t]|$)/)         { builtin_error() }
    else if (/^@exit([ \t]|$)/)          { builtin_exit() }
    else if (/^@fi([ \t]|$)/)            { builtin_endif() }
    else if (/^@if(_not)?(_(defined|env|exists|in))?([ \t]|$)/)
                                         { builtin_if() }
    else if (/^@ifn?def([ \t]|$)/)       { builtin_if() }
    else if (/^@ignore([ \t]|$)/)        { builtin_ignore() }
    else if (/^@include([ \t]|$)/)       { builtin_include() }
    else if (/^@incr([ \t]|$)/)          { builtin_incr() }
    else if (/^@init(ialize)?([ \t]|$)/) { builtin_default() }
    else if (/^@input([ \t]|$)/)         { builtin_input() }
    else if (/^@longdef([ \t]|$)/)       { builtin_longdef() }
    else if (/^@longend([ \t]|$)/)       { builtin_longend() }
    else if (/^@paste([ \t]|$)/)         { builtin_include() }
    else if (/^@print([ \t]|$)/)         { builtin_print() }
    else if (/^@read([ \t]|$)/)          { builtin_read() }
    else if (/^@rem([ \t]|$)/)           { } # Comments are ignored
    else if (/^@shell([ \t]|$)/)         { builtin_shell() }
    else if (/^@typeout([ \t]|$)/)       { builtin_typeout() }
    else if (/^@undef(ine)?([ \t]|$)/)   { builtin_undefine() }
    else if (/^@unless([ \t]|$)/)        { builtin_if() }
    else if (/^@warn([ \t]|$)/)          { builtin_error() }

    # Process @
    else {
        newstring = dosubs($0)
        if (newstring == $0 || index(newstring, "@") == 0) {
            if (currently_active_p())
                shipout_printf(newstring "\n")
        } else {
            buffer = newstring "\n" buffer
        }
    }
}


# Put next input line into global string "buffer".  The readline()
# function manages the "pushback."  After expanding a macro, macro
# processors examine the newly created text for any additional macro
# names.  Only after all expanded text has been processed and sent to
# the output does the program get a fresh line of input.
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
    # Hack: allow @Mname at start of line w/o closing @
    # if non-strict.  Note, macro name must start w/capital.
    if (not strictp())
        if ($0 ~ /^@[A-Z][a-zA-Z0-9_]*[ \t]*$/)
            sub(/[ \t]*$/, "@")
    return status
}


# The dosubs() function actually performs the macro substitution.  It
# processes the line left-to-right, replacing macro names with their
# bodies.  The rescanning of the new line is left to the higher-level
# logic that is jointly managed by readline() and dofile().  This
# version is considerably more efficient than the brute-force approach
# used in the m0 programs.
#
# M2 uses a fast substitution function.  The idea is to process the
# string from left to right, searching for the first substitution to be
# made.  We then make the substitution, and rescan the string starting
# at the fresh text.  We implement this idea by keeping two strings: the
# text processed so far is in L (for Left), and unprocessed text is in R
# (for Right).
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
function dosubs(s,    expand, i, j, l, m, nparam, p, param, r, symfunc)
{
    # Short-circuit check: no "@" characters means no action needed
    if (index(s, "@") == 0)
        return s

    l = ""                   # Left of current pos  - ready for output
    r = s                    # Right of current pos - as yet unexamined
    fencepost = 1

    while ((i = index(r, "@")) != 0) {
        l = l substr(r, 1, i-1)
        r = substr(r, i+1)      # Currently scanning @
        i = index(r, "@")
        if (i == 0) {
            l = l "@"
            break
        }
        m = substr(r, 1, i-1)   # Middle
        r = substr(r, i+1)

        # In the code that follows:
        # - m :: Entire text between @'s.  Example: "gensym foo 42".
        # - symfunc :: The name of the "function" to call.  The first
        #     element of m.  Example: "gensym".
        # - nparam :: Number of parameters supplied to the symfunc.
        #     @foo@         --> nparam == 0
        #     @foo BAR@     --> nparam == 1
        #     @foo BAR BAZ@ --> nparam == 2
        # In general, a symfunc's parameter N is available in variable
        #   param[N+1].  For "gensym foo 42", nparam is 2, the new prefix
        #   is at param[1+1] and the new count is at param[2+1].
        #   This offset of one is referred to as `fencepost' below.
        # Each `if' condition eventually performs
        #     r = <SOMETHING> r
        #   which injects <SOMETHING> just before the current value of
        #   r.  (r is defined above.)  r is what is to the right of the
        #   current position and contains as yet unexamined text that
        #   needs to be evaluated for possible macro processing.  This
        #   is the data we were going to evaluate anyway.  In other
        #   words, this injects the result of "invoking" symfunc.
        # Eventually this big while loop exits and we "return l r".
        nparam = split(m, param) - fencepost
        symfunc = param[fencepost]

        # basename SYM: Return base name of file
        if (symfunc == "basename") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            if (symbol_valid_p(p) && symbol_defined_p(p))
                p = get_symbol(p)
            "/usr/bin/basename " p | getline expand
            r = expand r

        # boolval : Return 1 if symbol is true, else 0
        #   @boolval SYM@ => 0 or 1     # error if not defined
        } else if (symfunc == "boolval") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = (symbol_true_p(p) ? "1" : "0") r

        # dirname : Return directory name of file
        } else if (symfunc == "dirname") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            if (symbol_valid_p(p) && symbol_defined_p(p))
                p = get_symbol(p)
            "/usr/bin/dirname " p | getline expand
            r = expand r

        # gensym : Generate symbol
        #   @gensym@ => _gen66
        #   @gensym 42@ (prefix unchanged, counter now 42) => _gen42
        #   @gensym foo 42@ => (prefix now "foo", counter now 42) => foo42
        } else if (symfunc == "gensym") {
            if (nparam == 1) {
                if (! integerp(param[1+fencepost]))
                    error("Value '" m "' must be numeric:" $0)
                set_symbol("__GENSYMCOUNT__", param[1+fencepost])
            } else if (nparam == 2) {
                if (! integerp(param[2+fencepost]))
                    error("Value '" m "' must be numeric:" $0)
                validate_symbol(param[1+fencepost])
                set_symbol("__GENSYMPREFIX__", param[1+fencepost])
                set_symbol("__GENSYMCOUNT__",  param[2+fencepost])
            } else if (nparam > 2)
                error("Bad parameters in '" m "':" $0)
            # 0, 1, or 2 param
            r = get_symbol("__GENSYMPREFIX__") get_symbol("__GENSYMCOUNT__") r
            incr_symbol("__GENSYMCOUNT__")

        # getenv : Get environment variable
        #   @getenv HOME@ => /home/user
        } else if (symfunc == "getenv") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            env = param[1+fencepost]
            if (env in ENVIRON)
                r = ENVIRON[env] r
            else if (strictp())
                error("Environment variable '" env "' not defined:" $0)

        # lc : Lower case
        } else if (symfunc == "lc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = tolower(get_symbol(p)) r

        # len : Length
        #   @len SYM@ => N
        } else if (symfunc == "len") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = length(get_symbol(p)) r

        # substr : Substring ...  SYMBOL, START[, LENGTH]
        #   @substr FOO 3@
        #   @substr FOO 2 2@
        } else if (symfunc == "substr") {
            if (nparam != 2 && nparam != 3)
                error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            if (! integerp(param[2+fencepost]))
                error("Value '" m "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(get_symbol(p), param[2+fencepost]+1) r
            } else if (nparam == 3) {
                if (! integerp(param[3+fencepost]))
                    error("Value '" m "' must be numeric:" $0)
                r = substr(get_symbol(p), param[2+fencepost]+1, param[3+fencepost]) r
            }

        # trim : Remove leading and trailing whitespace
        } else if (symfunc == "trim") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            expand = get_symbol(p)
            sub(/^[ \t]+/, "", expand)
            sub(/[ \t]+$/, "", expand)
            r = expand r

        # uc : Upper case
        } else if (symfunc == "uc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1+fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined:" $0)
            r = toupper(get_symbol(p)) r

        # uuid : Generate something that resembles a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (symfunc == "uuid") {
            r = uuid() r

        # <SOMETHING> : Call a user-defined macro, handles arguments
        } else if (symbol_valid_p(symfunc) && symbol_defined_p(symfunc)) {
            expand = get_symbol(symfunc)
            # Expand $N parameters (includes $0 for macro name)
            for (j = 0; j <= 9; j++)
                if (index(expand, "$" j) > 0) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$" j, param[j+fencepost], expand)
                }
            r = expand r

        # Throw an error on undefined symbol (strict-only)
        } else if (strictp()) {
            error("Symbol '" m "' not defined:" $0)

        } else {
            l = l "@" m
            r = "@" r
        }
    }

    if (symbol_true_p("__DEBUG__"))
        print_stderr("dosubs:l=<" l "> r=<" r ">")
    return l r
}


# Finally, the dodef() function handles the defining of macros.  It
# saves the macro name from $2, and then uses sub() to remove the first
# two fields.  The new value of $0 now contains just (the first line of)
# the macro body.  The Computer Language article explains that sub() is
# used on purpose, in order to preserve whitespace in the macro body.
# Simply assigning the empty string to $1 and $2 would rebuild the
# record, but with all occurrences of whitespace collapsed into single
# occurrences of the value of OFS (a single blank).  The function then
# proceeds to gather the rest of the macro body, indicated by lines that
# end with a "\".  This is an additional improvement over m0: macro
# bodies can be more than one line long.
#
# Caller is responsible for checking NF, so we don't check here.
# Caller is responsible for ensuring name is valid.
# Caller is responsible for ensuring name is not protected.
function dodef(append_flag,    name, str, x)
{
    name = $2
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")  # OLD BUG: last * was +
    str = $0
    while (str ~ /\\$/) {
        if (readline() == EOF)
            error("Unexpected end of definition")
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


# Try to read init file: $HOME/.m2rc
# No worries if it doesn't exist.
function load_home_m2rc()
{
    if ("HOME" in ENVIRON)
        dofile(ENVIRON["HOME"] "/.m2rc")
    init_needed = FALSE
}


function initialize(    d, dateout, egid, euid, host, hostname, user)
{
    TRUE            = 1
    FALSE           = 0
    EOF             = "EOF" SUBSEP "EOF" # Unlikely to occur in normal text
    ifdepth         = 0
    init_needed     = TRUE
    active[ifdepth] = TRUE
    buffer          = ""
    strbuf          = ""

    srand()                     # Seed random number generator
    "date +'%Y %m %d %H %M %S %z'" | getline dateout;   split(dateout, d)
    "id -g"                        | getline egid
    "id -u"                        | getline euid
    "hostname -s"                  | getline host
    "hostname"                     | getline hostname
    "id -un"                       | getline user

    set_symbol("__DATE__",         d[1] d[2] d[3])
    set_symbol("__DEBUG__",        FALSE); unprotected_symbols["__DEBUG__"]=1
    set_symbol("__GENSYMPREFIX__", "_gen")
    set_symbol("__GENSYMCOUNT__",  0)
    set_symbol("__GID__",          egid)
    set_symbol("__HOST__",         host)
    set_symbol("__HOSTNAME__",     hostname)
    set_symbol("__INPUT__",        "");    unprotected_symbols["__INPUT__"]=1
    set_symbol("__NFILE__",        0)
    set_symbol("__SHELL__",        "/bin/sh")
    set_symbol("__STRICT__",       TRUE);  unprotected_symbols["__STRICT__"]=1
    set_symbol("__TIME__",         d[4] d[5] d[6])
    set_symbol("__TIMESTAMP__",    d[1] "-" d[2] "-" d[3] "T" \
                                   d[4] ":" d[5] ":" d[6] d[7])
    set_symbol("__UID__",          euid)
    set_symbol("__USER__",         user)
    set_symbol("__VERSION__",      version)
}


# The main program occurs in the BEGIN procedure at the bottom.  It
# simply processes either standard input, if there are no arguments, or
# all of the files named on the command line.
BEGIN {
    initialize()
    # set_symbol("__DEBUG__", TRUE)

    if (ARGC == 1) {
        load_home_m2rc()
        dofile("-")
        exit 0
    } else if (ARGC > 1) {
        my_exit = 0             # EX_OK
        # Delay loading $HOME/.m2rc as long as possible.  This allows us
        # to set symbols on the command line (e.g., debug=1) which will
        # have taken effect by the time the init file loads.
        for (i = 1; i < ARGC; i++) {
            # Show each arg as we process it
            arg = ARGV[i]
            if (symbol_true_p("__DEBUG__"))
                print_stderr("BEGIN: ARGV[" i "]:" arg)
            if (arg ~ /^([^= ][^= ]*)=(.*)/) {
                # Define a symbol on the command line
                eq = index(arg, "=")
                name = substr(arg, 1, eq-1)
                val  = substr(arg, eq+1)
                if (symbol_protected_p(name))
                    error("Symbol '" name "' protected:" arg, i, "ARGV")
                if (! symbol_valid_p(name))
                    error("Symbol name '" name "' invalid:" arg, i, "ARGV")
                set_symbol(name, val)
                if (name == "strict")
                    set_symbol("__STRICT__", val)
            } else {
                # Load a file
                if (init_needed)
                    load_home_m2rc()
                if (! dofile(arg)) {
                    print_stderr(format_message("File '" arg "' does not exist", i, "ARGV"))
                    my_exit = 66 # EX_NOINPUT
                }
            }
        }
        # If we get here with init_needed still true, that means we used
        # up every ARGV defining symbols and didn't specify any files.
        # Not specifying any input files, like ARGC==1, means to read
        # standard input, so that's what we must do now.
        if (init_needed) {
            load_home_m2rc()
            dofile("-")
        }
        exit my_exit
    } else {
        print_stderr("Usage: m2 [NAME=VAL] [file...]")
        exit 64                 # EX_USAGE
    }
}
