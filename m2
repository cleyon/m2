#!/usr/bin/awk -f
#
#*****************************************************************************
#
# NAME
#       m2 - Line-oriented macro processor
#
# USAGE
#       m2 [NAME=VAL ...] [file ...]
#       awk -f m2 [file ...]
#
# DESCRIPTION
#       m2 is a line-oriented macro processor, a "little brother" to the
#       m4(1) macro processor found on Unix systems.  It is written in
#       portable "standard" Awk and does not depend on any GNU extensions.
#       It can perform several functions, including:
#
#       1. Define and expand macros.  Macros have two parts, a name and
#          a body.  All occurrences of a macro's name are replaced with
#          the macro's body.  Macro expansion may include parameters.
#
#       2. Include files.  Special include directives in a file are
#          replaced with the contents of the named file.  Includes can
#          be nested, with one included file including another.
#          Included files are processed for macros.
#
#       3. Conditional text inclusion and exclusion.  Different parts of
#          the text can be included in the final output, often based
#          upon whether a macro is or is not defined.
#
#       4. Comment lines will be removed from the final output.
#
#       Control commands (@if, @define, etc) are distinguished by a "@"
#       as the first character at the beginning of a line.  They consume
#       the entire line.  The following table lists control commands to
#       evaluate, control, or define macros for subsequent processing:
#
#           @append NAME TEXT      Add TEXT to an already defined macro NAME
#           @comment [TEXT]        Comment; ignore line.  Also @@, @c, @#, @rem
#           @decr NAME [N]         Subtract N (1) from an already defined NAME
#           @default NAME VAL      Like @define, but no-op if NAME already defined
#           @define NAME TEXT      Set NAME to TEXT
#           @dump(all) [FILE]      Output symbol names & definitions to FILE (stderr)
#           @error [TEXT]          Send TEXT to standard error; exit code 2
#           @exit [CODE]           Immediately stop parsing; exit CODE (default 0)
#           @if NAME               Include subsequent text if NAME is true (!= 0)
#           @if NAME <OP> TEXT     Test if NAME compares to TEXT (names or values)
#           @if(_not)_defined NAME Test if NAME is defined
#           @if(_not)_env VAR      Test if VAR is defined in the environment
#           @if(_not)_exists FILE  Test if FILE exists
#           @if(_not)_in KEY ARR   Test if symbol ARR[KEY] is defined (KEY in ARR)
#           @if(n)def NAME         Like @if_defined/@if_not_defined
#           @else                  Switch to the other branch of an @if statement
#           @endif                 Terminate @if or @unless.  Also @fi
#           @ignore DELIM          Ignore input until line that begins with DELIM
#           @include FILE          Read and process contents of FILE
#           @incr NAME [N]         Add N (1) to an already defined NAME
#           @initialize NAME VAL   Like @define, but abort if NAME already defined
#           @input [NAME]          Read a single line from keyboard and define NAME
#           @let NAME TEXT         Pass TEXT to bc(1), result in NAME
#           @longdef NAME          Set NAME to <...> (all lines until @longend)
#             <...>                  Don't use other @ commands inside definition
#           @longend                 But simple @NAME@ references should be okay
#           @paste FILE            Insert FILE contents literally, no macros
#           @read NAME FILE        Read FILE contents to define NAME
#           @shell DELIM [PROG]    Evaluate input until DELIM, send raw data to PROG
#                                    Output from prog is captured in output stream
#           @sleep [N]             Pause execution for N seconds (default 1)
#           @typeout               Print remainder of input literally, no macros
#           @undef NAME            Remove definition of NAME
#           @unless NAME           Include subsequent text if NAME == 0 (or undefined)
#           @warn [TEXT]           Send TEXT to standard error; continue
#                                    Also called @echo, @stderr
#
#       A definition may extend across many lines by ending each line
#       with a backslash, thus quoting the following newline.
#       (Alternatively, use @longdef.)  Short macros can be defined on
#       the command line by using the form "NAME=VAL", or "NAME=" to
#       define with empty value.  Any occurrence of @name@ in the input
#       is replaced in the output by the corresponding value.  They can
#       occur multiple times in a single line.
#
#       Example:
#           @define Condition under
#           You are clearly @Condition@worked.
#               => You are clearly underworked.
#
#       Specifying more than one word between @ signs, as in
#           @xxx A B C@
#       is used as a crude form of function invocation.  Macros can
#       expand positional parameters whose actual values will be
#       supplied when the macro is called.  The definition should refer
#       to $1, $2, etc.  $0 refers to the name of the macro itself.  You
#       may supply more parameters than needed, but it is an error if
#       a definition refers to a parameter which is not supplied.
#
#       Example:
#           @define greet Hello, $1!  m2 sends you $0ings.
#           @greet world@
#               => Hello, world!  m2 sends you greetings.
#
#       The following definitions are recognized:
#
#           @basename SYM@         Base (file) name of SYM
#           @boolval SYM@          Output "1" if SYM is true, else "0"
#           @currdate@             Current date as YYYY-MM-DD
#           @currtime@             Current time as HH:MM:SS
#           @dirname SYM@          Directory name of SYM
#           @gensym@               Generate symbol: <prefix><counter>
#             @gensym 42@            Set counter; prefix unchanged
#             @gensym pre 0@         Set prefix and counter
#           @getenv VAR@       [*] Get environment variable
#           @lc SYM@               Lower case
#           @len SYM@              Number of characters in SYM's value
#           @substr SYM BEG [LEN]@ Substring
#           @trim SYM@             Remove leading and trailing whitespace
#           @tz@                   Time zone offset from UTC (-0400)
#           @uc SYM@               Upper case
#           @uuid@                 Something that resembles a UUID:
#                                    C3525388-E400-43A7-BC95-9DF5FA3C4A52
#
#       [*] @getenv VAR@ will be replaced by the value of the environment
#           variable VAR.  An error is thrown if VAR is not defined.  To
#           ignore error and continue with empty string, disable __STRICT__.
#
#       Symbols can be suffixed with "[<key>]" to form simple arrays.
#
#       Symbols that start and end with "__" (like __FOO__) are called
#       "system" symbols.  The following system symbols are pre-defined;
#       example values or defaults are shown:
#
#           __DATE__               Run start date as YYYYMMDD (eg 19450716)
#           __DBG__[<id>]     [**] Debugging levels for m2 systems
#           __FILE__               Current file name
#           __FILE_UUID__          UUID unique to this file
#           __GENSYM__[count]      Count for generated symbols (def 0)
#           __GENSYM__[prefix]     Prefix for generated symbols (def _gen)
#           __GID__                Group id (effective gid)
#           __HOST__               Short host name (eg myhost)
#           __HOSTNAME__           FQDN host name (eg myhost.example.com)
#           __INPUT__         [**] The data read by @input
#           __LINE__               Current line number in __FILE__
#           __M2_UUID__            UUID unique to this m2 run
#           __M2_VERSION__         m2 version
#           __NFILE__              Number of files processed so far (eg 2)
#           __SCALE__         [**] Value of "scale" passed to bc (def 6)
#           __STRICT__        [**] Strict mode (def TRUE)
#           __TIME__               Run start time as HHMMSS (eg 053000)
#           __TIMESTAMP__          ISO 8601 timestamp (1945-07-16T05:30:00-0600)
#           __TMPDIR__        [**] Location for temporary files (def /tmp)
#           __UID__                User id (effective uid)
#           __USER__               User name
#
#       [**] Except for certain unprotected symbols, system symbols
#            cannot be modified by the user.  The values of __DATE__,
#            __TIME__, and __TIMESTAMP__ are fixed at program start and
#            do not change.  @currdate@ and @currtime@ do change, however:
#                @currdate@T@currtime@@tz@
#            will generate an up-to-date timestamp.
#
# ERROR MESSAGES
#       Error messages are printed to standard error in the following format:
#           <__FILE__>:<__LINE__>:<Error text>:<Offending input line>
#
#       All error texts and their meanings are as follows:
#
#           Bad parameters [in 'XXX']
#               - A command did not receive the expected/number of parameters.
#           Bad @{...} expansion
#               - Error expanding @{...}, often caused by a missing "}"
#           Cannot recursively read 'XXX'
#               - Attempt to @include the same file multiple times.
#           Comparison operator 'XXX' invalid
#               - An @if expression with an invalid comparison operator.
#           Delimiter 'XXX' not found
#               - A multi-line read (@ignore, @longdef, @shell) did not find
#                 its terminating delimiter line.
#               - An @if block was not properly terminated before end of input.
#               - Indicates an "starting" command did not find its finish.
#           Duplicate '@else' not allowed
#               - More than one @else found in a single @if block.
#           Environment variable 'XXX' invalid name
#               - Environment variable name does not pass validity check.
#           Environment variable 'XXX' not defined
#               - Attempt to getenv an undefined environment variable
#                 while __STRICT__ is in effect.
#           Error reading 'FILE'
#               - Read error on file.
#           File 'XXX' does not exist
#               - Attempt to @include a non-existent file in strict mode.
#           No corresponding 'XXX'
#               - @if: An @else or @endif was seen without a matching @if.
#               - @longdef: A @longend was seen without a matching @longdef.
#               - Indicates a "finishing" command was seen without a starter.
#           Parameter N not supplied in 'XXX'
#               - A macro referred to a parameter (such as $1) for which
#                 no value was supplied.
#           Symbol 'XXX' already defined
#               - @initialize attempted to define a previously defined symbol.
#           Symbol 'XXX' invalid name
#               - A symbol name does not pass validity check.  In __STRICT__
#                 mode (the default), a symbol name may only contain letters,
#                 digits, #, $, or _ characters.
#           Symbol 'XXX' not defined
#               - A symbol name without a value was passed to a function
#               - An undefined macro was referenced and __STRICT__ is true.
#           Symbol 'XXX' protected
#               - Attempt to modify a protected symbol (__XXX__).
#                 (__STRICT__ is an exception and can be modified.)
#           Unexpected end of definition
#               - Input ended before macro definition was complete.
#           Value 'XXX' must be numeric
#               - Something expected to be a number was not.
#
# EXIT CODES
#       0       Normal process completion, or @exit command
#       1       m2 error generated by error() function
#       2       User requested @error command in input
#       64      Usage error
#       66      A file specified on command line could not be read
#
# BUGS
#       m2 is two steps lower than m4.  You'll probably miss something
#       you have learned to expect.
#
#       Positional parameters are parsed by splitting on white space.
#       This means that in:
#           @foo "a b" c
#       foo has three arguments -- ('"a', 'b"', 'c') -- not two.
#
# EXAMPLE
#       This example demonstrates arrays, conditionals, and @{...}:
#
#           @#              Use default region if available
#           @if_env AWS_DEFAULT_REGION
#           @define region @getenv AWS_DEFAULT_REGION@
#           @endif
#           @#              If you want your own default region, uncomment
#           @#                      @default region us-west-2
#           @#              Otherwise, m2 will exit with error message
#           @ifndef region
#           @error You must provide a value for 'region' on the command line
#           @endif
#           @#              Validate region
#           @define valid_regions[us-east-1]
#           @define valid_regions[us-east-2]
#           @define valid_regions[us-west-1]
#           @define valid_regions[us-west-2]
#           @if_not_in @region@ valid_regions
#           @error Region '@region@' is not valid: choose us-{east,west}-{1,2}
#           @endif
#           @#              Configure image name according to region
#           @define imgs[us-east-1]     my-east1-image-name
#           @define imgs[us-east-2]     my-east2-image-name
#           @define imgs[us-west-1]     my-west1-image-name
#           @define imgs[us-west-2]     my-west2-image-name
#           @define my_image @imgs[@{@region@}]@
#           @#              Output begins here
#           Region: @region@
#           Image:  @my_image@
#
# FILES
#       $HOME/.m2rc, ./.m2rc
#           - Init files automatically read if available.
#
#       /dev/stdin, /dev/stderr, /dev/tty
#           - I/O is performed on these paths.
#
# ENVIRONMENT VARIABLES
#       HOME            Used to access your ~/.m2rc file
#       SHELL           Used as a possible default shell
#       TMPDIR          Used as a possible temporary directory
#
# AUTHOR
#       Jon L. Bentley, jlb@research.bell-labs.com
#
# EMBIGGENER
#       Chris Leyon, cleyon@gmail.com
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
    version = "2.2.1"
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


# One of these is bound to work, right?
function flush_stdout()
{
    fflush("/dev/stdout")
    # Reputed to be more portable:
    # system("")
}


function print_stderr(text)
{
    print text > "/dev/stderr"
    # Definitely more portable:
    # print text | "cat 1>&2"
}


function warn(text, line, file)
{
    print_stderr(format_message(text, line, file))
}

function error(text, line, file)
{
    warn(text, line, file)
    flush_stdout()
    exit EX_M2_ERROR
}


# Return first character of s
function first(s)
{
    return substr(s, 1, 1)
}

# Return last character of s
function last(s)
{
    return substr(s, length(s), 1)
}


# Return s but with last character (usually "\n") removed
function chop(s)
{
    return substr(s, 1, length(s)-1)
}

# If last character is newline, chop() it off
function chomp(s)
{
    return (last(s) == "\n") ? chop(s) : s
}

# If s is surrounded by quotes, remove them.
function rm_quotes(s)
{
    if (length(s) >= 2 && first(s) == "\"" && last(s) == "\"")
        s = substr(s, 2, length(s) - 2)
    return s
}


function build_subsep(s, t)
{
    return s SUBSEP t
}


function symbol_root(sym,    _isym)
{
    _isym = internal_form(sym)
    if (index(_isym, SUBSEP) == IDX_NOT_FOUND)
        return sym
    else
        return substr(_isym, 1, index(_isym, SUBSEP)-1)
}


# Convert a symbol name into its "internal" form (for table lookup
# purposes) by removing and separating any array-referring brackets.
#       "arr[key]"  =>  "arr <SUBSEP> key"
# If there are no array-referring brackets, the symbol is returned
# unchanged, without a <SUBSEB>.
function internal_form(sym,    lbracket, rbracket, arr, key)
{
    if ((lbracket = index(sym, "[")) == IDX_NOT_FOUND)
        return sym
    if (sym !~ /^.+\[.+\]$/)
        return sym
    rbracket = index(sym, "]")
    arr = substr(sym, 1, lbracket-1)
    key = substr(sym, lbracket+1, rbracket-lbracket-1)
    return build_subsep(arr, key)
}


# Convert a symbol name into a nice, user-friendly format, usually for
# printing (i.e., put the array-looking brackets back if needed).
#       "arr <SUBSEP> key"  =>  "arr[key]"
# If there is no <SUBSEP>, the symbol is returned unchanged.
function printable_form(sym,    sep, arr, key)
{
    if ((sep = index(sym, SUBSEP)) == IDX_NOT_FOUND)
        return sym
    arr = substr(sym, 1, sep-1)
    key = substr(sym, sep+1)
    return arr "[" key "]"
}


function integerp(pat)
{
    return pat ~ /^[-+]?[0-9]+$/
}


# System symbols start and end with double underscores
function symbol_sys_p(sym)
{
    return symbol_root(sym) ~ /^__.*__$/
}


# Environment variable names must match the following regexp:
#       /^[A-Za-z_][A-Za-z_0-9]*$/
function env_var_name_valid_p(var)
{
    return var ~ /^[A-Za-z_][A-Za-z_0-9]*$/
}


# In strict mode, a symbol must match the following regexp:
#       /^[A-Za-z#$_][A-Za-z#$_0-9]*$/
# In non-strict mode, any non-empty string is valid.
function symbol_valid_p(sym,    result, lbracket, rbracket, sym_root, sym_key)
{
    # These are the ways a symbol is not valid:
    result = FALSE

    do {
        # 1. Empty string is never a valid symbol name
        if (length(sym) == 0)
             break

        # Fake/hack out any "array name" by removing brackets
        if ((lbracket = index(sym, "[")) && (sym ~ /^.+\[.+\]$/)) {
            rbracket = index(sym, "]")
            sym_root = substr(sym, 1, lbracket-1)
            sym_key  = substr(sym, lbracket+1, rbracket-lbracket-1)
            # 2. Empty parts are not valid
            if (length(sym_root) == 0 || length(sym_key) == 0)
                break
            sym = sym_root
        }

        # 3. We're in strict mode and the name doesn't pass regexp check
        if (strictp() && sym !~ /^[A-Za-z#$_][A-Za-z#$_0-9]*$/)
            break

        # We've passed all the tests
        result = TRUE
    } while (FALSE)

    return result
}


# Throw an error if the symbol is not valid
function validate_symbol(sym)
{
    if (symbol_valid_p(sym))
        return TRUE
    error("Symbol '" sym "' invalid name:" $0)
}


# Throw an error if the environment variable name is not valid
function validate_env_var_name(var)
{
    if (env_var_name_valid_p(var))
        return TRUE
    error("Environment variable '" var "' invalid name:" $0)
}


# Protected symbols cannot be changed by the user.
function symbol_protected_p(sym)
{
    sym = symbol_root(sym)
    # Whitelist of known safe symbols
    if (sym in unprotected_syms)
        return FALSE
    return symbol_sys_p(sym)
}


function symbol_defined_p(sym)
{
    return internal_form(sym) in symtab
}

function aref_defined_p(arr, key)
{
    return build_subsep(arr, key) in symtab
}

function symbol_true_p(sym)
{
    return (symbol_defined_p(sym)    &&
            get_symbol(sym) != FALSE &&
            get_symbol(sym) != "")
}


function get_symbol(sym)
{
    return symtab[internal_form(sym)]
}

function get_aref(arr, key)
{
    return symtab[build_subsep(arr, key)]
}


function dbg(key, lev)
{
    if (lev == "")
        lev = 1
    if (key == "")
        key = "m2"
    if (! aref_defined_p("__DBG__", key))
        return false
    return get_aref("__DBG__", key) >= lev
}

function dbg_set_level(key, lev)
{
    if (lev == "")
        lev = 1
    if (key == "")
        key = "m2"
    set_aref("__DBG__", key, lev)
}

function dbg_print(key, lev, str)
{
    if (dbg(key, lev))
        print_stderr(str)
}


function set_symbol(sym, val)
{
    dbg_print("m2", 5, ("set_symbol(" sym "," val ")"))
    symtab[internal_form(sym)] = val
}

function set_aref(arr, key, val)
{
    dbg_print("m2", 5, ("set_aref(" arr "," key "," val ")"))
    symtab[build_subsep(arr, key)] = val
}


function incr_symbol(sym, incr)
{
    if (incr == "")
        incr = 1
    symtab[internal_form(sym)] += incr
}


function delete_symbol(sym)
{
    dbg_print("m2", 5, ("delete_symbol(" sym ")"))
    # It is legal to delete an array key that does not exist
    delete symtab[internal_form(sym)]
}


function currently_active_p()
{
    return active[ifdepth]
}


function strictp()
{
    return symbol_true_p("__STRICT__")
}


function build_prog_cmdline(prog, arg, silent)
{
    if (! aref_defined_p("__PROG__", prog))
        error("Symbol '__PROG__[" prog "]' not defined [build_prog_cmdline]:" $0)
    return sprintf("%s %s%s", \
                   get_aref("__PROG__", prog), \
                   arg, \
                   (silent ? " >/dev/null 2>/dev/null" : ""))
}


function exec_prog_cmdline(prog, arg,    sym)
{
    if (! aref_defined_p("__PROG__", prog))
        error("Symbol '__PROG__[" prog "]' not defined [exec_prog_cmdline]:" $0)
    return system(build_prog_cmdline(prog, arg, TRUE)) # always silent
}


# Return a likely path for storing temporary files.
# This path is guaranteed to end with a "/" character.
function tmpdir(    t)
{
    if (symbol_defined_p("M2_TMPDIR"))
        t = get_symbol("M2_TMPDIR")
    else if ("TMPDIR" in ENVIRON)
        t = ENVIRON["TMPDIR"]
    else
        t = get_symbol("__TMPDIR__")
    while (last(t) == "\n")
        t = chop(t)
    return t ((last(t) != "/") ? "/" : "")
}


function default_shell()
{
    if (symbol_defined_p("M2_SHELL"))
        return get_symbol("M2_SHELL")
    if ("SHELL" in ENVIRON)
        return ENVIRON["SHELL"]
    return get_aref("__PROG__", "sh")
}


function path_exists_p(path)
{
    return exec_prog_cmdline("stat", path) == EX_OK
}


# 0  <=  randint(N)  <  N
# To generate a hex digit (0..15), say `randint(16)'
# To roll a die (generate 1..6),   say `randint(6)+1'.
function randint(n)
{
    return int(n * rand())
}


# Return a string of N random hex digits [0-9A-F].
function hex_digits(n,    i, s)
{
    s = ""
    for (i = 0; i < n; i++)
        s = s sprintf("%X", randint(16))
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
# Used in m2_dump() to sort the symbol table.
function qsort(A, left, right,    i, last)
{
    if (left >= right)          # Do nothing if array contains
        return                  # less than two elements
    swap(A, left, left + int((right-left+1)*rand()))
    last = left                 # A[left] is now partition element
    for (i = left+1; i <= right; i++)
        if (_less_than(A[i], A[left]))
            swap(A, ++last, i)
    swap(A, left, last)
    qsort(A, left,   last-1)
    qsort(A, last+1, right)
}

function swap(A, i, j,    t)
{
    t = A[i];  A[i] = A[j];  A[j] = t
}

# Special comparison to sort leading underscores after all other values.
function _less_than(s1, s2,    s1_un, s2_un)
{
    # Determine if s1 and s2 have a leading underscore
    s1_un = first(s1) == "_"
    s2_un = first(s2) == "_"

    if      (  s1_un &&   s2_un) return _less_than(substr(s1,2), substr(s2,2))
    else if (  s1_un && ! s2_un) return FALSE
    else if (! s1_un &&   s2_un) return TRUE
    else                         return s1 < s2
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
        if (readline() != READ_OK) # eof or error, it's time to stop
            if (delim_len > 0)
                return EOF
            else
                break
        if (delim_len > 0 && substr($0, 1, delim_len) == delim)
            break
        buf = buf $0 "\n"
    }
    return chop(buf)
}


#*****************************************************************************
#
#       The m2_*() functions that follow can only be executed by
#       process_line().  That routine has already matched text at the
#       beginning of line in $0 to invoke a `control command' such as
#       @define, @if, etc.  Therefore, NF cannot be zero.
#
#       - NF==1 means @xxx called with zero arguments.
#       - NF==2 means @xxx called with 1 argument.
#       - NF==3 means @xxx called with 2 arguments.
#
#*****************************************************************************

# @default, @initialize NAME TEXT
function m2_default(    sym)
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


# @append, @define      NAME TEXT
function m2_define(    append_flag, sym)
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


# @dump[all]            [FILE]
function m2_dump(    buf, cnt, definition, dumpfile, i, key, keys, sym_name, all_flag)
{
    if (! currently_active_p())
        return
    all_flag = ($1 == "@dumpall")
    if (NF == 1)
        dumpfile = "/dev/stderr"
    else {
        $1 = ""
        sub("^[ \t]*", "")
        dumpfile = rm_quotes(dosubs($0))
    }
    # Count and sort the symbol table keys
    cnt = 0
    for (key in symtab) {
        if (all_flag || ! symbol_sys_p(key))
            keys[++cnt] = key
    }
    qsort(keys, 1, cnt)

    # Format definitions
    buf = ""
    for (i = 1; i <= cnt; i++) {
        key = keys[i]
        definition = get_symbol(key)
        sym_name = printable_form(key)
        if (index(definition, "\n") == IDX_NOT_FOUND)
            # No newline means it's a one-liner
            buf = buf "@define " sym_name "\t" definition "\n"
        else {
            buf = buf "@longdef " sym_name "\n"
            buf = buf definition           "\n"
            buf = buf "@longend"           "\n"
        }
    }
    buf = chop(buf)
    if (length(buf) > 0)
        print buf > dumpfile    # More portable: print_stderr(buf)
    close(dumpfile)
}


# @else
function m2_else()
{
    if (ifdepth == 0)
        error("No corresponding '@if':" $0)
    if (seen_else[ifdepth])
        error("Duplicate '@else' not allowed:" $0)
    seen_else[ifdepth] = TRUE
    active[ifdepth] = active[ifdepth-1] ? ! currently_active_p() : FALSE
}


# @endif, @fi
function m2_endif()
{
    if (ifdepth-- == 0)
        error("No corresponding '@if':" $0)
}


# @echo, @error, @stderr, @warn TEXT
function m2_error(    m2_will_exit, message)
{
    if (! currently_active_p())
        return
    m2_will_exit = ($1 == "@error")
    if (NF == 1) {
        message = format_message($1)
    } else {
        $1 = ""
        sub("^[ \t]*", "")
        message = dosubs($0)
    }
    print_stderr(message)
    if (m2_will_exit) {
        flush_stdout()
        exit EX_USER_REQUEST
    }
}


# @exit                 [CODE]
function m2_exit()
{
    if (! currently_active_p())
        return
    flush_stdout()
    exit (NF > 1 && integerp($2)) ? $2 : EX_OK
}


# @if[_not][_{defined|env|exists|in}], @if[n]def, @unless
function m2_if(    sym, cond, op, val2, val4)
{
    sub(/^@/, "")          # Remove leading @, otherwise dosubs($0) loses
    $0 = dosubs($0)

    if ($1 == "if") {
        if (NF == 2) {
            # @if [!]FOO
            if (first($2) == "!") {
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
        validate_env_var_name($2)
        cond = $2 in ENVIRON

    } else if ($1 == "if_not_env") {
        if (NF < 2) error("Bad parameters:" $0)
        validate_env_var_name($2)
        cond = ! ($2 in ENVIRON)

    } else if ($1 == "if_exists") {
        if (NF < 2) error("Bad parameters:" $0)
        cond = path_exists_p(rm_quotes($2))

    } else if ($1 == "if_not_exists") {
        if (NF < 2) error("Bad parameters:" $0)
        cond = ! path_exists_p(rm_quotes($2))

    # @if(_not)_in KEY ARR
    # Test if symbol ARR[KEY] is defined.  Key comes first, because in
    # Awk one says "key IN array" for the predicate.
    } else if ($1 == "if_in") {   # @if_in us-east-1 VALID_REGIONS
        # @if_in KEY ARR
        if (NF < 3) error("Bad parameters:" $0)
        validate_symbol($3)
        cond = aref_defined_p($3, $2)

    } else if ($1 == "if_not_in") {
        if (NF < 3) error("Bad parameters:" $0)
        validate_symbol($3)
        cond = ! aref_defined_p($3, $2)

    } else
        # Should not happen
        error("m2_if(): '" $1 "' not matched:" $0)

    active[++ifdepth] = currently_active_p() ? cond : FALSE
    seen_else[ifdepth] = FALSE
}


# @ignore               DELIM
function m2_ignore(    buf, delim, save_line, save_lineno)
{
    # Ignore input until line starts with $2.  This means
    #     @ignore The
    #       <...>
    #     Theodore Roosevelt
    # ignores <...> text up to the president's name.
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


# @include, @paste      FILE
function m2_include(    error_text, filename, read_literally)
{
    if (NF < 2) error("Bad parameters:" $0)
    if (! currently_active_p())
        return
    read_literally = ($1 == "@paste")   # @paste does not process macros
    $1 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))
    if (! dofile(filename, read_literally)) {
        error_text = "File '" filename "' does not exist:" $0
        if (strictp())
            error(error_text)
        else
            warn(error_text)
    }
}


# @decr, @incr          NAME [N]
function m2_incr(    incr, sym)
{
    if (NF < 2) error("Bad parameters:" $0)
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (NF >= 3 && ! integerp($3))
        error("Value '" $3 "' must be numeric:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
    if (! symbol_defined_p(sym))
        error("Symbol '" sym "' not defined [incr]:" $0)
    incr = (NF >= 3) ? $3 : 1
    incr_symbol(sym, ($1 == "@incr") ? incr : -incr)
}


# @input                [NAME]
function m2_input(    getstat, input, sym)
{
    # Read a single line from /dev/tty.  No prompt is issued; if you
    # want one, use @echo.  Specify the symbol you want to receive the
    # data.  If no symbol is specified, __INPUT__ is used by default.
    sym = (NF < 2) ? "__INPUT__" : $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    if (! currently_active_p())
        return
    validate_symbol(sym)
    getstat = getline input < "/dev/tty"
    if (getstat < 0) {
        warn("Error reading '/dev/tty' [input]:" $0)
        input = ""
    }
    set_symbol(sym, input)
}


# @let                  NAME TEXT
function m2_let(    sym, math, bcfile, val, cmd)
{
    dbg_print("let", 7, ("@let: NF=" NF " $0='" $0 "'"))
    if (NF < 3) error("Bad parameters:" $0)
    if (! currently_active_p())
        return

    sym = $2
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")
    math = "scale=" get_symbol("__SCALE__") "; " dosubs($0)
    bcfile = tmpdir() "m2-bcfile." get_symbol("__M2_UUID__")
    dbg_print("let", 7, ("@let: bcfile='" bcfile "', math='" math "'"))
    print math > bcfile
    close(bcfile)

    cmd = build_prog_cmdline("cat", bcfile) \
          " | " \
          build_prog_cmdline("bc", "-l") # pass "-l" (library) option to bc(1)
    val = ""
    while ((cmd | getline) > 0) {
        val = val $0 "\n"
    }
    close(cmd)
    exec_prog_cmdline("rm", ("-f " bcfile))
    set_symbol(sym, chop(val))
}


# @longdef              NAME
function m2_longdef(    buf, save_line, save_lineno, sym)
{
    if (NF != 2) error("Bad parameters:" $0)
    if (! currently_active_p())
        return
    save_line = $0
    save_lineno = get_symbol("__LINE__")
    sym = $2
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    validate_symbol(sym)
    buf = read_lines_until("@longend")
    if (buf == EOF)
        error("Delimiter '@longend' not found:" save_line, save_lineno)
    set_symbol(sym, buf)
}


# @longend
function m2_longend()
{
    # @longend should never be encountered alone because m2_longdef()
    # consumes any matching @longend.
    error("No corresponding '@longdef':" $0)
}


# @read                 NAME FILE
function m2_read(    sym, filename, line, val, getstat)
{
    # This is not intended to be a full-blown file inputter but rather just
    # to read short snippets like a file path or username.  As usual, multi-
    # line values are accepted but the final trailing \n (if any) is stripped.
    #dbg_print("read", 7, ("@read: $0='" $0 "'"))
    if (NF < 3) error("Bad parameters:" $0)
    if (! currently_active_p())
        return
    sym  = $2
    validate_symbol(sym)
    if (symbol_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
    $1 = $2 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))

    val = ""
    while (TRUE) {
        getstat = getline line < filename
        if (getstat < 0)        # Error
            warn("Error reading '" filename "' [read]")
        if (getstat <= 0)       # End of file
            break
        val = val line "\n"     # Read a line
    }
    close(filename)
    set_symbol(sym, chomp(val))
}


# @shell                DELIM [PROG]
# Set symbol "M2_SHELL" to override.
function m2_shell(    buf, delim, save_line, save_lineno, sendto)
{
    # The sendto program defaults to a reasonable shell but you can specify
    # where you want to send your data.  Possibly useful choices would be an
    # alternative shell, an email message reader, or /usr/bin/bc.
    if (NF < 2) error("Bad parameters:" $0)
    if (! currently_active_p())
        return
    save_line = $0
    save_lineno = get_symbol("__LINE__")
    delim = $2
    if (NF == 2) {              # @shell DELIM
        sendto = default_shell()
    } else {                    # @shell DELIM /usr/ucb/mail
        $1 = ""; $2 = ""
        sub("^[ \t]*", "")
        sendto = rm_quotes(dosubs($0))
    }

    buf = read_lines_until(delim)
    if (buf == EOF)
        error("Delimiter '" delim "' not found:" save_line, save_lineno)
    print dosubs(buf) | sendto
    close(sendto)
}


# @sleep                [N]
function m2_sleep(    sec)
{
    if (! currently_active_p())
        return
    sec = (NF > 1 && integerp($2)) ? $2 : 1
    flush_stdout()
    exec_prog_cmdline("sleep", sec)
}


# @typeout
function m2_typeout(    buf)
{
    if (! currently_active_p())
        return
    buf = read_lines_until("")
    if (length(buf) > 0)
        printf("%s\n", buf)
}


# @undef[ine]           NAME
function m2_undef(    sym)
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


# The high-level processing happens in the dofile() function, which
# reads one line at a time, and decides what to do with each line.  The
# activefiles array keeps track of open files.  The symbol __FILE__
# stores the current file to read data from.  When an "@include"
# directive is seen, dofile() is called recursively on the new file.
# Interestingly, the included filename is first processed for macros.
# Read this function carefully--there are some nice tricks here.
#
# Caller is responsible for removing potential quotes from filename.
function dofile(filename, read_literally,    savefile, saveline, savebuffer)
{
    if (filename == "-")
        filename = "/dev/stdin"
    if (! path_exists_p(filename))
        return FALSE
    dbg_print("m2", 1, ("dofile(" filename \
                        (read_literally ? ", read_literally=TRUE" : "") \
                        ")"))
    if (filename in activefiles)
        error("Cannot recursively read '" filename "':" $0)

    # Save old file context
    flush_stdout()
    savefile   = get_symbol("__FILE__")
    saveline   = get_symbol("__LINE__")
    saveuuid   = get_symbol("__FILE_UUID__")
    savebuffer = buffer

    # Set up new file context
    activefiles[filename] = TRUE
    buffer = ""
    incr_symbol("__NFILE__")
    set_symbol("__FILE__", filename)
    set_symbol("__LINE__", 0)
    set_symbol("__FILE_UUID__", uuid())

    # Read the file and process each line
    while (readline() == READ_OK)
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
    set_symbol("__FILE_UUID__", saveuuid)
    buffer = savebuffer

    return TRUE
}


# Put next input line into global string "buffer".  The readline()
# function manages the "pushback."  After expanding a macro, macro
# processors examine the newly created text for any additional macro
# names.  Only after all expanded text has been processed and sent to
# the output does the program get a fresh line of input.
# Return EOF or "" (null string)
function readline(    getstat, i, status)
{
    status = READ_OK
    if (buffer != "") {
        # Return the buffer even if somehow it doesn't end with a newline
        if ((i = index(buffer, "\n")) == IDX_NOT_FOUND) {
            $0 = buffer
            buffer = ""
        } else {
            $0 = substr(buffer, 1, i-1)
            buffer = substr(buffer, i+1)
        }
    } else {
        getstat = getline < get_symbol("__FILE__")
        if (getstat < 0) {      # Error
            status = READ_ERROR
            warn("Error reading '" get_symbol("__FILE__") "' [readline]")
        } else if (getstat == 0)  # End of file
            status = READ_EOF
        else                    # Read a line
            incr_symbol("__LINE__")
    }
    # Hack: allow @Mname at start of line without a closing @.
    # This only applies if in non-strict mode.  Note, macro name must
    # start with a capital letter and must not be passed any parameters.
    if (! strictp() && ($0 ~ /^@[A-Z][A-Za-z#$_0-9]*[ \t]*$/))
        sub(/[ \t]*$/, "@")
    return status
}


function process_line(read_literally,    newstring)
{
    # Short circuit if we're not processing macros, or no @ found
    if (read_literally ||
        (currently_active_p() && index($0, "@") == IDX_NOT_FOUND)) {
        printf("%s\n", $0)
        return
    }

    # Look for built-in control commands.
    # Note, these only match at beginning of line.
    if      (/^@(@|#)/)                  { } # Comments are ignored
    else if (/^@append([ \t]|$)/)        { m2_define() }
    else if (/^@c(omment)?([ \t]|$)/)    { } # Comments are ignored
    else if (/^@decr([ \t]|$)/)          { m2_incr() }
    else if (/^@default([ \t]|$)/)       { m2_default() }
    else if (/^@define([ \t]|$)/)        { m2_define() }
    else if (/^@dump(all)?([ \t]|$)/)    { m2_dump() }
    else if (/^@echo([ \t]|$)/)          { m2_error() }
    else if (/^@else([ \t]|$)/)          { m2_else() }
    else if (/^@endif([ \t]|$)/)         { m2_endif() }
    else if (/^@error([ \t]|$)/)         { m2_error() }
    else if (/^@exit([ \t]|$)/)          { m2_exit() }
    else if (/^@fi([ \t]|$)/)            { m2_endif() }
    else if (/^@if(_not)?(_(defined|env|exists|in))?([ \t]|$)/)
                                         { m2_if() }
    else if (/^@ifn?def([ \t]|$)/)       { m2_if() }
    else if (/^@ignore([ \t]|$)/)        { m2_ignore() }
    else if (/^@include([ \t]|$)/)       { m2_include() }
    else if (/^@incr([ \t]|$)/)          { m2_incr() }
    else if (/^@init(ialize)?([ \t]|$)/) { m2_default() }
    else if (/^@input([ \t]|$)/)         { m2_input() }
    else if (/^@let([ \t]|$)/)           { m2_let() }
    else if (/^@longdef([ \t]|$)/)       { m2_longdef() }
    else if (/^@longend([ \t]|$)/)       { m2_longend() }
    else if (/^@paste([ \t]|$)/)         { m2_include() }
    else if (/^@read([ \t]|$)/)          { m2_read() }
    else if (/^@rem([ \t]|$)/)           { } # Comments are ignored
    else if (/^@shell([ \t]|$)/)         { m2_shell() }
    else if (/^@sleep([ \t]|$)/)         { m2_sleep() }
    else if (/^@stderr([ \t]|$)/)        { m2_error() }
    else if (/^@typeout([ \t]|$)/)       { m2_typeout() }
    else if (/^@undef(ine)?([ \t]|$)/)   { m2_undef() }
    else if (/^@unless([ \t]|$)/)        { m2_if() }
    else if (/^@warn([ \t]|$)/)          { m2_error() }

    # Process @
    else {
        newstring = dosubs($0)
        if (newstring == $0 || index(newstring, "@") == IDX_NOT_FOUND) {
            if (currently_active_p())
                printf("%s\n", newstring)
        } else {
            buffer = newstring "\n" buffer
        }
    }
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
#     return L R
function dosubs(s,    expand, i, j, l, m, nparam, p, param, r, symfunc, cmd, at_brace)
{
    l = ""                   # Left of current pos  - ready for output
    r = s                    # Right of current pos - as yet unexamined
    while (TRUE) {
        i = index(r, "@")
        if (i == IDX_NOT_FOUND)
            break

        # Check entire string for recursive evaluation
        if (index(r, "@{") != IDX_NOT_FOUND) {
            r = expand_braces(r)
            i = index(r, "@")
            if (i == IDX_NOT_FOUND)
                break
        }

        # dbg_print("dosubs", 7, (sprintf("dosubs: top of loop: l='%s', r='%s', expand='%s'", l, r, expand)))
        l = l substr(r, 1, i-1)
        r = substr(r, i+1)      # Currently scanning @

        i = index(r, "@")
        if (i == IDX_NOT_FOUND) {
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
        #   param[N+1].  Consider "gensym foo 42".  nparam is 2.
        #   The symfunc is found in the first position, at param [0+1].
        #   The new prefix is at param[1+1] and new count is at param[2+1].
        #   This offset of one is referred to as `_fencepost' below.
        # Each symfunc condition eventually executes
        #     r = <SOMETHING> r
        #   which injects <SOMETHING> just before the current value of
        #   r.  (r is defined above.)  r is what is to the right of the
        #   current position and contains as yet unexamined text that
        #   needs to be evaluated for possible macro processing.  This
        #   is the data we were going to evaluate anyway.  In other
        #   words, this injects the result of "invoking" symfunc.
        # Eventually this big while loop exits and we return "l r".

        nparam = split(m, param) - _fencepost
        symfunc = param[0 + _fencepost]
        # dbg_print("dosubs", 7, sprintf("dosubs: symfunc=%s, nparam=%d; l='%s', m='%s', r='%s', expand='%s'", symfunc, nparam, l, m, r, expand))

        # basename SYM: Base (i.e., file name) of path
        if (symfunc == "basename") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            if (symbol_valid_p(p) && symbol_defined_p(p))
                p = get_symbol(p)
            cmd = build_prog_cmdline("basename", rm_quotes(p))
            cmd | getline expand
            close(cmd)
            r = expand r

        # boolval SYM: Print "1" if SYM is true, else "0"
        #   @boolval SYM@ => "0" or "1"     # error if not defined
        } else if (symfunc == "boolval") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined [boolval]:" $0)
            r = (symbol_true_p(p) ? "1" : "0") r

        # currdate : Current date as YYYY-MM-DD
        } else if (symfunc == "currdate") {
            cmd = build_prog_cmdline("date", "+'%Y-%m-%d'")
            cmd | getline expand
            close(cmd)
            r = expand r

        # currtime : Current time as HH:MM:SS
        } else if (symfunc == "currtime") {
            cmd = build_prog_cmdline("date", "+'%H:%M:%S'")
            cmd | getline expand
            close(cmd)
            r = expand r

        # dirname SYM: Directory name of path
        } else if (symfunc == "dirname") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            if (symbol_valid_p(p) && symbol_defined_p(p))
                p = get_symbol(p)
            cmd = build_prog_cmdline("dirname", rm_quotes(p))
            cmd | getline expand
            close(cmd)
            r = expand r

        # gensym ...: Generate symbol
        #   @gensym@        => _gen0
        #   @gensym 42@     => (prefix unchanged, count now 42) => _gen42
        #   @gensym foo 42@ => (prefix now "foo", count now 42) => foo42
        } else if (symfunc == "gensym") {
            if (nparam == 1) {
                # @gensym 42@
                if (! integerp(param[1 + _fencepost]))
                    error("Value '" m "' must be numeric:" $0)
                set_aref("__GENSYM__", "count", param[1 + _fencepost])
            } else if (nparam == 2) {
                # @gensym foo 42@
                if (! integerp(param[2 + _fencepost]))
                    error("Value '" m "' must be numeric:" $0)
                # Make sure the new requested prefix is valid
                validate_symbol(param[1 + _fencepost])
                set_aref("__GENSYM__", "prefix", param[1 + _fencepost])
                set_aref("__GENSYM__", "count",  param[2 + _fencepost])
            } else if (nparam > 2)
                error("Bad parameters in '" m "':" $0)

            # gensym returns something in all cases
            r = get_aref("__GENSYM__", "prefix") \
                get_aref("__GENSYM__", "count") \
                r
            incr_symbol("__GENSYM__[count]")

        # getenv : Get environment variable
        #   @getenv HOME@ => /home/user
        } else if (symfunc == "getenv") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_env_var_name(p)
            if (p in ENVIRON)
                r = ENVIRON[p] r
            else if (strictp())
                error("Environment variable '" p "' not defined:" $0)

        # lc : Lower case
        } else if (symfunc == "lc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined [lc]:" $0)
            r = tolower(get_symbol(p)) r

        # len : Length
        #   @len SYM@ => N
        } else if (symfunc == "len") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined [len]:" $0)
            r = length(get_symbol(p)) r

        # substr : Substring ...  SYMBOL, START[, LENGTH]
        #   @substr FOO 3@
        #   @substr FOO 2 2@
        } else if (symfunc == "substr") {
            if (nparam != 2 && nparam != 3)
                error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined [substr]:" $0)
            if (! integerp(param[2 + _fencepost]))
                error("Value '" m "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(get_symbol(p), param[2 + _fencepost]+1) r
            } else if (nparam == 3) {
                if (! integerp(param[3 + _fencepost]))
                    error("Value '" m "' must be numeric:" $0)
                r = substr(get_symbol(p), param[2 + _fencepost]+1, param[3 + _fencepost]) r
            }

        # trim SYM: Remove leading and trailing whitespace
        } else if (symfunc == "trim") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined [trim]:" $0)
            expand = get_symbol(p)
            sub(/^[ \t]+/, "", expand)
            sub(/[ \t]+$/, "", expand)
            r = expand r

        # tz : Time zone offset from UTC
        #   @tz@ => -0400
        } else if (symfunc == "tz") {
            cmd = build_prog_cmdline("date", "+'%z'")
            cmd | getline expand
            close(cmd)
            r = expand r

        # uc SYM: Upper case
        } else if (symfunc == "uc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            validate_symbol(p)
            if (! symbol_defined_p(p))
                error("Symbol '" p "' not defined [uc]:" $0)
            r = toupper(get_symbol(p)) r

        # uuid : Something that resembles but is not a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (symfunc == "uuid") {
            r = uuid() r

        # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
        } else if (symbol_valid_p(symfunc) && symbol_defined_p(symfunc)) {
            expand = get_symbol(symfunc)
            # Expand $N parameters (includes $0 for macro name)
            for (j = 0; j <= 9; j++)
                if (index(expand, "$" j) != IDX_NOT_FOUND) { # i.e., "found"
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$" j, param[j + _fencepost], expand)
                }
            r = expand r

        # Throw an error on undefined symbol (strict-only)
        } else if (strictp()) {
            error("Symbol '" m "' not defined [strict]:" $0)

        } else {
            l = l "@" m
            r = "@" r
        }
        i = index(r, "@")
    }

    # dbg_print("dosubs", 3, sprintf("dosubs: out of loop, returning l r: l='%s', r='%s'", l, r))
    return l r
}


function expand_braces(s,    atbr, cb, ltext, mtext, rtext)
{
    dbg_print("braces", 3, (">> expand_braces(s='" s "'"))

    while ((atbr = index(s, "@{")) != IDX_NOT_FOUND) {
        # There's a @{ somewhere in the string.  Find the matching
        # closing brace and expand the enclosed text.
        cb = find_closing_brace(s, atbr)
        if (cb <= 0)
            error("Bad @{...} expansion:" s, get_symbol("__LINE__"))
        dbg_print("braces", 5, ("   expand_braces: in loop, atbr=" atbr ", cb=" cb))

        # LTEXT  @{  MTEXT  }  RTEXT
        ltext = substr(s, 1,      atbr-1)
        mtext = substr(s, atbr+2, cb-atbr-2)
                gsub(/\\}/, "}", mtext)
        rtext = substr(s, cb+1)
        if (dbg("braces", 7)) {
            print_stderr("   expand_braces: ltext='" ltext "'")
            print_stderr("   expand_braces: mtext='" mtext "'")
            print_stderr("   expand_braces: rtext='" rtext "'")
        }

        s = ltext dosubs(mtext) rtext
    }

    dbg_print("braces", 3, ("<< expand_braces: returning '" s "'"))
    return s
}


# NAME
#     find_closing_brace
#
# DESCRIPTION
#     Given a starting point (position of @{ in string), move forward
# and return position of closing }.  Nested @{...} are accounted for.
# If closing } is not found, return 0.  On other error, return -1.
#
# PARAMETERS
#     s         String to examine
#     start     The position in s, not necessarily 1, of the "@{"
#               for which we need to find the closing brace.
#
# LOCAL VARIABLES
#     i         Counter of current offset into s from start.
#               Initially i=0.  As we scan right, i will be incremented.
#     c         The current character pointed to by i.
#                   c = substr(s, start+i, 1)
#     nc        The next character past i.
#                   nc = substr(s, start+i+1, 1)
#     cb        Position of inner "}" found via recursion
#
# RETURN VALUE
#     If successfully found a closing brace, return its position within s.
# The actual value returned is start+i.
#     If no closing brace is found, or the search proceeds beyond the end
# of the string (i.e., start+i > length(s)), return a "failure code" of 0.
# If the initial conditions are bad, return an "error code" of -1.
#
function find_closing_brace(s, start,    i, c, nc, cb, slen)
{
    dbg_print("braces", 3, (">> find_closing_brace(s='" s "', start=" start))

    # Check that we have at least two characters, and start points to "@{"
    slen = length(s)            # s is not modified so its length is constant
    if (slen - start + 1 < 2 || substr(s, start, 2) != "@{")
        return -1               # error

    # At this point, we've verified that we're looking at @{, so there
    # are at least two characters in the string.  Let's move along...
    i = 2

    # Look at the character (c) immediately following "@{", and also the
    # next character (nc) after that.  One or both might be empty string.
    c  = substr(s, start+i,   1)
    nc = substr(s, start+i+1, 1)

    while (start+i <= slen) {
        dbg_print("braces", 7, ("   find_closing_brace: i=" i ", c=" c ", nc=" nc))
        if (c == "") {          # end of string/error
            break
        } else if (c == "}") {
            dbg_print("braces", 3, ("<< find_closing_brace: returning " start+i))
            return start+i
        } else if (c == "\\" && nc == "}") {
            # "\}" in expansion text will result in a single close brace
            # without ending the expansion text scanner.  Skip over }
            # and do not return yet.  "\}" is fixed in expand_braces().
            i++; nc = substr(s, start+i+1, 1)
        } else if (c == "@" && nc == "{") {
            # "@{" in expansion text will invoke a recursive scan.
            cb = find_closing_brace(s, start+i)
            if (cb <= 0)
                return cb       # propagate failure/error

            # Since the return value is the *absolute* location of the
            # "}" in string s, update i to be the value corresponding to
            # that location.  In fact, i, being an offset, is exactly
            # the distance from that closing brace back to "start".
            i = cb - start
            nc = substr(s, start+i+1, 1)
            dbg_print("braces", 5, ("   find_closing_brace: (recursive) cb=" cb \
                                    ".  Now, i=" i ", nc=" nc))
        }

        # Advance to next character
        i++; c = nc; nc = substr(s, start+i+1, 1)
    }

    # If we fall out of the loop here, we never found a closing brace.
    return 0                    # failure
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
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")  # old bug: last * was +
    str = $0
    while (str ~ /\\$/) {
        if (readline() == READ_EOF)
            error("Unexpected end of definition:" name)
        # old bug: sub(/\\$/, "\n" $0, str)
        x = $0
        sub(/^[ \t]+/, "", x)
        str = chop(str) "\n" x
    }
    set_symbol(name, append_flag ? get_symbol(name) str : str)
}


# Try to read init files: $HOME/.m2rc and/or ./.m2rc
# No worries if they don't exist.
function load_init_files()
{
    # Don't load the init files more than once
    if (init_files_loaded == TRUE)
        return

    if ("HOME" in ENVIRON)
        dofile(ENVIRON["HOME"] "/.m2rc")
    dofile("./.m2rc")

    # Don't count init files in total file tally - it's better to keep
    # in sync with the command line.
    set_symbol("__NFILE__", 0)
    init_files_loaded = TRUE
}


# Change these paths as necessary for correct operation on your system.
# It is important that __PROG__ remain a protected symbol.  Otherwise,
# some bad person could entice you to evaluate:
#       @define __PROG__[stat]  /bin/rm
#       @include @getenv HOME@/my_precious_file
function setup_prog_paths()
{
    set_aref("__PROG__", "basename", "/usr/bin/basename")
    set_aref("__PROG__", "bc",       "/usr/bin/bc")
    set_aref("__PROG__", "cat",      "/bin/cat")
    set_aref("__PROG__", "date",     "/bin/date")
    set_aref("__PROG__", "dirname",  "/usr/bin/dirname")
    set_aref("__PROG__", "hostname", "/bin/hostname")
    set_aref("__PROG__", "id",       "/usr/bin/id")
    set_aref("__PROG__", "rm",       "/bin/rm")
    set_aref("__PROG__", "sh",       "/bin/sh")
    set_aref("__PROG__", "sleep",    "/bin/sleep")
    set_aref("__PROG__", "stat",     "/usr/bin/stat")
    set_symbol("__TMPDIR__",         "/tmp")
}


# Nothing here is user-customizable
function initialize(    d, dateout, egid, euid, host, hostname, user)
{
    TRUE              =  1
    FALSE             =  0

    EX_OK             =  0
    EX_M2_ERROR       =  1
    EX_USER_REQUEST   =  2
    EX_USAGE          = 64
    EX_NOINPUT        = 66
    IDX_NOT_FOUND     =  0
    READ_ERROR        = -1
    READ_EOF          =  0
    READ_OK           =  1

    exit_code         = EX_OK
    EOF               = build_subsep("EoF1", "EoF2") # Unlikely to occur in normal text
    init_files_loaded = FALSE
    ifdepth           =  0
    active[ifdepth]   = TRUE
    _fencepost        =  1
    buffer            = ""
    strbuf            = ""

    srand()                     # Seed random number generator
    setup_prog_paths()
    build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z'") | getline dateout;  split(dateout, d)
    build_prog_cmdline("id", "-g")                        | getline egid
    build_prog_cmdline("id", "-u")                        | getline euid
    build_prog_cmdline("hostname", "-s")                  | getline host
    build_prog_cmdline("hostname")                        | getline hostname
    build_prog_cmdline("id", "-un")                       | getline user

    set_symbol("__DATE__",           d[1] d[2] d[3])
    set_aref("__GENSYM__", "count",  0)
    set_aref("__GENSYM__", "prefix", "_gen")
    set_symbol("__GID__",            egid)
    set_symbol("__HOST__",           host)
    set_symbol("__HOSTNAME__",       hostname)
    set_symbol("__INPUT__",          "")
    set_symbol("__M2_UUID__",        uuid())
    set_symbol("__M2_VERSION__",     version)
    set_symbol("__NFILE__",          0)
    set_symbol("__SCALE__",          6)
    set_symbol("__STRICT__",         TRUE)
    set_symbol("__TIME__",           d[4] d[5] d[6])
    set_symbol("__TIMESTAMP__",      d[1] "-" d[2] "-" d[3] "T" \
                                     d[4] ":" d[5] ":" d[6] d[7])
    set_symbol("__UID__",            euid)
    set_symbol("__USER__",           user)

    unprotected_syms["__DBG__"]    = TRUE
    unprotected_syms["__INPUT__"]  = TRUE
    unprotected_syms["__SCALE__"]  = TRUE
    unprotected_syms["__STRICT__"] = TRUE
    unprotected_syms["__TMPDIR__"] = TRUE
}


# The main program occurs in the BEGIN procedure below.
BEGIN {
    initialize()

    # No command line arguments: process standard input.
    if (ARGC == 1) {
        load_init_files()
        exit_code = dofile("-") ? EX_OK : EX_NOINPUT

    # Else, process all command line files/macro definitions.
    } else if (ARGC > 1) {
        # Delay loading $HOME/.m2rc as long as possible.  This allows us
        # to set symbols on the command line which will have taken effect
        # by the time the init file loads.
        for (i = 1; i < ARGC; i++) {
            # Show each arg as we process it
            arg = ARGV[i]
            dbg_print("m2", 3, ("BEGIN: ARGV[" i "]:" arg))

            # If it's a definition on the command line, define it
            if (arg ~ /^([^= ][^= ]*)=(.*)/) {
                eq = index(arg, "=")
                name = substr(arg, 1, eq-1)
                if (name == "strict")
                    name = "__STRICT__"
                else if (name == "debug" || name == "dbg")
                    name = "__DBG__[m2]"
                val = substr(arg, eq+1)
                if (! symbol_valid_p(name))
                    error("Symbol '" name "' invalid name:" arg, i, "ARGV")
                if (symbol_protected_p(name))
                    error("Symbol '" name "' protected:" arg, i, "ARGV")
                set_symbol(name, val)

            # Otherwise load a file
            } else {
                load_init_files()
                if (! dofile(rm_quotes(arg))) {
                    warn("File '" arg "' does not exist", i, "ARGV")
                    exit_code = EX_NOINPUT
                }
            }
        }

        # If we get here with init_files_loaded still false, that means
        # we used up every ARGV defining symbols and didn't specify any
        # files.  Not specifying any input files, like ARGC==1, means to
        # read standard input, so that is what we must now do.
        if (! init_files_loaded) {
            load_init_files()
            exit_code = dofile("-") ? EX_OK : EX_NOINPUT
        }

    # ARGC < 1, can't happen...
    } else {
        print_stderr("Usage: m2 [NAME=VAL ...] [file ...]")
        exit_code = EX_USAGE
    }

    flush_stdout()
    exit exit_code
}
