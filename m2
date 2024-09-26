#!/usr/bin/awk -f
#!/usr/local/bin/mawk -f
#!/usr/local/bin/gawk -f

#*********************************************************** -*- mode: Awk -*-
#
#  File:        m2
#  Time-stamp:  <2024-09-26 09:30:40 cleyon>
#  Author:      Christopher Leyon <cleyon@gmail.com>
#  Created:     <2020-10-22 09:32:23 cleyon>
#
#  USAGE
#       m2 [NAME=VAL ...] [file ...]
#
#  DESCRIPTION
#       Line-oriented macro processor
#
#*****************************************************************************

BEGIN {
    M2_VERSION = "4.0.0"

    # Customize these paths as needed for correct operation on your system.
    # If a program is not available, it's okay to remove the entry entirely.
    PROG["basename"] = "/usr/bin/basename"
    PROG["date"]     = "/bin/date"
    PROG["dirname"]  = "/usr/bin/dirname"
    PROG["hostname"] = "/bin/hostname"
    PROG["id"]       = "/usr/bin/id"
    PROG["pwd"]      = "/bin/pwd"
    PROG["rm"]       = "/bin/rm"
    PROG["sh"]       = "/bin/sh"
    PROG["stat"]     = "/usr/bin/stat"
    PROG["uname"]    = "/usr/bin/uname"

    # Secure level 0 (default) allows user-code to run arbitrary
    # programs in a sub-shell.  This allows the @shell command to
    # function.  Secure level 1 prevents this, but does allow m2 to
    # utilise the (presumably secure) utilities listed above in PROG.
    # These are used to support more advanced m2 features, but are not
    # necessary for basic operation.  Secure level 2 prevents invoking
    # any programs, and will terminate with a security violation error
    # if an attempt is made.  At level 2, m2 does not know the current
    # time or date, host or user name, etc.
    __secure_level = 0

    # Largest legal diversion (stream) number.  Traditional m4 supports
    # nine diversions, but GNU m4 greatly increases that limit.  Despite
    # how bloated m2 may be, I don't have a need for more, but you might.
    MAX_STREAM = 9
}

# DO NOT CHANGE anything below this line

BEGIN {
    TRUE = OKAY      =  1
    FALSE = EOF      =  0
    ERROR = DISCARD  = -1
    EMPTY            = ""
    GLOBAL_NAMESPACE =  0

    # Exit codes
    EX_OK            =  0;              __exit_code = EX_OK
    EX_M2_ERROR      =  1
    EX_USER_REQUEST  =  2
    EX_NOINPUT       = 66

    # Flags
    TYPE_ANY         = "*";             FLAG_BLKARRAY    = "K"
    TYPE_ARRAY       = "A";             FLAG_BOOLEAN     = "B"
    TYPE_COMMAND     = "C";             FLAG_DEFERRED    = "D"
    TYPE_USER        = "U";             FLAG_IMMEDIATE   = "!"
    TYPE_FUNCTION    = "F";             FLAG_INTEGER     = "I"
    TYPE_SEQUENCE    = "Q";             FLAG_NUMERIC     = "N"
    TYPE_SYMBOL      = "S";             FLAG_READONLY    = "R"
                                        FLAG_WRITABLE    = "W"
                                        FLAG_SYSTEM      = "Y"

    FLAGS_READONLY_INTEGER = TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY FLAG_SYSTEM
    FLAGS_READONLY_NUMERIC = TYPE_SYMBOL FLAG_NUMERIC FLAG_READONLY FLAG_SYSTEM
    FLAGS_READONLY_SYMBOL  = TYPE_SYMBOL              FLAG_READONLY FLAG_SYSTEM

    FLAGS_WRITABLE_INTEGER = TYPE_SYMBOL FLAG_INTEGER FLAG_WRITABLE FLAG_SYSTEM
    FLAGS_WRITABLE_SYMBOL  = TYPE_SYMBOL              FLAG_WRITABLE FLAG_SYSTEM
    FLAGS_WRITABLE_BOOLEAN = TYPE_SYMBOL FLAG_BOOLEAN FLAG_WRITABLE FLAG_SYSTEM
}



#*****************************************************************************
#
#       S T R I N G   F U N C T I O N S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

# Predicate - empty string?
function emptyp(s)
{
    return length(s) == 0
}


# Return first character of s
function first(s)
{
    return substr(s, 1, 1)
}


function rest(s)
{
    return substr(s, 2)
}


# Return last character of s
function last(s)
{
    return substr(s, length(s), 1)
}


# Return s but with last character (usually "\n") removed
function chop(s)
{
    return substr(s, 1, length(s) - 1)
}


# If last character is newline, chop() it off
function chomp(s)
{
    return (last(s) == TOK_NEWLINE) ? chop(s) : s
}


# ltrim() - Remove whitespace on left
function ltrim(s)
{
    sub(/^[ \t]+/, "", s)
    return s
}


# rtrim() - Remove whitespace on right
function rtrim(s)
{
    sub(/[ \t]+$/, "", s)
    return s
}


# trim() - Remove whitespace on left and right
# function trim(s)
# {
#     sub(/^[ \t]+/, "", s)
#     sub(/[ \t]+$/, "", s)
#     return s
# }


# If s is surrounded by quotes, remove them.
function rm_quotes(s)
{
    if (length(s) >= 2 && first(s) == "\"" && last(s) == "\"")
        s = substr(s, 2, length(s) - 2)
    return s
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       M I S C   U T I L I T Y   F U N C T I O N S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function isalpha(s)
{
    return ((s >= "A" && s <= "Z") ||
            (s >= "a" && s <= "z"))
}


function isdigit(s)
{
    return (s >= "0" && s <= "9")
}


# Space characters are: space, TAB, newline, carriage return, form feed,
# and vertical tab
function isspace(pat)
{
    return pat ~ /^[ \t\n\r\f\v]$/
}


function abs(n)
{
    return n < 0 ? -n : n
}


function ppf__bool(x)
{
    return (x == 0 || x == "") ? "False" : "True"
}


function integerp(pat)
{
    return pat ~ /^[-+]?[0-9]+$/
}


function floatp(pat)
{
    return pat ~ /^[-+]?([0-9]+(\.[0-9]*)?([eE][-+]?[0-9]+)?|\.[0-9]+)$/
}


function with_trailing_slash(s)
{
    return s ((last(s) != "/") ? "/" : EMPTY)
}


function extract_cmd_name(text,
                          name)
{
    if (!match(text, "^@[a-zA-Z0-9_]+"))
        error("(extract_cmd_name) Could not understand command '" text "'")
    name = substr(text, 2, RLENGTH-1)
    dbg_print("xeq", 7, "(extract_cmd_name) '" text "' => '" name "'")
    return name
}


# Warning - Do not use this in the general case if you want to know if a
# string is "system" or not.  This code only checks for underscores in
# its argument, but there do exist system symbols which do not match
# this naming pattern.
function double_underscores_p(text)
{
    return text ~ /^__.*__$/
}


# Environment variable names must match the following regexp:
#       /^[A-Za-z_][A-Za-z_0-9]*$/
function env_var_name_valid_p(var)
{
    return var ~ /^[A-Za-z_][A-Za-z_0-9]*$/
}


# Throw an error if the environment variable name is not valid
function assert_valid_env_var_name(var)
{
    if (env_var_name_valid_p(var))
        return TRUE
    error("Name '" var "' not valid:" $0)
}


function path_exists_p(path,
                       status, not_used)
{
    if (secure_level() < 2)
        return exec_prog_cmdline("stat", path) == EX_OK
        
    # At security level 2+, exec_prog_cmdline() is disallowed,
    # so we'll use this workaround.
    #
    # WARNING: this code does not distinguish between non-existent and
    # unreadable files.
    status = (getline not_used < path)

    if (status > 0) {
        # Found
        close(path)
        return TRUE
    } else if (status == 0) {
        # Empty but readable
        close(path)
        return TRUE
    } else {
        # Error: non-existent or unreadable
        return FALSE
    }
}


function min(m, n)
{
    return m < n ? m : n
}

function max(m, n)
{
    return m > n ? m : n
}


# do normal rounding
# https://www.gnu.org/software/gawk/manual/html_node/Round-Function.html
function round(x,   ival, aval, fraction)
{
    ival = int(x)    # integer part, int() truncates

    # see if fractional part
    if (ival == x)   # no fraction
        return ival   # ensure no decimals

    if (x < 0) {
        aval = -x     # absolute value
        ival = int(aval)
        fraction = aval - ival
        if (fraction >= .5)
            return int(x) - 1   # -2.5 => -3
        else
            return int(x)       # -2.3 => -2
    } else {
        fraction = x - ival
        if (fraction >= .5)
            return ival + 1
        else
            return ival
    }
}


# 0  <=  randint(N)  <  N
# To generate a hex digit (0..15), say `randint(16)'
# To roll a die (generate 1..6),   say `randint(6)+1'.
function randint(n)
{
    return int(n * rand())
}


# Return a string of N random hex digits [0-9A-F].
function hex_digits(n,    s)
{
    s = EMPTY
    while (n-- > 0)
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


function secure_level()
{
    return sym_ll_read("__SECURE__", "", GLOBAL_NAMESPACE)
}


function LINE()
{
    return sym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
}


function FILE()
{
    return sym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
}


function strictp(ssys)
{
    if (ssys == EMPTY)
        error("(strictp) ssys cannot be empty!")
    # Use low-level function here, not sym_true_p(), to prevent infinite loop
    return sym_ll_read("__STRICT__", ssys, GLOBAL_NAMESPACE)
}


function build_prog_cmdline(prog, arg, mode)
{
    if (! sym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        error(sprintf("build_prog_cmdline: __PROG__[%s] not defined", prog))
    return sprintf("%s %s%s", \
                   sym_ll_read("__PROG__", prog, GLOBAL_NAMESPACE),  \
                   arg, \
                   ((mode == MODE_IO_SILENT) ? " >/dev/null 2>/dev/null" : EMPTY))
}


function exec_prog_cmdline(prog, arg,    sym)
{
    if (secure_level() >= 2)
        error("(exec_prog_cmdline) Security violation")

    if (! sym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        error(sprintf("(exec_prog_cmdline) __PROG__[%s] not defined", prog))
    return system(build_prog_cmdline(prog, arg, MODE_IO_SILENT)) # always silent
}


# Return a likely path for storing temporary files.
# This path is guaranteed to end with a "/" character.
function tmpdir(    t)
{
    if (sym_defined_p("M2_TMPDIR"))
        t = sym_fetch("M2_TMPDIR")
    else if ("TMPDIR" in ENVIRON)
        t = ENVIRON["TMPDIR"]
    else
        t = sym_ll_read("__TMPDIR__", "", GLOBAL_NAMESPACE)
    while (last(t) == TOK_NEWLINE)
        t = chop(t)
    return with_trailing_slash(t)
}


function default_shell()
{
    if (sym_defined_p("M2_SHELL"))
        return sym_fetch("M2_SHELL")
    if ("SHELL" in ENVIRON)
        return ENVIRON["SHELL"]
    return sym_ll_read("__PROG__", "sh", GLOBAL_NAMESPACE)
}


# ATMODE is a property of the source.  If there is no source, we're probably
# in the process of undiverting some streams after the program ends.  Streams
# are not processed for macros, so the default mode in this case is literal.
function curr_atmode(    src_block)
{
    if (stk_emptyp(__source_stack))
        return MODE_AT_LITERAL
    src_block = stk_top(__source_stack)
    dbg_print_block("ship_out", 7, src_block, "(curr_atmode) src_block [top of __source_stack]")
    if (! ((src_block, 0, "atmode") in blktab)) {
        error("(curr_atmode) Top block " src_block " does not have 'atmode'")
    }
    return blktab[src_block, 0, "atmode"]
}


# DSTBLK is a property of the parser.  There should always be at least a
# pass-through TERMINAL parser because initialize() creates it and it
# gets popped at the end of main().
function curr_dstblk(    top_block)
{
    if (stk_emptyp(__parse_stack))
        error("(curr_dstblk) Parse stack is empty!")
    top_block = stk_top(__parse_stack)
    dbg_print_block("ship_out", 7, top_block, "(curr_dstblk) top_block [top of __parse_stack]")
    if (! ((top_block, 0, "dstblk") in blktab)) {
        error("(curr_dstblk) Top block " top_block " does not have 'dstblk'")
    }
    return blktab[top_block, 0, "dstblk"] + 0
}


function ppf__mode(mode)
{
         if (mode == MODE_AT_LITERAL)       return "Literal"
    else if (mode == MODE_AT_PROCESS)       return "ProcessAt"
    else if (mode == MODE_IO_CAPTURE)       return "CaptureIO"
    else if (mode == MODE_IO_SILENT)        return "SilentIO"
    else if (mode == MODE_TEXT_PRINT)       return "PrintText"
    else if (mode == MODE_TEXT_STRING)      return "StringText"
    else if (mode == MODE_STREAMS_DISCARD)  return "DiscardStream"
    else if (mode == MODE_STREAMS_SHIP_OUT) return "ShipOutStream"
    # else
    #     error("(ppf__mode) Unknown mode '" mode "'")
    else return "UnknownMode('" mode "')"
}


function raise_namespace()
{
    __namespace++
    dbg_print("namespace", 4, "(raise_namespace) namespace now " __namespace)
    return __namespace
}


function lower_namespace()
{
    if (__namespace == GLOBAL_NAMESPACE)
        error("(lower_namespace) Cannot be called from global namespace")
    sym_purge(__namespace)
    nam_purge(__namespace)
    __namespace--
    dbg_print("namespace", 4, "(lower_namespace) namespace now " __namespace)
    return __namespace
}


# Return value:
#       0       No problems detected
#       1       Parse stack is empty
#       2       Parser mismatch (block type not as expected)
#       3       Depth problem mismatch
# In error cases, warning messages are printed.
function check__parse_stack(expected_block_type,
                                btop)
{
    if (stk_emptyp(__parse_stack)) {
        __m2_msg = "Empty parse stack"
        return ERR_PARSE_STACK
    }

    btop = stk_top(__parse_stack)
    if (blk_type(btop) != expected_block_type) {
        __m2_msg = sprintf("Missing parser; wanted %s but found %s", 
                           ppf__block_type(expected_block_type), ppf__block_type(blk_type(btop)))
        return ERR_PARSE_MISMATCH
    }

    # We have to subtract 1 because the original "depth" was stored
    # before the block was pushed onto the __parse_stack; and at this
    # point it hasn't been popped yet...
    if (blktab[btop, 0, "depth"] != stk_depth(__parse_stack) - 1) {
        __msg_msg = sprintf("Bad depth; wanted %d but found %d",
                            stk_depth(__parse_stack) - 1, blktab[btop, 0, "depth"])
        return ERR_PARSE_DEPTH
    }

    return ERR_OKAY
}


function expand_braces(s,    atbr, cb, ltext, mtext, rtext)
{
    dbg_print("braces", 3, (">> expand_braces(s='" s "'"))

    while ((atbr = index(s, "@{")) > 0) {
        # There's a @{ somewhere in the string.  Find the matching
        # closing brace and expand the enclosed text.
        cb = find_closing_brace(s, atbr)
        if (cb <= 0)
            error("Bad @{...} expansion:" s)
        dbg_print("braces", 5, ("   expand_braces: in loop, atbr=" atbr ", cb=" cb))

        #      atbr---v
        # s == LTEXT  @{  MTEXT  }  RTEXT
        #                        ^---cb
        ltext = substr(s, 1,      atbr-1)
        mtext = substr(s, atbr+2, cb-atbr-2)
                gsub(/\\}/, "}", mtext)
        rtext = substr(s, cb+1)
        if (dbg("braces", 7)) {
            print_stderr("   expand_braces: ltext='" ltext "'")
            print_stderr("   expand_braces: mtext='" mtext "'")
            print_stderr("   expand_braces: rtext='" rtext "'")
        }

        while (length(mtext) >= 2 && first(mtext) == TOK_AT && last(mtext) == TOK_AT)
            mtext = substr(mtext, 2, length(mtext) - 2)
        s = !emptyp(mtext) ? ltext dosubs(TOK_AT mtext TOK_AT) rtext \
                           : ltext                             rtext
    }

    dbg_print("braces", 3, ("<< expand_braces: => '" s "'"))
    return s
}


# NAME
#     find_closing_brace
#
# DESCRIPTION
#     Given a starting point (position of @{ in string), move forward
#     and return position of closing }.  Nested @{...} are accounted for.
#     If closing } is not found, return EOF.  On other error, return ERROR.
#
# PARAMETERS
#     s         String to examine.
#     start     The position in s, not necessarily 1, of the "@{"
#               for which we need to find the closing brace.
#
# LOCAL VARIABLES
#     offset    Counter of current offset into s from start.
#               Initially offset=0.  As we scan right, offset is incremented.
#     c         The current character, at position offset.
#                   c = substr(s, start+offset, 1)
#     nc        The next character past c, at position offset+1.
#                   nc = substr(s, start+offset+1, 1)
#     cb        Position of inner "}" found via recursion.
#     slen      Length of s.  s is not modified so its length is constant.
#
# RETURN VALUE
#     If successfully found a closing brace, return its position within s.
#     The actual value returned is start+offset.  If no closing brace is
#     found, or the search proceeds beyond the end of the string (i.e.,
#     start+offset > length(s)), return EOF as a "failure code".  If the
#     initial conditions are bad, return ERROR.
#
function find_closing_brace(s, start,    offset, c, nc, cb, slen)
{
    dbg_print("braces", 3, (">> find_closing_brace(s='" s "', start=" start))

    # Check that we have at least two characters, and start points to "@{"
    slen = length(s)
    if (slen - start + 1 < 2 || substr(s, start, 2) != "@{")
        return ERROR

    # At this point, we've verified that we're looking at @{, so there
    # are at least two characters in the string.  Let's move along...
    # Look at the character (c) immediately following "@{", and also the
    # next character (nc) after that.  One or both might be empty string.
    offset = 2
    c  = substr(s, start+offset,   1)
    nc = substr(s, start+offset+1, 1)

    while (start+offset <= slen) {
        dbg_print("braces", 7, ("   find_closing_brace: offset=" offset ", c=" c ", nc=" nc))
        if (c == "") {          # end of string/error
            break
        } else if (c == TOK_RBRACE) {
            dbg_print("braces", 3, ("<< find_closing_brace: => " start+offset))
            return start+offset
        } else if (c == "\\" && nc == TOK_RBRACE) {
            # "\}" in expansion text will result in a single close brace
            # without ending the expansion text parser.  Skip over }
            # and do not return yet.  "\}" is fixed in expand_braces().
            offset++; nc = substr(s, start+offset+1, 1)
        } else if (c == TOK_AT && nc == TOK_LBRACE) {
            # "@{" in expansion text will invoke a recursive scan.
            cb = find_closing_brace(s, start+offset)
            if (cb <= 0)
                return cb       # propagate failure/error

            # Since the return value is the *absolute* location of the
            # "}" in string s, update i to be the value corresponding to
            # that location.  In fact, i, being an offset, is exactly
            # the distance from that closing brace back to "start".
            offset = cb - start
            nc = substr(s, start+offset+1, 1)
            dbg_print("braces", 5, ("   find_closing_brace: (recursive) cb=" cb \
                                    ".  Now, offset=" offset ", nc=" nc))
        }

        # Advance to next character
        offset++; c = nc; nc = substr(s, start+offset+1, 1)
    }

    # If we fall out of the loop here, we never found a closing brace.
    return EOF
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       I  /  O   F U N C T I O N S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

#  "m2:"  FILE  ":"  LINE  ":"  TEXT
function format_message(text, file, line,    s)
{
    file = file ""
    if (file == EMPTY)
        file = FILE()
    if (file == "/dev/stdin" || file == "-")
        file = "<STDIN>"
    line = line ""
    if (line == EMPTY)
        line = LINE()

    # If file and line are provided with default values, why is the if()
    # guard still necessary?  Ah, because this function might get invoked
    # very early in m2 execution, before the symbol table is populated.
    # The defaults are therefore empty, resulting in superfluous ":"s.
              s =   "m2" TOK_COLON
    if (file) s = s file TOK_COLON
    if (line) s = s line TOK_COLON
    if (text) s = s text
    return s
}


function flush_stdout(flushlev)
{
    if (flushlev <= sym_ll_read("__SYNC__", "", GLOBAL_NAMESPACE)) {
        # One of these is bound to work, right?
        fflush("/dev/stdout")
        # Reputed to be more portable:
        #    system("")
        # Also, fflush("") will flush ALL files and pipes.  (gawk-specific?)
    }
}


function print_stderr(text)
{
    printf "%s\n", text > "/dev/stderr"
    # Definitely more portable:
    #    print text | "cat 1>&2"
}


function warn(text, file, line)
{
    print_stderr(format_message(text, file, line))
}


function error(text, file, line)
{
    warn(text, file, line)
    __exit_code = EX_M2_ERROR
    end_program(MODE_STREAMS_DISCARD)
}


# Put next input line into global string "__buffer".  The readline()
# function manages the "pushback."  After expanding a macro, macro
# processors examine the newly created text for any additional macro
# names.  Only after all expanded text has been processed and sent to
# the output does the program get a fresh line of input.
# Return OKAY, ERROR, or EOF.  parse() is the only caller of readline.
# (That used to be true, but read_lines_until() now also calls readline.)
function readline(    getstat, i)
{
    getstat = OKAY
    if (!emptyp(__buffer)) {
        # Return the buffer even if somehow it doesn't end with a newline
        if ((i = index(__buffer, TOK_NEWLINE)) == IDX_NOT_FOUND) {
            $0 = __buffer
            __buffer = EMPTY
        } else {
            $0 = substr(__buffer, 1, i-1)
            __buffer = substr(__buffer, i+1)
        }

    } else if (blk_type(stk_top(__source_stack)) == SRC_STRING) {
        dbg_print("io", 6, "(readline) [STRING] RETURNING EOF")
        return EOF

    } else {
        dbg_print("io", 8, "source_stack count = " stk_depth(__source_stack))
        dbg_print_block("io", 7, stk_top(__source_stack), "In readline:")
        getstat = getline < FILE()
        if (getstat == ERROR) {
            warn("(readline) getline=>Error reading file '" FILE() "'")
        } else if (getstat != EOF) {
            sym_increment("__LINE__", 1)
            sym_increment("__NLINE__", 1)
        }
    }
    dbg_print("io", 6, sprintf("(readline) RETURNING %d, $0='%s'", getstat, $0))
    return getstat
}


# Read multiple lines until regexp is seen on a line and return TRUE.  If is not found,
# return FALSE.  The lines are always read literally.  Special case if
# regexp is "": read until end of file and return whatever is found,
# without error.
function read_lines_until(regexp, dstblk,
                          readstat)
{
    dbg_print("parse", 3, sprintf("(read_lines_until) START; regexp='%s', dstblk=%d",
                                 regexp, dstblk))
    if (dstblk == TERMINAL)
        error("(read_lines_until) dstblk must not be 0")

    while (TRUE) {
        readstat = readline()   # OKAY, EOF, ERROR
        if (readstat == ERROR) {
            # Whatever just happened, the read didn't finish properly
            dbg_print("parse", 1, "(read_lines_until) readline()=>ERROR")
            return FALSE
        }
        if (readstat == EOF) {
            dbg_print("parse", 5, "(read_lines_until) readline()=>EOF")
            return regexp == EMPTY
        }

        dbg_print("parse", 5, "(read_lines_until) readline()=>OKAY; $0='" $0 "'")
        if (regexp != EMPTY && match($0, regexp)) {
            dbg_print("parse", 5, "(read_lines_until) END => TRUE")
            return TRUE
        }

        if (dstblk > 0)
            blk_append(dstblk, OBJ_TEXT, $0)
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       D E B U G   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
BEGIN {
    TOK_SPACE = " "
    namtab["__SECURE__",     GLOBAL_NAMESPACE] = FLAGS_WRITABLE_INTEGER
    symtab["__SECURE__", "", GLOBAL_NAMESPACE, "symval"] = __secure_level

    # Early initialize debug configuration.  This makes `gawk --lint' happy.
    namtab["__DEBUG__",      GLOBAL_NAMESPACE] = FLAGS_WRITABLE_BOOLEAN
    symtab["__DEBUG__", "",  GLOBAL_NAMESPACE, "symval"] = FALSE

    namtab["__DBG__", GLOBAL_NAMESPACE] = TYPE_ARRAY FLAG_SYSTEM
    split("args block bool braces case cmd del divert dosubs dump expr for if io" \
          " nam namespace parse read seq ship_out stk sym while xeq",
          _dbg_sys_array, TOK_SPACE)
    for (_dsys in _dbg_sys_array) {
        __dbg_sysnames[_dbg_sys_array[_dsys]] = TRUE
    }
}


# This function is called automagically (it's baked into sym_ll_write())
# every time a non-zero value is stored into __DEBUG__.
function initialize_debugging()
{
    dbg_set_level("args",       0)
    dbg_set_level("block",      0)
    dbg_set_level("bool",       5)
    dbg_set_level("braces",     0)
    dbg_set_level("case",       5)
    dbg_set_level("cmd",        6)
    dbg_set_level("del",        5)
    dbg_set_level("divert",     7)
    dbg_set_level("dosubs",     7)
    dbg_set_level("dump",       5)
    dbg_set_level("expr",       0)
    dbg_set_level("for",        5)
    dbg_set_level("if",         5)
    dbg_set_level("io",         3)
    dbg_set_level("nam",        3)
    dbg_set_level("namespace",  5)
    dbg_set_level("read",       0)
    dbg_set_level("parse",      7)
    dbg_set_level("seq",        3)
    dbg_set_level("ship_out",   3)
    dbg_set_level("stk",        5)
    dbg_set_level("sym",        3)
    dbg_set_level("while",      5)
    dbg_set_level("xeq",        5)

    sym_ll_write("__SYNC__",      "", GLOBAL_NAMESPACE, SYNC_LINE)
}


function clear_debugging(    dsys)
{
    for (dsys in __dbg_sysnames)
        sym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, 0)
    # sym_ll_write("__SYNC__",      "", GLOBAL_NAMESPACE, SYNC_FILE)
}


function debugp()
{
    return sym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE)+0 > 0
}


# Predicate: TRUE if debug system level >= provided level (lev).
# Example:
#     if (dbg("sym", 3))
#         warn("Debugging sym at level 3 or higher")
# NB - do NOT call sym_defined_p() here, you will get infinite recursion
function dbg(dsys, lev)
{
    if (lev == EMPTY)           lev = 1
    if (dsys == EMPTY)          error("(dbg) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) error("(dbg) Unknown dsys name '" dsys "' (lev=" lev "): " $0)
    if (lev < 0)                return TRUE
    if (!debugp())              return FALSE
    if (lev == 0)               return TRUE
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    if (!sym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
        return FALSE
    return dbg_get_level(dsys) >= lev
}


# Return the debug level for a given dsys.  If debugging is not enabled,
# return its negative value (i.e., multiply by -1) to indicate this.
#
# Caller can easily call abs() to get the correct value.  Currently,
# dbg() is the only caller of this, and negative values are always
# going to be less than any LEV.
function dbg_get_level(dsys)
{
    if (dsys == EMPTY) error("(dbg_get_level) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) error("(dbg_get_level) Unknown dsys name '" dsys "'")
    # return (sym_fetch(sprintf("%s[%s]", "__DBG__", dsys))+0) \
    if (!sym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
        return 0
    return (sym_ll_read("__DBG__", dsys, GLOBAL_NAMESPACE)+0) \
         * (debugp() ? 1 : -1)
}


# Set the level (lev) for the debug dsys
function dbg_set_level(dsys, lev)
{
    if (dsys == EMPTY)           error("(dbg_set_level) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) error("(dbg_set_level) Unknown dsys name '" dsys "'")
    if (lev == EMPTY)           lev = 1
    # Formerly, negative levels were automagically set to zero.
    # Now, the new level is the absolute value.  Since dbg_get_level()
    # returns a negative level when not debugging, this new version
    # allows the following:
    #           foolev = dbg_get_level("foo")
    #           dbg_set_level("foo", 7)
    #           ...
    #           dbg_set_level("foo", foolev)
    # regardless of whether debugging is enabled or not.  It does mean
    # dbg_set_level("foo", -4) doesn't quite do what you say, but that
    # idiom was never supported before anyway.
    if (lev < 0)                lev = abs(lev)
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    sym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, lev+0)
}


function dbg_print(dsys, lev, text,
                   retval)
{
    if (dbg(dsys, lev))
        print_stderr(text)
}


function dbg_print_block(dsys, lev, blknum, description,
                         block_type, blk_label, text)
{
    if (! dbg(dsys, lev))
        return
##    blknum = blknum+0
    # print_stderr("(dbg_print_block) blknum = " blknum)
    if (! ((blknum, 0, "type") in blktab))
        error("(dbg_print_block) No 'type' field for block " blknum)
    block_type = blk_type(blknum)
    blk_label = ppf__block_type(block_type)
    # print_stderr("(dbg_print_block) block_type = " block_type)

    print_stderr(sprintf("Block # %d, Type=%s: %s", blknum, blk_label, description))
    print_stderr(ppf__BLK(blknum))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       B L O C K   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function blk_new(block_type,
                  new_blknum)
{
    if (block_type == EMPTY)
        error("(blk_new) Missing type")
    new_blknum = ++__block_cnt
    blktab[new_blknum, 0, "depth"] = stk_depth(__parse_stack)
    blktab[new_blknum, 0, "type"] = block_type
    if (block_type == BLK_AGG)
        blktab[new_blknum, 0, "count"] = 0
    else if (block_type == BLK_CASE)
        blktab[new_blknum, 0, "terminator"] = "@(endcase|esac)"
    else if (block_type == BLK_IF)
        blktab[new_blknum, 0, "terminator"] = "@(endif|fi)"
    else if (block_type == SRC_FILE) {
        blktab[new_blknum, 0, "open"] = FALSE
        blktab[new_blknum, 0, "terminator"] = ""
        blktab[new_blknum, 0, "oob_terminator"] = "EOF"
    } else if (block_type == SRC_STRING) {
        blktab[new_blknum, 0, "terminator"] = ""
        blktab[new_blknum, 0, "oob_terminator"] = "EOS"
    } else if (block_type == BLK_FOR)
        blktab[new_blknum, 0, "terminator"] = "@next"
    else if (block_type == BLK_LONGDEF)
        blktab[new_blknum, 0, "terminator"] = "@endlong(def)?"
    else if (block_type == BLK_TERMINAL) {
        blktab[new_blknum, 0, "dstblk"] = TERMINAL
        blktab[new_blknum, 0, "terminator"] = ""
    } else if (block_type == BLK_USER)
        blktab[new_blknum, 0, "terminator"] = "@endcmd"
    else if (block_type == BLK_WHILE)
        blktab[new_blknum, 0, "terminator"] = "@(endwhile|wend)"
    else
        error("(blk_new) Uncaught block_type '" block_type "'")

    dbg_print("ship_out", 1, sprintf("(blk_new) Block # %d; type=%s",
                                      new_blknum, ppf__block_type(block_type)))
    return new_blknum
}


function blk_type(blknum,
                  bt)
{
    if (! ((blknum, 0, "type") in blktab))
        error("(blk_type) Block # " blknum " has no type!")
    bt = blktab[blknum, 0, "type"]
    if (! (bt in __blk_label))
        error("(blk_type) Block # " blknum " has invalid block type '" bt "'")
   return bt
}


function blk_ll_slot_type(blknum, slot)
{
    if ((blknum, slot, "slot_type") in blktab)
        return blktab[blknum, slot, "slot_type"]
    error("(blk_ll_slot_type) Not found: blknum=" blknum ", slot=" slot)
}


function blk_ll_slot_value(blknum, slot)
{
    if ((blknum, slot, "slot_value") in blktab)
        return blktab[blknum, slot, "slot_value"]
    error("(blk_ll_slot_value) Not found: blknum=" blknum ", slot=" slot)
}


function blk_ll_write(blknum, slot, type, new_val)
{
    blktab[blknum, slot, "slot_type"]  = type
    blktab[blknum, slot, "slot_value"] = new_val
    return new_val
}


function blk_append(blknum, slot_type, value,
                     slot)
{
    if (blk_type(blknum) != BLK_AGG)
        error(sprintf("(blk_append) Block %d has type %s, not AGG",
                      blknum, ppf__block_type(blk_type(blknum))))

    if (slot_type != OBJ_CMD  && slot_type != OBJ_BLKNUM &&
        slot_type != OBJ_TEXT && slot_type != OBJ_USER)
        error(sprintf("(blk_append) Argument has bad type %s; should be OBJ_{CMD,BLKNUM,TEXT,USER}", ppf__block_type(slot_type)))

    slot = ++blktab[blknum, 0, "count"]
    dbg_print("ship_out", 3,
              sprintf("(blk_append) blknum=%d, slot=%d, slot_type=%s, value='%s'",
                      blknum, slot, ppf__block_type(slot_type), value))
    blk_ll_write(blknum, slot, slot_type, value)
}


function blk_dump_blktab(    x, k, blknum, seen, type)
{
    for (k in blktab) {
        split(k, x, SUBSEP)
        blknum = x[1] + 0
        if (! (blknum in seen)) {
            type = blk_type(blknum+0)
            dbg_print("xeq", 5, "(blk_dump_blktab) type=" type)
            dbg_print_block("xeq", -1, blknum, "(blk_dump_blktab)")
        }
        seen[blknum]++
    }
    return "(blk_dump_blktab)"
}


function blk_dump_block_raw(blknum,
                            x, k, blk, type)
{
    type = blk_type(blknum)
    dbg_print("xeq", 5, "(blk_dump_blktab) type=" type)
    dbg_print_block("xeq", -1, blknum, "(blk_dump_blktab)")

    for (k in blktab) {
        split(k, x, SUBSEP)
        blk = x[1] + 0
        if (blk == blknum) {
            print k
            print x[1], "/", x[2], "/", x[3], "/", x[4]
        }
    }
}


function blk_to_string(blknum,
                        string, old_print_mode, old_textbuf)
{
    # Save original settings
    old_textbuf = __textbuf
    old_print_mode = __print_mode

    # Set up for string output, and do it
    __textbuf = EMPTY
    __print_mode = MODE_TEXT_STRING
    execute__block(blknum)
    string = __textbuf

    # Restore old settings
    __print_mode = old_print_mode
    __textbuf = old_textbuf

    return chomp(string)
}


function ppf__block_type(block_type)
{
    if (block_type == EMPTY)
        error("(ppf__block_type) block_type is empty, how did that happen?")
    dbg_print("xeq", 7, "(ppf__block_type) block_type = " block_type)
    if (! (block_type in __blk_label)) {
        error("(ppf__block_type) Invalid block type '" block_type "'")
    }
    return __blk_label[block_type]
}


function ppf__block(blknum,
                    block_type, buf)
{
    block_type = blk_type(blknum)
    dbg_print("xeq", 3, sprintf("(ppf__block) START blknum=%d, type=%s",
                                blknum, ppf__block_type(block_type)))

    if      (block_type == BLK_AGG)       buf = ppf__agg(blknum)
    else if (block_type == BLK_CASE)      buf = ppf__case(blknum)
    else if (block_type == SRC_FILE)      buf = EMPTY
    else if (block_type == BLK_FOR)       buf = ppf__for(blknum)
    else if (block_type == BLK_IF)        buf = ppf__if(blknum)
    else if (block_type == BLK_LONGDEF)   buf = ppf__longdef(blknum)
    else if (block_type == BLK_TERMINAL)  buf = EMPTY
    else if (block_type == BLK_USER)      buf = ppf__user(blknum)
    else if (block_type == BLK_WHILE)     buf = ppf__while(blknum)
    else
        error(sprintf("(ppf__block) Block # %d: type %s (%s) not handled",
                      blknum, block_type, ppf__block_type(block_type)))
    return buf
}


function ppf__BLK(blknum,
                  block_type, text)
{
    block_type = blk_type(blknum)
    dbg_print("xeq", 3, sprintf("(ppf__BLK) START blknum=%d, type=%s",
                                blknum, ppf__block_type(block_type)))

    if      (block_type == BLK_AGG)      text = ppf__BLK_AGG(blknum)
    else if (block_type == BLK_CASE)     text = ppf__BLK_CASE(blknum)
    else if (block_type == SRC_FILE)     text = ppf__SRC_FILE(blknum)
    else if (block_type == SRC_STRING)   text = ppf__SRC_STRING(blknum)
    else if (block_type == BLK_FOR)      text = ppf__BLK_FOR(blknum)
    else if (block_type == BLK_IF)       text = ppf__BLK_IF(blknum)
    else if (block_type == BLK_LONGDEF)  text = ppf__BLK_LONGDEF(blknum)
    else if (block_type == BLK_USER)     text = ppf__BLK_USER(blknum)
    else if (block_type == BLK_TERMINAL) text = EMPTY
    else if (block_type == BLK_WHILE)    text = ppf__BLK_WHILE(blknum)
    else
        error(sprintf("(ppf__BLK) Can't handle type '%s' for block %d",
                      block_type, blknum))

    return text
}


function execute__block(blknum,
                        block_type, old_level)
{
    block_type = blk_type(blknum)
    dbg_print("xeq", 3, sprintf("(execute__block) START blknum=%d, type=%s",
                                blknum, ppf__block_type(block_type)))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg_print("xeq", 3, "(execute__block) NOP due to __xeq_ctl=" __xeq_ctl)
        return
    }

    old_level = __namespace
    if      (block_type == BLK_AGG)       xeq__BLK_AGG(blknum)
    else if (block_type == BLK_CASE)      xeq__BLK_CASE(blknum)
    else if (block_type == BLK_FOR)       xeq__BLK_FOR(blknum)
    else if (block_type == BLK_IF)        xeq__BLK_IF(blknum)
    else if (block_type == BLK_LONGDEF)   xeq__BLK_LONGDEF(blknum)
    else if (block_type == BLK_USER)      xeq__BLK_USER(blknum)
    else if (block_type == BLK_WHILE)     xeq__BLK_WHILE(blknum)
    else
        error(sprintf("(execute__block) Block # %d: type %s (%s) not handled",
                      blknum, block_type, ppf__block_type(block_type)))

    if (__namespace != old_level)
        error(sprintf("(execute__block) blknum=%d, type=%s: %s; old_level=%d, __namespace=%d",
                      blknum, ppf__block_type(block_type), "Namespace level mismatch", old_level, __namespace))
}


function xeq__BLK_AGG(agg_block,
                      i, lim, slot_type, value, block_type, name)
{
    block_type = blk_type(agg_block)
    dbg_print("xeq", 3, sprintf("(xeq__BLK_AGG) START dstblk=%d, agg_block=%d, type=%s",
                                curr_dstblk(), agg_block, ppf__block_type(block_type)))

    dbg_print_block("xeq", 7, agg_block, "(xeq__BLK_AGG) agg_block")
    lim = blktab[agg_block, 0, "count"]
    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(agg_block, i)
        value = blk_ll_slot_value(agg_block, i)
        dbg_print("xeq", 3, sprintf("(xeq__BLK_AGG) LOOP; dstblk=%d, agg_block=%d, slot=%d, slot_type=%s, value='%s'",
                                    curr_dstblk(), agg_block, i, ppf__block_type(slot_type), value))

        dbg_print("xeq", 3, sprintf("(xeq__BLK_AGG) CALLING ship_out(%s, '%s')", slot_type, value))
        ship_out(slot_type, value)
        dbg_print("xeq", 3, "(xeq__BLK_AGG) RETURNED FROM ship_out()")
    }
}


function ppf__agg(agg_block,
                  lim, i, slot_type, value, buf)
{
    if (blk_type(agg_block) != BLK_AGG)
        error(sprintf("(ppf__agg) Block %d type != AGG",
                      agg_block))
    lim = blktab[agg_block, 0, "count"]
    buf = ""
    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(agg_block, i)
        value = blk_ll_slot_value(agg_block, i)

        if (slot_type == OBJ_BLKNUM)
            buf = buf ppf__block(value) TOK_NEWLINE
        else if (slot_type == OBJ_CMD  ||
                 slot_type == OBJ_TEXT ||
                 slot_type == OBJ_USER) {
            buf = buf value TOK_NEWLINE
        } else
            error(sprintf("(ppf__agg) Bad slot type %s", slot_type))
    }

    return chomp(buf)
}


function ppf__BLK_AGG(blknum,
                      slotinfo, count, x)
{
    slotinfo = ""
    count = blktab[blknum, 0, "count"]
    if (count > 0 ) {
        slotinfo = "  Slots:\n"
        for (x = 1; x <= count; x++)
            slotinfo = slotinfo sprintf("  [%d]=%s: %s\n",
                                        x,
                                        ppf__block_type(blk_ll_slot_type(blknum, x)),
                                        blk_ll_slot_value(blknum, x))
    }
    return sprintf("  count   : %d\n" \
                   "%s",
                   count,
                   chomp(slotinfo))

}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       C O M M A N D   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# function cmd_defined_p(name, code)
# {
#     print_stderr("(cmd_defined_p) BROKEN")
#     if (!cmd_valid_p(name))
#         return FALSE
#     if (! nam_ll_in(name, GLOBAL_NAMESPACE))
#         return FALSE
#     return TRUE
#     #return flag_1true_p(code, TYPE_USER)
# }


function cmd_definition_ppf(name,
                            info, level, user_block)
{
    if (nam__scan(name, info) == ERROR)
        error("Scan error, " __m2_msg)
    if ((level = nam_lookup(info)) == ERROR)
        error("(cmd_definition_ppf) nam_lookup failed -- should not happen")
    # See if it's a user command
    if (flag_1false_p(nam_ll_read(name, level), TYPE_USER))
        error("(cmd_definition_ppf) " name " seems to no longer be a command")

    user_block = cmd_ll_read(name, level)
    return ppf__user(user_block)
}


function ppf__user(user_block,
                   name, params, i)
{
    if ((blk_type(user_block) != BLK_USER) ||
        (blktab[user_block, 0, "valid"] != TRUE))
        error("(ppf__user) Bad user_block config")

    name = blktab[user_block, 0, "name"]
    params = ""
    for (i = 1; i <= blktab[user_block, 0, "nparam"]; i++)
        params = params TOK_LBRACE blktab[user_block, i, "param_name"] TOK_RBRACE
    dbg_print("cmd", 5, "params='" params "'") # probably 7 or 8

    return "@newcmd " name params                             TOK_NEWLINE \
              ppf__agg(blktab[user_block, 0, "body_block"]) TOK_NEWLINE \
           "@endcmd"
}


function cmd_destroy(id)
{
    dbg_print("cmd", 1, "(cmd_destroy) BROKEN!")
    # delete namtab[id, GLOBAL_NAMESPACE]
    # delete cmdtab[id, "definition"]
    # delete cmdtab[id, "nparam"]
}


function cmd_valid_p(text)
{
    return nam_valid_strict_regexp_p(text) &&
           !double_underscores_p(text)
}


function cmd_ll_read(name, level)
{
    return cmdtab[name, level, "user_block"]
}


function cmd_ll_write(name, level, user_block)
{
    return cmdtab[name, level, "user_block"] = user_block
}


function execute__command(name, cmdline,
                          old_level)
{
    dbg_print("xeq", 3, sprintf("(execute__command) START name='%s', cmdline='%s'",
                                name, cmdline))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg_print("xeq", 3, "(execute__command) NOP due to __xeq_ctl=" __xeq_ctl)
        return
    }

    old_level = __namespace

    # DISPATCH
    # Also need an array entry to initialize command name.  [search: CMDS]
    # NB - immediate commands are not listed here; instead, [search: IMMEDS]
    if      (name ==  "append")         xeq_cmd__define(name, cmdline)
    else if (name ==  "array")          xeq_cmd__array(name, cmdline)
    else if (name ==  "break")          xeq_cmd__break(name, cmdline)
    else if (name ==  "cleardivert")    xeq_cmd__cleardivert(name, cmdline)
    else if (name ==  "continue")       xeq_cmd__continue(name, cmdline)
    else if (name ==  "debug")          xeq_cmd__error(name, cmdline)
    else if (name ==  "decr")           xeq_cmd__incr(name, cmdline)
    else if (name ==  "default")        xeq_cmd__define(name, cmdline)
    else if (name ==  "define")         xeq_cmd__define(name, cmdline)
    else if (name ==  "divert")         xeq_cmd__divert(name, cmdline)
    else if (name ~   /dump(all)?/)     xeq_cmd__dump(name, cmdline)
    else if (name ~ /s?echo/)           xeq_cmd__error(name, cmdline)
    else if (name ==  "error")          xeq_cmd__error(name, cmdline)
    else if (name ==  "errprint")       xeq_cmd__error(name, cmdline)
    else if (name ==  "eval")           xeq_cmd__eval(name, cmdline)
    else if (name ==  "exit")           xeq_cmd__exit(name, cmdline)
    else if (name ==  "ignore")         xeq_cmd__ignore(name, cmdline)
    else if (name ~ /s?include/)        xeq_cmd__include(name, cmdline)
    else if (name ==  "incr")           xeq_cmd__incr(name, cmdline)
    else if (name ==  "initialize")     xeq_cmd__define(name, cmdline)
    else if (name ==  "input")          xeq_cmd__input(name, cmdline)
    else if (name ==  "local")          xeq_cmd__local(name, cmdline)
    else if (name ==  "m2ctl")          xeq_cmd__m2ctl(name, cmdline)
    else if (name ==  "nextfile")       xeq_cmd__nextfile(name, cmdline)
    else if (name ~ /s?paste/)          xeq_cmd__include(name, cmdline)
    else if (name ~ /s?readarray/)      xeq_cmd__readarray(name, cmdline)
    else if (name ~ /s?readfile/)       xeq_cmd__readfile(name, cmdline)
    else if (name ==  "readonly")       xeq_cmd__readonly(name, cmdline)
    else if (name ==  "return")         xeq_cmd__return(name, cmdline)
    else if (name ==  "sequence")       xeq_cmd__sequence(name, cmdline)
    else if (name ==  "shell")          xeq_cmd__shell(name, cmdline)
    else if (name ==  "syscmd")         xeq_cmd__syscmd(name, cmdline)
    else if (name ==  "typeout")        xeq_cmd__typeout(name, cmdline)
    else if (name ==  "undefine")       xeq_cmd__undefine(name, cmdline)
    else if (name ==  "undivert")       xeq_cmd__undivert(name, cmdline)
    else if (name ==  "warn")           xeq_cmd__error(name, cmdline)
    else if (name ==  "wrap")           xeq_cmd__wrap(name, cmdline)
    else
        error("(execute__command) Unrecognized command '" name "' in '" cmdline "'")

    if (__namespace != old_level)
        error("(execute__command) @%s %s: Namespace level mismatch")
}


function assert_cmd_okay_to_define(name)
{
    if (!cmd_valid_p(name))
        error("Name '" name "' not valid:" $0)

    # FIXME This is not quite sufficient (I think).  I probably need
    # to do a full nam__scan() / nam_lookup() because I don't want
    # to shadow a system symbol.  At least I need to be more careful
    # than "it's not in the current namespace, looks good!!"
    if (nam_ll_in(name, __namespace))
        error("Name '" name "' not available:" $0)
    return TRUE
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       F I L E S   &   S C A N N I N G
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function dump_parse_stack(    level, block, block_type)
{
    print_stderr("(dump_parse_stack) BEGIN")
    if (stk_depth(__parse_stack) == 0)
        print_stderr("Parse stack is empty")
    else
        for (level = stk_depth(__parse_stack); level > 0; level--) {
            block = __parse_stack[level]
            block_type = blk_type(block)
            print_stderr("Level " level ", block # " block ", type=" block_type )
            dbg_print_block("xeq", -1, block)
        }
    print_stderr("(dump_parse_stack) END")
}


function prep_file(filename,
                   file_block, retval)
{
    dbg_print("parse", 7, "(prep_file) START filename='" filename "'")
    # create and return a SRC_FILE set up for the terminal
    file_block = blk_new(SRC_FILE)
    if (filename == "-")
        filename = "/dev/stdin"
    blktab[file_block, 0, "filename"] = filename
    blktab[file_block, 0, "atmode"] = MODE_AT_PROCESS

    dbg_print("parse", 7, "(prep_file) END; file_block => " file_block)
    return file_block
}


function dofile(filename,
                file_block, retval)
{
    dbg_print("parse", 5, "(dofile) START filename='" filename "'")

    # Prepare to read filename; set up a SRC_FILE block to manage input
    # and a BLK_TERMINAL to receive output
    file_block = prep_file(filename)
    dbg_print("parse", 7, sprintf("(dofile) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)
    stk_push(__parse_stack, __terminal)

    dbg_print("parse", 5, "(dofile) CALLING parse__file()")
    retval = parse__file()
    dbg_print("parse", 5, "(dofile) RETURNED FROM parse__file()")

    # Clean up
    # (parse_file() pops the source stack)
    stk_pop(__parse_stack)

    dbg_print("parse", 5, "(dofile) END => " ppf__bool(retval))
    return retval
}


# Create a File block  and read the file.
# atmode flag overrides and disables any/all processing.
#
# The high-level processing happens in the dofile() function, which
# reads one line at a time, and decides what to do with each line.  The
# __active_files array keeps track of open files.  The symbol __FILE__
# stores the current file to read data from.  When an "@include"
# directive is seen, dofile() is called recursively on the new file.
# Interestingly, the included filename is first processed for macros.
# Read this function carefully--there are some nice tricks here.
#
# Caller is responsible for removing potential quotes from filename.
function parse__file(    filename, file_block1, file_block2, pstat, d)
{
    if (stk_emptyp(__source_stack))
        error("(parse__file) Source stack empty")
    file_block1 = stk_top(__source_stack)

    filename = blktab[file_block1, 0, "filename"]
    dbg_print("parse", 1, sprintf("(parse__file) filename='%s', dstblk=%d, mode=%s",
                                  filename, curr_dstblk(),
                                  ppf__mode(blktab[file_block1, 0, "atmode"])))
    if (!path_exists_p(filename)) {
        dbg_print("parse", 1, sprintf("(parse__file) END File '%s' does not exist => %s",
                                     filename, ppf__bool(FALSE)))
        stk_pop(__source_stack) # Remove SRC_FILE for non-existent file
        return FALSE
    }
    if (filename in __active_files)
        error("Cannot recursively read '" filename "':" $0)
    __active_files[filename] = TRUE
    sym_increment("__NFILE__", 1)
    blktab[file_block1, 0, "open"]          = TRUE
    blktab[file_block1, 0, "old.buffer"]    = __buffer
    blktab[file_block1, 0, "old.file"]      = FILE()
    blktab[file_block1, 0, "old.line"]      = LINE()
    blktab[file_block1, 0, "old.file_uuid"] = sym_ll_read("__FILE_UUID__", "", GLOBAL_NAMESPACE)
    dbg_print_block("ship_out", 7, file_block1, "(parse__file) file_block1")

    # # Set up new file context
    __buffer = EMPTY
    sym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, filename)
    sym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, 0)
    sym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, uuid())

    # Read the file and process each line
    dbg_print("parse", 5, "(parse__file) CALLING parse()")
    pstat = parse()
    dbg_print("parse", 5, "(parse__file) RETURNED FROM parse() => " ppf__bool(pstat))

    # Reached end of file
    flush_stdout(SYNC_FILE)

    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != "/dev/stdin")
        close(filename)
    blktab[file_block1, 0, "open"] = FALSE
    delete __active_files[filename]

    file_block2 = stk_pop(__source_stack)
    if (file_block1 != file_block2)
        error("(parse__file) File block mismatch")
    __buffer = blktab[file_block2, 0, "old.buffer"]
    sym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, blktab[file_block2, 0, "old.file"])
    sym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, blktab[file_block2, 0, "old.line"])
    sym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, blktab[file_block2, 0, "old.file_uuid"])

    dbg_print("parse", 1, sprintf("(parse__file) END '%s' => %s",
                                 filename, ppf__bool(pstat)))
    return pstat
}


# PARSE
function parse(    code, terminator, rstat, name, retval, new_block, fc,
                   info, level, parser, parser_type, parser_label, i, scnt, found,
                   new_cmd_name, clevel, cmdline, src_block)
{
    dbg_print("parse", 3, "(parse) START dstblk=" curr_dstblk() ", mode=" ppf__mode(curr_atmode()))

    # The "parser" is the topmost element of the __parse_stack
    # which we wish to access a few times
    if (stk_emptyp(__parse_stack))
        error("Parse error, Empty parse stack")
    parser = stk_top(__parse_stack)
    parser_type = blk_type(parser)
    parser_label = ppf__block_type(parser_type)

    if (stk_emptyp(__source_stack))
        error("Parse error, Empty source stack")
    src_block = stk_top(__source_stack)

    # terminator is a regular expression, and we call
    # match($1, terminator) to see if terminator is seen.
    terminator = blktab[parser, 0, "terminator"]
    retval = FALSE

    while (TRUE) {
        dbg_print("parse", 4, sprintf("(parse) [%s] TOP OF LOOP: __FILE__ %s __LINE__ %d ________________",
                                     parser_label, FILE(), LINE()+1)) # LINE will be +1 after upcoming readline() 

        rstat = readline()   # OKAY, EOF, ERROR
        if (rstat == ERROR) {
            # Whatever just happened, the parse didn't finish properly
            dbg_print("parse", 1, "(parse) [" parser_label "] readline()=>ERROR")
            break          # out of entire parsing loop, to then return
        }
        if (rstat == EOF) {
            # End of file SRC_FILE is fine, just return a TRUE to say so.
            # EOF on any other block type means the parse didn't find
            # a terminator, so return FALSE.
            dbg_print("parse", 5, sprintf("(parse) [%s] readline() detected EOF on '%s'",
                                         parser_label, blktab[src_block, 0, "filename"]))
            if ((src_block, 0, "oob_terminator") in blktab &&
                blktab[src_block, 0, "oob_terminator"] == "EOF")
                retval = TRUE
            break          # out of entire parsing loop, to then return
        }
        dbg_print("parse", 5, "(parse) [" parser_label "] readline() okay; $0='" $0 "'")

        # Maybe short-circuit and ship line out now
        if (curr_atmode() == MODE_AT_LITERAL || index($0, TOK_AT) == IDX_NOT_FOUND) {
            dbg_print("parse", 3, sprintf("(parse) [%s, short circuit] CALLING ship_out(OBJ_TEXT, '%s')",
                                         parser_label, $0))
            ship_out(OBJ_TEXT, $0)
            dbg_print("parse", 3, "(parse) [" parser_label ", short circuit] RETURNED FROM ship_out()")
            continue           # text shipped out, continue to next line
        }

        # Quickly skip comments
        if ($1 == "@@" || $1 == "@;" || $1 == "@#" ||
            $1 == "@c" || $1 == "@comment")
            continue

        # See if it's a command of some kind.  Of course we want
        # first($1)==TOK_AT because we expect the at-sign in column one for
        # a command.  Adding AND last($1)!=TOK_AT catches when we're
        # looking at a line like @date@, which is invoking an inline
        # "sym-function" to be resolved by dosubs().  It has a @ in
        # column one, but that's just a coincidence.
        #
        # first == @ and last != @ catches @foo...@ at BOL not being a command
        if (first($1) == TOK_AT && last($1) != TOK_AT) { # looks like it might be a command
            # Winnow out the primary name.  Be sure to handle
            # "@myfn{aaa}{ccc ddd}".  (Naive old code name=$1 resulted
            # in $1 being "@myfn{aaa}{ccc" which wrecks havoc.)
            # However, we need to keep $1 intact in order for upcoming
            # match($1,terminator) checks to work.  This takes advantage
            # of the fact that all commands must have strict names.
            for (i = 2; substr($0, i, 1) ~ /[A-Za-z#_0-9]/; i++)
                ;
            name = substr($0, 2, i-2)
            dbg_print("parse", 7, "(parse) [" parser_label "] name now '" name "'")
            
            # See if it's a built-in command
            if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
                flag_1true_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)),
                             TYPE_COMMAND)) {
                # See if it's immediate
                if (flag_1true_p(code, FLAG_IMMEDIATE)) {
                    # This command is immediate, so we must run it right now.
                    # Some are known to create and return new blocks,
                    # which must be shipped out.

                    if (name == "break" || name == "continue") {
                        # @break and @continue are hybrid commands, with
                        # both immediate and regular components.  The
                        # parse_stack check for a FOR or WHILE must be
                        # done immediately because the parse_stack is
                        # gone by the time the command is shipped out.
                        # But the actual effect of @break or @continue
                        # is not seen until run-time, so the command
                        # must also be shipped out like a normal command
                        # would have been.
                        found = FALSE
                        for (i = stk_depth(__parse_stack); i > 0; i--) {
                            scnt = blk_type(__parse_stack[i])
                            if (scnt == BLK_FOR || scnt == BLK_WHILE) {
                                found = TRUE
                                break
                            }
                        }
                        if (! found)
                            error(sprintf("[@%s] Parse error, Missing parser; wanted FOR or WHILE but found %s",
                                          name, parser_label))
                        dbg_print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg_print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else if (name == "case") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__case(dstblk=" curr_dstblk() ")"))
                        new_block = parse__case()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__case() : new_block => " new_block))
                        dbg_print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "else") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__else(dstblk=" curr_dstblk() ")"))
                        parse__else()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__else() : dstblk => " curr_dstblk()))

                    } else if (name == "endcase" || name == "esac") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endcase(dstblk=" curr_dstblk() ")"))
                        parse__endcase()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endcase() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("parse", 5, "(parse) [" parser_label "] END; @endcase matched terminator => TRUE")
                            return TRUE
                        }
                        error(sprintf("[@%s] Parse error, Missing terminator; wanted '%s' but found '@endcase'",
                                      name, terminator))

                    } else if (name == "endcmd") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endcmd(dstblk=" curr_dstblk() ")"))
                        new_block = parse__endcmd()
                        dbg_print_block("parse", 7, new_block, sprintf("newcmd block returned from parse__endcmd"))
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endcmd() : dstblk => " curr_dstblk()))

                        if (match($1, terminator)) {
                            dbg_print("parse", 5, "(parse) [" parser_label "] END; @endcmd matched terminator => TRUE")

                            # Create an entry for the new command name.
                            # We do this at Parse time so that future
                            # invocations of new command @FOO will
                            # immediately be recognized as an available
                            # user command.  All we need to do is create
                            # a namtab entry with correct TYPE_USER.
                            # NOTE - we don't have an entry in the cmdtab
                            # yet.  That's okay because the command is
                            # only being declared, not defined, and it's
                            # not ready to run yet.  (That next bit
                            # happens in xeq__BLK_USER.)
                            if (! nam_ll_in(name, __namespace)) {
                                new_cmd_name = blktab[new_block, 0, "name"]
                                dbg_print("parse", 3, sprintf("Declaring new user command '%s' at level %d",
                                                             new_cmd_name, __namespace))
                                nam_ll_write(new_cmd_name, __namespace, TYPE_USER)
                            }
                            return TRUE
                        }
                        error(sprintf("[@%s] Parse error; Missing terminator; wanted '%s' but found '@endcmd'",
                                      name, terminator))

                    } else if (name == "endif" || name == "fi") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endif(dstblk=" curr_dstblk() ")"))
                        parse__endif()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endif() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("parse", 5, "(parse) [" parser_label "] END; @endif matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endif but expecting '" terminator "'")

                    } else if (name == "endlong" || name == "endlongdef") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endlongdef(dstblk=" curr_dstblk() ")"))
                        parse__endlongdef()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endlongdef() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("parse", 5, "(parse) [" parser_label "] END; @endlongdef matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endlongdef but expecting '" terminator "'")

                    } else if (name == "endwhile" || name == "wend") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endwhile(dstblk=" curr_dstblk() ")"))
                        parse__endwhile()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endwhile() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("parse", 5, "(parse) [" parser_label "] END; @endwhile matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endwhile but expecting '" terminator "'")

                    } else if (name == "for" || name == "foreach") {
                        dbg_print("parse", 5, sprintf("(parse) [%s] curr_dstblk()=%d CALLING parse__for()",
                                                     parser_label, curr_dstblk()))
                        new_block = parse__for()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__for() : new_block is " new_block))
                        dbg_print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "if" || name == "unless") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__if(dstblk=" curr_dstblk() ")"))
                        new_block = parse__if()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__if() : new_block => " new_block))
                        dbg_print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "longdef") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__longdef(dstblk=" curr_dstblk() ")"))
                        new_block = parse__longdef()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__longdef() : new_block => " new_block))
                        dbg_print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "newcmd") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__newcmd(dstblk=" curr_dstblk() ")"))
                        new_block = parse__newcmd()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__newcmd() : new_block => " new_block))
                        dbg_print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "next") {
                        dbg_print("parse", 5, sprintf("(parse) [%s] dstblk=%d; CALLING parse__next()",
                                                     parser_label, curr_dstblk()))
                        parse__next()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__next() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("parse", 5, "(parse) [" parser_label "] END Matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @next but expecting '" terminator "'")

                    } else if (name == "of") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__of(dstblk=" curr_dstblk() ")"))
                        parse__of()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__of() : dstblk => " curr_dstblk()))

                    } else if (name == "otherwise") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__otherwise(dstblk=" curr_dstblk() ")"))
                        parse__otherwise()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__otherwise() : dstblk => " curr_dstblk()))

                    } else if (name == "return") {
                        found = FALSE
                        for (i = stk_depth(__parse_stack); i > 0; i--) {
                            dbg_print("parse", 2, sprintf("i=%d, __parse_stack[i])=%d", i, __parse_stack[i]))
                            dbg_print_block("parse", 2, __parse_stack[i], "Parsing @return:")
                            scnt = blk_type(__parse_stack[i])
                            if (scnt == BLK_USER) {
                                found = TRUE
                                break
                            }
                        }
                        if (! found)
                            error("@return: Not executing a user command")
                        dbg_print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg_print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else if (name == "while" || name == "until") {
                        dbg_print("parse", 5, ("(parse) [" parser_label "] CALLING parse__while(dstblk=" curr_dstblk() ")"))
                        new_block = parse__while()
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__while() : new_block => " new_block))
                        dbg_print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg_print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else
                        error("(parse) [" parser_label "] Found immediate command " name " but no handler")

                } else {
                    # It's a non-immediate built-in command -- ship it
                    # out as a command to be executed later.
                    dbg_print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_CMD, '%s')", parser_label, $0))
                    ship_out(OBJ_CMD, $0)
                    dbg_print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
                }
                continue
            } else {
                # Look up user command
                if (nam__scan(name, info) == ERROR)
                    error("Scan error; " __m2_msg)
                if ((level = nam_lookup(info)) != ERROR) {
                    # An ERROR here simply means not found, in which case
                    # name is definitely not a user command, so we do nothing
                    # for the moment in that case and let normal text ship out.
                    # But it's not an ERROR, so something was found at "level".
                    # See if it's a user command and ship it out if so.
                    if (flag_1true_p((code = nam_ll_read(name, level)), TYPE_USER)) {
                        cmdline = scan__usercmd_call()
                        dbg_print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_USER, '%s')", parser_label, cmdline))
                        ship_out(OBJ_USER, cmdline)
                        dbg_print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
                        continue
                    }
                }
            }
            # It's okay to reach here with no actions taken.  In this
            # case, just process the line as normal text.
        } # doesn't look like a command - ship it out as text
        dbg_print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_TEXT, '%s')", parser_label, $0))
        ship_out(OBJ_TEXT, $0)
        dbg_print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
    } # continue loop again, reading next line
    dbg_print("parse", 5, "(parse) END => " ppf__bool(retval))
    return retval
}


# Unlike built-in CMDs, which must be complete on a single line, USER
# commands might span multiple physical lines.  This is because (unlike
# CMDs), parameters are enclosed with braces, so the user might say:
#       @mycmd{Title}{A very very very
#       very long title}
# Call readline() repeatedly until braces are closed properly.
# This function returns its command line, possibly appended to by readline().
function scan__usercmd_call(    s, name, obj, i, oldi, c, nc, narg, nlbr,
                                  readstat)
{
    s = $0
    narg = 0
    dbg_print("parse", 5, "(scan__usercmd_call) s='" s "'")

    i = 1
    c = substr(s, i, 1)
    if (c != TOK_AT)
        error(sprintf("(scan__usercmd_call) Doesn't start with @: s-'%s'", s))

    # Read cmd name
    c = substr(s, (oldi = ++i), 1)
    while (c != "" && c != TOK_LBRACE) {
        # print_stderr(sprintf("(scan__usercmd_call) LOOP: i=%d, c='%s', nam='%s'",
        #                      i, c, substr(s, 2, i-2)))
        c = substr(s, ++i, 1)
    }
    name = substr(s, oldi, i-oldi)
    dbg_print("parse", 3, sprintf("(scan__usercmd_call) OUT: name='%s'", name))

    if (c != TOK_LBRACE) {
        # It's just @Foo, no braces, no scanning needed
        dbg_print("parse", 1, sprintf("(scan__usercmd_call) END 1: narg=%d, name='%s', s='%s'", narg, name, s))
        return s
    }

    # It *IS* a brace, so set things up that way
    narg = nlbr = 1
    oldi = ++i
    c = substr(s, i, 1)
    while (nlbr >= 0) {
        #print_stderr(sprintf("(scan__usercmd_call) TOP, i=%d, c='%s', nlbr now=%d", i, c, nlbr))
        if (i > 255)
            error(sprintf("(scan__usercmd_call) ERROR, i too big: i=%d, c='%s'", i, c))
        else if (c == "") {
            if (nlbr == 0) {
                dbg_print("parse", 1, sprintf("(scan__usercmd_call) END 2 (eos, {} bal): narg=%d, s='%s'", narg, s))
                return s
            }
            # We ran out of characters looking for a }
            # Try reading some more lines to fill our need
            readstat = readline()
            if (readstat <= 0)
                error(sprintf("(scan__usercmd_call) ERROR, missing '}': i=%d, c='%s'", i, c))
            #print_stderr("just read = >" $0 "<")
            s = s TOK_NEWLINE $0
            c = substr(s, i, 1)
            dbg_print("parse", 7, sprintf("(scan__usercmd_call) INFO, After readline, i=%d, c='%s', nlbr now=%d, s='%s'", i, c, nlbr, s))
            continue
        } else if (c == TOK_LBRACE) {
            nlbr++
            narg++
            dbg_print("parse", 5, sprintf("(scan__usercmd_call) INFO, found '{': i=%d, c='%s', nlbr now=%d", i, c, nlbr))
            oldi = i+1
        } else if (c == TOK_RBRACE) {
            nlbr--
            dbg_print("parse", 5, sprintf("(scan__usercmd_call) INFO, found '}': i=%d, c='%s', nlbr now=%d", i, c, nlbr))
            dbg_print("parse", 3, sprintf("(scan__usercmd_call) Arg[%d]='%s'", narg, substr(s, oldi, i-oldi)))
        }
        # else normal character
        c = substr(s, ++i, 1)
    }
    dbg_print("parse", 1, sprintf("(scan__usercmd_call) END 3: narg=%d, s='%s'", narg, s))
    return s
}


function ppf__SRC_FILE(blknum)
{
    return sprintf("  filename: %s (%s)\n" \
                   "  atmode  : %s",
                   blktab[blknum, 0, "filename"],
                   blktab[blknum, 0, "open"] ? "OPEN" : "CLOSED",
                   ppf__mode(blktab[blknum, 0, "atmode"]))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       F L A G S   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       A flag is a single character boolean-valued piece of information
#       about a "name", an entry in namtab.  The flag is True if the
#       character is present in the flags string and False if it is absent.
#       The following flag characters are recognized:
#
#       Type is mutually exclusive; exactly one must be present:
#           TYPE_ARRAY          1 : Array refs must use subscripts
#           TYPE_COMMAND        2 : Built-in "@" command; Global namespace
#           TYPE_USER           3 : User-defined command; dynamic namespace
#           TYPE_FUNCTION       4 : Global namespace
#           TYPE_SEQUENCE       5 : Global namespace
#           TYPE_SYMBOL         6
#
#       Read-Only/Writable is mutually exclusive; both are optional:
#           FLAG_READONLY       R : Read-only; immune from user modification
#           FLAG_WRITABLE       W : User is able to modify symbol's value
#
#       Flags indicating value "type" are mutually exclusive; all are optional:
#           FLAG_BOOLEAN        B : Value forced to be a Boolean (0 or 1)
#           FLAG_INTEGER        I : Value must be an integer
#           FLAG_NUMERIC        N : Value must be a number
#
#       Other flags, all optional:
#           FLAG_DEFERRED       D : Deferred means value will be defined later
#           FLAG_IMMEDIATE      ! : parse() will immediately execute command
#           FLAG_SYSTEM         Y : Internal variable, level 0, usually
#                                   (but not always) read-only.  Also,
#                                   system symbols cannot be shadowed.
#
#       When TYPE_ARRAY is set:
#           no flags            User can add/delete/whatever to array & elements
#           FLAG_SYSTEM         User cannot add or delete elements.  Existing
#                               elements may be updated.  As usual, level=0 and
#                               name cannot be shadowed.
#           FLAG_READONLY       User cannot change, add, or delete any element.
#           FLAG_WRITABLE       User can add, delete, change elements
#
#*****************************************************************************

# TRUE if the one lone flag single_f is absent from code,
# else FALSE indicating its presence.
function flag_1false_p(code, single_f)
{
    if (single_f == TYPE_ANY) return FALSE
    return index(code, single_f) == IDX_NOT_FOUND
}


# TRUE if the one lone flag single_f is present in code,
# else FALSE indicating its absence.
function flag_1true_p(code, single_f)
{
    if (single_f == TYPE_ANY) return TRUE
    return index(code, single_f) > 0
}


# TRUE iff all flags in multi_fs are True (set in code).
function flag_alltrue_p(code, multi_fs,
                        l, x)
{
    # If multi_fs is empty, we treat that as False.
    if ((l = length(multi_fs)) == 0)
        return FALSE

    # Loop through all the flag characters in multi_fs.
    # If any of them are false, the whole thing is false.
    # If you reach the end, it's true.
    for (x = 1; x <= l; x++)
        if (flag_1false_p(code, substr(multi_fs, x, 1)))
            return FALSE
    return TRUE
}


# TRUE iff any flag in multi_fs are True (set in code).
function flag_anytrue_p(code, multi_fs,
                        l, x)
{
    # If multi_fs is empty, we treat that as False.
    if ((l = length(multi_fs)) == 0)
        return FALSE

    # True if any flag is True, else False
    for (x = 1; x <= l; x++)
        if (flag_1true_p(code, substr(multi_fs, x, 1)))
            return TRUE
    return FALSE
}


function flag_allfalse_p(code, multi_fs)
{
    return !flag_anytrue_p(code, multi_fs)
}


function flag_anyfalse_p(code, multi_fs)
{
    return !flag_alltrue_p(code, multi_fs)
}


# Return a new code string (NB - old one is NOT updated in place!)
# with corresponding flags either set or cleared.
function flag_set_clear(code, set_fs, clear_fs,
                        l, sf_arr, cf_arr, flag, _idx, x)
{
    # First, clear flags listed in clear_fs
    if ((l = length(clear_fs)) > 0)
        for (x = 1; x <= l; x++) {
            flag = substr(clear_fs, x, 1)
            if (flag_1true_p(code, flag)) {
                _idx = index(code, flag)
                code = substr(code, 1, _idx-1) \
                       substr(code, _idx+1)
            }
        }
        
    # Now set the ones in set_fs
    if ((l = length(set_fs)) > 0)
        for (x = 1; x <= l; x++) {
            flag = substr(set_fs, x, 1)
            if (flag_1false_p(code, flag))
                code = code flag
        }

    return code
}


function ppf__flag_type(code,
                        type)
{
    if (code == EMPTY)
        warn("(ppf__flag_type) code is empty, how did that happen?")
    code = first(code)
    dbg_print("xeq", 7, "(ppf__flag_type) code = " code)
    if (! (code in __flag_label)) {
        error("(ppf__flag_type) Invalid type '" code "'")
    }
    return __flag_label[code]
}


function ppf__flags(code,
                    l, s, desc, x)
{
    if ((l = length(code)) == 0)
        error("(ppf_flag) Did not specify code")
    s = ppf__flag_type(code) # __flag_label[first(code)]
    if (l > 1) {
        desc = ""
        for (x = 2; x <= l; x++)
            desc = desc __flag_label[substr(code, x, 1)] ","
        s = s "<" chop(desc) ">"
    }
    return s
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       N A M E   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

#*****************************************************************************
#
# This code scans random string "text" into either NAME or NAME[KEY].
# Rudimentary error checking is done.
#
# Return value:
#    -1 (ERROR)
#       Text does not pass simple scan test.  Even so, it still
#       may be invalid depending strict, etc).
#    1 or 2
#       Text scanned.  1 is returned if it's a simple NAME,
#       2 indicates a NAME[KEY] format.
#
# Info is an array with following entries:
#
# Info[] :=
#       hasbracket : TRUE if text matches CHARS[CHARS..]
#                    It is normal for plain "NAME" to be FALSE here.
#       key        : key part[2]  (may be empty)
#       keyvalid   : TRUE if KEY is valid according to non-strict.
#                    This restricts it to most printable characters.
#       name       : name part[1]
#       namevalid  : TRUE if NAME is valid according to current __STRICT__[symbol]
#       nparts     : 1 or 2 depending if text is NAME or NAME[KEY]
#      #text       : original text string
#*****************************************************************************
function nam__scan(text, info,
                    name, key, nparts, part, count, i)
{
    dbg_print("nam", 5, sprintf("(nam__scan) START text='%s'", text))
    #info["text"] = text

    # Simple test for CHARS or CHARS[CHARS]
    #   CHARS ::= [-!-Z^-z~]+
    # Match CHARS optionally followed by bracket CHARS bracket
    #   /^ CHARS ( \[ CHARS \] )? $/
    #if (text !~ /^[^[\]]+(\[[^[\]]+\])?$/) {   # too broad: matches non-printing characters
    # We carefully construct CHARS with about regexp
    # to exclude ! [ \ ] { | }
    if (text !~ /^["-Z^-z~]+(\[["-Z^-z~]+\])?$/) {
        #warn("(nam__scan) Name '" text "' not valid")
        dbg_print("nam", 2, sprintf("(nam__scan) '%s' => %d", text, ERROR))
        __m2_msg = "Invalid name: '" text "'"
        return ERROR            # interpret as ERR_SCAN_INVALID_NAME
    }

    count = split(text, part, "(\\[|\\])")
    if (dbg("nam", 8)) {
        print_stderr("'" text "' ==> " count " fields:")
        for (i = 1; i <= count; i++)
            print_stderr(i " = '" part[i] "'")
    }
    info["name"] = name = part[1]
    info["key"]   = key = part[2]

    # Since we passed the regexp in first if() statement, we can be
    # assured that text is either ^CHARS$ or ^CHARS\[CHARS\]$.  Thus, a
    # simple index() for an open bracket should suffice here.
    info["hasbracket"] = index(text, "[") > 0
    info["keyvalid"]   = nam_valid_with_strict_as(key, FALSE)
    info["namevalid"]  = nam_valid_with_strict_as(name, strictp("symbol"))
    info["nparts"]     = nparts = (count == 1) ? 1 : 2
    dbg_print("nam", 4, sprintf("(nam__scan) '%s' => %d", text, nparts))
    return nparts
}


# Remove any name at level "level" or greater
function nam_purge(level,
                    x, k, del_list)
{
    dbg_print("nam", 7, "(nam_purge) BEGIN")
    
    for (k in namtab) {
        split(k, x, SUBSEP)
        if (x[2]+0 >= level)
            del_list[x[1], x[2]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        dbg_print("nam", 3, sprintf("(nam_purge) Delete namtab['%s', %d]",
                                     x[1], x[2]))
        delete namtab[x[1], x[2]]
    }
    dbg_print("nam", 7, "(nam_purge) START")
}


function nam_dump_namtab(filter_fs, include_sys,
                           x, k, code, s, desc, name, level, f_arr, l,
                           include_system)
{
    include_system = flag_1true_p(filter_fs, FLAG_SYSTEM)
    print(sprintf("Begin namtab (%s%s):", filter_fs,
                  include_system ? "+System" : ""))

    for (k in namtab) {
        split(k, x, SUBSEP)
        name  = x[1]
        level = x[2] + 0
        code = nam_ll_read(name, level)

        if (! flag_alltrue_p(code, filter_fs)) {
            #print_stderr(sprintf("code=%s, filter=%s, flag filter failed", code, filter_fs))
            continue
        }
        if (flag_1true_p(code, FLAG_SYSTEM) && !include_system) {
            #print_stderr("system filter failed")
            continue
        }
        print "namtab:" nam_ppf_name_level(name, level)
        # print "----------------"
    }
    print("End namtab")
}


function nam_valid_strict_regexp_p(text)
{
    return text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
}


function nam_valid_with_strict_as(text, tmp_strict)
{
    if (emptyp(text))
        return FALSE
    if (tmp_strict)
        # In strict mode, only letters, #, and _ (and then digits)
        return nam_valid_strict_regexp_p(text) # text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
    else
        # In non-strict mode, printable characters except ! [ \ ] { | }
        return text ~ /^["-Z^-z~]+$/
}


function nam_ll_read(name, level)
{
    if (level == EMPTY) level = GLOBAL_NAMESPACE
    return namtab[name, level] # returns code
}


function nam_ll_in(name, level)
{
    if (level == EMPTY) error("(nam_ll_in) LEVEL missing")
    if (name != "__LINE__" && name != "__NLINE__")
        dbg_print("sym", 5, sprintf("(nam_ll_in) Looking for '%s' at level %d", name, level))
    return (name, level) in namtab
}


function nam_ll_write(name, level, code,
                       retval)
{
    if (level == EMPTY) error("(nam_ll_write) LEVEL missing")
    # It's important to use low-level functions here, and not invoke
    # dbg_* functions in this procedure.  Nasty loops ensue.
    if (sym_ll_in("__DBG__", "nam", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "nam", GLOBAL_NAMESPACE) >= 5)
        print_stderr(sprintf("(nam_ll_write) namtab[\"%s\", %d] = %s", name, level, code))
    return namtab[name, level] = code
}


#*****************************************************************************
# This will examine namtab from __namespace downto 0
# seeing if name is a match.  If so, it populates info["code"]
# with the corresponding code string and returns level (0..n)
# If no matching name is found, return ERROR
#
# Info[] :=
#       code    : Code string from namtab
#       isarray : TRUE if NAME is TYPE_ARRAY
#       level   : Level at which name was found
#       type    : Character code for TYPE_xxx
#*****************************************************************************
function nam_lookup(info,
                    name, level, code)
{
    name = info["name"]
    dbg_print("sym", 5, sprintf("(nam_lookup) sym='%s' START", name))

    for (level = __namespace; level >= GLOBAL_NAMESPACE; level--)
        if (nam_ll_in(name, level)) {
            info["code"] = code = nam_ll_read(name, level)
            info["isarray"] = flag_1true_p(code, TYPE_ARRAY)
            info["level"]   = level
            info["type"]    = first(code)
            dbg_print("nam", 2, sprintf("(nam_lookup) END name '%s', level=%d, code=%s=%s Found in namtab => %d",
                                         name, level, code, nam_ppf_name_level(name, level), level))
            return level
        }
    dbg_print("nam", 2, sprintf("(nam_lookup) END Could not find name '%s' on any level in namtab => ERROR", name))
    return ERROR
}


function nam_ppf_name_level(name, level,
                            s, code, desc, l, x)
{
    code = nam_ll_read(name, level)
    s = __flag_label[first(code)] "'" name "'{" level "}"
    code = rest(code)
    desc = ""
    if ((l = length(code)) > 0)
        for (x = 1; x <= l; x++)
            desc = desc __flag_label[substr(code, x, 1)] ","
    s = s "<" chop(desc) ">"
    return s
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S E Q U E N C E   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# Sequence names must always match strict symbol name syntax:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
function seq_valid_p(text)
{
    return nam_valid_strict_regexp_p(text) &&
           !double_underscores_p(text)
}


# A Sequence is defined if its name exists in namtab with the correct type
# and if it's Defined.
function seq_defined_p(name,
                        code)
{
    if (!seq_valid_p(name))
        return FALSE
    if (! nam_ll_in(name, GLOBAL_NAMESPACE))
        return FALSE
    code = nam_ll_read(name, GLOBAL_NAMESPACE)
    return flag_1true_p(code, TYPE_SEQUENCE)
}


function seq_definition_ppf(name,    buf, TAB)
{
    buf =         "@sequence " name TOK_TAB "create\n"
    if (seq_ll_read(name) != SEQ_DEFAULT_INIT)
        buf = buf "@sequence " name TOK_TAB "setval " seq_ll_read(name) TOK_NEWLINE
    if (seqtab[name, "init"] != SEQ_DEFAULT_INIT)
        buf = buf "@sequence " name TOK_TAB "setinit " seqtab[name, "init"] TOK_NEWLINE
    if (seqtab[name, "incr"] != SEQ_DEFAULT_INCR)
        buf = buf "@sequence " name TOK_TAB "setincr " seqtab[name, "incr"] TOK_NEWLINE
    if (seqtab[name, "fmt"] != sym_ll_read("__FMT__", "seq"))
        buf = buf "@sequence " name TOK_TAB "format " seqtab[name, "fmt"] TOK_NEWLINE
    return chop(buf)
}


function seq_destroy(name)
{
    delete namtab[name, GLOBAL_NAMESPACE]
    delete seqtab[name, "incr"]
    delete seqtab[name, "init"]
    delete seqtab[name, "fmt"]
    delete seqtab[name, "seqval"]
}


function seq_ll_read(name)
{
    return seqtab[name, "seqval"]
}


function seq_ll_write(name, new_val)
{
    return seqtab[name, "seqval"] = new_val
}


function seq_ll_incr(name, incr)
{
    if (incr == EMPTY)
        incr = seqtab[name, "incr"]
    seqtab[name, "seqval"] += incr
}


function assert_seq_valid_name(name)
{
    if (seq_valid_p(name))
        return TRUE
    error("Name '" name "' not valid:" $0)
}


function assert_seq_okay_to_define(name)
{
    assert_seq_valid_name(name)
    if (nam_ll_in(name, GLOBAL_NAMESPACE))
        error("Name '" name "' not available:" $0)
    return TRUE
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S T A C K   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function stk_depth(stack)
{
    return stack[0]
}


function stk_push(stack, new_elem)
{
    return stack[++stack[0]] = new_elem
}


function stk_emptyp(stack)
{
    return (stk_depth(stack) == 0)
}


function stk_top(stack)
{
    if (stk_emptyp(stack))
        error("(stk_top) Empty stack")
    return stack[stack[0]]
}


function stk_pop(stack)
{
    if (stk_emptyp(stack))
        error("(stk_pop) Empty stack")
    return stack[stack[0]--]
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S T R E A M   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Send text to the destination stream __DIVNUM__
#         < 0         Discard
#         = 0         Standard output
#         > 0         Stream # N
#
#       See @divert, @undivert
#
#*****************************************************************************
function DIVNUM()
{
    return sym_ll_read("__DIVNUM__", "", GLOBAL_NAMESPACE) + 0
}


# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-scanned for macros, and buffer is cleared after
# injection into target stream.
function undivert(stream,
                  count, i, dstblk)
{
    dstblk = curr_dstblk()
    dbg_print("divert", 1, sprintf("(undivert) START dstblk=%d, stream=%d",
                                   curr_dstblk(), stream))
    if (dstblk < 0) {
        dbg_print("divert", 3, "(undivert) END because dstblk <0")
        return
    }
    if (stream < 0 || stream == DIVNUM()) {
        dbg_print("divert", 3, "(undivert) END because stream <0 or ==DIVNUM")
        return
    }
    if (blk_type(stream) != BLK_AGG)
        error(sprintf("(undivert) Block %d has type %s, not AGG",
                      stream, ppf__block_type(blk_type(stream))))
    if ((count = blktab[stream, 0, "count"]) > 0) {
        # It is required to clear the stream immediately after undiverting.
        # This is to prevent
        #        @undivert N
        #        @undivert N
        # from producing double output.  Move each slot manually to the
        # target stream, then clear the original diversion.
        if (dstblk == TERMINAL)
            execute__block(stream)
        else
            for (i = 1; i <= count; i++)
                blk_append(dstblk, blk_ll_slot_type(stream, i), blk_ll_slot_value(stream, i))
        cleardivert(stream)
    }
}


function undivert_all(    stream)
{
    for (stream = 1; stream <= MAX_STREAM; stream++)
        if (blktab[stream, 0, "count"] > 0)
            undivert(stream)
}


# Remove all slots from an AGG block and return its count to zero.
function cleardivert(stream,
                     count, i)
{
    dbg_print("divert", 1, sprintf("(cleardivert) START dstblk=%d, stream=%d",
                                   curr_dstblk(), stream))
    if (stream < 0) {
        dbg_print("divert", 3, "(cleardivert) END because stream <0")
        return
    }
    if (blk_type(stream) != BLK_AGG)
        error(sprintf("(cleardivert) Block %d has type %s, not AGG",
                      stream, ppf__block_type(blk_type(stream))))
    if ((count = blktab[stream, 0, "count"]) > 0) {
        for (i = 1; i <= count; i++) {
            delete blktab[stream, i, "slot_type"]
            delete blktab[stream, i, "slot_value"]
        }
        blktab[stream, 0, "count"] = 0
    }
}


function cleardivert_all(    stream)
{
    for (stream = 1; stream <= MAX_STREAM; stream++)
        if (blktab[stream, 0, "count"] > 0)
            cleardivert(stream)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S Y M B O L   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

# In strict [symbol] mode, a symbol must match the following regexp:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
# see function nam_valid_strict_regexp_p()
# In non-strict mode, any non-empty string is valid.  NOT TRUE
function sym_valid_p(sym,
                      nparts, info, retval)
{
    dbg_print("sym", 5, sprintf("(sym_valid_p) sym='%s' START", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR) {
        __msg_m2 = "Invalid name: '" sym "'"
        #error("(sym_valid_p) ERROR nam__scan('" sym "') failed")
        return FALSE
    }
    # nparts must be either 1 or 2
    retval = (nparts == 1) ?  info["namevalid"] \
                           : (info["namevalid"] && info["keyvalid"])
    dbg_print("sym", 4, sprintf("(sym_valid_p) END sym='%s' => %s",
                                 sym, ppf__bool(retval)))
    return retval
}


# function sym_create(sym, code,
#                      nparts, name, key, info, level)
# {
#     dbg_print("sym", 4, sprintf("sym_create: START (sym=%s, code=%s)", sym, code))
#
#     # Scan sym => name, key
#     if ((nparts = nam__scan(sym, info)) == ERROR) {
#         error("ERROR because nam__scan failed")
#     }
#     name = info["name"]
#     key  = info["key"]
#
#     # I believe this code can never create system symbols, therefore
#     # there's no need to look it up.  This is because m2 internally
#     # wouldn't call this function (it would be done more directly in
#     # code, with the level specified directly), and the user certainly
#     # can't do it.
#     #level = nam_system_p(name) ? GLOBAL_NAMESPACE : __namespace
#     level = __namespace
#
#     # Error if name exists at that level
#     if (sym_info_defined_lev_p(info, level))
#         error("sym_create name already exists at that level")
#
#     # Error if first(code) != valid TYPE
#     if (!flag_1true_p(code, TYPE_SYMBOL))
#         error("sym_create asked to create a non-symbol")
#
#     # Add entry:        namtab[name,level] = code
#     # Create an entry in the name table
#     #dbg_print("sym", 2, sprintf("...
#     # print_stderr(sprintf("sym_create: namtab += [\"%s\",%d]=%s", name, level, code))
#     if (! nam_ll_in(name, level)) {
#         nam_ll_write(name, level, code)
#     }
#     # What if things aren't compatible?
#
#     # MORE
# }


# This is only for internal use, to easily create and define symbols at
# program start.  code must be correctly formatted.  No error checking is done.
# This function only creates symbols in the global namespace.
function sym_ll_fiat(name, key, code, new_val,
                      level)
{
    level = GLOBAL_NAMESPACE

    # Create an entry in the name table
    if (! nam_ll_in(name, level))
        nam_ll_write(name, level, code)

    # Set its value in the symbol table
    sym_ll_write(name, key, level, new_val)
}


# Deferred symbols cannot have keys, so don't even pass anything
function sym_deferred_symbol(name, code, deferred_prog, deferred_arg,
                              level)
{
    level = GLOBAL_NAMESPACE

    # Create an entry in the name table
    if (nam_ll_in(name, level))
        error("Cannot create deferred symbol when it already exists")

    nam_ll_write(name, level, code FLAG_DEFERRED)
    # It has no symbol value (yet), but we do store the two args in the
    # symbol table
    symtab[name, "", level, "deferred_prog"] = deferred_prog
    symtab[name, "", level, "deferred_arg"]  = deferred_arg
}


function sym_destroy(name, key, level)
{
    dbg_print("sym", 5, sprintf("(sym_destroy) START; name='%s', key='%s', level=%d",
                                 name, key, level))

    # Scan sym => name, key
    # if nam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if nam_system_p(name)
    # A ::= Cond: name is array T/F
    # B ::= Cond: sym has name[key] syntax T/F
    # if A & B          delete symtab[name, key, level, "symval"]
    # if A & !B         delete every symtab entry for key; delete namtab entry
    # if !A & B         syntax error: NAME is not an array and cannot be deindexed
    # if !A & !B        (normal symbol) delete symtab[name, "", level, "symval"];
    #                                   delete namtab[name]
    delete symtab[name, key, level, "symval"]
}


# DO NOT require CODE parameter.  Instead, look up NAME and
# find its code as normal.  NAME might not even be defined!
function nam_system_p(name)
{
    if (name == EMPTY)
        error("nam_system_p: NAME missing")
    return nam_ll_in(name, GLOBAL_NAMESPACE) &&
           flag_1true_p(nam_ll_read(name, GLOBAL_NAMESPACE), FLAG_SYSTEM)
}


# Remove any symbol at level "level" or greater
function sym_purge(level,
                    x, k, del_list)
{
    dbg_print("sym", 7, "(sym_purge) BEGIN")
    for (k in symtab) {
        split(k, x, SUBSEP)
        if (x[3]+0 >= level)
            del_list[x[1], x[2], x[3], x[4]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        dbg_print("sym", 3, sprintf("(sym_purge) Delete symtab['%s', '%s', %d, %s]",
                                     x[1], x[2], x[3], x[4]))
        delete symtab[x[1], x[2], x[3], x[4]]
    }
    dbg_print("sym", 7, "(sym_purge) END")
}


# Deferred symbols have an entry in namtab of TYPE_SYMBOL
# and FLAG_DEFERRED.  Only system symbols in global namespace
# are deferred, so we don't need to be super careful
function sym_deferred_p(sym,
                        code, level)
{
    level = GLOBAL_NAMESPACE
    if (!nam_ll_in(sym, level))
        return FALSE
    code = nam_ll_read(sym, level)
    if (flag_anyfalse_p(code, TYPE_SYMBOL FLAG_DEFERRED))
        return FALSE
    return ((sym, "", level, "deferred_prog") in symtab &&
            (sym, "", level, "deferred_arg")  in symtab &&
          !((sym, "", level, "symval")        in symtab))
}


function sym_define_all_deferred(    x, k, def_list, sym, code)
{
    dbg_print("nam", 5, "(sym_define_all_deferred) BEGIN")
    if (secure_level() >= 2)
        return

    for (k in namtab) {
        split(k, x, SUBSEP)
        sym = x[1]
        code = nam_ll_read(sym, GLOBAL_NAMESPACE)
        if (flag_1true_p(code, FLAG_DEFERRED)) {
            dbg_print("nam", 7, "(sym_define_all_deferred) Defining deferred " sym)
            def_list[sym] = TRUE
        }
    }

    for (sym in def_list) {
        dbg_print("nam", 5, "(sym_define_all_deferred) Defining deferred " sym)
        sym_deferred_define_now(sym)
    }
    dbg_print("nam", 5, "(sym_define_all_deferred) END")
}


# User should have checked to make sure, so let's do it
function sym_deferred_define_now(sym,
                                 code, deferred_prog, deferred_arg, cmdline, output)
{
    if (secure_level() >= 2)
        error("(sym_deferred_define_now) Security violation")

    code = nam_ll_read(sym, GLOBAL_NAMESPACE)
    deferred_prog = symtab[sym, "", GLOBAL_NAMESPACE, "deferred_prog"]
    deferred_arg  = symtab[sym, "", GLOBAL_NAMESPACE, "deferred_arg"]

    # Build the command to generate the output value, then store it in the symbol table
    cmdline = build_prog_cmdline(deferred_prog, deferred_arg, MODE_IO_CAPTURE)
    cmdline | getline output
    close(cmdline)
    # Kluge to add trailing slash to pwd(1) output
    if (sym == "__CWD__")
        output = with_trailing_slash(output)
    sym_ll_write(sym, "", GLOBAL_NAMESPACE, output)

    # Get rid of any trace of FLAG_DEFERRED
    nam_ll_write(sym, GLOBAL_NAMESPACE, flag_set_clear(code, EMPTY, FLAG_DEFERRED))
    delete symtab[sym, "", GLOBAL_NAMESPACE, "deferred_prog"]
    delete symtab[sym, "", GLOBAL_NAMESPACE, "deferred_arg"]
}


function sym_defined_p(sym,
                        nparts, info, name, key, code, level, i,
                        agg_block, count)
{
    dbg_print("sym", 5, sprintf("(sym_defined_p) sym='%s' START", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR) {
        dbg_print("sym", 2, sprintf("(sym_defined_p) END nam__scan('%s') failed => %s", sym, ppf__bool(FALSE)))
        __m2_msg = "Scan error, " __m2_msg
        return FALSE
    }
    name = info["name"]
    key  = info["key"]

    # Now call nam_lookup(info)
    level = nam_lookup(info)
    if (level == ERROR) {
        dbg_print("sym", 2, sprintf("(sym_defined_p) END nam_lookup('%s') failed, maybe ok? => %s", sym, ppf__bool(FALSE)))
        return FALSE
    }

    # We've found some matching name on some level, but not sure if it's a Symbol or not.
    # This step is necessary to make sure it's actually a Symbol.
    for (i = nam_system_p(name) ? GLOBAL_NAMESPACE : __namespace; i >= GLOBAL_NAMESPACE; i--) {
        if (sym_info_defined_lev_p(info, i)) {
            dbg_print("sym", 2, sprintf("(sym_defined_p) END sym='%s', level=%d => %s", sym, i, ppf__bool(TRUE)))
            return TRUE
        }
    }

    # If it's not a normal symbol table entry, maybe a block-array
    if (flag_alltrue_p(info["code"], TYPE_ARRAY FLAG_BLKARRAY)) {
        if (!integerp(key)) {
            dbg_print("sym", 2, sprintf("(sym_defined_p) Block array indices must be integers"))
            return FALSE
        }
        if (! ((name, "", level, "agg_block") in symtab))
            error(sprintf("Could not find ['%s','%s',%d,'agg_block'] in symtab",
                          name, "", level))

        agg_block = symtab[name, "", level, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, key) != OBJ_TEXT)
                error(sprintf("(sym_defined_p) Block # %d slot %d is not OBJ_TEXT", agg_block, key))
            dbg_print("sym", 2, sprintf("(sym_defined_p) END sym='%s', level=%d => %s", sym, level, ppf__bool(TRUE)))
            return TRUE
        }
    }

    dbg_print("sym", 2, sprintf("(sym_defined_p) END No symbol named '%s' on any level => %s", sym, ppf__bool(FALSE)))
    return FALSE
}


# Caller MUST have previously called nam__scan().
# It's the only way to get the `info' parameter value.
#
# The caller is responsible for inquiring about nam_system_p(name),
# and overriding level to zero if appropriate.  This code does
# not make any assumptions about name/levels.
function sym_info_defined_lev_p(info, level,
                                 name, key, code,
                                 x, k, thought_so)
{
    name = info["name"]
    key  = info["key"]
    # code = info["code"]
    dbg_print("sym", 5, sprintf("(sym_info_defined_lev_p) sym='%s' START", name))


    if (key == EMPTY) {
        if ((name, "", 0+level, "symval") in symtab) {
            dbg_print("sym", 5, sprintf("(sym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Found in symtab => TRUE", name, key, level))
            return TRUE
        }
        dbg_print("sym", 5, sprintf("(sym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Not found => FALSE", name, key, level))
        return FALSE
    } else {
        # Non-empty key means we have to sequential search through table
        # Eh, why is that?
        if ((name, key, 0+level, "symval") in symtab)
            thought_so = TRUE

        for (k in symtab) {
            split(k, x, SUBSEP)
            if (x[1]   != name  ||
                x[2]   != key   ||
                x[3]+0 != level ||
                x[4]   != "symval")
                continue
            # Everything matches
            if (! thought_so)
                warn("(sym_info_defined_lev_p) I didn't think you'd find a match")
            dbg_print("sym", 5, sprintf("(sym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Found in symtab => TRUE", name, key, level))
            return TRUE
        }
        if (thought_so)
            warn("sym_info_defined_lev_p) But...  I thought you'd find a match")
        dbg_print("sym", 5, sprintf("(sym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Not found => FALSE", name, key, level))
        return FALSE
    }
}


function sym_store(sym, new_val,
                    nparts, info, name, key, level, code, good, dbg5)
{
    # Fetch debug level first before it might possibly change
    dbg5 = dbg("sym", 5)
    if (dbg5)
        print_stderr(sprintf("(sym_store) START sym='%s'", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR) {
        #error("(sym_store) Scan error; bad characters in '" sym "'")
        error("Scan error, " __m2_msg)
    }
    name = info["name"]
    key  = info["key"]

    # Compute level
    # Now call nam_lookup(info)
    level = nam_lookup(info)
    # It's okay if nam_lookup "fails" (level == ERROR) because
    # we might be attempting to store a new, non-existing symbol.

    # At this point:
    #   level == ERROR            -> no matching name of any kind
    #   level == GLOBAL_NAMESPACE -> found in global
    #   0 < level < ns-1          -> find in other non-global frame
    #   level == __namespace      -> found in current namespace
    # Just because we found a namtab entry doesn't
    # mean it's okay to just muck about with symtab.

    good = FALSE
    do {
        if (level == ERROR) {   # name not found in nam
            # No namtab entry, no code : This means a normal
            # @define in the global namespace
            if (info["hasbracket"])
                error(sprintf("(sym_store) %s is not an array; cannot use brackets here", name))
            # Do scalar store
            level = info["level"] = GLOBAL_NAMESPACE
            code  = info["code"]  = TYPE_SYMBOL
            nam_ll_write(name, level, code)
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        # At this point we know nam_lookup() found *something* because
        # level != ERROR
        code = info["code"]

        # Error if we found an array without key,
        # or a plain symbol with a subscript.
        if (flag_1true_p(code, TYPE_ARRAY) && !info["hasbracket"])
            error(sprintf("(sym_store) %s is an array, so brackets are required", name))
        if (flag_1false_p(code, TYPE_ARRAY) && info["hasbracket"])
            error(sprintf("(sym_store) %s is not an array; cannot use brackets here", name))

        if (flag_1true_p(code, TYPE_SYMBOL) &&
            !sym_ll_protected(name, code) &&
            !info["hasbracket"] &&
            flag_1false_p(code, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (flag_1true_p(code, TYPE_ARRAY) &&
            !sym_ll_protected(name, code) &&
            info["hasbracket"] &&
            flag_1false_p(code, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (dbg5) {
            print_stderr(sprintf("(sym_store) LOOP BOTTOM: name='%s', key='%s', level=%d, code='%s', good=%s",
                                 name, key, level, code, ppf__bool(good)))
            nam_dump_namtab(TYPE_SYMBOL, FALSE)
            print_stderr(dump__symtab(TYPE_SYMBOL, FALSE)) # print_stderr() adds newline.  FALSE means omit system symbols
        }
    } while (FALSE)

    # if nam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if symbol is an array but sym doesn't have array[key] syntax
    # Error if symbol is not an array but sym has array[key] syntax
    # Error if you don't have permission to write to the symbol
    #   == Error ("read-only") if (flag_true(FLAG_READONLY))
    # Error if new_val is not consistent with symbol type (haha)
    #   or else coerce it to something acceptable (boolean)
    # Special processing (CONVFMT, __DEBUG__)

    # Add entry:        symtab[name, key, level, "symval"] = new_val
    if (good) {
        dbg_print("sym", 1, sprintf("(sym_store) [\"%s\",\"%s\",%d,\"symval\"]=%s",
                                     name, key, level, new_val))
        sym_ll_write(name, key, level, new_val)
    } else {
        warn(sprintf("(sym_store) !good sym='%s'", sym))
    }
    if (dbg5)
        print_stderr(sprintf("(sym_store) END;"))
}


function sym_ll_read(name, key, level)
{
    if (level == EMPTY) level = GLOBAL_NAMESPACE
    # if key == EMPTY that's probaby just fine.
    # if name == EMPTY that's probably NOT fine.
    return symtab[name, key, level, "symval"] # returns value
}


function sym_ll_in(name, key, level)
{
    if (level == EMPTY) error("sym_ll_in: LEVEL missing")
    return (name, key, level, "symval") in symtab
}


function sym_ll_write(name, key, level, val)
{
    if (level == EMPTY) error("sym_ll_write: LEVEL missing")
    if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 5 &&
        !nam_system_p(name))
        print_stderr(sprintf("(sym_ll_write) symtab[\"%s\", \"%s\", %d, \"symval\"] = %s", name, key, level, val))

    # Trigger debugging setup
    if (name == "__DEBUG__" && sym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE) == FALSE &&
        val != FALSE)
        initialize_debugging()
    else if (name == "__SECURE__") {
        val = max(secure_level(), val) # Don't allow __SECURE__ to decrease
        #print_stderr(sprintf("New __SECURE__ = %d", val))
    }
    # Maintain equivalence:  __FMT__[number] === CONVFMT
    if (name == "__FMT__" && key == "number" && level == GLOBAL_NAMESPACE) {
        if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
            sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 6)
            print_stderr(sprintf("(sym_ll_write) Setting CONVFMT to %s", val))
        CONVFMT = val
    }

    return symtab[name, key, level, "symval"] = val
}


function sym_ll_incr(name, key, level, incr)
{
    if (incr == EMPTY) incr = 1
    if (level == EMPTY) error("sym_ll_incr: LEVEL missing")
    if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 5 &&
        !nam_system_p(name))
        print_stderr(sprintf("(sym_ll_incr) symtab[\"%s\", \"%s\", %d, \"symval\"] += %d",
                             name, key, level, incr))
    return symtab[name, key, level, "symval"] += incr
}


function sym_fetch(sym,
                    nparts, info, name, key, code, level, val, good,
                    agg_block, count)
{
    dbg_print("sym", 5, sprintf("(sym_fetch) START; sym='%s'", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR)
        error("(sym_fetch) Scan error, '" sym "'")
    name = info["name"]
    key  = info["key"]

    # Now call nam_lookup(info)
    level = nam_lookup(info)
    if (level == ERROR)
        error("(sym_fetch) nam_lookup(info) failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # symtab because NAME[KEY] might not be defined.
    code = info["code"]
    dbg_print("sym", 5, sprintf("(sym_fetch) nam_lookup ok; level=%d, code=%s", level, code))

    # Sanity checks
    good = FALSE

    # 1. Fetching @ARRNAME@ w/o key return # elements in ARRNAME.
    if (info["isarray"] == TRUE && info["hasbracket"] == FALSE)
        error("sym_fetch: Fetching @ARRNAME@ without a key is not supported yet")

    # 2. Error if symbol is not an array but sym has array[key] syntax
    if (info["isarray"] == FALSE && info["hasbracket"] == TRUE)
        error("sym_fetch: Symbol is not an array but sym has array[key] syntax")

    # Now, either both isarray and hasbracket are TRUE
    # or both are FALSE.
    do {
        # 3. Check code for TYPE_SYMBOL
        if (info["isarray"] == FALSE &&
            info["hasbracket"] == FALSE &&
            flag_1true_p(code, TYPE_SYMBOL) &&
            key == EMPTY) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }
        # 4. Check code for TYPE_ARRAY
        if (info["isarray"] == TRUE &&
            info["hasbracket"] == TRUE &&
            flag_1true_p(code, TYPE_ARRAY) &&
            key != EMPTY) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        # print_stderr(sprintf("(sym_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
        #                      sym, name, key, level, code))

    } while (FALSE)

    if (flag_1true_p(code, FLAG_DEFERRED))
        sym_deferred_define_now(sym)

    if (flag_1true_p(code, FLAG_BLKARRAY)) {
        # Look up block
        if (!integerp(key))
            error(sprintf("(sym_fetch) Block array indices must be integers"))
        if (! ((name, "", level, "agg_block") in symtab))
            error(sprintf("Could not find ['%s','%s',%d,'agg_block'] in symtab",
                          name, "", level))

        agg_block = symtab[name, "", level, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, key) != OBJ_TEXT)
                error(sprintf("(sym_fetch) Block # %d slot %d is not OBJ_TEXT", agg_block, key))
            val = blk_ll_slot_value(agg_block, key)
        } else
            error(sprintf("(sym_fetch) Out of bounds"))
    } else {
        # It's a normal symbol
        if (! sym_ll_in(name, key, level))
            error("(sym_fetch) Not in symtab: NAME='" name "', KEY='" key "'")
        val = sym_ll_read(name, key, level)
    }

        dbg_print("sym", 2, sprintf("(sym_fetch) END sym='%s', level=%d => %s", sym, level, ppf__bool(TRUE)))
    if (flag_1true_p(code, FLAG_INTEGER))
        return 0 + val
    else if (flag_1true_p(code, FLAG_NUMERIC))
        return 0.0 + val
    else if (flag_1true_p(code, FLAG_BOOLEAN))
        return !! (0 + val)
    else
        return val
}


# XXX Bare bones, no checking yet
function sym_increment(sym, incr,
                        name, key)
{
    if (incr == EMPTY)
        incr = 1

    # Scan sym => name, key
    # Compute level
    # if nam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if incr is not numeric
    # Error if symbol is an array but sym doesn't have array[key] syntax
    # Error if symbol is not an array but sym has array[key] syntax
    # Error if you don't have permission to write to the symbol
    #   == Error ("read-only") if (flag_true(FLAG_READONLY))
    # Error if value is not consistent with symbol type (haha)
    #   or else coerce it to something acceptable (boolean)

    # Add entry:        symtab[name, key, level, "symval"] += incr
    #symtab[sym, "", GLOBAL_NAMESPACE, "symval"] += incr
    sym_ll_incr(sym, "", GLOBAL_NAMESPACE, incr)
}


function sym_protected_p(sym,
                          nparts, info, name, key, code, level, retval)
{
    dbg_print("sym", 5, sprintf("(sym_protected_p) START sym='%s'", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR)
        error("(sym_protected_p) Scan error, '" sym "'")
    name = info["name"]
    key  = info["key"]

    # Now call nam_lookup(info)
    level = nam_lookup(info)
    if (level == ERROR)
        return double_underscores_p(name)

    # Error if (! name in namtab)
    if (!nam_ll_in(name, level))
        error("not in namtab!?  name=" name ", level=" level)

    # Error if name does not exist at that level
    code = nam_ll_read(name, level)
    retval = sym_ll_protected(name, code)
    dbg_print("sym", 4, sprintf("(sym_protected_p) END; sym '%s' => %s", sym, ppf__bool(retval)))
    return retval
}


# Protected symbols cannot be changed by the user.
function sym_ll_protected(name, code)
{
    if (flag_1true_p(code, FLAG_READONLY))
        return TRUE
    if (flag_1true_p(code, FLAG_WRITABLE))
        return FALSE
    if (double_underscores_p(name))
        return TRUE
    return FALSE
}


function sym_definition_ppf(sym,
                            definition)
{
    definition = sym_fetch(sym)
    return (index(definition, TOK_NEWLINE) == IDX_NOT_FOUND) \
        ? "@define "  sym TOK_TAB definition \
        : "@longdef " sym TOK_NEWLINE \
          definition      TOK_NEWLINE \
          "@endlongdef"
}


function sym_true_p(sym,
                     val)
{
    return (sym_defined_p(sym) &&
            ((val = sym_fetch(sym)) != FALSE &&
              val                    != EMPTY))
}


# Throw an error if symbol is NOT defined
function assert_sym_defined(sym, hint,    s)
{
    if (sym_defined_p(sym))
        return TRUE
    s = sprintf("Name '%s' not defined%s%s",  sym,
                ((hint != EMPTY) ? " [" hint "]" : ""),
                ((!emptyp($0)) ? TOK_COLON $0 : ""))
    error(s)
}


function assert_sym_okay_to_define(name,
                                    code)
{
    assert_sym_valid_name(name)
    assert_sym_unprotected(name)

    if (nam_ll_in(name, __namespace) &&
        flag_alltrue_p((code = nam_ll_read(name, __namespace)), TYPE_SYMBOL) &&
        flag_allfalse_p(code, FLAG_READONLY))
        return TRUE
    if (nam_ll_in(name, __namespace)) return FALSE

    if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
        flag_alltrue_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL) &&
        flag_allfalse_p(code, FLAG_READONLY))
        return TRUE
    if (nam_ll_in(name, GLOBAL_NAMESPACE)) return FALSE

    # Can't shadow a system symbol
    if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
        flag_alltrue_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL FLAG_SYSTEM))
        return FALSE

    if (double_underscores_p(name))
        return FALSE

    # You can redefine a symbol, but not a command, function, or sequence
    # if (!name_available_in_all_p(name, TYPE_USER TYPE_FUNCTION TYPE_SEQUENCE))
    #     error("Name '" name "' not available:" $0)
    return TRUE
}


# Throw an error if symbol IS protected
function assert_sym_unprotected(sym)
{
    if (sym_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
}


# Throw an error if the symbol name is NOT valid
function assert_sym_valid_name(sym)
{
    if (! sym_valid_p(sym))
        error("Name '" sym "' not valid:" $0)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       T E X T   &   P R I N T I N G
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function execute__text(text,
                       stream)
{
    dbg_print("xeq", 3, sprintf("(execute__text) START; text='%s'", text))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg_print("xeq", 3, "(execute__text) NOP due to __xeq_ctl=" __xeq_ctl)
        return
    }

    if (curr_atmode() == MODE_AT_PROCESS)
        text = dosubs(text)

    if ((stream = DIVNUM()) > TERMINAL) {
        dbg_print("ship_out", 5, sprintf("(execute__text) END Appending text to stream %d", stream))
        blk_append(stream, OBJ_TEXT, text)
        return
    }

    if (__print_mode == MODE_TEXT_PRINT) {
        printf("%s\n", text)
        flush_stdout(SYNC_LINE)
    } else if (__print_mode == MODE_TEXT_STRING)
        __textbuf = sprintf("%s%s\n", __textbuf, text)
    else
        error("(execute__text) Bad __print_mode " __print_mode)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       P A R S E   B O O L E A N   E X P R
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function evaluate_boolean(text, negate,
                          condval)
{
    if (negate == "")
        negate = FALSE
    bool__tokenize_string(text)
    __bf = 1
    condval = bool__scan_expr(text)
    if (negate)
        condval = !condval
    return condval
}


function bool__tokenize_string(s,
                               slen, i, oldi, c, pcnt, name)
{
    dbg_print("bool", 6, "(bool__tokenize_string) START")
    slen = length(s)
    i = 1
    __bnf = 0
    c = substr(s, i, 1)
    dbg_print("bool", 5, sprintf("(bool__tokenize_string) START; slen=%d, i=%d, c=%s", slen, i, c))

    while (TRUE) {
        if (i > slen || c == "")
            break
        while (c == TOK_SPACE || c == TOK_TAB)   # skip whitespace
            c = substr(s, ++i, 1)

        if (c == TOK_NOT ||
            c == TOK_LPAREN ||
            c == TOK_RPAREN) {
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Found '%s' at i=%d", c, i))
            __btoken[++__bnf] = c
            i++
            c = substr(s, i, 1)
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) %s __btoken[%d]=TOK_{NOT|LPAREN|RPAREN}, i now %d", __btoken[__bnf], __bnf, i))

        } else if (substr(s, i, 2) == "&&") {
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Found '&&' at i=%d", i))
            __btoken[++__bnf] = TOK_AND
            i += 2
            c = substr(s, i, 1)
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) && __btoken[%d]=TOK_AND, i now %d", __bnf, i))

        } else if (substr(s, i, 2) == "||") {
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Found '||' at i=%d", i))
            __btoken[++__bnf] = TOK_OR
            i += 2
            c = substr(s, i, 1)
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) || __btoken[%d]=TOK_OR, i now %d", __bnf, i))

        } else if (substr(s, i, 8) == "defined(") {
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Found 'defined(' at i=%d", i))
            i += 8
            oldi = i
            while (c != TOK_RPAREN && i <= slen)
                c = substr(s, ++i, 1)
            if (substr(s, i, 1) != TOK_RPAREN)
                error(sprintf("(bool__tokenize_string) defined - no closing paren; __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))
            name = substr(s, oldi, i-oldi)
            if (emptyp(name))
                error("(bool__tokenize_string) defined(); Name cannot be empty")
            assert_sym_valid_name(name)
            __btoken[++__bnf] = TOK_DEFINED_P
            __btoken[++__bnf] = name
            c = substr(s, ++i, 1)       # char after closing paren
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) defined() __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))

        } else if (substr(s, i, 4) == "env(") {
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Found 'env(' at i=%d", i))
            i += 4
            oldi = i
            while (c != TOK_RPAREN && i <= slen)
                c = substr(s, ++i, 1)
            if (substr(s, i, 1) != TOK_RPAREN)
                error(sprintf("(bool__tokenize_string) env - no closing paren; __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))
            name = substr(s, oldi, i-oldi)
            if (emptyp(name))
                error("(bool__tokenize_string) env(); Name cannot be empty")
            assert_valid_env_var_name(name)
            __btoken[++__bnf] = TOK_ENV_P
            __btoken[++__bnf] = name
            c = substr(s, ++i, 1)       # char after closing paren
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) env() __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))

        } else if (substr(s, i, 7) == "exists(") {
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Found 'exists(' at i=%d", i))
            i += 7
            oldi = i
            while (c != TOK_RPAREN && i <= slen)
                c = substr(s, ++i, 1)
            if (substr(s, i, 1) != TOK_RPAREN)
                error(sprintf("(bool__tokenize_string) exists - no closing paren; __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))
            name = substr(s, oldi, i-oldi)
            if (emptyp(name))
                error("(bool__tokenize_string) exists(); Name cannot be empty")
            __btoken[++__bnf] = TOK_EXISTS_P
            __btoken[++__bnf] = dosubs(name)
            c = substr(s, ++i, 1)       # char after closing paren
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) exists() __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))

        } else {                # OTHER
            pcnt = 0
            oldi = i            # start pos
            dbg_print("bool", 7, sprintf("(bool__tokenize_string) Starting to scan other at i=%d, s='%s'", i, substr(s, i)))
            while (TRUE) {
                if (i > slen || c == "")
                    break
                if (c == TOK_LPAREN) {
                    pcnt++
                    c = substr(s, ++i, 1) # next char
                    dbg_print("bool", 7, "(bool__tokenize_string) other: '(', pcnt now " pcnt ", at i=" i)
                } else if (c == TOK_RPAREN) {
                    if (pcnt > 0) {
                        pcnt--
                        dbg_print("bool", 7, "(bool__tokenize_string) other: ')', but pcnt was " pcnt+1 " so just decr; pcnt now " pcnt "; at i=" i)
                    } else {
                        dbg_print("bool", 7, "(bool__tokenize_string) other: '(', all parens closed (pcnt=" pcnt "), we're done, at i=" i)
                        break
                    }
                } else if (substr(s, i, 2) == "&&" || substr(s, i, 2) == "||") {
                    # && and || cannot appear in a calc3 expression -
                    # they must separate boolean clauses here.
                    dbg_print("bool", 7, "(bool__tokenize_string) other: found '" substr(s, i, 2) "' at i=" i)
                    c = substr(s, i, 1)
                    break
                } else {
                    c = substr(s, ++i, 1) # next char
                    dbg_print("bool", 8, "(bool__tokenize_string) other: continuing, i=" i "...")
                }
            }
            __btoken[++__bnf] = rtrim(substr(s, oldi, i-oldi))
            while (c == TOK_SPACE || c == TOK_TAB)   c = substr(s, ++i, 1) # skip ws
            dbg_print("bool", 5, sprintf("(bool__tokenize_string) other __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))
        }
    }
    dbg_print("bool", 7, "(bool__tokenize_string) DONE; __bnf=" __bnf)
    if (dbg("bool", 3))
        for (i = 1; i <= __bnf; i++)
            print_stderr(sprintf("(bool__tokenize_string) __btoken[%d]='%s'", i, __btoken[i]))
}


function bool__scan_expr(    e, f, r)           # term   | term || term
{
    # print_stderr(sprintf("(bool__scan_expr) __bf=%d, __btoken[]=%s, e='%s'", __bf, __btoken[__bf], e))
    e = bool__scan_term()
    if (e == ERROR) {
        warn("(bool__scan_expr) Initial e returned ERROR, propagating")
        return e
    }

    # print_stderr(sprintf("(bool__scan_expr) After bool__scan_term, __bf=%d, __btoken[%d]=%s, e='%s'(%s)", __bf, __bf, __btoken[__bf], e, ppf__bool(e)))
    while (__btoken[__bf] == TOK_OR) {
        __bf++
        f = bool__scan_term()
        r = e || f
        #print_stderr("Found TOK_OR, __bf now " __bf++)
        dbg_print("bool", 5, sprintf("(bool__scan_expr) TOK_OR, e'%s' || f'%s' => %s", e, f, ppf__bool(r)))
        e = r
    }
    return e
}


function bool__scan_term(    e, f, r)           # factor | factor && factor
{
    e = bool__scan_factor()
    if (e == ERROR) {
        warn("(bool__scan_term) Initial e returned ERROR, propagating")
        return e
    }
    # print_stderr(sprintf("(bool__scan_term) After bool__scan_factor, __bf=%d, __btoken[]=%s, e='%s'(%s)", __bf, __btoken[__bf], e, ppf__bool(e)))
    while (__btoken[__bf] == TOK_AND) {
        __bf++
        f = bool__scan_factor()
        if (f == ERROR) {
            warn("(bool__scan_term) f returned ERROR, propagating")
            return f
        }
        r = e && f
        dbg_print("bool", 5, sprintf("(bool__scan_term) TOK_AND, e'%s' && f'%s' => %s", e, f, ppf__bool(r)))
        e = r
    }
    return e
}


function bool__scan_factor(    e, r,         # ! factor | variable | ( expression )
                                name)
{
    dbg_print("bool", 5, sprintf("(bool__scan_factor) __bf=%d, __btoken[]=%s, e='%s'", __bf, __btoken[__bf], e))
    if (__btoken[__bf] ~ /^[01]$/) {
        dbg_print("bool", 5, "(bool__scan_factor) Match regexp 1")
        return 0+__btoken[__bf++]

    } else if (__btoken[__bf] == TOK_LPAREN) {
        __bf++
        e = bool__scan_expr()
        if (__btoken[__bf++] != TOK_RPAREN)
            error("(bool__scan_factor) Missing ')' at " __btoken[__bf])
        dbg_print("bool", 5, "(bool__scan_factor) Found parens, returning " ppf__bool(e))
        return e

    } else if (__btoken[__bf] == TOK_NOT) {
        __bf++
        e = bool__scan_factor()
        if (e == ERROR) {
            dbg_print("bool", 5, "(bool__scan_factor): NOT: scan_factor => ERROR, propagating")
            return ERROR
        } else {
            dbg_print("bool", 5, "(bool__scan_factor) NOT: Just read " e ", so returning " ppf__bool(!e))
            return !e
        }

    } else if (__btoken[__bf] == TOK_DEFINED_P) {
        name = __btoken[++__bf]
        if (name == EMPTY) return ERROR
        assert_sym_valid_name(name)
        r = sym_defined_p(name)
        dbg_print("bool", 5, "(bool__scan_factor): DEFINED; name='" name "', returning " ppf__bool(r))
        __bf++
        return r

    } else if (__btoken[__bf] == TOK_ENV_P) {
        name = __btoken[++__bf]
        if (name == EMPTY) return ERROR
        assert_valid_env_var_name(name)
        r = name in ENVIRON
        dbg_print("bool", 5, "(bool__scan_factor): ENV; name='" name "', returning " ppf__bool(r))
        __bf++
        return r

    } else if (__btoken[__bf] == TOK_EXISTS_P) {
        name = __btoken[++__bf]
        if (name == EMPTY) return ERROR
        r = path_exists_p(name)
        dbg_print("bool", 5, "(bool__scan_factor) EXISTS; name='" name "', returning " ppf__bool(r))
        __bf++
        return r

    } else if (__btoken[__bf] ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/) { # symbol?
        r = sym_true_p(__btoken[__bf])
        dbg_print("bool", 5, "(bool__scan_factor): SYM; just read '" __btoken[__bf] "', so returning " ppf__bool(r))
        __bf++
        return r

    } else {
        # Boolean evaluation would normally fail here, but we'll pass it along to 'evaluate_condition'
        #print_stderr(sprintf("bool__scan_factor: Did not match __bf=%d, __btoken[]=%s, e='%s'", __bf, __btoken[__bf], e))
        r = evaluate_condition(__btoken[__bf], FALSE) 
        if (r == ERROR)
            warn("(bool__scan_factor): evaluate_condition('" __btoken[__bf] "') returned ERROR")
        else
            dbg_print("bool", 5, "(bool__scan_factor) evaluate_condition('" __btoken[__bf] "') returned " ppf__bool(r))
        return r
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  A R R A Y
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @array                ARR
function xeq_cmd__array(name, cmdline,
                        arr)
{
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    arr = $1
    assert_sym_okay_to_define(arr)
    if (nam_ll_in(arr, __namespace))
        error("Array '" arr "' already defined")
    nam_ll_write(arr, __namespace, TYPE_ARRAY)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  B R E A K
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @break
function xeq_cmd__break(name, cmdline,
                        level, block, block_type)
{
    # Logical check
    if (__xeq_ctl != XEQ_NORMAL)
        error("(xeq_cmd__break) __xeq_ctl is not normal, how did that happen?")

    __xeq_ctl = XEQ_BREAK
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  C A S E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @case
function parse__case(                case_block, preamble_block, pstat)
{
    dbg_print("case", 3, sprintf("(parse__case) START dstblk=%d, $0='%s'", curr_dstblk(), $0))

    raise_namespace()

    # Create a new block for case_block
    case_block = blk_new(BLK_CASE)
    dbg_print("case", 5, "(parse__case) New block # " case_block " type " ppf__block_type(blk_type(case_block)))
    preamble_block = blk_new(BLK_AGG)
    dbg_print("case", 5, "(parse__case) New block # " case_block " type " ppf__block_type(blk_type(preamble_block)))

    $1 = ""
    blktab[case_block, 0, "casevar"]        = $2
    blktab[case_block, 0, "preamble_block"] = preamble_block
    blktab[case_block, 0, "seen_otherwise"] = FALSE
    blktab[case_block, 0, "dstblk"]         = preamble_block
    blktab[case_block, 0, "valid"]          = FALSE
    dbg_print_block("case", 7, case_block, "(parse__case) case_block")
    stk_push(__parse_stack, case_block) # Push it on to the parse_stack

    dbg_print("case", 5, "(parse__case) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcase
    dbg_print("case", 5, "(parse__case) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@case] Parse error")

    dbg_print("case", 5, "(parse__case) END; => " case_block)
    return case_block
}


function parse__of(                case_block, of_block, of_val)
{
    dbg_print("case", 3, sprintf("(parse__of) START dstblk=%d, mode=%s, $0='%s'",
                                 curr_dstblk(), ppf__mode(curr_atmode()), $0))
    if (check__parse_stack(BLK_CASE) != 0)
        error("[@of] Parse error; " __m2_msg)
    case_block = stk_top(__parse_stack)

    lower_namespace()           # trigger name/symbol purge
    raise_namespace()

    # Create a new block for the new Of branch and make it current
    of_block = blk_new(BLK_AGG)
    sub(/^@of[ \t]+/, "")
    of_val = $0
    if ((case_block, of_val, "of_block") in blktab)
        error("(parse__of) Duplicate '@of' values not allowed:@of " $0)

    blktab[case_block, of_val, "of_block"] = of_block
    blktab[case_block, 0, "dstblk"]  = of_block
    return of_block
}


function parse__otherwise(                case_block, otherwise_block)
{
    dbg_print("case", 3, sprintf("(parse__otherwise) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_CASE) != 0)
        error("[@otherwise] Parse error; " __m2_msg)
    case_block = stk_top(__parse_stack)

    # Check if already seen @else
    if (blktab[case_block, 0, "seen_otherwise"] == TRUE)
        error("(parse__otherwise) Cannot have more than one @otherwise")

    lower_namespace()           # trigger name/symbol purge
    raise_namespace()

    # Create a new block for the False branch and make it current
    blktab[case_block, 0, "seen_otherwise"] = TRUE
    otherwise_block = blk_new(BLK_AGG)
    blktab[case_block, 0, "otherwise_block"] = otherwise_block
    blktab[case_block, 0, "dstblk"]  = otherwise_block
    return otherwise_block
}


# @endcase
function parse__endcase(                case_block) # OK
{
    dbg_print("case", 3, sprintf("(parse__endcase) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_CASE) != 0)
        error("[@endcase] Parse error; " __m2_msg)

    case_block = stk_pop(__parse_stack)
    blktab[case_block, 0, "valid"] = TRUE
    lower_namespace()
    return case_block
}


function xeq__BLK_CASE(case_block,
                       block_type, casevar, caseval, preamble_block)
{
    block_type = blk_type(case_block)
    dbg_print("case", 3, sprintf("(xeq__BLK_CASE) START dstblk=%d, case_block=%d, type=%s",
                                 curr_dstblk(), case_block, ppf__block_type(block_type)))

    dbg_print_block("case", 7, case_block, "(xeq__BLK_CASE) case_block")
    if ((blk_type(case_block) != BLK_CASE) ||  \
        (blktab[case_block, 0, "valid"] != TRUE))
        error("(xeq__BLK_CASE) Bad config")

    # Check if the case variable value matches any @of values
    casevar = blktab[case_block, 0, "casevar"]
    dbg_print("case", 5, sprintf("(xeq__BLK_CASE) casevar '%s'", casevar))
    assert_sym_defined(casevar)
    caseval = sym_fetch(casevar)
    dbg_print("case", 5, sprintf("(xeq__BLK_CASE) caseval '%s'", caseval))

    if ((case_block, caseval, "of_block") in blktab) {
        # See if there's a preamble which is non-empty.  Preambles get
        # their own namespace.
        preamble_block = blktab[case_block, 0, "preamble_block"]
        if (blktab[preamble_block, 0, "count"]+0 > 0) {
            dbg_print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                         blktab[case_block, 0, "preamble_block"]))
            raise_namespace()
            execute__block(blktab[case_block, 0, "preamble_block"])
            lower_namespace()
            dbg_print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        }

        # The @of branch gets a new namespace
        raise_namespace()
        dbg_print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                     blktab[case_block, caseval, "of_block"]))
        execute__block(blktab[case_block, caseval, "of_block"])
        dbg_print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        lower_namespace()
    } else if (blktab[case_block, 0, "seen_otherwise"] == TRUE) {
        # NB - @otherwise branches DO NOT execute the preamble (if any)
        raise_namespace()
        dbg_print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                     blktab[case_block, 0, "otherwise_block"]))
        execute__block(blktab[case_block, 0, "otherwise_block"])
        dbg_print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        lower_namespace()
    }

    dbg_print("case", 3, sprintf("(xeq__BLK_CASE) END"))
}


function ppf__case(case_block,
                   buf, i, caseval, x, k)
{
    buf = "@case " blktab[case_block, 0, "casevar"] TOK_NEWLINE
    buf = buf ppf__block(blktab[case_block, 0, "preamble_block"]) TOK_NEWLINE
    for (k in blktab) {
        split(k, x, SUBSEP)
        if (x[1] == case_block && x[3] == "of_block")
            buf = buf "@of " x[2] TOK_NEWLINE \
                ppf__block(blktab[case_block, x[2], "of_block"]) TOK_NEWLINE
    }
    if (blktab[case_block, 0, "seen_otherwise"])
        buf = buf "@otherwise\n" \
            ppf__block(blktab[case_block, 0, "otherwise_block"]) TOK_NEWLINE
    buf = buf "@endcase"
    return buf
}


function ppf__BLK_CASE(blknum)
{
    return "(ppf__BLK_CASE) BROKEN"
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  C L E A R D I V E R T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @cleardivert [N]...
function xeq_cmd__cleardivert(name, cmdline,
                           i, stream)
{
    $0 = cmdline
    dbg_print("divert", 1, sprintf("(xeq_cmd__cleardivert) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    dbg_print_block("ship_out", 8, curr_dstblk(), "(xeq_cmd__cleardivert) curr_dstblk()")
    if (NF == 0)
        cleardivert_all()
    else {
        i = 0
        while (++i <= NF) {
            stream = dosubs($i)
            if (!integerp(stream))
                error(sprintf("Value '%s' must be numeric:", stream) $0)
            if (stream > MAX_STREAM)
                error("Bad parameters:" $0)
            dbg_print("divert", 5, sprintf("(xeq_cmd__cleardivert) CALLING cleardivert(%d)", stream))
            cleardivert(stream)
        }
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  C O N T I N U E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @continue
function xeq_cmd__continue(name, cmdline)
{
    # Logical check
    if (__xeq_ctl != XEQ_NORMAL)
        error("(xeq_cmd__continue) __xeq_ctl is not normal, how did that happen?")

    __xeq_ctl = XEQ_CONTINUE
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D E F I N E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @append
# @default
# @define      NAME TEXT
# @initialize
function xeq_cmd__define(name, cmdline,
                         sym, append_flag, nop_if_defined, error_if_defined)
{
    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)
    append_flag = (name == "append")
    nop_if_defined = (name == "default")
    error_if_defined = (name == "initialize")

    sym = $1
    assert_sym_okay_to_define(sym)
    if (sym_defined_p(sym)) {
        if (nop_if_defined)
            return
        if (error_if_defined)
            error("Symbol '" sym "' already defined:" $0)
    }

    #sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")
    sub(/^[ \t]*[^ \t]+[ \t]*/, "")
    if ($0 == EMPTY) $0 = "1"
    # XXX No checking, dangerous!!
    sym_store(sym, append_flag ? sym_fetch(sym) $0 \
                                : $0)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D I V E R T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Documentation explicitly states: "If argument is not an integer,
#       no action is taken and no error is thrown.
#
#*****************************************************************************
# @divert               [N]
function xeq_cmd__divert(name, cmdline,
                        new_stream)
{
    $0 = cmdline
    dbg_print("divert", 1, sprintf("(xeq_cmd__divert) START dstblk=%d, NF=%d, cmdline='%s'",
                                   curr_dstblk(), NF, cmdline))
    new_stream = (NF == 0) ? "0" : dosubs($1)
    if (!integerp(new_stream))
        # error(sprintf("Value '%s' must be integer:", new_stream) $0)
        return
    if (new_stream > MAX_STREAM)
        error("Bad parameters:" $0)

    sym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, int(new_stream))
    dbg_print("divert", 1, sprintf("(xeq_cmd__divert) END; __DIVNUM__ now %d", new_stream))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D U M P
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @dump[all]            [WHAT] [FILE]
# Output format:
#       @<command>  SPACE  <name>  TAB  <stuff includes spaces...>
function xeq_cmd__dump(name, cmdline,
                       buf, cnt, definition, dumpfile, i, key, keys, sym_name, all_flag,
                       what, what_type, block_type, blk_label, desc)
{
    all_flag = name == "dumpall"
    dumpfile = EMPTY

    $0 = cmdline
    if (NF > 1) {
        warn("(xeq_cmd__dump) Dumpfile is not supported yet")
        what = $1
        $1 = ""
        sub("^[ \t]*", "")
        dumpfile = rm_quotes(dosubs($0))
        # print_stderr(sprintf("dumpfile = '%s'", dumpfile))
    } else if (NF == 0) {
        what = "symbols"
    } else {                    # NF == 1
        what = tolower($1)
    }

    if (what ~ /sym(bol)?s?/) {
        what_type = TYPE_SYMBOL
        buf = dump__symtab(what_type, all_flag)
    } else if (what ~ /seq(uence)?s?/) {
        what_type = TYPE_SEQUENCE
        buf = dump__seqtab(what_type, all_flag)
    } else if (what ~ /(cmd|command)s?/) {
        what_type = TYPE_USER
        #buf = nam_dump_namtab(what_type, all_flag)
        buf = dump__cmdtab(what_type, all_flag)
    } else if (what ~ /name?s?/) {
        what_type = TYPE_ANY
        buf = nam_dump_namtab(what_type, all_flag)
    } else if (what ~ /bl(oc)?ks?/) {
        buf = "BROKEN: " blk_dump_blktab()
    } else if (what ~ /[0-9]+/) {
        what_type = TYPE_ANY    # There is no "block" type
        #print_stderr("Dump of block # " what)
        if (! ((what, 0, "type") in blktab))
            error("(xeq_cmd__dump) No 'type' field for block " what)
        block_type = blk_type(what)
        blk_label = ppf__block_type(block_type)
        # print_stderr("(xeq_cmd__dump) block_type = " block_type)
        desc = ppf__BLK(what)
        buf = sprintf("Block # %d, Type=%s:\n", what, blk_label)
        if (!emptyp(desc))
            buf += ppf__BLK(what)
        if (all_flag)
            buf = buf "\nCode:\n" ppf__block(what)
    } else
        error("Invalid dump argument " what)

    # Format definitions
    if (emptyp(buf)) {
        # I don't usually condone chatty programs, but it seems to me
        # that if the user asks for the symbol table and there's nothing
        # to print, she'd probably like to know.  Perhaps a config file
        # was not read properly...
        warn(sprintf("(xeq_cmd__dump) Empty %s table; dumpfile='%s'", ppf__flags(what_type), dumpfile))
    } else if (emptyp(dumpfile))  # No FILE arg provided to @dump command
        print buf
    else {
        dbg_print("sym", 3, sprintf("(xeq_cmd__dump) %s table dump to '%s'",
                                    ppf__flags(what_type), dumpfile))
        print buf > dumpfile
        close(dumpfile)
    }
}


# Quicksort - from "The AWK Programming Language" p. 161.
# Used in blt_dump() to sort the symbol table.
function qsort(A, left, right,    i, lastpos)
{
    if (left >= right)          # Do nothing if array contains
        return                  #   less than two elements
    _swap(A, left, left + int((right-left+1)*rand()))
    lastpos = left              # A[left] is now partition element
    for (i = left+1; i <= right; i++)
        if (_less_than(A[i], A[left]))
            _swap(A, ++lastpos, i)
    _swap(A, left, lastpos)
    qsort(A, left,   lastpos-1)
    qsort(A, lastpos+1, right)
}

function _swap(A, i, j,    t)
{
    t = A[i];  A[i] = A[j];  A[j] = t
}

# Special comparison to sort leading underscores after all other values,
# and numbers before other values.
function _less_than(s1, s2,    fs1, fs2, d1, d2)
{
    dbg_print("dump", 7, sprintf("_less_than: s1='%s', s='%s'", s1, s2))
    fs1 = first(s1)
    fs2 = first(s2)

    if      (fs1 == "" && fs2 == "") error("(_less_than) fs1 and fs2 are empty!")
    else if (fs1 == "" && fs2 != "") return TRUE
    else if (fs1 != "" && fs2 == "") return FALSE

    # Sort underscore vs other
    else if (fs1 == "_" && fs2 != "_") return FALSE
    else if (fs1 != "_" && fs2 == "_") return TRUE

    # Sort digit vs non-digit
    else if ( isdigit(fs1) && !isdigit(fs2)) return FALSE
    else if (!isdigit(fs1) &&  isdigit(fs2)) return TRUE

    # If we're looking at numbers, grab them and do a numeric comparison
    # -- hopefully they're different.
    # BUG: Can't sort foo123A vs foo123B properly
    else if (isdigit(fs1) && isdigit(fs2)) {
        d1 = int(s1); d2 = int(s2)
        if (d1 != d2)
            return d1 < d2
        else
            # numbers are the same, so do a raw comparison
            return s1 < s2

    # If we're looking at the same character, compare the following ones
    } else if (toupper(fs1) == toupper(fs2))
        return _less_than(substr(s1,2), substr(s2,2))

    # Sort characters case-insensitively
    else if (isalpha(fs1) && isalpha(fs2))
        return toupper(s1) < toupper(s2)

    else
        return s1 < s2
}


# Like ppf__XX functions, last line of multi-line buffer
# *omits* newline.
function dump__symtab(type, include_sys, # caller names this "all_flag"
                      x, k, code, buf, cond_matched,
                      keys, cnt, i)
{
    dbg_print("sym", 4, "(dump__symtab) BEGIN")
    if (first(type) != TYPE_SYMBOL)
        error("(dump__symtab) Bad type " ppf__flags(first(type)))
    sym_define_all_deferred()

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (k in symtab) {
        split(k, x, SUBSEP)
        # print "name  =", x[1]
        # print "key   =", x[2]
        # print "level =", x[3]
        # print "elem  =", x[4]
        if (x[4] != "symval") continue
        code = nam_ll_read(x[1], x[3]) # name, level
        dbg_print("sym", 7, sprintf("(dump__symtab) name='%s', key='%s', code=%s",
                                    x[1], x[2], code))
        if (((flag_1true_p(code, TYPE_SYMBOL) && x[2] == EMPTY) ||
             (flag_1true_p(code, TYPE_ARRAY)  && x[2] != EMPTY))) {
            # So far so good - now see if we should eliminate system symbols
            if (!include_sys && flag_1true_p(code, FLAG_SYSTEM))
                continue
            keys[++cnt] = x[1] (x[2] != EMPTY ? "[" x[2] "]" : "")
        }
    }

    qsort(keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf sym_definition_ppf(keys[i]) TOK_NEWLINE
    dbg_print("sym", 4, "(dump__symtab) END")
    return chomp(buf)
}


function dump__seqtab(type, include_sys,
                      x, k, keys, cnt, code, buf, i)
{
    dbg_print("seq", 4, "(dump__seqtab) BEGIN")
    if (first(type) != TYPE_SEQUENCE)
        error("(dump__seqtab) Bad type " ppf__flags(first(type)))

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (k in seqtab) {
        split(k, x, SUBSEP)
        # print "name  =", x[1]
        # print "elem  =", x[2]
        if (x[2] != "seqval") continue
        code = nam_ll_read(x[1], GLOBAL_NAMESPACE) # name, level
        dbg_print("seq", 7, sprintf("(dump__seqtab) name='%s', code=%s",
                                    x[1], code))
        if (flag_1true_p(code, TYPE_SEQUENCE)) {
            # I don't think there are any system sequences yet...
            if (!include_sys && flag_1true_p(code, FLAG_SYSTEM))
                continue
            keys[++cnt] = x[1]
        }
    }

    qsort(keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf seq_definition_ppf(keys[i]) TOK_NEWLINE
    dbg_print("seq", 4, "(dump__seqtab) END")
    return chomp(buf)
}


function dump__cmdtab(type, include_sys,
                      x, k, keys, cnt, code, buf, i)
{
    dbg_print("cmd", 4, "(dump__cmdtab) BEGIN")
    if (first(type) != TYPE_USER)
        error("(dump__cmdtab) Bad type " ppf__flags(first(type)))

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (k in cmdtab) {
        split(k, x, SUBSEP)
        # print_stderr("x[1]=" x[1])
        # print_stderr("x[2]=" x[2])
        # print_stderr("x[3]=" x[3])
        # print_stderr("value => " cmdtab[x[1], x[2], x[3]])

        if (x[3] != "user_block") continue
        code = nam_ll_read(x[1], x[2]) # name, level
        dbg_print("cmd", 5, sprintf("(dump__cmdtab) name='%s', code=%s",
                                    x[1], code))
        if (flag_1true_p(code, TYPE_USER)) {
            # # I don't think there are any system sequences yet...
            # if (!include_sys && flag_1true_p(code, FLAG_SYSTEM))
            #     continue
            keys[++cnt] = x[1]
        }
    }

    qsort(keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf cmd_definition_ppf(keys[i]) TOK_NEWLINE
    dbg_print("cmd", 4, "(dump__cmdtab) END")
    return chomp(buf)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E R R O R
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @debug, @echo, @error, @errprint, @warn TEXT
#
# debug, error and warn "format" the message, adorning it with with
# current file name, line number, etc.  echo and errprint do no
# additional formatting.  @debug only prints its message if debugging is
# enabled.  The user can control this since __DEBUG__ is an unprotected
# symbol.  @debug is purposefully not given access to the various dbg()
# keys and levels.
#
#       | Cmd      | Format? | Exit? | Notes              |
#       |----------+---------+-------+--------------------|
#       | debug    | Format  | No    | Only if __DEBUG __ |
#       | echo     | Raw     | No    | Same as @errprint  |
#       | error    | Format  | Yes   |                    |
#       | errprint | Raw     | No    | Same as @echo      |
#       | secho    | Raw     | No    | No newline         |
#       | warn     | Format  | No    |                    |
function xeq_cmd__error(name, cmdline,
                       m2_will_exit, do_format, do_print, message)
{
    m2_will_exit = (name == "error")
    do_format = (name == "debug" || name == "error" || name == "warn")
    do_print  = (name != "debug" || debugp())
    message = dosubs(cmdline)
    if (do_format)
        message = format_message(message)
    if (do_print)
        if (name == "secho")
            printf "%s", message > "/dev/stderr"
        else
            print_stderr(message) # adds newline
    if (m2_will_exit) {
        __exit_code = EX_USER_REQUEST
        end_program(MODE_STREAMS_DISCARD)
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E V A L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @eval                 [CODE]
function xeq_cmd__eval(name, cmdline)
{
    $1 = ""
    sub("^[ \t]*", "")
    # print_stderr("@eval: '" $0 "'")
    dostring($0)
}


function dostring(str,
                string_block, term2, retval)
{
    dbg_print("parse", 5, "(dostring) START str='" str "'")

    # Set up a SRC_STRING parser for str, and the __terminal
    string_block = blk_new(SRC_STRING)
    blktab[string_block, 0, "str"]    = dosubs(str) # str
    blktab[string_block, 0, "atmode"] = MODE_AT_PROCESS
    dbg_print("parse", 7, sprintf("(dostring) Pushing string block %d onto source_stack", string_block))
    stk_push(__source_stack, string_block)

    stk_push(__parse_stack, __terminal)
    dbg_print("parse", 5, "(dostring) CALLING parse__string()")
    retval = parse__string()
    dbg_print("parse", 5, "(dostring) RETURNED FROM parse__string()")
    stk_pop(__parse_stack) # Pop the terminal parser; parse_string() pops the source stack
    
    dbg_print("parse", 5, "(dostring) END => " ppf__bool(retval))
    return retval
}


function parse__string(    str, string_block1, string_block2, pstat, d)
{
    if (stk_emptyp(__source_stack))
        error("(parse__string) Source stack empty")
    string_block1 = stk_top(__source_stack)
    str = blktab[string_block1, 0, "str"]

    dbg_print("parse", 1, sprintf("(parse__string) str='%s', dstblk=%d, mode=%s",
                                  str, curr_dstblk(),
                                  ppf__mode(blktab[string_block1, 0, "atmode"])))

    blktab[string_block1, 0, "old.buffer"]    = __buffer
    dbg_print_block("ship_out", 7, string_block1, "(parse__string) string_block1")

    # Set up new file context
    __buffer = str

    # Read the file and process each line
    dbg_print("parse", 5, "(parse__string) CALLING parse()")
    pstat = parse()
    dbg_print("parse", 5, "(parse__string) RETURNED FROM parse() => " ppf__bool(pstat))

    string_block2 = stk_pop(__source_stack)
    if (string_block1 != string_block2)
        error("(parse__string) String block mismatch")
    __buffer = blktab[string_block2, 0, "old.buffer"]

    dbg_print("parse", 1, sprintf("(parse__string) END '%s' => %s",
                                 str, ppf__bool(pstat)))
    return pstat
}


function ppf__SRC_STRING(blknum)
{
    return sprintf("  str     : %s\n"             \
                   "  atmode  : %s",
                   blktab[blknum, 0, "str"],
                   ppf__mode(blktab[blknum, 0, "atmode"]))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E X I T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @exit                 [CODE]
function xeq_cmd__exit(name, cmdline)
{
    __exit_code = (!emptyp(cmdline) && integerp(cmdline)) ? cmdline+0 : EX_OK

    # For full portability, exit values should be between 0 and 126, inclusive.
    # Negative values, and values of 127 or greater, may not produce
    # consistent results across different operating systems.
    if (__exit_code < 0 || __exit_code > 126)
        __exit_code = 1
    end_program(__exit_code == 0 ? MODE_STREAMS_SHIP_OUT \
                                 : MODE_STREAMS_DISCARD)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  F O R
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @for     VAR START END [INCR]
# @foreach VAR ARRAY
function parse__for(                  for_block, body_block, pstat, incr, info, nparts, level)
{
    dbg_print("for", 5, sprintf("(parse__for) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))
    if (NF < 3)
        error("(parse__for) Bad parameters")

    raise_namespace()

    # Create two new blocks: "for_block" for loop control (for_block),
    # and "body_block" for the loop code definition.
    for_block = blk_new(BLK_FOR)
    dbg_print("for", 5, "(parse__for) for_block # " for_block " type " ppf__block_type(blk_type(for_block)))
    body_block = blk_new(BLK_AGG)
    dbg_print("for", 5, "(parse__for) body_block # " body_block " type " ppf__block_type(blk_type(body_block)))

    blktab[for_block, 0, "body_block"] = body_block
    blktab[for_block, 0, "dstblk"] = body_block
    blktab[for_block, 0, "valid"] = FALSE
    blktab[for_block, 0, "loop_var"] = $2

    if ($1 == "@for") {
        #print_stderr("(parse__for) Found FOR: " $0)
        blktab[for_block, 0, "loop_type"] = "iter"
        blktab[for_block, 0, "loop_start"] = $3 + 0
        blktab[for_block, 0, "loop_end"] = $4 + 0
        blktab[for_block, 0, "loop_incr"] = incr = NF >= 5 ? ($5 + 0) : 1
        if (incr == 0)
            error("(parse__for) Increment value cannot be zero!")

    } else if ($1 == "@foreach") {
        #print_stderr("(parse__for) Found FOREACH: " $0)
        if ((nparts = nam__scan($3, info)) != 1)
            error("[@for] Scan error, " __m2_msg)
        level = nam_lookup(info)
        if (level == ERROR)
            error(sprintf("(parse__for) Name '%s' not found", info["name"]))
        if (! info["isarray"])
            error(sprintf("(parse__for) Name '%s' is not an array", info["name"]))
        blktab[for_block, 0, "loop_type"] = "each"
        blktab[for_block, 0, "loop_array_name"] = $3
        blktab[for_block, 0, "level"] = level

    } else
        error("(parse__for) How did I get here?")

    dbg_print_block("for", 7, for_block, "(parse__for) for_block")
    stk_push(__parse_stack, for_block) # Push it on to the parse_stack

    dbg_print("for", 5, "(parse__for) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @next
    dbg_print("for", 5, "(parse__for) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@for] Parse error")

    dbg_print("for", 5, "(parse__for) END => " for_block)
    return for_block
}


# @next VAR                       # end normal FOR loop
function parse__next(                   for_block)
{
    dbg_print("for", 3, sprintf("(parse__next) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))
    if (check__parse_stack(BLK_FOR) != 0)
        error("[@next] Parse error; " __m2_msg)
    for_block = stk_pop(__parse_stack)

    if (blktab[for_block, 0, "loop_var"] != $2)
        error(sprintf("(parse__next) Variable mismatch; '%s' specified, but '%s' was expected",
                      $2, blktab[for_block, 0, "loop_var"]))
    blktab[for_block, 0, "valid"] = TRUE

    lower_namespace()

    dbg_print("for", 3, sprintf("(parse__next) END => %d", for_block))
    return for_block
}


function xeq__BLK_FOR(for_block,
                      block_type)
{
    block_type = blk_type(for_block)
    dbg_print("for", 3, sprintf("(xeq__BLK_FOR) START dstblk=%d, for_block=%d, type=%s",
                                curr_dstblk(), for_block, ppf__block_type(block_type)))
    dbg_print_block("for", 7, for_block, "(xeq__BLK_FOR) for_block")
    if ((block_type != BLK_FOR) || \
        (blktab[for_block, 0, "valid"] != TRUE))
        error("(xeq__BLK_FOR) Bad config")

    if (blktab[for_block, 0, "loop_type"] == "each")
        execute__foreach(for_block)
    else
        execute__for(for_block)
}


function execute__for(for_block,
                      loopvar, start, end, incr, done, counter, body_block, new_level)
{
    # Evaluate loop
    loopvar    = blktab[for_block, 0, "loop_var"]
    start      = blktab[for_block, 0, "loop_start"] + 0
    end        = blktab[for_block, 0, "loop_end"]   + 0
    incr       = blktab[for_block, 0, "loop_incr"]  + 0
    done       = FALSE
    counter    = start
    body_block = blktab[for_block, 0, "body_block"]

    dbg_print_block("for", 7, for_block, "(execute__for) for_block")
    dbg_print_block("for", 7, body_block, "(execute__for) body_block")
    dbg_print("for", 4, sprintf("(execute__for) loopvar='%s', start=%d, end=%d, incr=%d",
                                 loopvar, start, end, incr))

    if (start > end && incr > 0)
        error("(execute__for) Start cannot be greater than End")
    if (start < end && incr < 0)
        error("(execute__for) Start cannot be less than End")
        
    while (!done) {
        new_level = raise_namespace()
        nam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY)
        sym_ll_write(loopvar, "", new_level, counter)
        dbg_print("for", 5, sprintf("(execute__for) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg_print("for", 5, sprintf("(execute__for) RETURNED FROM execute__block()"))
        lower_namespace()
        done = (incr > 0) ? (counter +=     incr ) > end \
                          : (counter -= abs(incr)) < end

        # Check for break or continue
        if (__xeq_ctl == XEQ_BREAK) {
            __xeq_ctl = XEQ_NORMAL
            break
        }
        if (__xeq_ctl == XEQ_CONTINUE) {
            __xeq_ctl = XEQ_NORMAL
            # Actual "continue" wouldn't do anything here since we're
            # about to re-iterate the loop anyway
        }
    }
    dbg_print("for", 1, "(execute__for) END")
}


function execute__foreach(for_block,
                          loopvar, arrname, level, keys, x, k, body_block, new_level)
{
    loopvar = blktab[for_block, 0, "loop_var"]
    arrname = blktab[for_block, 0, "loop_array_name"]
    level = blktab[for_block, 0, "level"]
    body_block = blktab[for_block, 0, "body_block"]
    dbg_print("for", 4, sprintf("(execute__foreach) loopvar='%s', arrname='%s'",
                                loopvar, arrname))
    # Find the keys
    for (k in symtab) {
        split(k, x, SUBSEP)
        if (x[1] == arrname && x[3] == level && x[4] == "symval")
            keys[x[2]] = 1
    }

    # Run the loop
    for (k in keys) {
        new_level = raise_namespace()
        nam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_READONLY)
        sym_ll_write(loopvar, "", new_level, k)
        dbg_print("for", 5, sprintf("(execute__foreach) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg_print("for", 5, sprintf("(execute__foreach) RETURNED FROM execute__block()"))
        lower_namespace()

        # Check for break or continue
        if (__xeq_ctl == XEQ_BREAK) {
            __xeq_ctl = XEQ_NORMAL
            break
        }
        if (__xeq_ctl == XEQ_CONTINUE) {
            __xeq_ctl = XEQ_NORMAL
            # Actual "continue" wouldn't do anything here since we're
            # about to re-iterate the loop anyway
        }
    }
    dbg_print("for", 1, "(execute__foreach) END")
}


function ppf__for(for_block,
                  buf)
{
    if (blktab[for_block, 0, "loop_type"] == "each")
        buf = "@foreach " blktab[for_block, 0, "loop_var"] TOK_SPACE blktab[for_block, 0, "loop_array_name"] TOK_NEWLINE
    else
        buf = "@for " blktab[for_block, 0, "loop_var"] TOK_SPACE blktab[for_block, 0, "loop_start"] TOK_SPACE blktab[for_block, 0, "loop_end"] TOK_SPACE blktab[for_block, 0, "loop_incr"] TOK_NEWLINE
    buf = buf ppf__block(blktab[for_block, 0, "body_block"]) TOK_NEWLINE
    buf = buf "@next "  blktab[for_block, 0, "loop_var"]
    return buf
}


function ppf__BLK_FOR(blknum)
{
    return sprintf("  valid   : %s\n" \
                   "  loopvar : %s\n"       \
                   "  start   : %d\n"       \
                   "  end     : %d\n"       \
                   "  incr    : %d\n"       \
                   "  body    : %d",
                   ppf__bool(blktab[blknum, 0, "valid"]),
                   blktab[blknum, 0, "loop_var"],
                   blktab[blknum, 0, "loop_start"],
                   blktab[blknum, 0, "loop_end"],
                   blktab[blknum, 0, "loop_incr"],
                   blktab[blknum, 0, "body_block"])
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I F
#   
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @if CONDITION
function parse__if(                 name, if_block, true_block, pstat)
{
    dbg_print("if", 3, sprintf("(parse__if) START dstblk=%d, $0='%s'", curr_dstblk(), $0))
    name = $1
    $1 = ""
    sub("^[ \t]*", "")

    raise_namespace()

    # Create two new blocks: one for if_block, other for true branch
    if_block = blk_new(BLK_IF)
    dbg_print("if", 5, "(parse__if) New block # " if_block " type " ppf__block_type(blk_type(if_block)))
    true_block = blk_new(BLK_AGG)
    dbg_print("if", 5, "(parse__if) New block # " true_block " type " ppf__block_type(blk_type(true_block)))

    blktab[if_block, 0, "condition"]   = $0
    blktab[if_block, 0, "init_negate"] = (name == "@unless")
    blktab[if_block, 0, "seen_else"]   = FALSE
    blktab[if_block, 0, "true_block"]  = true_block
    blktab[if_block, 0, "dstblk"]      = true_block
    blktab[if_block, 0, "valid"]       = FALSE
    dbg_print_block("if", 7, if_block, "(parse__if) if_block")
    stk_push(__parse_stack, if_block) # Push it on to the parse_stack

    dbg_print("if", 5, "(parse__if) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endif
    dbg_print("if", 5, "(parse__if) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@if] Parse error")

    dbg_print("if", 5, "(parse__if) END; => " if_block)
    return if_block
}


# @else
function parse__else(                   if_block, false_block)
{
    dbg_print("if", 3, sprintf("(parse__else) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_IF) != 0)
        error("[@else] Parse error; " __m2_msg)
    if_block = stk_top(__parse_stack)

    # Check if already seen @else
    if (blktab[if_block, 0, "seen_else"] == TRUE)
        error("(parse__else) Cannot have more than one @else")

    lower_namespace()           # trigger name/symbol purge
    raise_namespace()

    # Create a new block for the False branch and make it current
    blktab[if_block, 0, "seen_else"] = TRUE
    false_block = blk_new(BLK_AGG)
    blktab[if_block, 0, "false_block"] = false_block
    blktab[if_block, 0, "dstblk"]  = false_block
    return false_block
}


# @endif
function parse__endif(                    if_block)
{
    dbg_print("if", 3, sprintf("(parse__endif) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_IF) != 0)
        error("[@endif] Parse error; " __m2_msg)

    if_block = stk_pop(__parse_stack)
    blktab[if_block, 0, "valid"] = TRUE
    lower_namespace()
    return if_block
}


function xeq__BLK_IF(if_block,
                     block_type, condition, condval, negate)
{
    block_type = blk_type(if_block)
    dbg_print("if", 3, sprintf("(xeq__BLK_IF) START dstblk=%d, if_block=%d, type=%s",
                               curr_dstblk(), if_block, ppf__block_type(block_type)))

    dbg_print_block("if", 7, if_block, "(xeq__BLK_IF) if_block")
    if ((block_type != BLK_IF) || \
        (blktab[if_block, 0, "valid"] != TRUE))
        error("(xeq__BLK_IF) Bad config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    condition = blktab[if_block, 0, "condition"]
    negate = blktab[if_block, 0, "init_negate"]
    condval = evaluate_boolean(condition, negate)
    dbg_print("if", 1, sprintf("(xeq__BLK_IF) evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
    if (condval == ERROR)
        error("@if: Error evaluating condition '" condition "'")

    raise_namespace()
    if (condval) {
        dbg_print("if", 5, sprintf("(xeq__BLK_IF) [true branch] CALLING execute__block(%d)",
                                   blktab[if_block, 0, "true_block"]))
        execute__block(blktab[if_block, 0, "true_block"])
        dbg_print("if", 5, sprintf("(xeq__BLK_IF) RETURNED FROM execute__block()"))
    } else if (blktab[if_block, 0, "seen_else"] == TRUE) {
        dbg_print("if", 5, sprintf("(xeq__BLK_IF) [false branch] CALLING execute__block(%d)",
                                   blktab[if_block, 0, "false_block"]))
        execute__block(blktab[if_block, 0, "false_block"])
        dbg_print("if", 5, sprintf("(xeq__BLK_IF) RETURNED FROM execute__block()"))
    }
    lower_namespace()

    dbg_print("if", 3, sprintf("(xeq__BLK_IF) END"))
}


function ppf__if(if_block,
    buf)
{
    buf = "@if " blktab[if_block, 0, "condition"] TOK_NEWLINE \
        ppf__block(blktab[if_block, 0, "true_block"]) TOK_NEWLINE
    if (blktab[if_block, 0, "seen_else"])
        buf = buf "@else\n" \
            ppf__block(blktab[if_block, 0, "false_block"]) TOK_NEWLINE
    return buf "@endif" 
}


# Returns TRUE, FALSE, or ERROR
#           @if NAME
#           @if SOMETHING <OP> TEXT
#           @if KEY in ARR
function evaluate_condition(cond, negate,
                            retval, name, sp, op, expr,
                            nparts, arr, key, info, level, lhs, rhs, lval, rval)
{
    dbg_print("if", 7, sprintf("(evaluate_condition) START cond='%s'", cond))
    if (cond == EMPTY) {
        error("@if: Condition cannot be empty")
        return ERROR
    }

    retval = ERROR
    if (first(cond) == "!") {
        negate = !negate
        cond = ltrim(rest(cond))
    }

    cond = dosubs(cond)
    dbg_print("if", 4, sprintf("(evaluate_condition) After dosubs, negate=%s, cond='%s'",
                               ppf__bool(negate), cond))

    if (cond ~ /^[0-9]+$/) {
        dbg_print("if", 6, sprintf("(evaluate_condition) Found simple integer '%s'", cond))
        retval = (cond+0) != 0

    } else if (cond ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
        dbg_print("if", 6, sprintf("(evaluate_condition) Found simple name '%s'", cond))
        assert_sym_valid_name(cond)
        retval = sym_true_p(cond)

    } else if (match(cond, ".* (in|IN) .*")) { # poor regexp, fragile
        # This whole section is pretty easy to confound....
        dbg_print("if", 5, sprintf("(evaluate_condition) Found IN expression"))
        # Find name
        sp = index(cond, TOK_SPACE)
        key = substr(cond, 1, sp-1)
        cond = substr(cond, sp+1)
        # Find the condition
        match(cond, " *(in|IN) *")
        arr = substr(cond, RSTART+3)
        dbg_print("if", 5, sprintf("key='%s', op='%s', arr='%s'", key, "IN", arr))

        if (nam__scan(arr, info) == ERROR)
            error("Scan error, " __m2_msg)
        level = nam_lookup(info)
        if (level == ERROR)
            error("Name '" arr "' lookup failed")
        if (info["isarray"] == FALSE)
            error(sprintf("'%s' is not an array", arr))
        
        retval = sym_ll_in(arr, key, info["level"])

    } else if (match(cond, "[^ ]+ *(<|<=|=|==|!=|>=|>) *[^ ]+")) { # poor regexp, fragile
        # This whole section is pretty easy to confound....
        dbg_print("if", 6, sprintf("(evaluate_condition) Found comparison"))
        # Find name
        sp = index(cond, TOK_SPACE)
        lhs = substr(cond, 1, sp-1)
        cond = substr(cond, sp+1)
        # Find the condition
        match(cond, "[<>=!]*")
        op = substr(cond, RSTART, RLENGTH)
        rhs = substr(cond, RLENGTH+2)

        if (sym_valid_p(lhs) && sym_defined_p(lhs))
            lval = sym_fetch(lhs)
        else if (seq_defined_p(lhs))
            lval = seq_ll_read(lhs)
        else
            lval = lhs

        if (sym_valid_p(rhs) && sym_defined_p(rhs))
            rval = sym_fetch(rhs)
        else if (seq_defined_p(rhs))
            rval = seq_ll_read(rhs)
        else
            rval = rhs

        dbg_print("if", 6, sprintf("(evaluate_condition) lhs='%s'[%s], op='%s', rhs='%s'[%s]", lhs, lval, op, rhs, rval))

        # If both sides look like numbers, compare them numerically;
        # otherwise do normal (string-based) comparison.
        if (floatp(lval) && floatp(rval)) {
            if      (op == "<")                retval = lval+0 <  rval+0
            else if (op == "<=")               retval = lval+0 <= rval+0
            else if (op == "==")               retval = lval+0 == rval+0
            else if (op == "!=" || op == "<>") retval = lval+0 != rval+0
            else if (op == ">=")               retval = lval+0 >= rval+0
            else if (op == ">")                retval = lval+0 >  rval+0
            else
                error("Comparison operator '" op "' invalid")
        } else {
            if      (op == "<")                retval = lval <  rval
            else if (op == "<=")               retval = lval <= rval
            else if (op == "==")               retval = lval == rval
            else if (op == "!=" || op == "<>") retval = lval != rval
            else if (op == ">=")               retval = lval >= rval
            else if (op == ">")                retval = lval >  rval
            else
                error("Comparison operator '" op "' invalid")
        }
    }

    if (negate && retval != ERROR)
        retval = !retval
    dbg_print("if", 3, sprintf("(evaluate_condition) END retval=%s", (retval == ERROR) ? "ERROR" \
                                                                   : ppf__bool(retval)))
    return retval
}


function ppf__BLK_IF(blknum)
{
    return sprintf("  valid       : %s\n" \
                   "  condition   : '%s'\n" \
                   "  true_block  : %d\n" \
                   "  seen_else   : %s\n" \
                   "  false_block : %s",
                   ppf__bool(blktab[blknum, 0, "valid"]),
                   blktab[blknum, 0, "condition"],
                   blktab[blknum, 0, "true_block"],
                   ppf__bool(blktab[blknum, 0, "seen_else"]),
                   ((blknum, 0, "false_block") in blktab) \
                   ? blktab[blknum, 0, "false_block"]      \
                     : "<no false block>")

}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I G N O R E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @ignore    DELIM
function xeq_cmd__ignore(name, cmdline,
                         rstat)
{
    dbg_print("parse", 5, sprintf("(xeq_cmd__ignore) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)

    dbg_print("parse", 5, "(xeq_cmd__ignore) CALLING read_lines_until()")
    rstat = read_lines_until(cmdline, DISCARD)
    dbg_print("parse", 5, "(xeq_cmd__ignore) RETURNED FROM read_lines_until() => " ppf__bool(rstat))
    if (!rstat)
        error("[@ignore] Read error")
    dbg_print("parse", 5, "(xeq_cmd__ignore) END")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I N C L U D E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @{s,}{include,paste}  FILE
function xeq_cmd__include(name, cmdline,
                          error_text, filename, silent, file_block, rc)
{
    dbg_print("parse", 5, sprintf("(xeq_cmd__include) name='%s', cmdline='%s'",
                                 name, cmdline))
    if (cmdline == EMPTY)
        error("Bad parameters:" $0)
    # paste does not process macros
    silent = (first(name) == "s") # silent mutes file errors, even in strict mode

    filename = search_file(cmdline)
    if (emptyp(filename)) {
        if (silent) return
        error_text = "File '" cmdline "' does not exist:" $0
        if (strictp("file"))
            error(error_text)
        else
            warn(error_text)
    }
    file_block = prep_file(filename)
    blktab[file_block, 0, "atmode"] = substr(name, length(name)-4) == "paste" \
                                      ? MODE_AT_LITERAL : MODE_AT_PROCESS
    # prep_file doesn't push the SRC_FILE onto the __source_stack,
    # so we have to do that ourselves due to customization
    dbg_print("parse", 7, sprintf("(xeq_cmd__include) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)

    dbg_print("parse", 5, "(xeq_cmd__include) CALLING parse__file()")
    rc = parse__file()
    dbg_print("parse", 5, "(xeq_cmd__include) RETURNED FROM parse__file()")
    if (!rc) {
        if (silent) return
        error_text = "File '" filename "' does not exist:" $0
        if (strictp("file"))
            error(error_text)
        else
            warn(error_text)
    }
}


function search_file(f,
                     count, ip, p, i)
{
    f = rm_quotes(dosubs(f))
    count = split(__inc_path, ip, TOK_COLON)
    ip[0] = "."
    for (i = 0; i <= count; i++) {
        p = with_trailing_slash(ip[i]) f
        if (path_exists_p(p))
            return p
    }
    return EMPTY
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I N C R
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @decr, @incr          NAME [N]
function xeq_cmd__incr(name, cmdline,
                       sym, incr)
{
    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)
    sym = $1
    assert_sym_okay_to_define(sym)
    assert_sym_defined(sym, "incr")
    if (NF >= 2 && ! integerp($2))
        error("Value '" $2 "' must be numeric:" $0)
    incr = (NF >= 2) ? $2 : 1
    sym_increment(sym, (name == "incr") ? incr : -incr)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I N P U T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @input                [NAME]
#
# Read a single line from /dev/tty.  No prompt is issued; if you
# want one, use @echo.  Specify the symbol you want to receive the
# data.  If no symbol is specified, __INPUT__ is used by default.
function xeq_cmd__input(name, cmdline,
                        sym, getstat, input)
{
    $0 = cmdline
    sym = (NF == 0) ? "__INPUT__" : $1
    assert_sym_okay_to_define(sym)

    input = EMPTY
    getstat = getline input < "/dev/tty"
    if (getstat == ERROR)
        warn("Error reading file '/dev/tty' [input]:" $0)
    sym_store(sym, input)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  L O C A L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @local                NAME
# @local FOO adds to namtab (as a scalar) in the current namespace, does not define it
function xeq_cmd__local(name, cmdline,
                        sym)
{
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    if (__namespace == GLOBAL_NAMESPACE)
        error("Cannot use @local in global namespace")
    sym = $1
    # check for valid name
    if (!nam_valid_with_strict_as(sym, strictp("symbol")))
        error("@local: Invalid name '" sym "'")
    assert_sym_okay_to_define(sym)
    if (nam_ll_in(sym, __namespace))
        error("Symbol '" sym "' already defined")
    nam_ll_write(sym, __namespace, TYPE_SYMBOL)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  L O N G D E F
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @longdef              NAME
function parse__longdef(    sym, sym_block, body_block, pstat)
{
    dbg_print("sym", 5, "(parse__longdef) START dstblk=" curr_dstblk() ", mode=" ppf__mode(curr_atmode()) "; $0='" $0 "'")

    # Create two new blocks: one for the "longdef" block, other for definition body
    sym_block = blk_new(BLK_LONGDEF)
    dbg_print("sym", 5, "(parse__longdef) New block # " sym_block " type " ppf__block_type(blk_type(sym_block)))
    body_block = blk_new(BLK_AGG)
    dbg_print("sym", 5, "(parse__longdef) New block # " body_block " type " ppf__block_type(blk_type(body_block)))

    $1 = ""
    sym = $2
    assert_sym_okay_to_define(sym)
    blktab[sym_block, 0, "name"] = sym
    blktab[sym_block, 0, "body_block"] = body_block
    blktab[sym_block, 0, "dstblk"] = body_block
    blktab[sym_block, 0, "valid"] = FALSE
    dbg_print_block("sym", 7, sym_block, "(parse__longdef) sym_block")
    stk_push(__parse_stack, sym_block) # Push it on to the parse_stack

    dbg_print("sym", 5, "(parse__longdef) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcmd
    dbg_print("sym", 5, "(parse__longdef) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@longdef] Parse error")

    dbg_print("sym", 5, "(parse__longdef) END => " sym_block)
    return sym_block
}


function parse__endlongdef(    sym_block)
{
    dbg_print("sym", 3, sprintf("(parse__endlongdef) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_LONGDEF) != 0)
        error("[@endlongdef] Parse error; " __m2_msg)
    sym_block = stk_pop(__parse_stack)

    blktab[sym_block, 0, "valid"] = TRUE
    dbg_print("sym", 3, sprintf("(parse__endlongdef) END => %d", sym_block))
    return sym_block
}


function xeq__BLK_LONGDEF(longdef_block,
                          block_type, name, body_block, opm)
{
    block_type = blk_type(longdef_block)
    dbg_print("sym", 3, sprintf("(xeq__BLK_LONGDEF) START dstblk=%d, longdef_block=%d, type=%s",
                                 curr_dstblk(), longdef_block, ppf__block_type(block_type)))
    dbg_print_block("sym", 7, longdef_block, "(xeq__BLK_LONGDEF) longdef_block")
    if ((block_type != BLK_LONGDEF) ||
        (blktab[longdef_block, 0, "valid"] != TRUE))
        error("(xeq__BLK_LONGDEF) Bad config")

    name = blktab[longdef_block, 0, "name"]
    assert_sym_okay_to_define(name)

    body_block = blktab[longdef_block, 0, "body_block"]
    dbg_print_block("sym", 3, body_block, "(xeq__BLK_LONGDEF) body_block")
    sym_store(name, blk_to_string(body_block))
    dbg_print("sym", 1, "(xeq__BLK_LONGDEF) END")
}


function ppf__longdef(longdef_block,
                      buf)
{
    return "@longdef " blktab[longdef_block, 0, "name"] TOK_NEWLINE      \
            ppf__block(blktab[longdef_block, 0, "body_block"]) TOK_NEWLINE \
            "@endlong"
}


function ppf__BLK_LONGDEF(longdef_block)
{
    return sprintf("  symbol      : '%s'\n" \
                   "  valid       : %s\n" \
                   "  body_block  : %d",
                   blktab[longdef_block, 0, "name"],
                   ppf__bool(blktab[longdef_block, 0, "valid"]),
                   blktab[longdef_block, 0, "body_block"])
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  M 2 C T L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       @m2ctl booltest                 Scan boolean expr from user
#       @m2ctl clear_debugging          Clear debugging
#       @m2ctl dbg_namespace            Debug namespaces
#       @m2ctl dbg_ship_out
#       @m2ctl dump_block BLOCK         Raw dump block #
#       @m2ctl dump_parse_stack         Dump parse stack
#       @m2ctl set_dbg DSYS LEVEL       Set debug level directly
#
#*****************************************************************************

# Undocumented - Reserved for internal use
# @m2ctl                ARGS
function xeq_cmd__m2ctl(name, cmdline,
                        getstat, input, e, dsys, lev, blk)
{
    $0 = cmdline
    dbg_print("xeq", 1, sprintf("(xeq_cmd__m2ctl) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    if (NF == 0)
        error("Bad parameters:" $0)

    if ($1 == "booltest") { # Interactively evaluate boolean expressions
        do {
            print_stderr("Enter line to scan as boolean expr (RETURN to end):")
            getstat = getline input < "/dev/tty"
            #print("just read '" input "'")
            if (input == EMPTY) {
                print_stderr("Exiting boolean expr; returning to regular commands!")
                break
            }

            bool__tokenize_string(input)
            __bf = 1
            e = bool__scan_expr(input)
            if (e == ERROR)
                warn(sprintf("(xeq_cmd__m2ctl) bool__scan_expr('%s') returned ERROR - should exit?", input))
            else
                print_stderr(sprintf("(xeq_cmd__m2ctl) __bf=%d,__bnf=%d; FINAL ANSWER: %d == %s", __bf, __bnf, e, ppf__bool(e)))
        } while (TRUE)

    } else if ($1 == "clear_debugging") {
        clear_debugging()

    } else if ($1 == "dbg_namespace") {
        # Debug namespaces
        dbg_set_level("for",       5)
        dbg_set_level("namespace", 5)
        dbg_set_level("cmd",       5)
        dbg_set_level("nam",       3)
        dbg_set_level("sym",       5)

    } else if ($1 == "dbg_ship_out") {
        clear_debugging()
        dbg_set_level("ship_out",   3)

    } else if ($1 == "dump_block") {
        blk = $2 + 0
        blk_dump_block_raw(blk)

    } else if ($1 == "dump_parse_stack") {
        dump_parse_stack()

    } else if ($1 == "incpath") {
        print_stderr("__inc_path = " __inc_path)

    } else if ($1 == "set_dbg") { # Set __DBG__[dsys] level directly
        dsys = $2                 # Note, does not affect __DEBUG__
        lev = $3
        print_stderr(sprintf("Setting __DBG__[%s] to %d", dsys, lev))
        dbg_set_level(dsys, lev)

    } else
        error("Unrecognized parameter " $1) 
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  N E W C M D
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function parse__newcmd(                     name, newcmd_block, body_block, pstat, nparam, p, pname)
{
    nparam = 0
    dbg_print("cmd", 5, "(parse__newcmd) START dstblk=" curr_dstblk() ", mode=" ppf__mode(curr_atmode()) "; $0='" $0 "'")

    raise_namespace()

    # Create two new blocks: one for the "new command" block, other for command body
    newcmd_block = blk_new(BLK_USER)
    dbg_print("cmd", 5, "(parse__newcmd) New block # " newcmd_block " type " ppf__block_type(blk_type(newcmd_block)))
    body_block = blk_new(BLK_AGG)
    dbg_print("cmd", 5, "(parse__newcmd) New block # " body_block " type " ppf__block_type(blk_type(body_block)))

    $1 = ""
    name = $2
    while (match(name, "{[^}]*}")) {
        p = ++nparam
        pname = substr(name, RSTART+1, RLENGTH-2)
        dbg_print("cmd", 5, sprintf("(parse__newcmd) Parameter %d : %s",
                                     p, pname))
        blktab[newcmd_block, p, "param_name"] = pname
        name = substr(name, 1, RSTART-1) substr(name, RSTART+RLENGTH)
    }
    assert_cmd_okay_to_define(name)

    blktab[newcmd_block, 0, "name"] = name
    blktab[newcmd_block, 0, "body_block"] = body_block
    blktab[newcmd_block, 0, "dstblk"] = body_block
    blktab[newcmd_block, 0, "valid"] = FALSE
    blktab[newcmd_block, 0, "nparam"] = nparam
    dbg_print_block("cmd", 7, newcmd_block, "(parse__newcmd) newcmd_block")
    stk_push(__parse_stack, newcmd_block) # Push it on to the parse_stack

    dbg_print("cmd", 5, "(parse__newcmd) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcmd
    dbg_print("cmd", 5, "(parse__newcmd) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@newcmd] Parse error")

    dbg_print("cmd", 5, "(parse__newcmd) END => " newcmd_block)
    return newcmd_block
}


function parse__endcmd(                     newcmd_block)
{
    dbg_print("cmd", 3, sprintf("(parse__endcmd) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_USER) != 0)
        error("[@endcmd] Parse error; " __m2_msg)
    newcmd_block = stk_pop(__parse_stack)

    blktab[newcmd_block, 0, "valid"] = TRUE
    lower_namespace()

    dbg_print("cmd", 3, sprintf("(parse__endcmd) END => %d", newcmd_block))
    dbg_print_block("parse", 7, newcmd_block, sprintf("newcmd block:"))
    return newcmd_block
}


function xeq__BLK_USER(newcmd_block,
                       block_type, name)
{
    block_type = blk_type(newcmd_block)
    dbg_print("cmd", 3, sprintf("(xeq__BLK_USER) START dstblk=%d, newcmd_block=%d, type=%s",
                                 curr_dstblk(), newcmd_block, ppf__block_type(block_type)))
    dbg_print_block("cmd", 7, newcmd_block, "(xeq__BLK_USER) newcmd_block")
    if ((block_type != BLK_USER) ||
        (blktab[newcmd_block, 0, "valid"] != TRUE))
        error("(xeq__BLK_USER) Bad config")

    # Instantiate command, but do not run.  "@newcmd FOO" is just declaring FOO.
    # @FOO{...} actually ships it out (and is done under ship_out/xeq_user).
    name = blktab[newcmd_block, 0, "name"]
    dbg_print("cmd", 3, sprintf("(xeq__BLK_USER) name='%s', level=%d: TYPE_USER, value=%d",
                                 name, __namespace, newcmd_block))
    nam_ll_write(name, __namespace, TYPE_USER)
    cmd_ll_write(name, __namespace, newcmd_block)

    dbg_print("cmd", 1, "(xeq__BLK_USER) END")
}


function execute__user(name, cmdline,
                       level, info, code,
                       old_level,
                       user_block,
                       args, arg, narg, argval)
{
    dbg_print("xeq", 3, sprintf("(execute__user) START name='%s', cmdline='%s'",
                                name, cmdline))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg_print("xeq", 3, "(execute__user) NOP due to __xeq_ctl=" __xeq_ctl)
        return
    }

    old_level = __namespace

    if (nam__scan(name, info) == ERROR)
        #error("(execute__user) Scan error on '" name "' -- should not happen")
        error("Scan error, " __m2_msg)
    if ((level = nam_lookup(info)) == ERROR)
        error("(execute__user) nam_lookup failed -- should not happen")

    # See if it's a user command
    if (flag_1false_p((code = nam_ll_read(name, level)), TYPE_USER))
        error("(execute__user) " name " seems to no longer be a command")

    user_block = cmd_ll_read(name, level)

    dbg_print_block("xeq", 7, user_block, "(execute__user) user_block")
    dbg_print_block("xeq", 7, blktab[user_block, 0, "body_block"], "(execute__user) body_block")

    # Check for cmd arguments
    narg = 0
    while (match(cmdline, "{[^}]*}")) {
        arg = ++narg
        argval = substr(cmdline, RSTART+1, RLENGTH-2)
        dbg_print("parse", 5, sprintf("[@%s] Scan arg %d : %s",
                                      name, arg, argval))
        #print_stderr("args[" arg "] = " argval)
        args[arg] = argval
        cmdline = substr(cmdline, 1, RSTART-1) substr(cmdline, RSTART+RLENGTH)
    }

    execute__user_body(user_block, args)

    if (__namespace != old_level)
        error("(execute__user) @%s %s: Namespace level mismatch")
}


function execute__user_body(user_block, args,
                       block_type, new_level, i, p, body_block)
{
    block_type = blk_type(user_block)
    dbg_print("cmd", 3, sprintf("(execute__user_body) START dstblk=%d, user_block=%d, type=%s",
                                 curr_dstblk(), user_block, ppf__block_type(block_type)))
    dbg_print_block("cmd", 7, user_block, "(execute__user_body) user_block")
    if ((block_type != BLK_USER) ||
        (blktab[user_block, 0, "valid"] != TRUE))
        error("(execute__user_body) Bad config")

    # Always raise namespace level, even if nparam == 0
    # because user-mode might run @local
    new_level = raise_namespace()
    body_block = blktab[user_block, 0, "body_block"]
    dbg_print_block("cmd", 7, body_block, "(execute__user_body) body_block")

    # Instantiate parameters
    for (i = 1; i <= blktab[user_block, 0, "nparam"]; i++) {
        p = blktab[user_block, i, "param_name"]
        nam_ll_write(p, new_level, TYPE_SYMBOL)
        sym_ll_write(p, "", new_level, args[i])
        dbg_print("cmd", 6, sprintf("(execute__user_body) Setting param %s to '%s'", p, args[i]))
    }

    dbg_print("cmd", 5, sprintf("(execute__user_body) CALLING execute__block(%d)", body_block))
    execute__block(body_block)
    dbg_print("cmd", 5, sprintf("(execute__user_body) RETURNED FROM execute__block()"))
    lower_namespace()

    # If we've been asked to return, well now we have
    if (__xeq_ctl == XEQ_RETURN)
        __xeq_ctl = XEQ_NORMAL
    # If things are still not normal, that's a problem
    if (__xeq_ctl != XEQ_NORMAL)
        error("(xeq_cmd__return) __xeq_ctl is not normal, how did that happen?")

    dbg_print("cmd", 1, "(execute__user_body) END")
}


function ppf__BLK_USER(blknum,
                       param_desc, nparam, x)
{
    param_desc = ""
    nparam = blktab[blknum, 0, "nparam"]
    if (nparam > 0 ) {
        param_desc = "  Parameters:\n"
        for (x = 1; x <= nparam; x++)
            param_desc = param_desc sprintf("  [%d]=%s\n",
                                            x, blktab[blknum, x, "param_name"])
    }
    return sprintf("  name       : %s\n" \
                   "  valid      : %s\n" \
                   "  nparam     : %d\n" \
                   "  body_block : %d\n" \
                   "%s",
                   blktab[blknum, 0, "name"],
                   ppf__bool(blktab[blknum, 0, "valid"]),
                   nparam,
                   blktab[blknum, 0, "body_block"],
                   chomp(param_desc))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  N E X T F I L E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @nextfile
function xeq_cmd__nextfile(name, cmdline,
                           rstat)
{
    dbg_print("parse", 5, sprintf("(xeq_cmd__nextfile) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

    dbg_print("parse", 5, "(xeq_cmd__nextfile) CALLING read_lines_until()")
    rstat = read_lines_until("", DISCARD)
    dbg_print("parse", 5, "(xeq_cmd__nextfile) RETURNED FROM read_lines_until() => " ppf__bool(rstat))
    if (!rstat)
        error("[@nextfile] Read error")
    dbg_print("parse", 5, "(xeq_cmd__nextfile) END")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  R E A D A R R A Y
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @{s,}readarray        ARR FILE
# ARR must be known to be an array (regular or block).
# Any existing array entries are deleted before reading file contents.
# Yes, this implies that user code must say
#     @array A
#     @readarray A myfile
# The first is the declaration that creates an entry in the name table.
# The second command performs the block creation and file reading.
function xeq_cmd__readarray(name, cmdline,
                            arr, filename, line, getstat, line_cnt, silent, level,
                            nparts, info, code, key,
                            file_block, agg_block, rc, error_text    )
{
    $0 = cmdline
    dbg_print("xeq", 1, sprintf("(xeq_cmd__readarray) START dstblk=%d, name=%s, cmdline='%s'",
                                curr_dstblk(), name, cmdline))

    if (NF < 2)
        error("(xeq_cmd__readarray) Bad parameters:" cmdline)
    silent = first(name) == "s" # silent mutes file errors
    arr = $1
    filename = $2

    # Check that arr is really an ARRAY and that it's writable
    if ((nparts = nam__scan(arr, info)) == ERROR)
        error("[@readarry] Scan error, " __m2_msg)
    if (nparts == 2)
        error(sprintf("(xeq_cmd__readarray) Array name cannot have subscripts: '%s'", arr))

    # Now call nam_lookup(info)
    level = nam_lookup(info)
    if (level == ERROR)
        error(sprintf("(xeq_cmd__readarray) Name not found: '%s'", arr))
    # I don't think I care about this....
    # if (info["level"] != __namespace)
    #     error(sprintf("(xeq_cmd__readarray) Name not in current namespace: '%s'", arr))
    if (info["isarray"] != TRUE)
        error(sprintf("(xeq_cmd__readarray) Name not an array: '%s'", arr))
    code = info["code"]
    if (flag_anytrue_p(code, FLAG_SYSTEM FLAG_READONLY))
        error(sprintf("(xeq_cmd__readarray) Array not writable: '%s'", arr))
    # Maybe more checks later as I think of them
    dbg_print("xeq", 5, sprintf("(xeq_cmd__readarray) code=%s", code))
    namtab[arr, level] = code = flag_set_clear(code, FLAG_BLKARRAY, "")
    dbg_print("xeq", 5, sprintf("(xeq_cmd__readarray) namtab[%s,%d] = %s", arr, level, code))
    assert_sym_okay_to_define(arr)

    # check if variable name available

    # create a new Agg block
    agg_block = blk_new(BLK_AGG)
    dbg_print("parse", 5, sprintf("symtab['%s','%s',%d,'agg_block'] = %d",
                                 arr, key, level, agg_block))
    symtab[arr, key, level, "agg_block"] = agg_block
    blktab[agg_block, 0, "dstblk"] = agg_block
    stk_push(__parse_stack, agg_block)

    # create a new literal file parser
    file_block = prep_file(filename)
    blktab[file_block, 0, "atmode"] = MODE_AT_LITERAL
    # Push file block manually because prep_file doesn't do that
    dbg_print("parse", 7, sprintf("(xeq_cmd__readarray) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)

    dbg_print("parse", 5, "(xeq_cmd__readarray) CALLING parse__file()")
    rc = parse__file()
    dbg_print("parse", 5, "(xeq_cmd__readarray) RETURNED FROM parse__file()")
    # parse__file pops the source stack
    stk_pop(__parse_stack)

    if (!rc) {
        if (silent) return
        error_text = "File '" filename "' does not exist:" $0
        if (strictp("file"))
            error(error_text)
        else
            warn(error_text)
    }

    # set up array variable, FLAG_BLKARRAY, to point to agg block.

    dbg_print("xeq", 1, sprintf("(xeq_cmd__readarray) END"))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  R E A D F I L E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @{s,}readfile         NAME FILE
function xeq_cmd__readfile(name, cmdline,
                           sym, filename, line, val, getstat, silent)
{
    # We could play games and use fancy file blocks and literal atmode, but we
    # really just want to read in a file and assign its contents to a symbol.
    $0 = cmdline
    if (NF < 2)
        error("(xeq_cmd__readfile) Bad parameters:" $0)
    silent = first(name) == "s" # silent mutes file errors, even in strict mode
    sym  = $1
    assert_sym_okay_to_define(sym)
    # These contortions because a filename might have embedded spaces
    $1 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))

    val = EMPTY
    while (TRUE) {
        getstat = getline line < filename
        if (getstat == ERROR && !silent)
            warn("Error reading file '" filename "' [readfile]")
        if (getstat != OKAY)
            break
        # This concatenation becomes quite slow after more than a few
        # dozen lines, which is why @readarray exists.
        val = val line TOK_NEWLINE
    }
    close(filename)
    sym_store(sym, chomp(val))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  R E A D O N L Y
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @readonly             NAME
#   @readonly VAR.  makes existing variable read-only.  No way to undo
#   @readonly ARR also works, freezes array preventing adding new elements.
#   @readonly cannot be performed on SYSTEM symbols or arrays
function xeq_cmd__readonly(cmd, cmdline,
                           sym, info, nparts, name, key, level, code)
{
    dbg_print("xeq", 5, sprintf("(xeq_cmd__readonly) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0)
        error("(xeq_cmd__readonly) Bad parameters:" $0)
    sym = $1

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR)
        error("[@readonly] Scan error, " __m2_msg)
    name = info["name"]
    key  = info["key"]

    # Now call nam_lookup(info)
    level = nam_lookup(info)
    if (level == ERROR)
        error("(xeq_cmd__readonly) nam_lookup(info) failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # symtab because NAME[KEY] might not be defined.
    code = info["code"]

    assert_sym_okay_to_define(sym)
    assert_sym_defined(sym, "readonly")

    # if (flag_allfalse_p(code, TYPE_ARRAY TYPE_SYMBOL))
    #     error("@readonly: name must be symbol or array")
    if (flag_1true_p(code, FLAG_SYSTEM))
        error("@readonly: name protected")
    nam_ll_write(name, level, flag_set_clear(code, FLAG_READONLY))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  R E T U R N
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @return
function xeq_cmd__return(name, cmdline,
                        level, block, block_type)
{
    # Logical check
    if (__xeq_ctl != XEQ_NORMAL)
        error("(xeq_cmd__return) __xeq_ctl is not normal, how did that happen?")

    __xeq_ctl = XEQ_RETURN
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  S E Q U E N C E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @sequence             ID SUBCMD [ARG...]
function xeq_cmd__sequence(name, cmdline,
                          id, action, arg, saveline)
{
    $0 = cmdline
    dbg_print("seq", 1, sprintf("(xeq_cmd__sequence) START dstblk=%d, name=%s, cmdline='%s'",
                                curr_dstblk(), name, cmdline))
    if (NF == 0)
        error("Bad parameters: Missing sequence name:" $0)
    id = $1
    assert_seq_valid_name(id)
    if (NF == 1)
        $2 = "create"
    action = $2
    if (action != "create" && !seq_defined_p(id))
        error("Name '" id "' not defined [sequence]:" $0)
    if (NF == 2) {
        if (action == "create") {
            assert_seq_okay_to_define(id)
            nam_ll_write(id, GLOBAL_NAMESPACE, TYPE_SEQUENCE FLAG_INTEGER)
            seqtab[id, "incr"] = SEQ_DEFAULT_INCR
            seqtab[id, "init"] = SEQ_DEFAULT_INIT
            seqtab[id, "fmt"]  = sym_ll_read("__FMT__", "seq", GLOBAL_NAMESPACE)
            seq_ll_write(id, SEQ_DEFAULT_INIT)
        } else if (action == "delete") {
            seq_destroy(id)
        } else if (action == "next") { # Increment counter only, no output
            seq_ll_incr(id, seqtab[id, "incr"])
        } else if (action == "prev") { # Decrement counter only, no output
            seq_ll_incr(id, -seqtab[id, "incr"])
        } else if (action == "restart") { # Set current counter value to initial value
            seq_ll_write(id, seqtab[id, "init"])
        } else
            error("Bad parameters:" $0)
    } else {    # NF >= 4
        saveline = $0
        dbg_print("seq", 2, sprintf("(xeq_cmd__sequence) cmdline was '%s'", cmdline))
        #sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/, "") # a + this time because ARG is required
        sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+/, "", cmdline) # a + this time because ARG is required
        dbg_print("seq", 2, sprintf("(xeq_cmd__sequence) cmdline now '%s'", cmdline))
        # arg = $0
        arg = cmdline
        if (action == "format") {
            # format STRING :: Set format string for printf to STRING.
            # Arg should be the format string to use with printf.  It
            # must include exactly one %d for the sequence value, and no
            # other argument-consuming formatting characters.  You might
            # specify %x to print in hexadecimal instead.  The point is,
            # m2 can't police your format string and a bad value might
            # cause a crash if printf() fails.
            dbg_print("seq", 2, sprintf("(xeq_cmd__sequence) fmt now '%s'", arg))
            seqtab[id, "fmt"] = arg
        } else if (action == "setincr") {
            # setincr N :: Set increment value to N.
            if (!integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            if (arg+0 == 0)
                error(sprintf("Bad parameters in 'incr':%s", saveline))
            seqtab[id, "incr"] = int(arg)
        } else if (action == "setinit") {
            # setinit N :: Set initial  value to N.  If current
            # value == old init value (i.e., never been used), then set
            # the current value to the new init value also.  Otherwise
            # current value remains unchanged.
            if (!integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            if (seq_ll_read(id) == seqtab[id, "init"])
                seq_ll_write(id, int(arg))
            seqtab[id, "init"] = int(arg)
        } else if (action == "setval") {
            # setval N :: Set counter value directly to N.
            if (!integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            seq_ll_write(id, int(arg))
        } else
           error("Bad parameters:" saveline)
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  S H E L L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @shell                DELIM [PROG]
# Set symbol "M2_SHELL" to override.
function xeq_cmd__shell(name, cmdline,
                        delim, save_line, save_lineno, shell_text_in, input_file,
                        output_text, output_file, sendto, path_fmt, getstat,
                        shell_cmdline, line, shell_data_blk, readstat)
{
    # The sendto program defaults to a reasonable shell but you can
    # specify where you want to send your data.  Possibly useful choices
    # would be an alternative shell, an email message reader, or
    # /usr/bin/bc.  It must be a program that functions as a filter (in
    # the Unix sense, i.e., reading from standard input and writing to
    # standard output).  Standard error is not redirected, so any errors
    # will appear on the user's terminal.
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = LINE()
    delim = $1
    if (NF == 1) {              # @shell DELIM
        sendto = default_shell()
    } else {                    # @shell DELIM /usr/ucb/mail
        $1 = ""
        sub("^[ \t]*", "")
        sendto = rm_quotes(dosubs($0))
    }

    shell_data_blk = blk_new(BLK_AGG)
    readstat = read_lines_until(delim, shell_data_blk)
    if (readstat != TRUE)
        error("Delimiter '" delim "' not found:" save_line, "", save_lineno)

    # Don't check security level until now so we can properly read to
    # the delimiter.
    if (secure_level() >= 1) {
        warn("(xeq_cmd__shell) @shell - Security violation")
        return
    }

    shell_text_in = blk_to_string(shell_data_blk)
    dbg_print("parse", 5, sprintf("(xeq_cmd__shell) shell_text_in='%s'", shell_text_in))
    
    path_fmt    = sprintf("%sm2-%d.shell-%%s", tmpdir(), sym_fetch("__PID__"))
    input_file  = sprintf(path_fmt, "in")
    output_file = sprintf(path_fmt, "out")
    print dosubs(shell_text_in) > input_file
    close(input_file)

    # Don't tell me how fragile this is, we're whistling past the graveyard
    # here.  But it suffices to run /bin/sh, which is enough for now.
    shell_cmdline = sprintf("%s < %s > %s", sendto, input_file, output_file)
    flush_stdout(SYNC_FORCE)    # force flush stdout
    sym_ll_write("__SYSVAL__", "", GLOBAL_NAMESPACE, system(shell_cmdline))
    while (TRUE) {
        getstat = getline line < output_file
        if (getstat == ERROR)
            warn("Error reading file '" output_file "' [shell]")
        if (getstat != OKAY)
            break
        output_text = output_text line TOK_NEWLINE # Read a line
    }
    close(output_file)

    exec_prog_cmdline("rm", ("-f " input_file))
    exec_prog_cmdline("rm", ("-f " output_file))
    ship_out(OBJ_TEXT, chomp(output_text))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  S Y S C M D
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @syscmd CMDLINE ...
function xeq_cmd__syscmd(name, cmdline,
                        rc)
{
    if (secure_level() >= 2)
        error("@syscmd: Security violation")
    cmdline = cmdline " >/dev/null 2>/dev/null"
    dbg_print("cmd", 3, sprintf("(xeq_cmd__syscmd) START; cmdline='%s'", cmdline))

    flush_stdout(SYNC_FORCE)
    rc = system(cmdline)
    sym_ll_write("__SYSVAL__", "", GLOBAL_NAMESPACE, rc)
    dbg_print("cmd", 3, sprintf("(xeq_cmd__syscmd) END; rc=%d", rc))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  T Y P E O U T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @typeout
function xeq_cmd__typeout(name, cmdline,
#                          i, parser)
                          src_block)
{
    if (stk_emptyp(__source_stack))
        error("(xeq_cmd__typeout) Source stack is empty")

    src_block = stk_top(__source_stack)
    blktab[src_block, 0, "atmode"] = MODE_AT_LITERAL
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  U N D E F I N E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @undef[ine]           NAME
function xeq_cmd__undefine(name, cmdline,
                           sym, info, level, code, nparts, type)
{
    $0 = cmdline
    if (NF != 1)
        error("Bad parameters:" $0)
    sym = $1

    dbg_print("sym", 4, sprintf("(xeq_cmd__undefine) START; sym=%s", sym))

    # This is the old way:
    # if (seq_valid_p(sym) && seq_defined_p(sym))
    #     seq_destroy(sym)
    # else if (cmd_valid_p(sym) && cmd_defined_p(sym)) {
    #     cmd_destroy(sym)
    # } else {
    #     assert_sym_valid_name(sym)
    #     assert_sym_unprotected(sym)
    #     # System symbols, even unprotected ones -- despite being subject
    #     # to user modification -- cannot be undefined.
    #     if (nam_system_p(sym))
    #         error("Name '" sym "' not available:" $0)
    #     dbg_print("sym", 3, ("About to sym_destroy('" sym "')"))
    #     sym_destroy(sym)
    # }

    # A better way:
    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR)
        error("[@undefine] Scan error, " __m2_msg)
    if ((level = nam_lookup(info)) == ERROR) {
        error("(xeq_cmd__undefine) '" sym "' not found")
    }
    if ((type = info["type"]) == TYPE_SYMBOL)
        sym_destroy(info["name"], info["key"], info["level"])
    else if (type == TYPE_SEQUENCE)
        seq_destroy(sym)
    else if (type == TYPE_USER)
        cmd_destroy(sym)
    else
        error("(xeq_cmd__undefine) '" sym "' of type " type " cannot be destroyed")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  U N D I V E R T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @undivert             [N]
function xeq_cmd__undivert(name, cmdline,
                           i, stream)
{
    $0 = cmdline
    dbg_print("divert", 1, sprintf("(xeq_cmd__undivert) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    dbg_print_block("divert", 8, curr_dstblk(), "(xeq_cmd__undivert) curr_dstblk()")
    if (NF == 0)
        undivert_all()
    else {
        i = 0
        while (++i <= NF) {
            stream = dosubs($i)
            if (!integerp(stream))
                # error(sprintf("Value '%s' must be numeric:", stream) $0)
                continue
            if (stream > MAX_STREAM)
                error("Bad parameters:" $0)
            dbg_print("divert", 5, sprintf("(xeq_cmd__undivert) CALLING undivert(%d)", stream))
            undivert(stream)
        }
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  W H I L E
#   
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @while CONDITION
# @until CONDITION
function parse__while(                 name, while_block, body_block, pstat)
{
    dbg_print("while", 3, sprintf("(parse__while) START dstblk=%d, $0='%s'", curr_dstblk(), $0))
    name = $1
    $1 = ""
    sub("^[ \t]*", "")

    raise_namespace()

    # Create two new blocks: one for while_block, other for true branch
    while_block = blk_new(BLK_WHILE)
    dbg_print("while", 5, "(parse__while) New block # " while_block " type " ppf__block_type(blk_type(while_block)))
    body_block = blk_new(BLK_AGG)
    dbg_print("while", 5, "(parse__while) New block # " body_block " type " ppf__block_type(blk_type(body_block)))

    blktab[while_block, 0, "condition"] = $0
    blktab[while_block, 0, "init_negate"] = (name == "@until")
    blktab[while_block, 0, "body_block"] = body_block
    blktab[while_block, 0, "dstblk"] = body_block
    blktab[while_block, 0, "valid"]      = FALSE
    dbg_print_block("while", 7, while_block, "(parse__while) while_block")
    stk_push(__parse_stack, while_block) # Push it on to the parse_stack

    dbg_print("while", 5, "(parse__while) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endif
    dbg_print("while", 5, "(parse__while) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@while) Parse error")

    dbg_print("while", 5, "(parse__while) END; => " while_block)
    return while_block
}


# @endwhile
function parse__endwhile(                    while_block)
{
    dbg_print("while", 3, sprintf("(parse__endwhile) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_WHILE) != 0)
        error("[@endwhile] Parse error; " __m2_msg)
    while_block = stk_pop(__parse_stack)

    blktab[while_block, 0, "valid"] = TRUE
    lower_namespace()
    return while_block
}


function xeq__BLK_WHILE(while_block,
                        block_type, body_block, condition, condval, negate)
{
    block_type = blk_type(while_block)
    dbg_print("while", 3, sprintf("(xeq__BLK_WHILE) START dstblk=%d, while_block=%d, type=%s",
                               curr_dstblk(), while_block, ppf__block_type(block_type)))

    dbg_print_block("while", 7, while_block, "(xeq__BLK_WHILE) while_block")
    if ((block_type != BLK_WHILE) || \
        (blktab[while_block, 0, "valid"] != TRUE))
        error("(xeq__BLK_WHILE) Bad config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    body_block = blktab[while_block, 0, "body_block"]
    condition = blktab[while_block, 0, "condition"]
    negate = blktab[while_block, 0, "init_negate"]
    condval = evaluate_boolean(condition, negate)
    dbg_print("while", 1, sprintf("(xeq__BLK_WHILE) Initial evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
    if (condval == ERROR)
        error("@while: Error evaluating condition '" condition "'")

    while (condval) {
        raise_namespace()
        dbg_print("while", 5, sprintf("(xeq__BLK_WHILE) CALLING execute__block(%d)",
                                   body_block))
        execute__block(body_block)
        dbg_print("while", 5, sprintf("(xeq__BLK_WHILE) RETURNED FROM execute__block()"))
        lower_namespace()

        condval = evaluate_boolean(condition, negate)
        dbg_print("while", 3, sprintf("(xeq__BLK_WHILE) Repeat evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
        if (condval == ERROR)
            error("@while: Error evaluating condition '" condition "'")

        # Check for break or continue
        if (__xeq_ctl == XEQ_BREAK) {
            __xeq_ctl = XEQ_NORMAL
            break
        }
        if (__xeq_ctl == XEQ_CONTINUE) {
            __xeq_ctl = XEQ_NORMAL
            # Actual "continue" wouldn't do anything here since we're
            # about to re-iterate the loop anyway
        }
    }

    dbg_print("while", 3, sprintf("(xeq__BLK_WHILE) END"))
}


function ppf__while(while_block,
                    buf)
{
    buf = "@while " blktab[while_block, 0, "condition"] TOK_NEWLINE \
          ppf__block(blktab[while_block, 0, "body_block"]) TOK_NEWLINE \
          "@endwhile"
    return buf
}


function ppf__BLK_WHILE(blknum)
{
    return sprintf("  valid       : %s\n"       \
                   "  condition   : '%s'\n"     \
                   "  body_block  : %d",
                   ppf__bool(blktab[blknum, 0, "valid"]),
                   blktab[blknum, 0, "condition"],
                   blktab[blknum, 0, "body_block"])
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  W R A P
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @wrap      TEXT
function xeq_cmd__wrap(name, cmdline,
                       rstat)
{
    dbg_print("parse", 5, sprintf("(xeq_cmd__wrap) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

    # dbg_print("parse", 5, "(xeq_cmd__ignore) CALLING read_lines_until()")
    # rstat = read_lines_until(cmdline, DISCARD)
    # dbg_print("parse", 5, "(xeq_cmd__ignore) RETURNED FROM read_lines_until() => " ppf__bool(rstat))
    # if (!rstat)
    #     error("[@ignore] Read error")
    # dbg_print("parse", 5, "(xeq_cmd__ignore) END")}

    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)

    __wrap_text[++__wrap_cnt] = $0
    dbg_print("parse", 5, sprintf("(xeq_cmd__wrap) END; text='%s'", $0))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       G E N E R I C   S H I P  -  O U T
#
#*****************************************************************************
function ship_out(obj_type, obj,
                  dstblk, name)
{
    dstblk = curr_dstblk()
    dbg_print("ship_out", 3, sprintf("(ship_out) START dstblk=%d, obj_type=%s, obj='%s'",
                                     dstblk, __blk_label[obj_type], obj))
    if (dstblk < 0) {
        dbg_print("ship_out", 3, "(ship_out) END, because dstblk <0")
        return
    }
    if (dstblk > MAX_STREAM) {
        dbg_print("ship_out", 5, sprintf("(ship_out) END Appending obj '%s' to block %d", obj, dstblk))
        blk_append(dstblk, obj_type, obj)
        return
    }
    if (dstblk != TERMINAL)
        error(sprintf("(ship_out) dstblk is %d, not zero!", dstblk))

    # dstblk is zero, so obj must be executed (or text printed)
    if (obj_type == OBJ_BLKNUM) {
        dbg_print("ship_out", 5, sprintf("(ship_out) CALLING execute__block(%d)", obj))
        execute__block(obj)
        dbg_print("ship_out", 5, sprintf("(ship_out) RETURNED FROM execute__block"))

    } else if (obj_type == OBJ_CMD) {
        name = extract_cmd_name(obj)
        sub(/^[ \t]*[^ \t]+[ \t]*/, "", obj)
        # Unlike every other command, @wrap ships out its line literally here.
        # Function end_program(), which handles wrapped text, calls dosubs().
        if (name != "wrap")
            obj = dosubs(obj)
        dbg_print("ship_out", 3, sprintf("(ship_out) CALLING execute__command('%s', '%s')",
                                         name, obj))
        execute__command(name, obj)
        dbg_print("ship_out", 3, sprintf("(ship_out) RETURNED FROM execute__command('%s', ...)",
                                         name))

    } else if (obj_type == OBJ_TEXT) {
        dbg_print("ship_out", 5, sprintf("(ship_out) CALLING execute__text()"))
        execute__text(obj)
        dbg_print("ship_out", 5, sprintf("(ship_out) RETURNED FROM execute__text()"))

    } else if (obj_type == OBJ_USER) {
        name = extract_cmd_name(obj)
        #sub(/^[ \t]*[^ \t]+[ \t]*/, "", obj)   # OBJ_CMD does this but not here, ???
        obj = dosubs(obj)
        dbg_print("ship_out", 3, sprintf("(ship_out) CALLING execute__user('%s', '%s')",
                                         name, obj))
        execute__user(name, obj)
        dbg_print("ship_out", 3, sprintf("(ship_out) RETURNED FROM execute__user('%s', ...)",
                                         name))

    } else
        error("(ship_out) Unrecognized obj_type '" obj_type "'")

    dbg_print("ship_out", 3, sprintf("(ship_out) END"))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       E X P R E S S I O N   C A L C U L A T O R
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Based on `calc3' from "The AWK Programming Language" p. 146
#       with enhancements by Kenny McCormack and Alan Linton.
#
#       calc3_eval is the main entry point.  All other _c3_* functions
#       are for internal use and should not be called by the user.
#
#*****************************************************************************
function calc3_eval(s,
                    e)
{
    _c3__Sexpr = s
    gsub(/[ \t]+/, "", _c3__Sexpr)

    # Bare @expr@ returns most recent result
    if (emptyp(_c3__Sexpr))
        return sym_ll_read("__EXPR__", "", GLOBAL_NAMESPACE)

    _c3__f = 1
    e = _c3_expr()
    if (_c3__f <= length(_c3__Sexpr))
        error(sprintf("Math expression error at '%s':", substr(_c3__Sexpr, _c3__f)) $0)
    else if (match(e, /^[-+]?(nan|inf)/))
        error(sprintf("Math expression error:'%s' returned \"%s\": ", s, e) $0)
    else
        return e
}


# rel | rel relop rel
function _c3_expr(    var, e, op1, op2, m2)
{
    if (match(substr(_c3__Sexpr, _c3__f), /^[A-Za-z#_][A-Za-z#_0-9]*=[^=]/)) {
        var = _c3_advance()
        sub(/=.*$/, "", var)
        assert_sym_okay_to_define(var)
        # match() sets RLENGTH which includes the match character [^=].
        # But that's the start of the value -- I need to back up over it
        # to read the value properly.
        _c3__f--
        return sym_store(var, _c3_expr()+0)
    }

    e = _c3_rel()
    # Only one relational operator allowed: 1<2<3 is a syntax error
    if ((m2 = ((op2 = substr(_c3__Sexpr, _c3__f, 2)) ~ /<=|==|!=|>=/))  ||
              ((op1 = substr(_c3__Sexpr, _c3__f, 1)) ~ /<|>/)) {
        if (m2) {
            _c3__f += 2             # Use +0 to force numeric comparison
            if (op2 == "<=") return e+0 <= _c3_rel()+0
            if (op2 == "==") return e+0 == _c3_rel()+0
            if (op2 == "!=") return e+0 != _c3_rel()+0
            if (op2 == ">=") return e+0 >= _c3_rel()+0
        } else {
            _c3__f += 1
            if (op1 == "<")  return e+0 <  _c3_rel()+0
            if (op1 == ">")  return e+0 >  _c3_rel()+0
        }
    }
    return e
}


# term | term [+-] term
function _c3_rel(    e, op)
{
    e = _c3_term()
    while ((op = substr(_c3__Sexpr, _c3__f, 1)) ~ /[+-]/) {
        _c3__f++
        e = op == "+" ? e + _c3_term() : e - _c3_term()
    }
    return e
}


# factor | factor [*/%] factor
#
# NOTE: Alan Linton's version of this function has a bug: the function
# returned prematurely, even when another op of equal precedence was
# encountered.  This results in "1*2*3" being rejected at the second `*'.
# The correction is to continue the while loop instead of returning.
function _c3_term(    e, op, f)
{
    e = _c3_factor()
    while ((op = substr(_c3__Sexpr, _c3__f, 1)) ~ /[*\/%]/) {
        _c3__f++
        f = _c3_factor()
        if (op == "*")
            e = e * f
        else {
            if (f == 0)         # Ugh
                error("Division by zero:" $0)
            e = (op == "/") ? e / f : e % f
        }
    }
    return e
}


# factor2 | factor2 ^ factor
function _c3_factor(    e)
{
    e = _c3_factor2()
    if (substr(_c3__Sexpr, _c3__f, 1) != "^") return e
    _c3__f++
    return e ^ _c3_factor()
}


# [+-]?factor3 | !*factor2
function _c3_factor2(    e)
{
    e = substr(_c3__Sexpr, _c3__f)
    if (e ~ /^[-+!]/) {      #unary operators [+-!]
        _c3__f++
        if (e ~ /^\+/) return +_c3_factor3() # only one unary + allowed
        if (e ~ /^-/)  return -_c3_factor3() # only one unary - allowed
        if (e ~ /^!/)  return !(_c3_factor2()+0) # unary ! may repeat
    }
    return _c3_factor3()
}


# number | varname | (expr) | function(...)
function _c3_factor3(    e, fun, e2)
{
    e = substr(_c3__Sexpr, _c3__f)

    # number
    if (match(e, /^([0-9]+[.]?[0-9]*|[.][0-9]+)([Ee][+-]?[0-9]+)?/)) {
        return _c3_advance()
    }

    # function ()
    if (match(e, /^([A-Za-z#_][A-Za-z#_0-9]+)?\(\)/)) {
        fun = _c3_advance()
        if (fun ~ /^srand()/) return srand()
        if (fun ~ /^rand()/)  return rand()
        error(sprintf("Unknown function '%s':%s",
                      (last(fun) == "(") ? chop(fun) : fun, $0))
    }

    # (expr) | function(expr) | function(expr,expr)
    if (match(e, /^([A-Za-z#_][A-Za-z#_0-9]+)?\(/)) {
        fun = _c3_advance()
        # These are for numeric functions only, not strings/symbols
        if (fun ~ /^(abs|acos|asin|ceil|cos|deg|exp|floor|int|log(10)?|rad|randint|round|sign|sin|sqrt|srand|tan)?\(/) {
            e = _c3_expr()
            e = _c3_calculate_function(fun, e)
        } else if (fun ~ /^defined\(/) {
            e2 = substr(e, 9, length(e)-9)
            #print_stderr(sprintf("defined(): e2='%s'", e2))
            _c3__f += length(e2)
            e = sym_defined_p(e2) ? TRUE : FALSE
        } else if (fun ~ /^(atan2|hypot|max|min|pow)\(/) {
            e = _c3_expr()
            if (substr(_c3__Sexpr, _c3__f, 1) != ",")
                error(sprintf("Missing ',' at '%s'", substr(_c3__Sexpr, _c3__f)))
            _c3__f++
            e2 = _c3_expr()
            e = _c3_calculate_function2(fun, e, e2)
        } else
            error(sprintf("Unknown function '%s':%s",
                          (last(fun) == "(") ? chop(fun) : fun, $0))

        if (substr(_c3__Sexpr, _c3__f++, 1) != ")")
            error(sprintf("Missing ')' at '%s'", substr(_c3__Sexpr, _c3__f)))
        return e
    }

    # predefined, symbol, or sequence name
    if (match(e, /^[A-Za-z#_][A-Za-z#_0-9]*/)) {
        e2 = _c3_advance()
        if      (e2 == "e")   return E
        else if (e2 == "pi")  return PI
        else if (e2 == "tau") return TAU
        else if (sym_valid_p(e2) && sym_defined_p(e2))
            return sym_fetch(e2)
        else if (seq_valid_p(e2) && seq_defined_p(e2))
            return seq_ll_read(e2)
    }

    # error
    error(sprintf("Expected number or '(' at '%s'", substr(_c3__Sexpr, _c3__f)))
}


# Mathematical functions of one variable
function _c3_calculate_function(fun, e,
                                c)
{
    if (fun == "(")        return e
    if (fun == "abs(")     return abs(e) # e < 0 ? -e : e
    if (fun == "acos(")    { if (e < -1 || e > 1)
                                 error(sprintf("Math expression error [acos(%d)]:", e) $0)
                             return atan2(sqrt(1 - e^2), e) }
    if (fun == "asin(")    { if (e < -1 || e > 1)
                                 error(sprintf("Math expression error [asin(%d)]:", e) $0)
                             return atan2(e, sqrt(1 - e^2)) }
    if (fun == "ceil(")    { c = int(e)
                             return e > c ? c+1 : c }
    if (fun == "cos(")     return cos(e)
    if (fun == "deg(")     return e * (360 / TAU)
    if (fun == "exp(")     return exp(e)
    if (fun == "floor(")   { c = int(e)
                             return e < c ? c-1 : c }
    if (fun == "int(")     return int(e)
    if (fun == "log(")     return log(e)
    if (fun == "log10(")   return log(e) / LOG10
    if (fun == "rad(")     return e * (TAU / 360)
    if (fun == "randint(") return randint(e) + 1
    if (fun == "round(")   return round(e)
    if (fun == "sign(")    return (e > 0) - (e < 0)
    if (fun == "sin(")     return sin(e)
    if (fun == "sqrt(")    return sqrt(e)
    if (fun == "srand(")   return srand(e)
    if (fun == "tan(")     { c = cos(e)
                             if (c == 0) error("Division by zero:" $0)
                             return sin(e) / c }
    error(sprintf("Unknown function '%s':%s",
                  (last(fun) == "(") ? chop(fun) : fun, $0))
}


# Functions of two variables
function _c3_calculate_function2(fun, e, e2,
                                 hmax, hmin, hr)
{
    if (fun == "atan2(")   return atan2(e, e2)
    if (fun == "hypot(")   { # Dangerous due to potentional overflow:
                             #    return sqrt(e^2 + e2^2)
                             # Better: the following algorithm computes
                             # sqrt(x*x + y*y) without risking overflow:
                             # https://www.johndcook.com/blog/2010/06/02/whats-so-hard-about-finding-a-hypotenuse/
                             hmax = max(abs(e), abs(e2))
                             hmin = min(abs(e), abs(e2))
                             hr = hmin / hmax
                             return hmax * sqrt(1 + hr^2)
                           }
    if (fun == "max(")     return e > e2 ? e : e2
    if (fun == "min(")     return e < e2 ? e : e2
    if (fun == "pow(")     return e ^ e2
    error(sprintf("Unknown function '%s':%s",
                  (last(fun) == "(") ? chop(fun) : fun, $0))
}


function _c3_advance(    tmp)
{
    tmp = substr(_c3__Sexpr, _c3__f, RLENGTH)
    _c3__f += RLENGTH
    return tmp
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       D O S U B S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

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
function dosubs(s,
                expand, i, j, l, m, nparam, p, param, r, fn, cmdline, c,
                at_brace, x, y, inc_dec, pre_post, subcmd, silent, off_by,
                br, ifcond, true_text, false_text, init_negate, arg)
{
    dbg_print("dosubs", 5, sprintf("(dosubs) START s='%s'", s))
    l = ""                   # Left of current pos  - ready for output
    r = s                    # Right of current pos - as yet unexamined
    inc_dec = pre_post = 0   # track ++ or -- on sequences
    off_by = 1

    while (TRUE) {
        # Check entire string for recursive evaluation
        if (index(r, "@{") > 0)
            r = expand_braces(r)

        if ((i = index(r, TOK_AT)) == IDX_NOT_FOUND)
            break

        dbg_print("dosubs", 7, (sprintf("(dosubs) Top of loop: l='%s', r='%s', expand='%s'", l, r, expand)))
        l = l substr(r, 1, i-1)
        r = substr(r, i+1)      # Currently scanning @

        # Look for a second "@" beyond the first one.  If not found,
        # this can't be a valid m2 substitution.  Ignore it, we're done.
        if ((i = index(r, TOK_AT)) == IDX_NOT_FOUND) {
            l = l TOK_AT
            break
        }

        # A lone "@" followed by whitespace is not valid syntax.  Ignore it,
        # but keep processing the line.
        if (isspace(first(r))) {
            l = l TOK_AT
            continue
        }

        m = substr(r, 1, i-1)   # Middle
        r = substr(r, i+1)

        # s == L  @  M  @  R
        #               ^---i

        # In the code that follows:
        # - m :: Entire text between @'s.  Example: "mid foo 3".
        # - fn :: The name of the "function" to call.  The first element
        #         of m.  Example: "mid".
        # - nparam :: Number of parameters supplied to the function.
        #     @mid@         -> nparam == 0
        #     @mid foo@     -> nparam == 1
        #     @mid foo 3@   -> nparam == 2
        # In general, a function's parameter N is available in variable
        #   param[N+1].  Consider "mid foo 3".  nparam is 2.
        #   The fn is found in the first position, at param [0+1].
        #   The new prefix is at param[1+1] and new count is at param[2+1].
        #   This offset of one is referred to as `off_by' below.
        # Each function condition eventually executes
        #     r = <SOMETHING> r
        #   which injects <SOMETHING> just before the current value of
        #   r.  (r is defined above.)  r is what is to the right of the
        #   current position and contains as yet unexamined text that
        #   needs to be evaluated for possible macro processing.  This
        #   is the data we were going to evaluate anyway.  In other
        #   words, this injects the result of "invoking" fn.
        # Eventually this big while loop exits and we return "l r".

        nparam = split(m, param) - off_by
        fn = param[0 + off_by]
        if ((br = index(m, TOK_LBRACE)) > 0)
            fn = substr(fn, 1, br-1)

        dbg_print("dosubs", 7, sprintf("(dosubs) fn=%s, nparam=%d; l='%s', m='%s', r='%s', expand='%s'", fn, nparam, l, m, r, expand))

        # Check for sequence modifiers.  First one wins, and
        # invalid syntax is silently ignored.
        if (substr(fn, 1, 2) == "++") {
            inc_dec  = +1
            pre_post = -1
            fn = substr(fn, 3)
        } else if (substr(fn, 1, 2) == "--") {
            inc_dec  = -1
            pre_post = -1
            fn = substr(fn, 3)
        } else if (substr(fn, length(fn)-1, 2) == "++") {
            inc_dec  = +1
            pre_post = +1
            fn = substr(fn, 1, length(fn) - 2)
        } else if (substr(fn, length(fn)-1, 2) == "--") {
            inc_dec  = -1
            pre_post = +1
            fn = substr(fn, 1, length(fn) - 2)
        }

        # basename SYM: Base (i.e., file name) of path, in Awk
        if (fn == "basename") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            # basename in Awk, assuming Unix style path separator.
            # Return filename portion of path.  If this is not
            # adequate, consider using @xbasename SYM@.
            expand = rm_quotes(sym_fetch(p))
            sub(/^.*\//, "", expand)
            r = expand r

        # boolval SYM: Print __FMT__[0 or 1], depending on SYM truthiness.
        #   @boolval SYM@ => <string>
        # The actual output is taken from __FMT__[].  The defaults are
        # "1" and "0", but a Fortran programmer might change them to
        # ".TRUE." and ".FALSE.", while a Lisp programmer might change
        # them to "t" and "nil".  If the symbol SYM is not defined:
        #  - In strict mode, throw an error if the symbol is not defined.
        #  - In non-strict mode, you get a 'false' output if not defined.
        #  - If it's not a symbol, use its value as a boolean state.
        } else if (fn == "boolval") {
            if (nparam == 0)
                # In an effort to spread a bit more chaos in the universe,
                # if you don't give an argument to boolval then you get
                # True 50% of the time and False the other 50%.
                r = sym_ll_read("__FMT__", rand() < 0.50) r
            else {
                p = param[1 + off_by]
                # Always accept your current representation of True or False
                # to actually be true or false without further evaluation.
                if (p == sym_ll_read("__FMT__", TRUE) ||
                    p == sym_ll_read("__FMT__", FALSE))
                    r = p r
                else if (sym_valid_p(p)) {
                    # It's a valid name -- now see if it's defined or not.
                    # If not, check if we're in strict mode (error) or not.
                    if (sym_defined_p(p))
                        r = sym_ll_read("__FMT__", sym_true_p(p)) r
                    else if (strictp("boolval"))
                        error("Name '" p "' not defined [boolval]:" $0)
                    else
                        r = sym_ll_read("__FMT__", FALSE) r
                } else
                    # It's not a symbol, so use its value interpreted as a boolean
                    r = sym_ll_read("__FMT__", !!p) r
            }

        # chr SYM: Output character with ASCII code SYM
        #   @chr 65@ => A
        } else if (fn == "chr") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            if (sym_valid_p(p)) {
                assert_sym_defined(p, fn)
                x = sprintf("%c", sym_fetch(p)+0)
                r = x r
            } else if (integerp(p) && p >= 0 && p <= 255) {
                x = sprintf("%c", p+0)
                r = x r
            } else
                error("Bad parameters in '" m "':" $0)

        # date    : Current date as YYYY-MM-DD
        # epoch   : Number of seconds since Epoch
        # strftime: User-specified date format, see strftime(3)
        # time    : Current time as HH:MM:SS
        # tz      : Current time zone name
        } else if (fn == "date" ||
                   fn == "epoch" ||
                   fn == "strftime" ||
                   fn == "time" ||
                   fn == "tz") {
            if (secure_level() >= 2)
                error(sprintf("(%s) Security violation", fn))
            if (fn == "strftime" && nparam == 0)
                error("Bad parameters in '" m "':" $0)
            y = fn == "strftime" ? substr(m, length(fn)+2) \
                : sym_ll_read("__FMT__", fn)
            gsub(/"/, "\\\"", y)
            cmdline = build_prog_cmdline("date", "+\"" y "\"", MODE_IO_CAPTURE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # dirname SYM: Directory name of path, in Awk
        } else if (fn == "dirname") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            # dirname in Awk, assuming Unix style path separator.
            # Return directory portion of path.  If this is not
            # adequate, consider using @xdirname SYM@.
            y = rm_quotes(sym_fetch(p))
            expand = (sub(/\/[^\/]*$/, "", y)) ? y : "."
            r = expand r

        # expr ...: Evaluate mathematical epxression, store in __EXPR__
        } else if (fn == "expr" || fn == "sexpr") {
            # "silent" expr performs the same calculations but does not
            # output the result.  However, assignments are still
            # performed and in particular __EXPR__ is still set.
            silent = first(fn) == "s"
            sub(/^s?expr[ \t]*/, "", m) # clean up expression to evaluate
            x = calc3_eval(m)
            dbg_print("expr", 1, sprintf("expr{%s} = %s", m, x))
            sym_ll_write("__EXPR__", "", GLOBAL_NAMESPACE, x+0)
            if (!silent)
                r = x r

        # getenv: Get environment variable
        # sgetenv
        #   @getenv HOME@ => /home/user
        } else if (fn == "getenv" || fn == "sgetenv") {
            # "silent" getenv returns empty string for non-existent
            # variable, regardless of strict setting.
            silent = first(fn) == "s"
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_valid_env_var_name(p)
            if (p in ENVIRON)
                r = ENVIRON[p] r
            else if (strictp("env") && !silent)
                error("Environment variable '" p "' not defined:" $0)

        # ifdef/ifndef: Expand text if symbol is defined
        #   @ifdef{FOO}{True text}{False text}@
        } else if (fn == "ifdef" || fn == "ifndef") {
            if (match(m, "^ifn?def{[^}]+}{[^}]*}{[^}]*}$"))
                ;          # @ifdef{FOO}{True text}{False text}@ is well-formed
            else if (match(m, "^ifn?def{[^}]+}{[^}]*}$"))
                m = m "{}" # @ifdef{FOO}{True text}@ will use empty FALSE string
            else
                error("(dosubs) Bad ifdef in '" m "':" $0)

            # Get symbol name (x) which will be handed to defined()
            m = substr(m, index(m, TOK_LBRACE)) # strip fn name
            if (!match(m, "^{[^}]*}"))
                error("(dosubs) Bad ifdef symbol in '" m "':" $0)
            x = substr(m, RSTART+1, RLENGTH-2)
            assert_sym_valid_name(x)
            ifcond = "defined(" x ")"
            init_negate = fn == "ifndef"
            dbg_print("dosubs", 7, "(dosubs) ifdef: ifcond='" ifcond "'")
            m = substr(m, RSTART+RLENGTH)

            # Get true_text
            if (!match(m, "^{[^}]*}"))
                error("(dosubs) Bad true_text in '" m "':" $0)
            true_text = substr(m, RSTART+1, RLENGTH-2)
            dbg_print("dosubs", 7, "(dosubs) ifdef: true_text='" true_text "'")
            m = substr(m, RSTART+RLENGTH)

            # Get false_text
            if (!match(m, "^{[^}]*}"))
                error("(dosubs) Bad false_text in '" m "':" $0)
            false_text = substr(m, RSTART+1, RLENGTH-2)
            dbg_print("dosubs", 7, "(dosubs) ifdef: if_false='" false_text "'")
            m = substr(m, RSTART+RLENGTH)
            if (!emptyp(m))
                error("(dosubs) Extra text in ifdef: m='" m "'")

            r = dosubs(evaluate_boolean(ifcond, init_negate) ? true_text : false_text) r

        # ifelse: Evaluate argument pairs for equality.
        #
        # @ifelse@ has three or more arguments.
        # If the first argument is equal to the second,
        #    then the value is the third argument.
        # If not, and if there are more than four arguments,
        #    the process is repeated with arguments 4, 5, 6, and 7.
        # Otherwise, the value is either the fourth argument, or null if omitted.
        } else if (fn == "ifelse") {
            # NOTE: All of the {} clauses must be on the same line,
            # since dosubs CANNOT call readline().
            m = substr(m, 7)    # strip away "ifelse"
            arg[1] = arg[2] = arg[3] = ""
            while (TRUE) {
                dbg_print("dosubs", 5, "(dosubs) [@ifelse@] TOP; m=" m)

                # Check that at least three pairs of braces are present,
                # and whatever remains are also well-formed brace pairs.
                # Pathological syntax (like {..\}..} will cause problems.
                if (! match(m, "^{[^}]+}{[^}]*}{[^}]*}({[^}]*})*$"))
                    error("(ifelse) Bad parameters in '" m "':" $0)

                # Grab the first three arguments
                for (j = 1; j <= 3; j++) {
                    match(m, "{[^}]*}")
                    arg[j] = substr(m, RSTART+1, RLENGTH-2)
                    m = substr(m, RSTART+RLENGTH)
                    dbg_print("dosubs", 7, sprintf("(dosubs) [@ifelse@] arg%d='%s'",
                                                   j, arg[j]))
                }

                # Check arg1 & arg2 for equality...  TODO integer check -> 0+n
                # If the first argument is equal to the second,
                #    then the value is the third argument.
                if (arg[1] == arg[2]) {
                    expand = arg[3]
                    break
                }
                # At this point, the three required args have been
                # stripped out of m.  What remains in m could be:
                # 1. Empty - no fourth argument, so use empty string.
                if (m == EMPTY) {
                    expand = ""
                    break
                }
                # 2. Exactly one brace clause remains; it is the fourth
                # (last) argument, so use it.
                if (match(m, "^{[^}]*}$")) {
                    # expand = "cc:<" substr(m, 2, length(m) - 2) ">"
                    expand = substr(m, 2, length(m) - 2)
                    break
                }
                # 3. If there are more than four args, there have to be a
                # minimum number to allow the cycle to continue.
                # You need  {1}{2}{3}  ||  {4}{5}{6} [ {7} ]
                #                      ||  {1}{2}{3}
                # which means that just one or two pairs of braces
                # constitute invalid syntax.  The one pair case was
                # caught in choice 2 just above, so we check for two pairs
                if (match(m, "^{[^}]+}{[^}]*}$"))
                    error("(ifelse) Bad parameters in '" m "':" $0)

                # # If not, and if there are more than four arguments,
                #    the process is repeated with arguments 4, 5, 6, and 7.
            }

            r = dosubs(expand) r

        # ifx: If Expression : Evaluate boolean expression to choose result text
        #   A and B are @ifx{A == B}{Equal}{Not equal}@
        } else if (fn == "ifx") {
            if (!match(m, "^ifx{[^}]+}{[^}]*}{[^}]*}$"))
                error("(dosubs) Bad ifx in '" m "':" $0)
            m = substr(m, index(m, TOK_LBRACE)) # strip fn name
            init_negate = FALSE

            # Get if_clause
            if (!match(m, "^{[^}]*}"))
                error("(dosubs) Bad ifcond in '" m "':" $0)
            ifcond = substr(m, RSTART+1, RLENGTH-2)
            dbg_print("dosubs", 7, "(dosubs) ifx: ifcond='" ifcond "'")
            m = substr(m, RSTART+RLENGTH)

            # Get true_text
            if (!match(m, "^{[^}]*}"))
                error("(dosubs) Bad true_text in '" m "':" $0)
            true_text = substr(m, RSTART+1, RLENGTH-2)
            dbg_print("dosubs", 7, "(dosubs) ifx: true_text='" true_text "'")
            m = substr(m, RSTART+RLENGTH)

            # Get false_text
            if (!match(m, "^{[^}]*}"))
                error("(dosubs) Bad false_text in '" m "':" $0)
            false_text = substr(m, RSTART+1, RLENGTH-2)
            dbg_print("dosubs", 7, "(dosubs) ifx: if_false='" false_text "'")
            m = substr(m, RSTART+RLENGTH)
            if (!emptyp(m))
                error("(dosubs) Extra text in ifx: m='" m "'")

            r = dosubs(evaluate_boolean(ifcond, init_negate) ? true_text : false_text) r

        # index: Location of substring
        #   NB - Awk index() returns 1 and so do we.  Different from m4.
        } else if (fn == "index") {
            if (nparam != 2)
                error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            x = param[2 + off_by]
            r = index(sym_fetch(p), x) r

        # lc : Lower case
        # len: Length
        # uc : Upper case
        #   @len ALPHABET@ => 26
        } else if (fn == "lc" ||
                   fn == "len" ||
                   fn == "uc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            r = ((fn == "lc")  ? tolower(sym_fetch(p)) : \
                 (fn == "len") ?  length(sym_fetch(p)) : \
                 (fn == "uc")  ? toupper(sym_fetch(p)) : \
                 error("Name '" m "' not defined [can't happen]:" $0)) \
                r   # ^^^ This error() bit can't happen but I need something
                    # to the right of the :, and error() will abend.

        # left: Left (substring)
        #   @left ALPHABET 7@ => ABCDEFG
        } else if (fn == "left") {
            if (nparam < 1 || nparam > 2) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            x = 1
            if (nparam == 2) {
                x = param[2 + off_by]
                if (!integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(sym_fetch(p), 1, x) r

        # mid: Substring ...  SYMBOL, START[, LENGTH]
        #   @mid ALPHABET 15 5@ => OPQRS
        #   @mid FOO 3@
        #   @mid FOO 2 2@
        } else if (fn == "mid" || fn == "substr") {
            if (nparam < 2 || nparam > 3)
                error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            x = param[2 + off_by]
            if (!integerp(x))
                error("Value '" x "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(sym_fetch(p), x) r
            } else if (nparam == 3) {
                y = param[3 + off_by]
                if (!integerp(y))
                    error("Value '" y "' must be numeric:" $0)
                r = substr(sym_fetch(p), x, y) r
            }

        # ord SYM: Output character with ASCII code SYM
        #   @define B *Nothing of interest*
        #   @ord A@ => 65
        #   @ord B@ => 42
        } else if (fn == "ord") {
            if (! __ord_initialized)
                initialize_ord()
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            if (sym_valid_p(p) && sym_defined_p(p))
                p = sym_fetch(p)
            r = __ord[first(p)] r

        # rem: Remark
        #   @rem STUFF@ is considered a comment and ignored
        #   @srem STUFF@ like @rem, but preceding whitespace is also discarded
        } else if (fn == "rem" || fn == "srem") {
            if (first(fn) == "s")
                sub(/[ \t]+$/, "", l)

        # right: Right (substring)
        #   @right ALPHABET 20@ => TUVWXYZ
        } else if (fn == "right") {
            if (nparam < 1 || nparam > 2) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            x = length(sym_fetch(p))
            if (nparam == 2) {
                x = param[2 + off_by]
                if (!integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(sym_fetch(p), x) r

        # rot13 SYM: Output value of symbol with rot13 text
        #   @define aRealSymbol *With 6, you get value!*
        #   @rot13 aRealSymbol@    => *Jvgu 6, lbh trg inyhr!*
        #   @rot13 NotaRealSymbol@ => AbgnErnyFlzoby
        } else if (fn == "rot13") {
            if (! __rot13_initialized)
                initialize_rot13()
            if (nparam == 0) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            p = (sym_valid_p(p) && sym_defined_p(p)) \
                ? sym_fetch(p) : substr(m, length(fn)+2)
            expand = ""
            for (x = 1; x <= length(p); x++) {
                c = substr(p, x, 1)
                expand = expand  (match(c, "[a-zA-Z]") ? __rot13[c] : c)
            }
            r = expand r

        # spaces [N]: N spaces
        } else if (fn == "spaces") {
            if (nparam > 1) error("Bad parameters in '" m "':" $0)
            x = 1
            if (nparam == 1) {
                x = param[1 + off_by]
                if (!integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            while (x-- > 0)
                expand = expand TOK_SPACE
            r = expand r

        # trim  SYM: Remove both leading and trailing whitespace
        # ltrim SYM: Remove leading whitespace
        # rtrim SYM: Remove trailing whitespace
        } else if (fn == "trim" || fn == "ltrim" || fn == "rtrim") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            expand = sym_fetch(p)
            if (fn == "trim" || fn == "ltrim")
                #sub(/^[ \t]+/, "", expand)
                expand = ltrim(expand)
            if (fn == "trim" || fn == "rtrim")
                expand = rtrim(expand)
            r = expand r

        # uuid: Something that resembles but is not a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (fn == "uuid") {
            r = uuid() r

        # xbasename SYM: Base (i.e., file name) of path, using external program
        } else if (fn == "xbasename") {
            if (secure_level() >= 2)
                error("(xbasename) Security violation")
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            cmdline = build_prog_cmdline(fn, rm_quotes(sym_fetch(p)), MODE_IO_CAPTURE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # xdirname SYM: Directory name of path, using external program
        } else if (fn == "xdirname") {
            if (secure_level() >= 2)

                error("(xdirname) Security violation")
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            cmdline = build_prog_cmdline(fn, rm_quotes(sym_fetch(p)), MODE_IO_CAPTURE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # Old code for macro processing
        # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
        } else if (sym_valid_p(fn) && (sym_defined_p(fn) || sym_deferred_p(fn))) {
            expand = sym_fetch(fn)
            # Expand $# => nparam
            if (index(expand, "$#") > 0)
                gsub("\\$#", nparam, expand)
            # Expand $* to all parameters, space separated
            if (index(expand, "$*") > 0) {
                x = ""
                for (j = 1; j <= nparam; j++)
                    x = x  param[j + off_by]  TOK_SPACE
                gsub("\\$\\*", chop(x), expand)
            }
            # Expand $N parameters (includes $0 for macro name)
            # Re-using j, excuse me
            j = MAX_PARAM   # but don't go overboard with params
            # Count backwards to get around $10 problem.
            while (j-- >= 0) {
                if (index(expand, "${" j "}") > 0)
                    gsub("\\$\\{" j "\\}", (j <= nparam) ? param[j + off_by] : "", expand)
                if (index(expand, "$" j) > 0)
                    gsub("\\$"    j      , (j <= nparam) ? param[j + off_by] : "", expand)
            }
            r = expand r

        # Check if it's a sequence
        } else if (seq_valid_p(fn) && seq_defined_p(fn)) {
            dbg_print("dosubs", 3, "(dosubs) It's a sequence")
            # Check for pre/post increment/decrement.
            # This is only performe on a bare reference.
            if (nparam == 0) {
                #   |          | pre_post | inc_dec |
                #   |----------+----------+---------|
                #   | foo      |        0 |     n/a |
                #   | --foo    |       -1 |      -1 |
                #   | ++foo    |       -1 |      +1 |
                #   | foo--    |       +1 |      -1 |
                #   | foo++    |       +1 |      +1 |
                if (pre_post == 0) {
                    # normal call : insert current value with formatting
                    #print_stderr(sprintf("fn='%s', Injecting '%s'", fn, seq_ll_read(fn)))
                    r = sprintf(seqtab[fn, "fmt"], seq_ll_read(fn)) r
                } else {
                    # Handle prefix xor postfix increment/decrement
                    if (pre_post == -1)    # prefix
                        if (inc_dec == -1) # decrement
                            seq_ll_incr(fn, -seqtab[fn, "incr"])
                        else
                            seq_ll_incr(fn, seqtab[fn, "incr"])
                    # Get current value with desired formatting
                    r = sprintf(seqtab[fn, "fmt"], seq_ll_read(fn)) r
                    if (pre_post == +1)    # postfix
                        if (inc_dec == -1)
                            seq_ll_incr(fn, -seqtab[fn, "incr"])
                        else
                            #seq_ll_incr(fn, seqtab[fn, "incr"])
                            seq_ll_incr(fn)
                }
            } else {
                if (pre_post != 0)
                    error("Bad parameters in '" m "':" $0)
                subcmd = param[1 + off_by]
                # @ID currval@ and @ID nextval@ are similar to @ID@ and
                # @++ID@ but {curr,next}val eschew any formatting.
                if (nparam == 1) {
                    # These subcommands do not take any parameters
                    if (subcmd == "currval") {
                        # - currval :: Return current value of counter
                        # without modifying it.  Also, no prefix/suffix.
                        # (This reference to "prefix/suffix" is of
                        # historical interest: it refers to an earlier
                        # version of m2 which did not have full sequence
                        # value formatting.  Instead, you had two strings
                        # which printed before and after the value.)
                        r = seq_ll_read(fn) r
                    } else if (subcmd == "nextval") {
                        # - nextval :: Increment and return new value of
                        # counter.  No prefix/suffix.
                        seq_ll_incr(fn, seqtab[fn, "incr"])
                        r = seq_ll_read(fn) r
                    } else
                        error("Bad parameters in '" m "':" $0)
                } else {
                    # These take one or more params.  Nothing here!
                    error("Bad parameters in '" m "':" $0)
                }
            }

        # Throw an error on undefined symbol (strict-only)
        } else if (strictp("undef")) {
            error("Name '" m "' not defined [strict mode]:" $0)

        } else {
            l = l TOK_AT m
            r = TOK_AT r
        }
        i = index(r, TOK_AT)
    }

    dbg_print("dosubs", 3, sprintf("(dosubs) END; Out of loop => '%s'", l r))
    return l r
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       I N I T I A L I Z E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Nothing in this function is user-customizable, so don't touch
#
#*****************************************************************************
function initialize(    get_date_cmd, d, dateout, array, elem, i, date_ok)
{
    # Constants
    E                           = exp(1)
    IDX_NOT_FOUND               = 0
    LOG10                       = log(10)
    MAX_DBG_LEVEL               = 10
    MAX_PARAM                   = 20
    PI                          = atan2(0, -1)
    SEQ_DEFAULT_INCR            = 1
    SEQ_DEFAULT_INIT            = 0
    TAU                         = 8 * atan2(1, 1) # 2 * PI
    TERMINAL                    = 0    # Block zero means standard output

    # Block types and labels
    BLK_AGG                     = "A"; __blk_label[BLK_AGG]      = "AGG"
      OBJ_BLKNUM                = "b"; __blk_label[OBJ_BLKNUM]   = "BLKNUM"
      OBJ_CMD                   = "c"; __blk_label[OBJ_CMD]      = "CMD"
      OBJ_TEXT                  = "t"; __blk_label[OBJ_TEXT]     = "TEXT"
      OBJ_USER                  = "u"; __blk_label[OBJ_USER]     = "USER"
    BLK_CASE                    = "C"; __blk_label[BLK_CASE]     = "CASE"
    BLK_IF                      = "I"; __blk_label[BLK_IF]       = "IF"
    BLK_FOR                     = "R"; __blk_label[BLK_FOR ]     = "FOR"
    BLK_LONGDEF                 = "L"; __blk_label[BLK_LONGDEF]  = "LONGDEF"
    BLK_TERMINAL                = "T"; __blk_label[BLK_TERMINAL] = "TERMINAL"
    BLK_USER                    = "U"; __blk_label[BLK_USER]     = "USER"
    BLK_WHILE                   = "W"; __blk_label[BLK_WHILE]    = "WHILE"
    SRC_FILE                    = "F"; __blk_label[SRC_FILE]     = "FILE"
    SRC_STRING                  = "S"; __blk_label[SRC_STRING]   = "STRING"

    # Errors                          # ERRORS  
    ERR_OKAY                    =   0

    ERR_PARSE                   = 100
    ERR_PARSE_STACK             = 101
    ERR_PARSE_MISMATCH          = 102
    ERR_PARSE_DEPTH             = 103

    ERR_SCAN                    = 200
    ERR_SCAN_INVALID_NAME       = 201

    # Various modes
    MODE_AT_LITERAL             = "L" # atmode - scan literally
    MODE_AT_PROCESS             = "P" # atmode - scan with "@" macro processing
    MODE_IO_CAPTURE             = "C" # build command for getline
    MODE_IO_SILENT              = "X" # redirect >/dev/null 2>/dev/null
    MODE_TEXT_PRINT             = "P" # executed text is printed
    MODE_TEXT_STRING            = "S" # executed text is stored in a string
    MODE_STREAMS_DISCARD        = "D" # diverted streams final disposition
    MODE_STREAMS_SHIP_OUT       = "O" # diverted streams final disposition

    # When to flush standard output
    SYNC_FORCE                  = 0 # only on request or end of job
    SYNC_FILE                   = 1 # at end of each processed file; default.
    SYNC_LINE                   = 2 # after every printed line

    # Tokens used in boolean expression evaluation
    TOK_AND                     = "&&"
    TOK_AT                      = "@"
    TOK_COLON                   = ":"
    TOK_DEFINED_P               = "?D"
    TOK_ENV_P                   = "?E"
    TOK_EXISTS_P                = "?X"
    TOK_LBRACE                  = "{"
    TOK_LPAREN                  = "("
    TOK_NEWLINE                 = "\n"
    TOK_NOT                     = "!"
    TOK_OR                      = "||"
    TOK_RBRACE                  = "}"
    TOK_RPAREN                  = ")"
    TOK_TAB                     = "\t"

    # Execution control states for loops
    XEQ_NORMAL                  = 0
    XEQ_BREAK                   = 1
    XEQ_CONTINUE                = 2
    XEQ_RETURN                  = 3

    # Global variables
    __block_cnt                 = 0
    __buffer                    = EMPTY
    __init_files_loaded         = FALSE # Becomes True in load_init_files()
    __namespace                 = GLOBAL_NAMESPACE
    __ord_initialized           = FALSE # Becomes True in initialize_ord()
    __print_mode                = MODE_TEXT_PRINT
    __rot13_initialized         = FALSE # Becomes True in initialize_rot13()
    __parse_stack[0]            = 0
    __source_stack[0]           = 0
    __wrap_cnt                  = 0
    __xeq_ctl                   = XEQ_NORMAL

    srand()                     # Seed random number generator
    initialize_prog_paths()
    __inc_path = "M2PATH" in ENVIRON ? ENVIRON["M2PATH"] : ""

    if (secure_level() < 2) {
        # Set up some symbols that depend on external programs

        # Current date & time
        if ("date" in PROG) {
            # Capture m2 run start time.                 1  2  3  4  5  6  7  8
            get_date_cmd = build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z %s'", MODE_IO_CAPTURE)
            get_date_cmd | getline dateout
            close(get_date_cmd)
            split(dateout, d)

            sym_ll_fiat("__DATE__",         "", FLAGS_READONLY_INTEGER, d[1] d[2] d[3])
            sym_ll_fiat("__EPOCH__",        "", FLAGS_READONLY_INTEGER, d[8])
            sym_ll_fiat("__TIME__",         "", FLAGS_READONLY_SYMBOL,  d[4] d[5] d[6]) # not an INTEGER because I want leading 0 if before 12:00
            sym_ll_fiat("__TIMESTAMP__",    "", FLAGS_READONLY_SYMBOL,  d[1] "-" d[2] "-" d[3] \
                                                                    "T" d[4] ":" d[5] ":" d[6] d[7])
            sym_ll_fiat("__TZ__",           "", FLAGS_READONLY_SYMBOL,  d[7])
        }

        # Deferred symbols
        if ("id" in PROG) {
            sym_deferred_symbol("__GID__",      FLAGS_READONLY_INTEGER, "id", "-g")
            sym_deferred_symbol("__UID__",      FLAGS_READONLY_INTEGER, "id", "-u")
            sym_deferred_symbol("__USER__",     FLAGS_READONLY_SYMBOL,  "id", "-un")
        }
        if ("hostname" in PROG) {
            sym_deferred_symbol("__HOST__",     FLAGS_READONLY_SYMBOL,  "hostname", "-s")
            # OpenBSD's hostname(1) does not support the `-f' flag;
            # since it is already the default on FreeBSD, I just removed it.
            sym_deferred_symbol("__HOSTNAME__", FLAGS_READONLY_SYMBOL,  "hostname", "")
        }
        if ("uname" in PROG) {
            sym_deferred_symbol("__OSNAME__",   FLAGS_READONLY_SYMBOL,  "uname", "-s")
        }
        if ("sh" in PROG) {
            sym_deferred_symbol("__PID__",      FLAGS_READONLY_INTEGER, "sh", "-c 'echo $PPID'")
        }
    }

    nam_ll_write("__FMT__",    GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)
    nam_ll_write("__STRICT__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)

    if ("PWD" in ENVIRON)
      sym_ll_fiat("__CWD__",        "", FLAGS_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["PWD"]))
    else if (secure_level() < 2 && ("pwd" in PROG))
      sym_deferred_symbol("__CWD__",    FLAGS_READONLY_SYMBOL,  "pwd", "")
    sym_ll_fiat("__DIVNUM__",       "", FLAGS_READONLY_INTEGER, 0)
    sym_ll_fiat("__EXPR__",         "", FLAGS_READONLY_NUMERIC, 0.0)
    sym_ll_fiat("__FILE__",         "", FLAGS_READONLY_SYMBOL,  "")
    sym_ll_fiat("__FILE_UUID__",    "", FLAGS_READONLY_SYMBOL,  "")
    sym_ll_fiat("__FMT__",        TRUE, "",                     "1")
    sym_ll_fiat("__FMT__",       FALSE, "",                     "0")
    sym_ll_fiat("__FMT__",      "date", "",                     "%Y-%m-%d")
    sym_ll_fiat("__FMT__",     "epoch", "",                     "%s")
    sym_ll_fiat("__FMT__",    "number", "",                     CONVFMT)
    sym_ll_fiat("__FMT__",       "seq", "",                     "%d")
    sym_ll_fiat("__FMT__",      "time", "",                     "%H:%M:%S")
    sym_ll_fiat("__FMT__",        "tz", "",                     "%Z")
    if ("HOME" in ENVIRON)
      sym_ll_fiat("__HOME__",       "", FLAGS_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["HOME"]))
    sym_ll_fiat("__INPUT__",        "", FLAGS_WRITABLE_SYMBOL,  EMPTY)
    sym_ll_fiat("__LINE__",         "", FLAGS_READONLY_INTEGER, 0)
    sym_ll_fiat("__M2_UUID__",      "", FLAGS_READONLY_SYMBOL,  uuid())
    sym_ll_fiat("__M2_VERSION__",   "", FLAGS_READONLY_SYMBOL,  M2_VERSION)
    sym_ll_fiat("__NFILE__",        "", FLAGS_READONLY_INTEGER, 0)
    sym_ll_fiat("__NLINE__",        "", FLAGS_READONLY_INTEGER, 0)
    sym_ll_fiat("__MAX_STREAM__",   "", FLAGS_READONLY_INTEGER, MAX_STREAM)
    sym_ll_fiat("__STRICT__","boolval", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "env", "",                     TRUE)
    sym_ll_fiat("__STRICT__",   "file", "",                     TRUE)
    sym_ll_fiat("__STRICT__", "symbol", "",                     TRUE)
    sym_ll_fiat("__STRICT__",  "undef", "",                     TRUE)
    sym_ll_fiat("__SYNC__",         "", FLAGS_WRITABLE_INTEGER, SYNC_FILE)
    sym_ll_fiat("__SYSVAL__",       "", FLAGS_READONLY_INTEGER, 0)

    # FUNCS
    # Functions cannot be used as symbol or sequence names.
    split("basename boolval chr date dirname epoch expr getenv" \
          " ifdef ifelse ifndef ifx index lc left len ltrim mid ord rem" \
          " right rot13 rtrim sexpr sgetenv spaces srem strftime" \
          " substr time trim tz uc uuid xbasename xdirname",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_FUNCTION FLAG_SYSTEM)

    # CMDS
    # Built-in commands
    # Also need to add entry in execute__command()  [search: DISPATCH]
    split("append array cleardivert debug decr default define divert dump dumpall" \
          " echo error errprint eval exit ignore include incr initialize input local m2ctl" \
          " nextfile paste readfile readarray readonly secho sequence shell" \
          " sinclude spaste sreadfile sreadarray syscmd typeout undefine" \
          " undivert warn wrap", array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_COMMAND FLAG_SYSTEM)


    # IMMEDS
    # These commands are Immediate
    split("break case continue else endcase endcmd endif endlong" \
          " endlongdef endwhile esac fi for foreach if longdef" \
          " newcmd next of otherwise return unless until wend while",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_COMMAND FLAG_SYSTEM FLAG_IMMEDIATE)

    __flag_label[TYPE_ANY]       = "ANY"
    __flag_label[TYPE_ARRAY]     = "ARR"
    __flag_label[TYPE_COMMAND]   = "CMD"
    __flag_label[TYPE_USER]      = "USR"
    __flag_label[TYPE_FUNCTION]  = "FUN"
    __flag_label[TYPE_SEQUENCE]  = "SEQ"
    __flag_label[TYPE_SYMBOL]    = "SYM"

    __flag_label[FLAG_BLKARRAY]  = "BlkArray"
    __flag_label[FLAG_BOOLEAN]   = "Boolean"
    __flag_label[FLAG_DEFERRED]  = "Deferred"
    __flag_label[FLAG_IMMEDIATE] = "Immediate"
    __flag_label[FLAG_INTEGER]   = "Integer"
    __flag_label[FLAG_NUMERIC]   = "Numeric"
    __flag_label[FLAG_READONLY]  = "Read-only"
    __flag_label[FLAG_WRITABLE]  = "Writable"
    __flag_label[FLAG_SYSTEM]    = "System"

    # Zero stream buffers
    for (i = 1; i <= MAX_STREAM; i++)
        blk_new(BLK_AGG)       # initialize to empty agg block

    # Set up terminal to receive output
    __terminal = blk_new(BLK_TERMINAL)
    stk_push(__parse_stack, __terminal)
}


# Arnold Robbins, arnold@gnu.org, Public Domain
# 16 January, 1992
# 20 July, 1992, revised
function initialize_ord(    low, high, i, t)
{
    low = sprintf("%c", 7)      # BEL is ascii 7
    if (low == "\a") {          # regular ascii
        low = 0
        high = 127
    } else if (sprintf("%c", 128 + 7) == "\a") {
        low = 128               # ascii, mark parity
        high = 255
    } else {                    # ebcdic(!)
        low = 0
        high = 255
    }

    for (i = low; i <= high; i++) {
        t = sprintf("%c", i)
        __ord[t] = i
    }

    __ord_initialized = TRUE
}


# From the ROT13 page:  http://www.miranda.org/~jkominek/rot13/
# Maintained by Jay Kominek <jkominek-rot13@miranda.org>
# https://web.archive.org/web/20090308134550/http://www.miranda.org/~jkominek/rot13/awk/rot13.awk
# Rot13 in Awk                          Teknovore <tek@wiw.org> 1998
function initialize_rot13(    from, to, i)
{
    from = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    to   = "NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm"
    for (i = 1; i <= length(from); i++)
        __rot13[substr(from, i, 1)] = substr(to, i, 1)
    __rot13_initialized = TRUE
}


# It is important that __PROG__ remain a read-only symbol.  Otherwise,
# some bad person could entice you to evaluate:
#       @define __PROG__[stat]  /bin/rm
#       @include my_precious_file
function initialize_prog_paths()
{
    sym_ll_fiat("__TMPDIR__", "",       FLAGS_WRITABLE_SYMBOL,  "/tmp/")

    nam_ll_write("__PROG__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_READONLY FLAG_SYSTEM)
    if ("basename" in PROG)
        sym_ll_fiat("__PROG__", "basename", FLAGS_READONLY_SYMBOL, PROG["basename"])
    if ("date" in PROG)
        sym_ll_fiat("__PROG__", "date",     FLAGS_READONLY_SYMBOL, PROG["date"])
    if ("dirname" in PROG)
        sym_ll_fiat("__PROG__", "dirname",  FLAGS_READONLY_SYMBOL, PROG["dirname"])
    if ("hostname" in PROG)
        sym_ll_fiat("__PROG__", "hostname", FLAGS_READONLY_SYMBOL, PROG["hostname"])
    if ("id" in PROG)
        sym_ll_fiat("__PROG__", "id",       FLAGS_READONLY_SYMBOL, PROG["id"])
    if ("pwd" in PROG)
        sym_ll_fiat("__PROG__", "pwd",      FLAGS_READONLY_SYMBOL, PROG["pwd"])
    if ("rm" in PROG)
        sym_ll_fiat("__PROG__", "rm",       FLAGS_READONLY_SYMBOL, PROG["rm"])
    if ("sh" in PROG)
        sym_ll_fiat("__PROG__", "sh",       FLAGS_READONLY_SYMBOL, PROG["sh"])
    if ("stat" in PROG)
        sym_ll_fiat("__PROG__", "stat",     FLAGS_READONLY_SYMBOL, PROG["stat"])
    if ("uname" in PROG)
        sym_ll_fiat("__PROG__", "uname",    FLAGS_READONLY_SYMBOL, PROG["uname"])
}


# Try to read init files: $M2RC, $HOME/.m2rc, and/or ./.m2rc
# M2RC is intended to *override* $HOME (in case HOME is unavailable or
# otherwise unsuitable), so if the variable is specified and the file
# exists, then do that file; only otherwise do $HOME/.m2rc.  An init
# file from the current directory is always attempted in any case.
# No worries or errors if any of them don't exist.
function load_init_files(    old_debug)
{
    # Don't load the init files more than once
    if (__init_files_loaded == TRUE)
        return

    # If debugging is enabled, temporarily disable it while loading the
    # init files.  We presumably don't need it for files we don't want
    # to check.  Be careful to manipulate the symbol table directly!  We
    # don't want to trigger the special __DEBUG__ processing that is
    # baked into sym_ll_write().
    old_debug = symtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"]
    symtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = FALSE

    if ("M2RC" in ENVIRON && path_exists_p(ENVIRON["M2RC"]))
        dofile(ENVIRON["M2RC"])
    else if ("HOME" in ENVIRON)
        dofile(ENVIRON["HOME"] "/.m2rc")
    dofile("./.m2rc")

    # Don't count init files in total line/file tally - it's better to
    # keep them in sync with the files from the command line.
    sym_ll_write("__NFILE__", "", GLOBAL_NAMESPACE, 0)
    sym_ll_write("__NLINE__", "", GLOBAL_NAMESPACE, 0)

    # Restore debugging, if any, and we're done
    symtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = old_debug
    __init_files_loaded = TRUE
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       M A I N
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       The MAIN program occurs in the BEGIN procedure below.
#
#*****************************************************************************
BEGIN {
    initialize()

    # No command line arguments: process standard input.
    if (ARGC == 1) {
        load_init_files()
        __exit_code = dofile("-") ? EX_OK : EX_NOINPUT

    # Else, process all command line files/macro definitions.  ARGC is never zero,
    # so if it's not 1 (no command line args), there must be parameters.
    } else {
        # Delay loading $HOME/.m2rc as long as possible.  This allows us
        # to set symbols on the command line which will have taken effect
        # by the time the init file loads.
        for (_i = 1; _i < ARGC; _i++) {
            # Show each arg as we process it
            _arg = ARGV[_i]
            dbg_print("args", 3, ("BEGIN: ARGV[" _i "]:" _arg))

            # If it's a definition on the command line, define it
            if (_arg ~ /^([^= ][^= ]*)=(.*)/) {
                _eq = index(_arg, "=")
                _name = substr(_arg, 1, _eq-1)
                _val = substr(_arg, _eq+1)
                if (_name == "debug") {
                    _name = "__DEBUG__"
                } else if (_name == "I") {
                    # Include-path elements on command-line are prepended
                    # to M2PATH so they override env variable values.
                    __inc_path = _val (emptyp(__inc_path) ? "" : ":" __inc_path)
                    continue
                } else if (_name == "init") {
                    if (_val == 0) {
                        # Do not load the init files.  Inhibit init file
                        # loading by pretending we already did it.
                        __init_files_loaded = TRUE
                    } else if (_val > 0) {
                        # Positive value loads init files without
                        # providing a command-line file.
                        load_init_files()
                    }
                    continue
                } else if (_name == "secure") {
                    _name = "__SECURE__"
                } else if (_name == "strict") {
                    if (_val == 0) {
                        # Turn off strict settings
                        sym_ll_write("__STRICT__","boolval", GLOBAL_NAMESPACE, FALSE)
                        sym_ll_write("__STRICT__",    "env", GLOBAL_NAMESPACE, FALSE)
                        sym_ll_write("__STRICT__",   "file", GLOBAL_NAMESPACE, FALSE)
                        sym_ll_write("__STRICT__", "symbol", GLOBAL_NAMESPACE, FALSE)
                        sym_ll_write("__STRICT__",  "undef", GLOBAL_NAMESPACE, FALSE)
                    } else if (_val > 0)  {
                        # Turn on strict settings
                        sym_ll_write("__STRICT__","boolval", GLOBAL_NAMESPACE, TRUE)
                        sym_ll_write("__STRICT__",    "env", GLOBAL_NAMESPACE, TRUE)
                        sym_ll_write("__STRICT__",   "file", GLOBAL_NAMESPACE, TRUE)
                        sym_ll_write("__STRICT__", "symbol", GLOBAL_NAMESPACE, TRUE)
                        sym_ll_write("__STRICT__",  "undef", GLOBAL_NAMESPACE, TRUE)
                    }
                    continue
                }
                if (!sym_valid_p(_name))
                    error("Name '" _name "' not valid:" _arg, "ARGV", _i)
                if (sym_protected_p(_name))
                    error("Symbol '" _name "' protected:" _arg, "ARGV", _i)
                if (!nam_ll_in(_name, GLOBAL_NAMESPACE))
                    error("Name '" _name "' not available:" _arg, "ARGV", _i)
                sym_store(_name, _val)

            # Otherwise load a file
            } else {
                load_init_files()
                if (! dofile(rm_quotes(_arg))) {
                    warn("File '" _arg "' does not exist", "ARGV", _i)
                    __exit_code = EX_NOINPUT
                }
            }
        }

        # If we get here with __init_files_loaded still false, that means
        # we used up every ARGV defining symbols and didn't specify any
        # files.  Not specifying any input files, like ARGC==1, means to
        # read standard input, so that is what we must now do.
        if (!__init_files_loaded) {
            load_init_files()
            __exit_code = dofile("-") ? EX_OK : EX_NOINPUT
        }
    }

    # Under normal execution, all blocks should have been popped from
    # the parse stack, so check that.  There should only be the terminal
    # block (created in initialize) remaining but we can't remove it
    # because we might need it in end_program to ship out diversions and
    # wraps.  I also can't move this check into end_program(), because
    # that routine might be called during execution with parsers still
    # present on the stack.
    if (stk_depth(__parse_stack) != 1) {
        warn("(main) Parse stack is not empty!")
        dump_parse_stack()
    }

    end_program(MODE_STREAMS_SHIP_OUT)
}


# Prepare to exit.  Normally, diverted_streams_final_disposition is
# MODE_STREAMS_SHIP_OUT, so we usually undivert all pending streams.
# When diverted_streams_final_disposition is MODE_STREAMS_DISCARD, any
# diverted data is dropped.  Standard output is always flushed, and
# program exits with value from global variable __exit_code.
function end_program(diverted_streams_final_disposition,
                     i)
{
    if (__exit_code == EX_OK  &&
        diverted_streams_final_disposition == MODE_STREAMS_SHIP_OUT) {

        # In the normal case of MODE_STREAMS_SHIP_OUT, ship out any remaining
        # diverted data.  See "STREAMS & DIVERSIONS" documentation above
        # to see how the user can prevent this, if desired.
        #
        # Regardless of whether the parse stack is empty or not, streams
        # which ship out when m2 ends must go to standard output.  So
        # always create a TERMINAL block to receive this data.  Since
        # the program is about to terminate anyway, we don't care about
        # managing the parse stack from here on out.
        sym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, TERMINAL)
        undivert_all()

        # Execute any wrapped text/commands
        if (__wrap_cnt > 0)
            for (i = 1; i <= __wrap_cnt; i++) {
                dostring(dosubs(__wrap_text[i]))
            }
    }

    flush_stdout(SYNC_FORCE)
    if (debugp())
        print_stderr("m2:END M2")
    exit __exit_code
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
