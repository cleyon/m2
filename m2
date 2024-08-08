#!/usr/bin/awk -f
#!/usr/local/bin/mawk -f
#!/usr/local/bin/gawk -f

#*********************************************************** -*- mode: Awk -*-
#
#  File:        m2
#  Time-stamp:  <2024-08-08 10:27:28 cleyon>
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
    M2_VERSION    = "4.0.0_pre2"

    # Customize these paths as needed for correct operation on your system.
    # If a program is not available, it's okay to remove the entry entirely.
    __secure_level   = 0        # secure_level 2 prevents invoking these programs
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

    # Do not change anything below this line
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
    return (last(s) == "\n") ? chop(s) : s
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


function ppf_bool(x)
{
    return (x == 0 || x == "") ? "FALSE" : "TRUE"
}


function integerp(pat)
{
    return pat ~ /^[-+]?[0-9]+$/
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
    return nsym_ll_read("__SECURE__", "", GLOBAL_NAMESPACE)
}


function strictp(ssys)
{
    if (ssys == EMPTY)
        error("(strictp) ssys cannot be empty!")
    # Use low-level function here, not nsym_true_p(), to prevent infinite loop
    return nsym_ll_read("__STRICT__", ssys, GLOBAL_NAMESPACE)
}


function build_prog_cmdline(prog, arg, mode)
{
    if (! nsym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        error(sprintf("build_prog_cmdline: __PROG__[%s] not defined", prog))
    return sprintf("%s %s%s", \
                   nsym_ll_read("__PROG__", prog, GLOBAL_NAMESPACE),  \
                   arg, \
                   ((mode == MODE_IO_SILENT) ? " >/dev/null 2>/dev/null" : EMPTY))
}


function exec_prog_cmdline(prog, arg,    sym)
{
    if (secure_level() >= 2)
        error("(exec_prog_cmdline) Security violation")

    if (! nsym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        error(sprintf("(exec_prog_cmdline) __PROG__[%s] not defined", prog))
    return system(build_prog_cmdline(prog, arg, MODE_IO_SILENT)) # always silent
}


# Return a likely path for storing temporary files.
# This path is guaranteed to end with a "/" character.
function tmpdir(    t)
{
    if (nsym_defined_p("M2_TMPDIR"))
        t = nsym_fetch("M2_TMPDIR")
    else if ("TMPDIR" in ENVIRON)
        t = ENVIRON["TMPDIR"]
    else
        t = nsym_ll_read("__TMPDIR__", "", GLOBAL_NAMESPACE)
    while (last(t) == "\n")
        t = chop(t)
    return with_trailing_slash(t)
}


function default_shell()
{
    if (nsym_defined_p("M2_SHELL"))
        return nsym_fetch("M2_SHELL")
    if ("SHELL" in ENVIRON)
        return ENVIRON["SHELL"]
    return nsym_ll_read("__PROG__", "sh", GLOBAL_NAMESPACE)
}


function curr_atmode(    top_block)
{
    if (nstk_emptyp(__scan_stack))
        error("(curr_atmode) Scan stack is empty!")
    top_block = nstk_top(__scan_stack)
    dbg_print_block("ship_out", 7, top_block, "(curr_atmode) top_block [top of __scan_stack]")
    if (! ( (top_block,"atmode") in nblktab) ) {
        error("(curr_atmode) Top block " top_block " does not have 'atmode'")
    }
    return nblktab[top_block, "atmode"]
}


function curr_dstblk(    top_block)
{
    if (nstk_emptyp(__scan_stack))
        error("(curr_dstblk) Scan stack is empty!")
    top_block = nstk_top(__scan_stack)
    dbg_print_block("ship_out", 7, top_block, "(curr_dstblk) top_block [top of __scan_stack]")
    if (! ( (top_block, "dstblk") in nblktab) ) {
        error("(curr_dstblk) Top block " top_block " does not have 'dstblk'")
    }
    return nblktab[top_block, "dstblk"] + 0
}


function ppf_mode(mode)
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
    #     error("(ppf_mode) Unknown mode '" mode "'")
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
    nsym_purge(__namespace)
    nnam_purge(__namespace)
    __namespace--
    dbg_print("namespace", 4, "(lower_namespace) namespace now " __namespace)
    return __namespace
}


function assert_scan_stack_okay(expected_blk_type,
                                blknum)
{
    if (nstk_emptyp(__scan_stack))
        error("(assert_scan_stack_okay) Scan stack is empty!")
    blknum = nstk_top(__scan_stack)
    if ((nblktab[blknum, "type"] != expected_blk_type) ||
        # We have to subtract 1 because the original "depth" was stored
        # before the block was pushed onto the __scan_stack; and at this
        # point it hasn't been popped yet...
        (nblktab[blknum, "depth"] != nstk_depth(__scan_stack) - 1))
        error("(assert_scan_stack_okay) Corrupt scan stack")
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

        while (length(mtext) >= 2 && first(mtext) == "@" && last(mtext) == "@")
            mtext = substr(mtext, 2, length(mtext) - 2)
        s = !emptyp(mtext) ? ltext dosubs("@" mtext "@") rtext \
                           : ltext                       rtext
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
        } else if (c == "}") {
            dbg_print("braces", 3, ("<< find_closing_brace: => " start+offset))
            return start+offset
        } else if (c == "\\" && nc == "}") {
            # "\}" in expansion text will result in a single close brace
            # without ending the expansion text scanner.  Skip over }
            # and do not return yet.  "\}" is fixed in expand_braces().
            offset++; nc = substr(s, start+offset+1, 1)
        } else if (c == "@" && nc == "{") {
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
        file = nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
    if (file == "/dev/stdin" || file == "-")
        file = "<STDIN>"
    line = line ""
    if (line == EMPTY)
        line = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)

    # If file and line are provided with default values, why is the if()
    # guard still necessary?  Ah, because this function might get invoked
    # very early in m2 execution, before the symbol table is populated.
    # The defaults are therefore empty, resulting in superfluous ":"s.
              s =   "m2" ":"
    if (file) s = s file ":"
    if (line) s = s line ":"
    if (text) s = s text
    return s
}


function flush_stdout(flushlev)
{
    if (flushlev <= nsym_ll_read("__SYNC__", "", GLOBAL_NAMESPACE)) {
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
# Return OKAY, ERROR, or EOF.  scan() is the only caller of readline.
function readline(    getstat, i)
{
    getstat = OKAY
    if (!emptyp(__buffer)) {
        # Return the buffer even if somehow it doesn't end with a newline
        if ((i = index(__buffer, "\n")) == IDX_NOT_FOUND) {
            $0 = __buffer
            __buffer = EMPTY
        } else {
            $0 = substr(__buffer, 1, i-1)
            __buffer = substr(__buffer, i+1)
        }
    } else {
        getstat = getline < nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
        if (getstat == ERROR) {
            warn("(readline) getline=>Error reading file '" nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE) "'")
        } else if (getstat != EOF) {
            nsym_increment("__LINE__", 1)
            nsym_increment("__NLINE__", 1)
        }
    }
    dbg_print("io", 6, sprintf("(readline) returns %d, $0='%s'", getstat, $0))
    return getstat
}


# Read multiple lines until regexp is seen on a line and return TRUE.  If is not found,
# return FALSE.  The lines are always read literally.  Special case if
# regexp is "": read until end of file and return whatever is found,
# without error.
function read_lines_until(regexp, dstblk,
                          readstat)
{
    dbg_print("scan", 3, sprintf("(read_lines_until) START; regexp='%s', dstblk=%d",
                                 regexp, dstblk))
    if (dstblk == TERMINAL)
        error("(read_lines_until) dstblk must not be 0")

    while (TRUE) {
        readstat = readline()   # OKAY, EOF, ERROR
        if (readstat == ERROR) {
            # Whatever just happened, the read didn't finish properly
            dbg_print("scan", 1, "(read_lines_until) readline()=>ERROR")
            return FALSE
        }
        if (readstat == EOF) {
            dbg_print("scan", 5, "(read_lines_until) readline()=>EOF")
            return regexp == EMPTY
        }

        dbg_print("scan", 5, "(read_lines_until) readline()=>OKAY; $0='" $0 "'")
        if (regexp != EMPTY && match($0, regexp)) {
            dbg_print("scan", 5, "(read_lines_until) END => TRUE")
            return TRUE
        }

        if (dstblk > 0)
            nblk_append(dstblk, SLOT_TEXT, $0)
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
    nnamtab["__SECURE__",     GLOBAL_NAMESPACE] = FLAGS_WRITABLE_INTEGER
    nsymtab["__SECURE__", "", GLOBAL_NAMESPACE, "symval"] = __secure_level

    # Early initialize debug configuration.  This makes `gawk --lint' happy.
    nnamtab["__DEBUG__",      GLOBAL_NAMESPACE] = FLAGS_WRITABLE_BOOLEAN
    nsymtab["__DEBUG__", "",  GLOBAL_NAMESPACE, "symval"] = FALSE

    nnamtab["__DBG__", GLOBAL_NAMESPACE] = TYPE_ARRAY FLAG_SYSTEM
    split("args block braces case del divert dosubs dump expr for if io namespace" \
          " ncmd nnam nseq nstk nsym read scan ship_out symbol while xeq",
          _dbg_sys_array, " ")
    for (_dsys in _dbg_sys_array) {
        __dbg_sysnames[_dbg_sys_array[_dsys]] = TRUE
    }
}


# This function is called automagically (it's baked into nsym_ll_write())
# every time a non-zero value is stored into __DEBUG__.
function initialize_debugging()
{
   #dbg_set_level("args",       1)
    dbg_set_level("block",      0)
   #dbg_set_level("braces",     0)
    dbg_set_level("case",       5)
    dbg_set_level("del",        5)
    dbg_set_level("divert",     1)
    dbg_set_level("dosubs",     7)
    dbg_set_level("dump",       5)
   #dbg_set_level("expr",       0)
    dbg_set_level("for",        5)
    dbg_set_level("if",         7)
    dbg_set_level("io",         3)
    dbg_set_level("namespace",  5)
    dbg_set_level("ncmd",       5)
    dbg_set_level("nnam",       3)
    dbg_set_level("nseq",       3)
    dbg_set_level("nstk",       5)
    dbg_set_level("nsym",       5)
   #dbg_set_level("read",       0)
    dbg_set_level("scan",       5)
    dbg_set_level("ship_out",   5)
   #dbg_set_level("symbol",     0)
    dbg_set_level("while",      5)
    dbg_set_level("xeq",        5)

    nsym_ll_write("__STRICT__", "cmd", GLOBAL_NAMESPACE, TRUE)
    nsym_ll_write("__SYNC__", "", GLOBAL_NAMESPACE, 2)
}


function clear_debugging(    dsys)
{
    for (dsys in _dbg_sys_array)
        nsym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, 0)

    # dbg_set_level("args",       0)
    # dbg_set_level("block",      0)
    # dbg_set_level("braces",     0)
    # dbg_set_level("case",       0)
    # dbg_set_level("del",        0)
    # dbg_set_level("divert",     0)
    # dbg_set_level("dosubs",     0)
    # dbg_set_level("dump",       0)
    # dbg_set_level("expr",       0)
    # dbg_set_level("for",        0)
    # dbg_set_level("if",         0)
    # dbg_set_level("io",         0)
    # dbg_set_level("namespace",  0)
    # dbg_set_level("ncmd",       0)
    # dbg_set_level("nnam",       0)
    # dbg_set_level("nseq",       0)
    # dbg_set_level("nstk",       0)
    # dbg_set_level("nsym",       0)
    # dbg_set_level("read",       0)
    # dbg_set_level("scan",       0)
    # dbg_set_level("ship_out",   0)
    # dbg_set_level("symbol",     0)
    # dbg_set_level("while",      0)
    # dbg_set_level("xeq",        0)
}


function debugp()
{
    return nsym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE)+0 > 0
}


# Predicate: TRUE if debug system level >= provided level (lev).
# Example:
#     if (dbg("nsym", 3))
#         warn("Debugging nsym at level 3 or higher")
# NB - do NOT call nsym_defined_p() here, you will get infinite recursion
function dbg(dsys, lev)
{
    if (lev == EMPTY)           lev = 1
    if (dsys == EMPTY)          error("(dbg) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) error("Unknown dsys name '" dsys "' (lev=" lev "): " $0)
    if (lev < 0)                return TRUE
    if (!debugp())              return FALSE
    if (lev == 0)               return TRUE
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    if (!nsym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
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
    if (! (dsys in __dbg_sysnames)) error("Unknown dsys name '" dsys "'")
    # return (nsym_fetch(sprintf("%s[%s]", "__DBG__", dsys))+0) \
    if (!nsym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
        return 0
    return (nsym_ll_read("__DBG__", dsys, GLOBAL_NAMESPACE)+0) \
         * (debugp() ? 1 : -1)
}


# Set the level (lev) for the debug dsys
function dbg_set_level(dsys, lev)
{
    if (dsys == EMPTY)           error("(dbg_set_level) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) error("Unknown dsys name '" dsys "'")
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
    nsym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, lev+0)
}


function dbg_print(dsys, lev, text,
                   retval)
{
    if (dbg(dsys, lev))
        print_stderr(text)
}


function dbg_print_block(dsys, lev, blknum, description,
                         blk_type, blk_label, text)
{
    if (! dbg(dsys, lev))
        return
    blknum = blknum+0
    # print_stderr("(dbg_print_block) blknum = " blknum)
    if (! ( (blknum,"type") in nblktab) )
        error("(dbg_print_block) No 'type' field for block " blknum)
    blk_type = nblktab[blknum, "type"]
    blk_label = ppf_block_type(blk_type)
    # print_stderr("(dbg_print_block) blk_type = " blk_type)

    if      (blk_type == BLK_AGG)    text = prt_blk__agg(blknum)
    else if (blk_type == BLK_CASE)   text = prt_blk__case(blknum)
    else if (blk_type == BLK_FILE)   text = prt_blk__file(blknum)
    else if (blk_type == BLK_FOR)    text = prt_blk__for(blknum)
    else if (blk_type == BLK_IF)     text = prt_blk__if(blknum)
    else if (blk_type == BLK_REGEXP) text = prt_blk__regexp(blknum)
    else if (blk_type == BLK_USER)   text = prt_blk__user(blknum)
    else if (blk_type == BLK_WHILE)  text = prt_blk__while()
    else
        error(sprintf("(dbg_print_block) Can't handle type '%s' for block %d",
                      nblk_type(blknum), blknum))

    print_stderr(sprintf("Block # %d [%s]: %s", blknum, blk_label, description))
    print_stderr(text)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       B L O C K   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function nblk_new(blk_type,
                  new_blknum)
{
    if (blk_type == EMPTY)
        error("(nblk_new) Missing type")
    new_blknum = ++__block_cnt
    nblktab[new_blknum, "depth"] = nstk_depth(__scan_stack)
    nblktab[new_blknum, "type"] = blk_type
    nblktab[new_blknum, "atmode"] = nstk_emptyp(__scan_stack) \
                                      ? MODE_AT_PROCESS : curr_atmode()
    if (blk_type == BLK_AGG)
        nblktab[new_blknum, "count"] = 0
    else if (blk_type == BLK_CASE)
        nblktab[new_blknum, "terminator"] = "@endcase|@esac"
    else if (blk_type == BLK_IF)
        nblktab[new_blknum, "terminator"] = "@endif|@fi"
    else if (blk_type == BLK_REGEXP)
        ;                       # Caller must set up desired terminator
    else if (blk_type == BLK_FILE) {
        nblktab[new_blknum, "terminator"] = ""
        nblktab[new_blknum, "oob_terminator"] = "EOF"
    } else if (blk_type == BLK_FOR)
        nblktab[new_blknum, "terminator"] = "@next"
    else if (blk_type == BLK_LONGDEF)
        nblktab[new_blknum, "terminator"] = "@endlong|@endlongdef"
    else if (blk_type == BLK_TERMINAL) {
        nblktab[new_blknum, "atmode"] = MODE_AT_LITERAL
        nblktab[new_blknum, "dstblk"] = TERMINAL
    } else if (blk_type == BLK_USER)
        nblktab[new_blknum, "terminator"] = "@endcmd"
    else if (blk_type == BLK_WHILE)
        nblktab[new_blknum, "terminator"] = "@endwhile"
    else
        error("(nblk_new) Uncaught blk_type '" blk_type "'")

    dbg_print("ship_out", 1, sprintf("(nblk_new) Block # %d; type=%s",
                                      new_blknum, ppf_block_type(blk_type)))
    return new_blknum
}


function nblk_type(blknum)
{
    if (! ((blknum,"type") in nblktab))
        error("(nblk_type) Block # " blknum " has no type!")

    return nblktab[blknum, "type"]
}


function nblk_ll_slot_type(blknum, slot,
                           x, k)
{
    if      ((blknum, slot, SLOT_CMD) in nblktab)
        return SLOT_CMD
    else if ((blknum, slot, SLOT_BLKNUM) in nblktab)
        return SLOT_BLKNUM
    else if ((blknum, slot, SLOT_TEXT) in nblktab)
        return SLOT_TEXT
    else if ((blknum, slot, SLOT_USER) in nblktab)
        return SLOT_USER
    else
        error("(nblk_ll_slot_type) Not found: blknum=" blknum ", slot=" slot)
}


function nblk_ll_slot_value(blknum, slot,
                           x, k)
{
    if ((blknum, slot, SLOT_CMD) in nblktab)
        return nblktab[blknum, slot, SLOT_CMD]
    else if ((blknum, slot, SLOT_BLKNUM) in nblktab)
        return nblktab[blknum, slot, SLOT_BLKNUM] + 0
    else if ((blknum, slot, SLOT_TEXT) in nblktab)
        return nblktab[blknum, slot, SLOT_TEXT]
    else if ((blknum, slot, SLOT_USER) in nblktab)
        return nblktab[blknum, slot, SLOT_USER]
    else
        error("(nblk_ll_slot_value) Not found: blknum=" blknum ", slot=" slot)
}


function nblk_ll_write(blknum, slot, type, new_val)
{
    return nblktab[blknum, slot, type] = new_val
}


function nblk_append(blknum, slot_type, value,
                     slot)
{
    if (nblktab[blknum, "type"] != BLK_AGG)
        error(sprintf("(nblk_append) Block %d has type %s, not AGG",
                      blknum, ppf_block_type(nblk_type(blknum))))

    if (slot_type != SLOT_CMD  && slot_type != SLOT_BLKNUM &&
        slot_type != SLOT_TEXT && slot_type != SLOT_USER)
        error(sprintf("(nblk_append) Argument has bad type %s; should be SLOT_{CMD,BLKNUM,TEXT,USER}", ppf_block_type(slot_type)))

    slot = ++nblktab[blknum, "count"]
    dbg_print("ship_out", 3,
              sprintf("(nblk_append) blknum=%d, slot=%d, slot_type=%s, value='%s'",
                      blknum, slot, ppf_block_type(slot_type), value))
    nblk_ll_write(blknum, slot, slot_type, value)
}


function nblk_dump_nblktab(    x, k, blknum, seen, type)
{
    for (k in nblktab) {
        split(k, x, SUBSEP)
        # if (x[2]+0 >= level)
        #     del_list[x[1], x[2]] = TRUE
        blknum = x[1] + 0
#        print_stderr(">" blknum "<")
        if (! (blknum in seen)) {
            type = nblk_type(blknum+0)
#            print_stderr(">> type=" type " <<")
            dbg_print_block("xeq", -1, blknum, "(nblk_dump_nblktab)")
        }
        seen[blknum]++
    }
}


function nblk_to_string(blknum,
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


function ppf_block_type(blk_type)
{
    if (blk_type == EMPTY)
        warn("(ppf_block_type) blk_type is empty, how did that happen?")
    dbg_print("xeq", 7, "(ppf_block_type) blk_type = " blk_type)
    if (! (blk_type in __blk_label)) {
        error("(ppf_block_type) Invalid block type '" blk_type "'")
    }
    return __blk_label[blk_type]
}


function ship_out__block(blknum,
                         dstblk, stream)
{
    dstblk = curr_dstblk()
    dbg_print("ship_out", 3, sprintf("(ship_out__block) START dstblk=%d, blknum=%d",
                                     dstblk, blknum))

    if (dstblk < 0) {
        dbg_print("ship_out", 3, "(ship_out__block) END because dstblk <0")
        return
    }
    if (dstblk > MAX_STREAM) {
        dbg_print("ship_out", 5, sprintf("(ship_out__block) END Appending block %d to block %d", blknum, dstblk))
        nblk_append(dstblk, SLOT_BLKNUM, blknum)
        return
    }

    if (dstblk != TERMINAL)
        error(sprintf("(ship_out__block) dstblk is %d, not zero!", dstblk))

    if ((stream = divnum()) > TERMINAL) {
        dbg_print("ship_out", 5, sprintf("(ship_out__block) END Appending block %d to stream %d", blknum, stream))
        nblk_append(stream, SLOT_BLKNUM, blknum)
        return
    }

    # dstblk is zero, so block must be executed
    dbg_print("ship_out", 5, sprintf("(ship_out__block) CALLING execute__block(%d)", blknum))
    execute__block(blknum)
    dbg_print("ship_out", 5, sprintf("(ship_out__block) RETURNED FROM execute__block"))
    dbg_print("ship_out", 3, sprintf("(ship_out__block) END"))
}


function execute__block(blknum,
                        blk_type, old_level)
{
    if (__loop_ctl != LOOP_NORMAL) {
        dbg_print("xeq", 3, "(execute__block) NOP due to loop_ctl=" __loop_ctl)
        return
    }

    blk_type = nblktab[blknum , "type"]
    dbg_print("xeq", 3, sprintf("(execute__block) START blknum=%d, type=%s",
                                blknum, ppf_block_type(blk_type)))

    old_level = __namespace
    if      (blk_type == BLK_AGG)       xeq_blk__agg(blknum)
    else if (blk_type == BLK_CASE)      xeq_blk__case(blknum)
    else if (blk_type == BLK_FOR)       xeq_blk__for(blknum)
    else if (blk_type == BLK_IF)        xeq_blk__if(blknum)
    else if (blk_type == BLK_LONGDEF)   xeq_blk__longdef(blknum)
    else if (blk_type == BLK_USER)      xeq_blk__user(blknum)
    else if (blk_type == BLK_WHILE)     xeq_blk__while(blknum)
    else {
        error(sprintf("(execute__block) Block # %d: type %s (%s) not handled",
                      blknum, blk_type, ppf_block_type(blk_type)))
    }
    if (__namespace != old_level)
        error(sprintf("(execute__block) blknum=%d, type=%s: %s; old_level=%d, __namespace=%d",
                      blknum, ppf_block_type(blk_type), "Namespace level mismatch", old_level, __namespace))
}


function xeq_blk__agg(agg_block,
                      i, lim, slot_type, value, blk_type, name)
{
    blk_type = nblktab[agg_block , "type"]
    dbg_print("xeq", 3, sprintf("(xeq_blk__agg) START dstblk=%d, agg_block=%d, type=%s",
                                curr_dstblk(), agg_block, ppf_block_type(blk_type)))

    dbg_print_block("xeq", 7, agg_block, "(xeq_blk__agg) agg_block")
    lim = nblktab[agg_block, "count"]
    for (i = 1; i <= lim; i++) {
        slot_type = nblk_ll_slot_type(agg_block, i)
        value = nblk_ll_slot_value(agg_block, i)
        dbg_print("xeq", 3, sprintf("(xeq_blk__agg) LOOP; dstblk=%d, agg_block=%d, slot=%d, slot_type=%s, value='%s'",
                                    curr_dstblk(), agg_block, i, ppf_block_type(slot_type), value))
        if (slot_type == SLOT_BLKNUM) {
            dbg_print("xeq", 3, sprintf("(xeq_blk__agg) CALLING ship_out__block(%d)", value+0))
            ship_out__block(value+0)
            dbg_print("xeq", 3, "(xeq_blk__agg) RETURNED FROM ship_out__block()")

        } else if (slot_type == SLOT_CMD) {
            dbg_print("xeq", 3, sprintf("(xeq_blk__agg) CALLING ship_out__command('%s')", value))
            ship_out__command(value)
            dbg_print("xeq", 3, "(xeq_blk__agg) RETURNED FROM ship_out__command()")

        } else if (slot_type == SLOT_TEXT) {
            dbg_print("xeq", 3, sprintf("(xeq_blk__agg) CALLING ship_out__text('%s')", value))
            ship_out__text(value)
            dbg_print("xeq", 3, "(xeq_blk__agg) RETURNED FROM ship_out__text()")

        } else if (slot_type == SLOT_USER) {
            dbg_print("xeq", 3, sprintf("(xeq_blk__agg) CALLING ship_out__user('%s')", value))
            ship_out__user(value)
            dbg_print("xeq", 3, "(xeq_blk__agg) RETURNED FROM ship_out__user()")

        } else
            error(sprintf("(xeq_blk__agg) Bad slot type %s", slot_type))
    }
}


function prt_blk__agg(blknum,
                      slotinfo, count, x)
{
    slotinfo = ""
    count = nblktab[blknum, "count"]
    if (count > 0 ) {
        slotinfo = "  Slots:\n"
        for (x = 1; x <= count; x++)
            slotinfo = slotinfo sprintf("  [%d]=%s: %s\n",
                                        x,
                                        ppf_block_type(nblk_ll_slot_type(blknum, x)),
                                        nblk_ll_slot_value(blknum, x))
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
#       Q. What is the difference between @define and @newcmd?
#       A. @define (and @longdef) create a symbol whose value can be substituted
#       in-line whenever you wish, by surrounding it with "@" characters, as in:
#
#           Hello @name@, I just got a great deal on this new @item@ !!!
#
#       You can also invoke mini "functions", little in-line functions that may
#       take parameters but generally produce or modify output in some way.
#
#       Names declared with @newcmd are recognized and run in the procedure
#       that processes the control commands (@if, @define, etc).  These things
#       can only be on a line of their own and (mostly) do not produce output.
#
#*****************************************************************************
function ncmd_defined_p(name, code)
{
    print_stderr("(ncmd_defined_p) BROKEN")
    if (!ncmd_valid_p(name))
        return FALSE
    if (! nnam_ll_in(name, GLOBAL_NAMESPACE))
        return FALSE
    return TRUE
    #return flag_1true_p(code, TYPE_USER)
}


function ncmd_definition_pp(name)
{
    print_stderr("(ncmd_definition_pp) BROKEN")
    # XXX parameters
    return "@newcmd " name    "\n" \
           ncmd_ll_read(name) "\n" \
           "@endcmd"          "\n"
}


function ncmd_destroy(id)
{
    #print_stderr("(ncmd_destroy) BROKEN") # still broken?
    delete nnamtab[id, GLOBAL_NAMESPACE]
    delete ncmdtab[id, "definition"]
    delete ncmdtab[id, "nparam"]
}


function ncmd_valid_p(text)
{
    return nnam_valid_strict_regexp_p(text) &&
           !double_underscores_p(text)
}


function ncmd_ll_read(name, level)
{
    return ncmdtab[name, level, "user_block"]
}


function ncmd_ll_write(name, level, user_block)
{
    return ncmdtab[name, level, "user_block"] = user_block
}


function ship_out__command(cmdline,
                           dstblk, stream, name, dsc)
{
    dstblk = curr_dstblk()
    dbg_print("ship_out", 3, sprintf("(ship_out__command) START dstblk=%d, cmdline='%s'", dstblk, cmdline))
    name = extract_cmd_name(cmdline)

    if (dstblk < 0) {
        dbg_print("ship_out", 3, "(ship_out__command) END, because dstblk <0")
        return
    }
    if (dstblk > MAX_STREAM) {
        # Block
        dbg_print("ship_out", 5, sprintf("(ship_out__command) END Appending cmd %s to block %d", name, dstblk))
        nblk_append(dstblk, SLOT_CMD, cmdline)
        return
    }
    if (dstblk != TERMINAL)
        error(sprintf("(ship_out_commnd) dstblk is %d, not zero!", dstblk))

    if ((stream = divnum()) > TERMINAL) {
        dbg_print("ship_out", 3, sprintf("(ship_out__command) stream=%d", stream))
        # ship_out__command has only two callers: 1) scan(), where a
        # line is examined and $1 checked to be a TYPE_COMMAND; and 2)
        # xeq_blk__agg(), which only calls when it's a SLOT_CMD.  In
        # either case, name is known to be a command; therefore it must
        # be in the symbol table with a code.
        sub(/^[ \t]*[^ \t]+[ \t]*/, "", cmdline)
        dbg_print("ship_out", 3, sprintf("(ship_out__command) name='%s', cmdline now '%s'",
                                         name, cmdline))

        if      (name == "divert")   xeq_cmd__divert(name, cmdline)
        else if (name == "undivert") xeq_cmd__undivert(name, cmdline)
        else {
            dbg_print("ship_out", 5, sprintf("(ship_out__command) END Appending cmd %s to stream %d", name, stream))
            nblk_append(stream, SLOT_CMD, cmdline)
        }
        return
    }

    # dstblk is definitely zero, so execute the command
    sub(/^[ \t]*[^ \t]+[ \t]*/, "", cmdline)
    dsc = dosubs(cmdline)
    dbg_print("ship_out", 3, sprintf("(ship_out__command) CALLING execute__command('%s', '%s')",
                                     name, dsc))
    execute__command(name, dsc) # dosubs(cmdline))
    dbg_print("ship_out", 3, sprintf("(ship_out__command) RETURNED FROM execute__command('%s', ...)",
                                     name))
    dbg_print("ship_out", 3, sprintf("(ship_out__command) END"))
}


function execute__command(name, cmdline,
                          old_level)
{
    if (__loop_ctl != LOOP_NORMAL) {
        dbg_print("xeq", 3, "(execute__command) NOP due to loop_ctl=" __loop_ctl)
        return
    }
    dbg_print("xeq", 3, sprintf("(execute__command) START name='%s', cmdline='%s'",
                                name, cmdline))

    old_level = __namespace

    # DISPATCH
    # Also need an array entry to initialize command name.  [search: CMDS]
    # NB - immediate commands are not listed here; instead, [search: IMMEDS]
    if      (name == "append")      xeq_cmd__define(name, cmdline)
    else if (name == "array")       xeq_cmd__array(name, cmdline)
    else if (name == "break")       xeq_cmd__break(name, cmdline)
    else if (name == "continue")    xeq_cmd__continue(name, cmdline)
    else if (name == "debug")       xeq_cmd__error(name, cmdline)
    else if (name == "decr")        xeq_cmd__incr(name, cmdline)
    else if (name == "default")     xeq_cmd__define(name, cmdline)
    else if (name == "define")      xeq_cmd__define(name, cmdline)
    else if (name == "divert")      xeq_cmd__divert(name, cmdline)
    else if (name == "dump")        xeq_cmd__dump(name, cmdline)
    else if (name ~  /s?echo/)      xeq_cmd__error(name, cmdline)
    else if (name == "error")       xeq_cmd__error(name, cmdline)
    else if (name ~  /s?exit/)      xeq_cmd__exit(name, cmdline)
    else if (name == "ignore")      xeq_cmd__ignore(name, cmdline)
    else if (name ~  /s?include/)   xeq_cmd__include(name, cmdline)
    else if (name == "incr")        xeq_cmd__incr(name, cmdline)
    else if (name == "initialize")  xeq_cmd__define(name, cmdline)
    else if (name == "input")       xeq_cmd__input(name, cmdline)
    else if (name == "local")       xeq_cmd__local(name, cmdline)
    else if (name == "m2")          xeq_cmd__m2(name, cmdline)
    else if (name == "nextfile")    xeq_cmd__nextfile(name, cmdline)
    else if (name ~  /s?paste/)     xeq_cmd__include(name, cmdline)
    else if (name ~  /s?readarray/) xeq_cmd__readarray(name, cmdline)
    else if (name ~  /s?readfile/)  xeq_cmd__readfile(name, cmdline)
    else if (name == "readonly")    xeq_cmd__readonly(name, cmdline)
    else if (name == "sequence")    xeq_cmd__sequence(name, cmdline)
    else if (name == "shell")       xeq_cmd__shell(name, cmdline)
    else if (name == "stderr")      xeq_cmd__error(name, cmdline)
    else if (name == "typeout")     xeq_cmd__typeout(name, cmdline)
    else if (name == "undefine")    xeq_cmd__undefine(name, cmdline)
    else if (name == "undivert")    xeq_cmd__undivert(name, cmdline)
    else if (name == "warn")        xeq_cmd__error(name, cmdline)
    else
        error("(execute__command) Unrecognized command '" name "' in '" cmdline "'")

    if (__namespace != old_level)
        error("(execute__command) @%s %s: Namespace level mismatch")
}


function assert_ncmd_okay_to_define(name)
{
    if (!ncmd_valid_p(name))
        error("Name '" name "' not valid:" $0)

    # FIXME This is not quite sufficient (I think).  I probably need
    # to do a full nnam_parse() / nnam_lookup() because I don't want
    # to shadow a system symbol.  At least I need to be more careful
    # than "it's not in the current namespace, looks good!!"
    if (nnam_ll_in(name, __namespace))
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
function dump_scan_stack(    level, block, blk_type)
{
    print_stderr("BEGIN dump scan stack")
    if (nstk_depth(__scan_stack) == 0)
        print_stderr("scan stack is empty")
    else
        for (level = nstk_depth(__scan_stack); level > 0; level--) {
            block = __scan_stack[level]
            blk_type = nblk_type(block)
            print_stderr("Level " level ", block # " block ", type=" blk_type )
            dbg_print_block("xeq", -1, block)
        }
    print_stderr("END dump scan stack")
}


function prep_file(filename,
                   file_block, retval)
{
    dbg_print("scan", 7, "(prep_file) START filename='" filename "'")
    # create and return a BLK_FILE set up for the terminal
    file_block = nblk_new(BLK_FILE)
    if (filename == "-")
        filename = "/dev/stdin"
    nblktab[file_block, "filename"] = filename
    nblktab[file_block, "dstblk"] = TERMINAL
    nblktab[file_block, "atmode"] = MODE_AT_PROCESS

    dbg_print("scan", 7, "(prep_file) END; file_block => " file_block)
    return file_block
}


function dofile(filename,
                file_block, retval)
{
    dbg_print("scan", 5, "(dofile) START filename='" filename "'")
    # create and return a BLK_FILE set up for the terminal
    file_block = prep_file(filename)

    dbg_print("scan", 7, sprintf("(dofile) Pushing file block %d (%s) onto scan_stack", file_block, filename))
    nstk_push(__scan_stack, file_block)
    dbg_print("scan", 5, "(dofile) CALLING scan__file()")
    retval = scan__file()
    dbg_print("scan", 5, "(dofile) RETURNED FROM scan__file()")

    dbg_print("scan", 5, "(dofile) END => " ppf_bool(retval))
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
function scan__file(    filename, file_block1, file_block2, scanstat, d)
{
    if (nstk_emptyp(__scan_stack))
        error("(scan__file) Scan stack is empty!")
    file_block1 = nstk_top(__scan_stack)
    if (nblk_type(file_block1) != BLK_FILE)
        error("(scan__file) Top file scanner has type != FILE")

    filename = nblktab[file_block1, "filename"]
    dbg_print("scan", 1, sprintf("(scan__file) filename='%s', dstblk=%d, mode=%s",
                                 filename, nblktab[file_block1, "dstblk"],
                                 ppf_mode(nblktab[file_block1, "atmode"])))
    if (!path_exists_p(filename)) {
        dbg_print("scan", 1, sprintf("(scan__file) END File '%s' does not exist => %s",
                                     filename, ppf_bool(FALSE)))
        nstk_pop(__scan_stack)  # Remove BLK_FILE for non-existent file
        return FALSE
    }
    if (filename in __active_files)
        error("Cannot recursively read '" filename "':" $0)
    __active_files[filename] = TRUE
    nsym_increment("__NFILE__", 1)

    nblktab[file_block1, "old.buffer"]    = __buffer
    nblktab[file_block1, "old.file"]      = nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
    nblktab[file_block1, "old.line"]      = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    nblktab[file_block1, "old.file_uuid"] = nsym_ll_read("__FILE_UUID__", "", GLOBAL_NAMESPACE)
    dbg_print_block("ship_out", 7, file_block1, "(scan__file) file_block1")

    # # Set up new file context
    __buffer = EMPTY
    nsym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, filename)
    nsym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, 0)
    nsym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, uuid())

    # Read the file and process each line
    dbg_print("scan", 5, "(scan__file) CALLING scan()")
    scanstat = scan()
    dbg_print("scan", 5, "(scan__file) RETURNED FROM scan() => " ppf_bool(scanstat))

    # Reached end of file
    flush_stdout(1)

    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != "/dev/stdin")
        close(filename)
    delete __active_files[filename]

    # file_block2 = nstk_pop(__scan_stack)
    # if ((nblktab[file_block2, "type"] != BLK_FILE) ||
    #     (nblktab[file_block2, "depth"] != nstk_depth(__scan_stack))) {
    #     error("(scan__file) Corrupt scan stack")
    # }
    assert_scan_stack_okay(BLK_FILE)
    file_block2 = nstk_pop(__scan_stack)
    __buffer = nblktab[file_block2, "old.buffer"]
    nsym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, nblktab[file_block2, "old.file"])
    nsym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, nblktab[file_block2, "old.line"])
    nsym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, nblktab[file_block2, "old.file_uuid"])

    dbg_print("scan", 1, sprintf("(scan__file) END '%s' => %s",
                                 filename, ppf_bool(scanstat)))
    return scanstat
}


# SCAN
function scan(              code, terminator, readstat, name, retval, new_block, fc,
                            info, level, scanner, scanner_type, scanner_label, i, scnt, found)
{
    dbg_print("scan", 3, "(scan) START dstblk=" curr_dstblk() ", mode=" ppf_mode(curr_atmode()))

    # The "scanner" is the topmost element of the __scan_stack
    # which we wish to access a few times
    if (nstk_emptyp(__scan_stack))
        error("(scan) Scan stack is empty!")
    scanner = nstk_top(__scan_stack)
    scanner_type = nblk_type(scanner)
    scanner_label = ppf_block_type(scanner_type)
    terminator = nblktab[scanner, "terminator"]
    retval = FALSE

    while (TRUE) {
        dbg_print("scan", 4, "(scan) [" scanner_label "] TOP OF LOOP ------------------------------------------------")
        readstat = readline()   # OKAY, EOF, ERROR
        if (readstat == ERROR) {
            # Whatever just happened, the scan didn't finish properly
            dbg_print("scan", 1, "(scan) [" scanner_label "] readline()=>ERROR")
            break          # out of entire scanning loop, to then return
        }
        if (readstat == EOF) {
            # End of file BLK_FILE is fine, just return a TRUE to say so.
            # EOF on any other block type means the scan didn't find
            # a terminator, so return FALSE.
            dbg_print("scan", 5, sprintf("(scan) [%s] readline() detected EOF on '%s'",
                                         scanner_label, nblktab[scanner, "filename"]))
            if ( (scanner,"oob_terminator") in nblktab &&
                nblktab[scanner, "oob_terminator"] == "EOF")
                retval = TRUE
            break          # out of entire scanning loop, to then return
        }
        dbg_print("scan", 5, "(scan) [" scanner_label "] readline() okay; $0='" $0 "'")

        # Check for Regexp block terminator - do this for every line, even in Literal mode
        if (scanner_type == BLK_REGEXP && match($0, terminator)) {
            dbg_print("scan", 5, sprintf("(scan) [%s] END; line matched terminator '%s' => TRUE", scanner_label, terminator))
            return TRUE
        }

        # Maybe short-circuit and ship line out now
        if (curr_atmode() == MODE_AT_LITERAL || index($0, "@") == IDX_NOT_FOUND) {
            dbg_print("scan", 3, sprintf("(scan) [%s, short circuit] CALLING ship_out__text('%s')",
                                         scanner_label, $0))
            ship_out__text($0)
            dbg_print("scan", 3, "(scan) [" scanner_label ", short circuit] RETURNED FROM ship_out__text()")
            continue           # text shipped out, continue to next line
        }

        # Quickly skip comments
        if ($1 == "@@" || $1 == "@;" || $1 == "@#" ||
            $1 == "@c" || $1 == "@comment")
            continue

        # See if it's a command of some kind
        dbg_print("scan", 7, "(scan) [" scanner_label "] $1='" $1 "'")
        # first = @ and last != @ catches @foo...@ at BOL not being a command
        if (first($1) == "@" && last($1) != "@") {
            name = rest($1)

            # Check for cmd arguments
            while (match(name, "\\{.*\\}"))
                name = substr(name, 1, RSTART-1) substr(name, RSTART+RLENGTH)
            
            # See if it's a built-in command
            if (nnam_ll_in(name, GLOBAL_NAMESPACE) &&
                flag_1true_p((code = nnam_ll_read(name, GLOBAL_NAMESPACE)),
                             TYPE_COMMAND)) {
                # See if it's immediate
                if (flag_1true_p(code, FLAG_IMMEDIATE)) {
                    # This command is immediate, so we must run it right now.
                    # Some are known to create and return new blocks,
                    # which must be shipped out.

                    if (name == "break" || name == "continue") {
                        # @break and @continue are hybrid commands, with
                        # both immediate and regular components.  The
                        # scan_stack check for a FOR or WHILE must be
                        # done immediately because the scan_stack is
                        # gone by the time the command is shipped out.
                        # But the actual effect of @break or @continue
                        # is not seen until run-time, so the command
                        # must also be shipped out like a normal command
                        # would have been.
                        found = FALSE
                        for (i = nstk_depth(__scan_stack); i > 0; i--) {
                            scnt = nblk_type(__scan_stack[i])
                            if (scnt == BLK_FOR || scnt == BLK_WHILE) {
                                found = TRUE
                                break
                            }
                        }
                        if (! found)
                            error("@break/@continue: Did not find a @for or @while loop")
                        dbg_print("scan", 3, sprintf("(scan) [%s] CALLING ship_out__command('%s')", scanner_label, $0))
                        ship_out__command($0)
                        dbg_print("scan", 3, "(scan) [" scanner_label "] RETURNED FROM ship_out__command()")

                    } else if (name == "case") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__case(dstblk=" curr_dstblk() ")"))
                        new_block = scan__case()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__case() : new_block => " new_block))
                        dbg_print("scan", 5, sprintf("(scan) [" scanner_label "] CALLING ship_out__block(%d)", new_block))
                        ship_out__block(new_block)
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM ship_out__block()"))

                    } else if (name == "dump!") {
                        xeq_cmd__dump("dump!", "WHAT?")

                    } else if (name == "else") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__else(dstblk=" curr_dstblk() ")"))
                        scan__else()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__else() : dstblk => " curr_dstblk()))

                    } else if (name == "endcase" || name == "esac") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__endcase(dstblk=" curr_dstblk() ")"))
                        scan__endcase()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__endcase() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("scan", 5, "(scan) [" scanner_label "] END; @endcase matched terminator => TRUE")
                            return TRUE
                        }
                        error("(scan) [" scanner_label "] Found @endcase but expecting '" terminator "'")

                    } else if (name == "endcmd") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__endcmd(dstblk=" curr_dstblk() ")"))
                        scan__endcmd()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__endcmd() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("scan", 5, "(scan) [" scanner_label "] END; @endcmd matched terminator => TRUE")
                            return TRUE
                        }
                        error("(scan) [" scanner_label "] Found @endcmd but expecting '" terminator "'")

                    } else if (name == "endif" || name == "fi") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__endif(dstblk=" curr_dstblk() ")"))
                        scan__endif()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__endif() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("scan", 5, "(scan) [" scanner_label "] END; @endif matched terminator => TRUE")
                            return TRUE
                        }
                        error("(scan) [" scanner_label "] Found @endif but expecting '" terminator "'")

                    } else if (name == "endlong" || name == "endlongdef") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__endlongdef(dstblk=" curr_dstblk() ")"))
                        scan__endlongdef()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__endlongdef() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("scan", 5, "(scan) [" scanner_label "] END; @endlongdef matched terminator => TRUE")
                            return TRUE
                        }
                        error("(scan) [" scanner_label "] Found @endlongdef but expecting '" terminator "'")

                    } else if (name == "endwhile") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__endwhile(dstblk=" curr_dstblk() ")"))
                        scan__endwhile()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__endwhile() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("scan", 5, "(scan) [" scanner_label "] END; @endwhile matched terminator => TRUE")
                            return TRUE
                        }
                        error("(scan) [" scanner_label "] Found @endwhile but expecting '" terminator "'")

                    } else if (name == "for" || name == "foreach") {
                        dbg_print("scan", 5, sprintf("(scan) [%s] curr_dstblk()=%d CALLING scan__for()",
                                                     scanner_label, curr_dstblk()))
                        new_block = scan__for()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__for() : new_block is " new_block))
                        dbg_print("scan", 5, sprintf("(scan) [" scanner_label "] CALLING ship_out__block(%d)", new_block))
                        ship_out__block(new_block)
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM ship_out__block()"))

                    } else if (name == "if" || name == "unless" || name ~ /ifn?def/) {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__if(dstblk=" curr_dstblk() ")"))
                        new_block = scan__if()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__if() : new_block => " new_block))
                        dbg_print("scan", 5, sprintf("(scan) [" scanner_label "] CALLING ship_out__block(%d)", new_block))
                        ship_out__block(new_block)
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM ship_out__block()"))

                    } else if (name == "longdef") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__longdef(dstblk=" curr_dstblk() ")"))
                        new_block = scan__longdef()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__longdef() : new_block => " new_block))
                        dbg_print("scan", 5, sprintf("(scan) [" scanner_label "] CALLING ship_out__block(%d)", new_block))
                        ship_out__block(new_block)
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM ship_out__block()"))

                    } else if (name == "newcmd") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__newcmd(dstblk=" curr_dstblk() ")"))
                        new_block = scan__newcmd()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__newcmd() : new_block => " new_block))
                        dbg_print("scan", 5, sprintf("(scan) [" scanner_label "] CALLING ship_out__block(%d)", new_block))
                        ship_out__block(new_block)
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM ship_out__block()"))

                    } else if (name == "next") {
                        dbg_print("scan", 5, sprintf("(scan) [%s] dstblk=%d; CALLING scan__next()",
                                                     scanner_label, curr_dstblk()))
                        scan__next()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__next() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg_print("scan", 5, "(scan) [" scanner_label "] END Matched terminator => TRUE")
                            return TRUE
                        }
                        error("(scan) [" scanner_label "] Found @next but expecting '" terminator "'")

                    } else if (name == "of") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__of(dstblk=" curr_dstblk() ")"))
                        scan__of()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__of() : dstblk => " curr_dstblk()))

                    } else if (name == "otherwise") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__otherwise(dstblk=" curr_dstblk() ")"))
                        scan__otherwise()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__otherwise() : dstblk => " curr_dstblk()))

                    } else if (name == "while") {
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] CALLING scan__while(dstblk=" curr_dstblk() ")"))
                        new_block = scan__while()
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM scan__while() : new_block => " new_block))
                        dbg_print("scan", 5, sprintf("(scan) [" scanner_label "] CALLING ship_out__block(%d)", new_block))
                        ship_out__block(new_block)
                        dbg_print("scan", 5, ("(scan) [" scanner_label "] RETURNED FROM ship_out__block()"))

                    } else
                        error("(scan) [" scanner_label "] Found immediate cmd " name " but no handler")

                } else {
                    # It's a non-immediate built-in command -- ship it
                    # out as a command to be executed later.
                    dbg_print("scan", 3, sprintf("(scan) [%s] CALLING ship_out__command('%s')", scanner_label, $0))
                    ship_out__command($0)
                    dbg_print("scan", 3, "(scan) [" scanner_label "] RETURNED FROM ship_out__command()")
                }
                continue
            } else {
                # Look up user command
                if (nnam_parse(name, info) == ERROR)
                    error("(scan) [" scanner_label "] Parse error on '" name "'")
                if ((level = nnam_lookup(info)) != ERROR) {
                    # An ERROR here simply means not found, in which case
                    # name is definitely not a user commands, so we do nothing
                    # for the moment in that case and let normal test ship out.
                    # But it's not an ERROR, so something was found at "level".
                    # See if it's a user command
                    if (flag_1true_p((code = nnam_ll_read(name, level)), TYPE_USER)) {
                        dbg_print("scan", 3, sprintf("(scan) [%s] CALLING ship_out__user('%s')", scanner_label, $0))
                        ship_out__user($0)
                        dbg_print("scan", 3, "(scan) [" scanner_label "] RETURNED FROM ship_out__user()")
                        continue
                    }
                }
            }
            # It's okay to reach here with no actions taken.  In this
            # case, just process the line as normal text.
        }
        dbg_print("scan", 3, sprintf("(scan) [%s] CALLING ship_out__text('%s')", scanner_label, $0))
        ship_out__text($0)
        dbg_print("scan", 3, "(scan) [" scanner_label "] RETURNED FROM ship_out__text()")
    } # continue loop again, reading next line
    dbg_print("scan", 5, "(scan) END => " ppf_bool(retval))
    return retval
}


function prt_blk__file(blknum)
{
    return sprintf("  filename: %s\n"             \
                   "  atmode  : %s\n"             \
                   "  dstblk  : %d",
                   nblktab[blknum, "filename"],
                   ppf_mode(nblktab[blknum, "atmode"]),
                   nblktab[blknum, "dstblk"])
}


function prt_blk__regexp(blknum)
{
    return sprintf("  valid       : %s\n"       \
                   "  terminator  : '%s'",
                   ppf_bool(nblktab[blknum, "valid"]),
                   nblktab[blknum, "terminator"])
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       F L A G S   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       A flag is a single character boolean-valued piece of information
#       about a "name", an entry in nnamtab.  The flag is True if the
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
#           FLAG_DEFERRED       D : Deferred means value will be defined leter
#           FLAG_IMMEDIATE      ! : scan() will immediately execute command
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
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       N A M E   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       TYPE_SYMBOL:            symtab
#           symtab[NAME] = <definition>
#           Check "foo in symtab" for defined
#
#*****************************************************************************

#*****************************************************************************
#
# This code parses random string "text" into either NAME or NAME[KEY].
# Rudimentary error checking is done.
#
# Return value:
#    -1 (ERROR)
#       Text does not pass simple parsing test.  Even so, it still be
#       invalid depending strict, etc).
#    1 or 2
#       Text parsed.  1 is returned if it's a simple NAME,
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
function nnam_parse(text, info,
                    name, key, nparts, part, count, i)
{
    dbg_print("nnam", 5, sprintf("nnam_parse) START text='%s'", text))
    #info["text"] = text

    # Simple test for CHARS or CHARS[CHARS]
    #   CHARS ::= [-!-Z^-z~]+
    # Match CHARS optionally followed by bracket CHARS bracket
    #   /^ CHARS ( \[ CHARS \] )? $/
    #if (text !~ /^[^[\]]+(\[[^[\]]+\])?$/) {   # too broad: matches non-printing characters
    # We carefully construct CHARS with about regexp
    # to exclude ! [ \ ] { | }
    if (text !~ /^["-Z^-z~]+(\[["-Z^-z~]+\])?$/) {
        warn("(nnam_parse) Name '" text "' not valid")
        dbg_print("nnam", 2, sprintf("nnam_parse(%s) => %d", text, ERROR))
        return ERROR
    }

    count = split(text, part, "(\\[|\\])")
    if (dbg("nnam", 8)) {
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
    info["keyvalid"]   = nnam_valid_with_strict_as(key, FALSE)
    info["namevalid"]  = nnam_valid_with_strict_as(name, strictp("symbol"))
    info["nparts"]     = nparts = (count == 1) ? 1 : 2
    dbg_print("nnam", 4, sprintf("(nnam_parse) '%s' => %d", text, nparts))
    return nparts
}


# Remove any name at level "level" or greater
function nnam_purge(level,
                    x, k, del_list)
{
    dbg_print("nnam", 5, "(nnam_purge) BEGIN")
    
    for (k in nnamtab) {
        split(k, x, SUBSEP)
        if (x[2]+0 >= level)
            del_list[x[1], x[2]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        dbg_print("nnam", 3, sprintf("(nnam_purge) Delete nnamtab['%s', %d]",
                                     x[1], x[2]))
        delete nnamtab[x[1], x[2]]
    }
    dbg_print("nnam", 5, "(nnam_purge) START")
}


function nnam_dump_nnamtab(filter_fs,
                           x, k, code, s, desc, name, level, f_arr, l,
                           include_system)
{
    include_system = flag_1true_p(filter_fs, FLAG_SYSTEM)
    print(sprintf("Begin nnamtab (%s%s):", filter_fs,
                  include_system ? "+System" : ""))

    for (k in nnamtab) {
        split(k, x, SUBSEP)
        name  = x[1]
        level = x[2] + 0
        code = nnam_ll_read(name, level)

        if (! flag_alltrue_p(code, filter_fs)) {
            #print_stderr(sprintf("code=%s, filter=%s, flag filter failed", code, filter_fs))
            continue
        }
        if (flag_1true_p(code, FLAG_SYSTEM) && !include_system) {
            #print_stderr("system filter failed")
            continue
        }
        print "nnamtab:" nnam_ppf_name_level(name, level)
        # print "----------------"
    }
    print("End nnamtab")
}


function nnam_valid_strict_regexp_p(text)
{
    return text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
}


function nnam_valid_with_strict_as(text, tmp_strict)
{
    if (emptyp(text))
        return FALSE
    if (tmp_strict)
        # In strict mode, only letters, #, and _ (and then digits)
        return nnam_valid_strict_regexp_p(text) # text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
    else
        # In non-strict mode, printable characters except ! [ \ ] { | }
        return text ~ /^["-Z^-z~]+$/
}


function nnam_ll_read(name, level)
{
    if (level == EMPTY) level = GLOBAL_NAMESPACE
    return nnamtab[name, level] # returns code
}


function nnam_ll_in(name, level)
{
    if (level == EMPTY) error("nnam_ll_in: LEVEL missing")
    return (name, level) in nnamtab
}


function nnam_ll_write(name, level, code,
                       retval)
{
    if (level == EMPTY) error("nnam_ll_write: LEVEL missing")
    if (nsym_ll_in("__DBG__", "nnam", GLOBAL_NAMESPACE) &&
        nsym_ll_read("__DBG__", "nnam", GLOBAL_NAMESPACE) >= 5)
        print_stderr(sprintf("nnam_ll_write: nnamtab[\"%s\", %d] = %s", name, level, code))
    return nnamtab[name, level] = code
}


#*****************************************************************************
# This will examine nnamtab from __namespace downto 0
# seeing if name is a match.  If so, it populates info["code"]
# with the corresponding code string and returns level (0..n)
# If no matching name is found, return ERROR
#
# Info[] :=
#       code    : Code string from nnamtab
#       isarray : TRUE if NAME is TYPE_ARRAY
#       level   : Level at which name was found
#       type    : Character code for TYPE_xxx
#*****************************************************************************
function nnam_lookup(info,
                     name, level, code)
{
    name = info["name"]
    dbg_print("nsym", 5, sprintf("(nnam_lookup) sym='%s' START", name))

    for (level = __namespace; level >= GLOBAL_NAMESPACE; level--)
        if (nnam_ll_in(name, level)) {
            info["code"] = code = nnam_ll_read(name, level)
            info["isarray"] = flag_1true_p(code, TYPE_ARRAY)
            info["level"]   = level
            info["type"]    = first(code)
            dbg_print("nnam", 2, sprintf("(nnam_lookup) END name '%s', level=%d, code=%s=%s Found in nnamtab => %d",
                                         name, level, code, nnam_ppf_name_level(name, level), level))
            return level
        }
    dbg_print("nnam", 2, sprintf("(nnam_lookup) END Could not find name '%s' on any level in nnamtab => ERROR", name))
    return ERROR
}


function nnam_ppf_name_level(name, level,
                             s, code, desc, l, x)
{
    code = nnam_ll_read(name, level)
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
function nseq_valid_p(text)
{
    return nnam_valid_strict_regexp_p(text) &&
           !double_underscores_p(text)
}


# A Sequence is defined if its name exists in nnamtab with the correct type
# and if it's Defined.
function nseq_defined_p(name,
                        code)
{
    if (!nseq_valid_p(name))
        return FALSE
    if (! nnam_ll_in(name, GLOBAL_NAMESPACE))
        return FALSE
    code = nnam_ll_read(name, GLOBAL_NAMESPACE)
    return flag_1true_p(code, TYPE_SEQUENCE)
}


function nseq_definition_pp(name,    buf, TAB)
{
    print_stderr("(nseq_definition_pp) BROKEN")
    TAB = "\t"
        buf =     "@sequence " name TAB "create\n"
    if (nseq_ll_read(name) != SEQ_DEFAULT_INIT)
        buf = buf "@sequence " name TAB "set " nseq_ll_read(name) "\n"
    if (nseqtab[name, "init"] != SEQ_DEFAULT_INIT)
        buf = buf "@sequence " name TAB "init " nseqtab[name, "init"] "\n"
    if (nseqtab[name, "incr"] != SEQ_DEFAULT_INCR)
        buf = buf "@sequence " name TAB "incr " nseqtab[name, "incr"] "\n"
    if (nseqtab[name, "fmt"] != nsym_ll_read("__FMT__", "seq"))
        buf = buf "@sequence " name TAB "format " nseqtab[name, "fmt"] "\n"
    return buf
}


function nseq_dump_nseqtab(flagset,
                           x, k, code)
{
    print("Begin nseqtab:")
    for (k in nseqtab) {
        split(k, x, SUBSEP)
        print sprintf("nseqtab[\"%s\",\"%s\"] = '%s'",
                      x[1], x[2],
                      nseqtab[x[1], x[2]])
        # print "----------------"
    }
    print("End nseqtab")
}


function nseq_destroy(name)
{
    delete nnamtab[name, GLOBAL_NAMESPACE]
    delete nseqtab[name, "incr"]
    delete nseqtab[name, "init"]
    delete nseqtab[name, "fmt"]
    delete nseqtab[name, "seqval"]
}


function nseq_ll_read(name)
{
    return nseqtab[name, "seqval"]
}


function nseq_ll_write(name, new_val)
{
    return nseqtab[name, "seqval"] = new_val
}


function nseq_ll_incr(name, incr)
{
    if (incr == EMPTY)
        incr = nseqtab[name, "incr"]
    nseqtab[name, "seqval"] += incr
}


function assert_nseq_valid_name(name)
{
    if (nseq_valid_p(name))
        return TRUE
    error("Name '" name "' not valid:" $0)
}


function assert_nseq_okay_to_define(name)
{
    assert_nseq_valid_name(name)
    if (nnam_ll_in(name, GLOBAL_NAMESPACE))
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
function nstk_depth(stack)
{
    return stack[0]
}


function nstk_push(stack, new_elem)
{
    return stack[++stack[0]] = new_elem
}


function nstk_emptyp(stack)
{
    return (nstk_depth(stack) == 0)
}


function nstk_top(stack)
{
    if (nstk_emptyp(stack))
        error("(nstk_top) Empty stack")
    return stack[stack[0]]
}


function nstk_pop(stack)
{
    if (nstk_emptyp(stack))
        error("(nstk_pop) Empty stack")
    return stack[stack[0]--]
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S T R E A M   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       See @divert, @undivert
#
#*****************************************************************************

# Send text to the destination stream __DIVNUM__
#   < 0         Discard
#   = 0         Standard output
#   > 0         Stream # N

function divnum()
{
    return nsym_ll_read("__DIVNUM__", "", GLOBAL_NAMESPACE) + 0
}


# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-parsed for macros, and buffer is cleared after
# injection into target stream.
function undivert(stream)
{
    dbg_print("divert", 1, sprintf("(undivert) START dstblk=%d, stream=%d",
                                   curr_dstblk(), stream))
    if (stream < 0 || stream == divnum()) {
        dbg_print("divert", 3, "(undivert) END ship_out__block() because stream <0 or ==DIVNUM")
        return
    }
    if (nblktab[stream, "type"] != BLK_AGG)
        error(sprintf("(undivert) Block %d has type %s, not AGG",
                      stream, ppf_block_type(nblk_type(stream))))
    if (nblktab[stream, "count"] > 0) {
        dbg_print("divert", 3, sprintf("(undivert) CALLING ship_out__block(%d)", stream))
        ship_out__block(stream)
        dbg_print("divert", 3, "(undivert) RETURNED FROM ship_out__block()")
    }
}


function undivert_all(    stream)
{
    for (stream = 1; stream <= MAX_STREAM; stream++)
        if (nblktab[stream, "count"] > 0)
            undivert(stream)
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
# see function nnam_valid_strict_regexp_p()
# In non-strict mode, any non-empty string is valid.  NOT TRUE
function nsym_valid_p(sym,
                      nparts, info, retval)
{
    dbg_print("nsym", 5, sprintf("(nsym_valid_p) sym='%s' START", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("(nsym_valid_p) ERROR nnam_parse('" sym "') failed")
    }
    # nparts must be either 1 or 2
    retval = (nparts == 1) ?  info["namevalid"] \
                           : (info["namevalid"] && info["keyvalid"])
    dbg_print("nsym", 4, sprintf("(nsym_valid_p) END sym='%s' => %s",
                                 sym, ppf_bool(retval)))
    return retval
}


# function nsym_create(sym, code,
#                      nparts, name, key, info, level)
# {
#     dbg_print("nsym", 4, sprintf("nsym_create: START (sym=%s, code=%s)", sym, code))
#
#     # Parse sym => name, key
#     if ((nparts = nnam_parse(sym, info)) == ERROR) {
#         error("ERROR because nnam_parse failed")
#     }
#     name = info["name"]
#     key  = info["key"]
#
#     # I believe this code can never create system symbols, therefore
#     # there's no need to look it up.  This is because m2 internally
#     # wouldn't call this function (it would be done more directly in
#     # code, with the level specified directly), and the user certainly
#     # can't do it.
#     #level = nnam_system_p(name) ? GLOBAL_NAMESPACE : __namespace
#     level = __namespace
#
#     # Error if name exists at that level
#     if (nsym_info_defined_lev_p(info, level))
#         error("nsym_create name already exists at that level")
#
#     # Error if first(code) != valid TYPE
#     if (!flag_1true_p(code, TYPE_SYMBOL))
#         error("nsym_create asked to create a non-symbol")
#
#     # Add entry:        nnamtab[name,level] = code
#     # Create an entry in the name table
#     #dbg_print("nsym", 2, sprintf("...
#     # print_stderr(sprintf("nsym_create: nnamtab += [\"%s\",%d]=%s", name, level, code))
#     if (! nnam_ll_in(name, level)) {
#         nnam_ll_write(name, level, code)
#     }
#     # What if things aren't compatible?
#
#     # MORE
# }


# This is only for internal use, to easily create and define symbols at
# program start.  code must be correctly formatted.  No error checking is done.
# This function only creates symbols in the global namespace.
function nsym_ll_fiat(name, key, code, new_val,
                      level)
{
    level = GLOBAL_NAMESPACE

    # Create an entry in the name table
    if (! nnam_ll_in(name, level))
        nnam_ll_write(name, level, code)

    # Set its value in the symbol table
    nsym_ll_write(name, key, level, new_val)
}


# Deferred symbols cannot have keys, so don't even pass anything
function nsym_deferred_symbol(name, code, deferred_prog, deferred_arg,
                              level)
{
    level = GLOBAL_NAMESPACE

    # Create an entry in the name table
    if (nnam_ll_in(name, level))
        error("Cannot create deferred symbol when it already exists")

    nnam_ll_write(name, level, code FLAG_DEFERRED)
    # It has no symbol value (yet), but we do store the two args in the
    # symbol table
    nsymtab[name, "", level, "deferred_prog"] = deferred_prog
    nsymtab[name, "", level, "deferred_arg"]  = deferred_arg
}


function nsym_destroy(name, key, level)
{
    dbg_print("nsym", 5, sprintf("(nsym_destroy) START; name='%s', key='%s', level=%d",
                                 name, key, level))

    # Parse sym => name, key
    # if nnam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if nnam_system_p(name)
    # A ::= Cond: name is array T/F
    # B ::= Cond: sym has name[key] syntax T/F
    # if A & B          delete nsymtab[name, key, level, "symval"]
    # if A & !B         delete every nsymtab entry for key; delete nnamtab entry
    # if !A & B         syntax error: NAME is not an array and cannot be deindexed
    # if !A & !B        (normal symbol) delete nsymtab[name, "", level, "symval"];
    #                                   delete nnamtab[name]
    delete nsymtab[name, key, level, "symval"]
}


# DO NOT require CODE parameter.  Instead, look up NAME and
# find its code as normal.  NAME might not even be defined!
function nnam_system_p(name)
{
    if (name == EMPTY)
        error("nnam_system_p: NAME missing")
    return nnam_ll_in(name, GLOBAL_NAMESPACE) &&
           flag_1true_p(nnam_ll_read(name, GLOBAL_NAMESPACE), FLAG_SYSTEM)
}


function nsym_dump_nsymtab(flagset,    \
                           x, k, code)
{
    print_stderr("(BROKEN?) Begin nsymtab:")
    for (k in nsymtab) {
        split(k, x, SUBSEP)
        # print "name  =", x[1]
        # print "key   =", x[2]
        # print "level =", x[3]
        # print "elem  =", x[4]
        print_stderr(sprintf("nsymtab[\"%s\",\"%s\",%s,\"%s\"] = '%s'",
                      x[1], x[2], x[3], x[4],
                             nsymtab[x[1], x[2], x[3], x[4]]))
        # print "----------------"
    }
    print_stderr("End nsymtab")
}


# Remove any symbol at level "level" or greater
function nsym_purge(level,
                    x, k, del_list)
{
    dbg_print("nsym", 5, "(nsym_purge) BEGIN")
    for (k in nsymtab) {
        split(k, x, SUBSEP)
        if (x[3]+0 >= level)
            del_list[x[1], x[2], x[3], x[4]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        dbg_print("nsym", 3, sprintf("(nsym_purge) Delete nsymtab['%s', '%s', %d, %s]",
                                     x[1], x[2], x[3], x[4]))
        delete nsymtab[x[1], x[2], x[3], x[4]]
    }
    dbg_print("nsym", 5, "(nsym_purge) END")
}


# Deferred symbols have an entry in nnamtab of TYPE_SYMBOL
# and FLAG_DEFERRED.  Only system symbols in global namespace
# are deferred, so we don't need to be super careful
function nsym_deferred_p(sym,
                        code, level)
{
    level = GLOBAL_NAMESPACE
    if (!nnam_ll_in(sym, level))
        return FALSE
    code = nnam_ll_read(sym, level)
    if (flag_anyfalse_p(code, TYPE_SYMBOL FLAG_DEFERRED))
        return FALSE
    return ((sym, "", level, "deferred_prog") in nsymtab &&
            (sym, "", level, "deferred_arg")  in nsymtab &&
          !((sym, "", level, "symval")        in nsymtab))
}


# User should have checked to make sure, so let's do it
function nsym_deferred_define_now(sym,
                                 code, deferred_prog, deferred_arg, cmdline, output)
{
    if (secure_level() >= 2)
        error("(nsym_deferred_define_now) Security violation")

    code = nnam_ll_read(sym, GLOBAL_NAMESPACE)
    deferred_prog = nsymtab[sym, "", GLOBAL_NAMESPACE, "deferred_prog"]
    deferred_arg  = nsymtab[sym, "", GLOBAL_NAMESPACE, "deferred_arg"]

    # Build the command to generate the output value, then store it in the symbol table
    cmdline = build_prog_cmdline(deferred_prog, deferred_arg, MODE_IO_CAPTURE)
    cmdline | getline output
    close(cmdline)
    # Kluge to add trailing slash to pwd(1) output
    if (sym == "__CWD__")
        output = with_trailing_slash(output)
    nsym_ll_write(sym, "", GLOBAL_NAMESPACE, output)

    # Get rid of any trace of FLAG_DEFERRED
    nnam_ll_write(sym, GLOBAL_NAMESPACE, flag_set_clear(code, EMPTY, FLAG_DEFERRED))
    delete nsymtab[sym, "", GLOBAL_NAMESPACE, "deferred_prog"]
    delete nsymtab[sym, "", GLOBAL_NAMESPACE, "deferred_arg"]
}


function nsym_defined_p(sym,
                        nparts, info, name, key, code, level, i,
                        agg_block, count)
{
    dbg_print("nsym", 5, sprintf("(nsym_defined_p) sym='%s' START", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        dbg_print("nsym", 2, sprintf("(nsym_defined_p) END nnam_parse('%s') failed => %s", sym, ppf_bool(FALSE)))
        return FALSE
    }
    name = info["name"]
    key  = info["key"]

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    if (level == ERROR) {
        dbg_print("nsym", 2, sprintf("(nsym_defined_p) END nnam_lookup('%s') failed, maybe ok? => %s", sym, ppf_bool(FALSE)))
        return FALSE
    }

    # We've found some matching name on some level, but not sure if it's a Symbol or not.
    # This step is necessary to make sure it's actually a Symbol.
    for (i = nnam_system_p(name) ? GLOBAL_NAMESPACE : __namespace; i >= GLOBAL_NAMESPACE; i--) {
        if (nsym_info_defined_lev_p(info, i)) {
            dbg_print("nsym", 2, sprintf("(nsym_defined_p) END sym='%s', level=%d => %s", sym, i, ppf_bool(TRUE)))
            return TRUE
        }
    }

    # If it's not a normal symbol table entry, maybe a block-array
    if (flag_alltrue_p(info["code"], TYPE_ARRAY FLAG_BLKARRAY)) {
        if (!integerp(key)) {
            dbg_print("nsym", 2, sprintf("(nsym_defined_p) Block array indices must be integers"))
            return FALSE
        }
        if (! ( (name, "", level, "agg_block") in nsymtab) )
            error(sprintf("Could not find ['%s','%s',%d,'agg_block'] in nsymtab",
                          name, "", level))

        agg_block = nsymtab[name, "", level, "agg_block"]
        count = nblktab[agg_block, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (nblk_ll_slot_type(agg_block, key) != SLOT_TEXT)
                error(sprintf("(nsym_defined_p) Block # %d slot %d is not SLOT_TEXT", agg_block, key))
            dbg_print("nsym", 2, sprintf("(nsym_defined_p) END sym='%s', level=%d => %s", sym, level, ppf_bool(TRUE)))
            return TRUE
        }
    }

    dbg_print("nsym", 2, sprintf("(nsym_defined_p) END No symbol named '%s' on any level => %s", sym, ppf_bool(FALSE)))
    return FALSE
}


# Caller MUST have previously called nnam_parse().
# It's the only way to get the `info' parameter value.
#
# The caller is responsible for inquiring about nnam_system_p(name),
# and overriding level to zero if appropriate.  This code does
# not make any assumptions about name/levels.
function nsym_info_defined_lev_p(info, level,
                                 name, key, code,
                                 x, k, thought_so)
{
    name = info["name"]
    key  = info["key"]
    # code = info["code"]
    dbg_print("nsym", 5, sprintf("(nsym_info_defined_lev_p) sym='%s' START", name))


    if (key == EMPTY) {
        if ( (name,"",0+level,"symval") in nsymtab) {
            dbg_print("nsym", 5, sprintf("(nsym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Found in nsymtab => TRUE", name, key, level))
            return TRUE
        }
        dbg_print("nsym", 5, sprintf("(nsym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Not found => FALSE", name, key, level))
        return FALSE
    } else {
        # Non-empty key means we have to sequential search through table
        # Eh, why is that?
        if ( (name,key,0+level,"symval") in nsymtab)
            thought_so = TRUE

        for (k in nsymtab) {
            split(k, x, SUBSEP)
            if (x[1]   != name  ||
                x[2]   != key   ||
                x[3]+0 != level ||
                x[4]   != "symval")
                continue
            # Everything matches
            if (! thought_so)
                warn("(nsym_info_defined_lev_p) I didn't think you'd find a match")
            dbg_print("nsym", 5, sprintf("(nsym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Found in nsymtab => TRUE", name, key, level))
            return TRUE
        }
        if (thought_so)
            warn("nsym_info_defined_lev_p) But...  I thought you'd find a match")
        dbg_print("nsym", 5, sprintf("(nsym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Not found => FALSE", name, key, level))
        return FALSE
    }
}


function nsym_store(sym, new_val,
                    nparts, info, name, key, level, code, good, dbg5)
{
    # Fetch debug level first before it might possibly change
    dbg5 = dbg("nsym", 5)
    if (dbg5)
        print_stderr(sprintf("(nsym_store) START sym='%s'", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("(nsym_store) nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # Compute level
    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    # It's okay if nnam_lookup "fails" (level == ERROR) because
    # we might be attempting to store a new, non-existing symbol.

    # At this point:
    #   level == ERROR            -> no matching name of any kind
    #   level == GLOBAL_NAMESPACE -> found in global
    #   0 < level < ns-1          -> find in other non-global frame
    #   level == __namespace      -> found in current namespace
    # Just because we found a nnamtab entry doesn't
    # mean it's okay to just muck about with nsymtab.

    good = FALSE
    do {
        if (level == ERROR) {   # name not found in nnam
            # No nnamtab entry, no code : This means a normal
            # @define in the global namespace
            if (info["hasbracket"])
                error(sprintf("(nsym_store) %s is not an array; cannot use brackets here", name))
            # Do scalar store
            level = info["level"] = GLOBAL_NAMESPACE
            code  = info["code"]  = TYPE_SYMBOL
            nnam_ll_write(name, level, code)
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        # At this point we know nnam_lookup() found *something* because
        # level != ERROR
        code = info["code"]

        # Error if we found an array without key,
        # or a plain symbol with a subscript.
        if (flag_1true_p(code, TYPE_ARRAY) && !info["hasbracket"])
            error(sprintf("(nsym_store) %s is an array, so brackets are required", name))
        if (flag_1false_p(code, TYPE_ARRAY) && info["hasbracket"])
            error(sprintf("(nsym_store) %s is not an array; cannot use brackets here", name))

        if (flag_1true_p(code, TYPE_SYMBOL) &&
            !nsym_ll_protected(name, code) &&
            !info["hasbracket"] &&
            flag_1false_p(code, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (flag_1true_p(code, TYPE_ARRAY) &&
            !nsym_ll_protected(name, code) &&
            info["hasbracket"] &&
            flag_1false_p(code, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        nnam_dump_nnamtab(TYPE_SYMBOL)
        nsym_dump_nsymtab()
        # print_stderr(sprintf("(nsym_store) LOOP BOTTOM: name='%s', key='%s', level=%d, code='%s'",
        #                      name, key, level, code))
    } while (FALSE)

    # if nnam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if symbol is an array but sym doesn't have array[key] syntax
    # Error if symbol is not an array but sym has array[key] syntax
    # Error if you don't have permission to write to the symbol
    #   == Error ("read-only") if (flag_true(FLAG_READONLY))
    # Error if new_val is not consistent with symbol type (haha)
    #   or else coerce it to something acceptable (boolean)
    # Special processing (CONVFMT, __DEBUG__)

    # Add entry:        nsymtab[name, key, level, "symval"] = new_val
    if (good) {
        dbg_print("nsym", 1, sprintf("(nsym_store) [\"%s\",\"%s\",%d,\"symval\"]=%s",
                                     name, key, level, new_val))
        nsym_ll_write(name, key, level, new_val)
    } else {
        warn(sprintf("(nsym_store) !good sym='%s'", sym))
    }
    if (dbg5)
        print_stderr(sprintf("(nsym_store) END;"))
}


function nsym_ll_read(name, key, level)
{
    if (level == EMPTY) level = GLOBAL_NAMESPACE
    # if key == EMPTY that's probaby just fine.
    # if name == EMPTY that's probably NOT fine.
    return nsymtab[name, key, level, "symval"] # returns value
}


function nsym_ll_in(name, key, level)
{
    if (level == EMPTY) error("nsym_ll_in: LEVEL missing")
    return (name, key, level, "symval") in nsymtab
}


function nsym_ll_write(name, key, level, val)
{
    if (level == EMPTY) error("nsym_ll_write: LEVEL missing")
    if (nsym_ll_in("__DBG__", "nsym", GLOBAL_NAMESPACE) &&
        nsym_ll_read("__DBG__", "nsym", GLOBAL_NAMESPACE) >= 5 &&
        !nnam_system_p(name))
        print_stderr(sprintf("(nsym_ll_write) nsymtab[\"%s\", \"%s\", %d, \"symval\"] = %s", name, key, level, val))

    # Trigger debugging setup
    if (name == "__DEBUG__" && nsym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE) == FALSE &&
        val != FALSE)
        initialize_debugging()
    else if (name == "__SECURE__") {
        val = max(secure_level(), val) # Don't allow __SECURE__ to decrease
        print_stderr(sprintf("New __SECURE__ = %d", val))
    }
    # Maintain equivalence:  __FMT__[number] === CONVFMT
    if (name == "__FMT__" && key == "number" && level == GLOBAL_NAMESPACE) {
        if (nsym_ll_in("__DBG__", "nsym", GLOBAL_NAMESPACE) &&
            nsym_ll_read("__DBG__", "nsym", GLOBAL_NAMESPACE) >= 6)
            print_stderr(sprintf("(nsym_ll_write) Setting CONVFMT to %s", val))
        CONVFMT = val
    }

    return nsymtab[name, key, level, "symval"] = val
}


function nsym_ll_incr(name, key, level, incr)
{
    if (incr == EMPTY) incr = 1
    if (level == EMPTY) error("nsym_ll_incr: LEVEL missing")
    if (nsym_ll_in("__DBG__", "nsym", GLOBAL_NAMESPACE) &&
        nsym_ll_read("__DBG__", "nsym", GLOBAL_NAMESPACE) >= 5 &&
        !nnam_system_p(name))
        print_stderr(sprintf("(nsym_ll_incr) nsymtab[\"%s\", \"%s\", %d, \"symval\"] += %d",
                             name, key, level, incr))
    return nsymtab[name, key, level, "symval"] += incr
}


function nsym_fetch(sym,
                    nparts, info, name, key, code, level, val, good,
                    agg_block, count)
{
    dbg_print("nsym", 5, sprintf("(nsym_fetch) START; sym='%s'", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("(nsym_fetch) nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    if (level == ERROR)
        error("(nsym_fetch) nnam_lookup(info) failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # nsymtab because NAME[KEY] might not be defined.
    code = info["code"]
    dbg_print("nsym", 5, sprintf("(nsym_fetch) nnam_lookup ok; level=%d, code=%s", level, code))

    # Sanity checks
    good = FALSE

    # 1. Fetching @ARRNAME@ w/o key return # elements in ARRNAME.
    if (info["isarray"] == TRUE && info["hasbracket"] == FALSE)
        error("nsym_fetch: Fetching @ARRNAME@ without a key is not supported yet")

    # 2. Error if symbol is not an array but sym has array[key] syntax
    if (info["isarray"] == FALSE && info["hasbracket"] == TRUE)
        error("nsym_fetch: Symbol is not an array but sym has array[key] syntax")

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

        # print_stderr(sprintf("(nsym_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
        #                      sym, name, key, level, code))

    } while (FALSE)

    if (flag_1true_p(code, FLAG_DEFERRED))
        nsym_deferred_define_now(sym)

    if (flag_1true_p(code, FLAG_BLKARRAY)) {
        # Look up block
        if (!integerp(key))
            error(sprintf("(nsym_fetch) Block array indices must be integers"))
        if (! ( (name, "", level, "agg_block") in nsymtab) )
            error(sprintf("Could not find ['%s','%s',%d,'agg_block'] in nsymtab",
                          name, "", level))

        agg_block = nsymtab[name, "", level, "agg_block"]
        count = nblktab[agg_block, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (nblk_ll_slot_type(agg_block, key) != SLOT_TEXT)
                error(sprintf("(nsym_fetch) Block # %d slot %d is not SLOT_TEXT", agg_block, key))
            val = nblk_ll_slot_value(agg_block, key)
        } else
            error(sprintf("(nsym_fetch) Out of bounds"))
    } else {
        # It's a normal symbol
        if (! nsym_ll_in(name, key, level))
            error("(nsym_fetch) Not in nsymtab: NAME='" name "', KEY='" key "'")
        val = nsym_ll_read(name, key, level)
    }

        dbg_print("nsym", 2, sprintf("(nsym_fetch) END sym='%s', level=%d => %s", sym, level, ppf_bool(TRUE)))
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
function nsym_increment(sym, incr,
                        name, key)
{
    if (incr == EMPTY)
        incr = 1

    # Parse sym => name, key
    # Compute level
    # if nnam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if incr is not numeric
    # Error if symbol is an array but sym doesn't have array[key] syntax
    # Error if symbol is not an array but sym has array[key] syntax
    # Error if you don't have permission to write to the symbol
    #   == Error ("read-only") if (flag_true(FLAG_READONLY))
    # Error if value is not consistent with symbol type (haha)
    #   or else coerce it to something acceptable (boolean)

    # Add entry:        nsymtab[name, key, level, "symval"] += incr
    #nsymtab[sym, "", GLOBAL_NAMESPACE, "symval"] += incr
    nsym_ll_incr(sym, "", GLOBAL_NAMESPACE, incr)
}


function nsym_protected_p(sym,
                          nparts, info, name, key, code, level, retval)
{
    dbg_print("nsym", 5, sprintf("(nsym_protected_p) START sym='%s'", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("nsym_protected_p: nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    if (level == ERROR)
        return double_underscores_p(name)

    # Error if (! name in nnamtab)
    if (!nnam_ll_in(name, level))
        error("not in nnamtab!?  name=" name ", level=" level)

    # Check for intermediate level - endpoints are excluded
    if (GLOBAL_NAMESPACE < level && level < __namespace)
        error("nsym_protected_p: Cannot select random namespace")

    # Error if name does not exist at that level
    code = nnam_ll_read(name, level)
    retval = nsym_ll_protected(name, code)
    dbg_print("nsym", 4, sprintf("(nsym_protected_p) END; sym '%s' => %s", sym, ppf_bool(retval)))
    return retval
    #return nsym_ll_protected(name, code)
}


function nsym_ll_protected(name, code)
{
    if (flag_1true_p(code, FLAG_READONLY))
        return TRUE
    if (flag_1true_p(code, FLAG_WRITABLE))
        return FALSE
    if (double_underscores_p(name))
        return TRUE
    return FALSE
}


function nsym_definition_pp(sym,    sym_name, definition)
{
    print_stderr("(nsym_definition_pp) BROKEN")
    sym_name = sym
    definition = nsym_fetch(sym)
    return (index(definition, "\n") == IDX_NOT_FOUND) \
        ? "@define " sym_name "\t" definition "\n" \
        : "@longdef " sym_name "\n" \
          definition           "\n" \
          "@endlongdef"        "\n"
}


# Caller is responsible for ensuring user is allowed to delete symbol
# function sym_destroy(sym)
# {
#     dbg_print("symbol", 5, ("sym_destroy(" sym ")"))
#     # It is legal to delete an array key that does not exist
#     delete symtab[sym_internal_form(sym)]
# }


# Protected symbols cannot be changed by the user.
# function sym_protected_p(sym,    root)
# {
#     root = sym
#     # Names known to be protected
#     if (root in protected_syms)
#         return TRUE
#     # Whitelist of known safe symbols
#     if (root in unprotected_syms)
#         return FALSE
#     return double_underscores_p(root)
# }


# function sym_store(sym, val)
# {
#     # __DEBUG__ and __STRICT__[xxx] can only store boolean values
#     if (sym == "__DEBUG__" || sym == "__STRICT__")
#         val = !! (val+0)
#     return symtab[sym_internal_form(sym)] = val
# }


function nsym_true_p(sym,
                     val)
{
    return (nsym_defined_p(sym) &&
            ((val = nsym_fetch(sym)) != FALSE &&
              val                    != EMPTY))
}


# Throw an error if symbol is NOT defined
function assert_nsym_defined(sym, hint,    s)
{
    if (nsym_defined_p(sym))
        return TRUE
    s = sprintf("Name '%s' not defined%s%s",  sym,
                ((hint != EMPTY) ? " [" hint "]" : ""),
                ((!emptyp($0)) ? ":" $0 : "") )
    error(s)
}


function assert_nsym_okay_to_define(name,
                                    code)
{
    assert_nsym_valid_name(name)
    assert_nsym_unprotected(name)

    if (nnam_ll_in(name, __namespace) &&
        flag_alltrue_p((code = nnam_ll_read(name, __namespace)), TYPE_SYMBOL) &&
        flag_allfalse_p(code, FLAG_READONLY))
        return TRUE
    if (nnam_ll_in(name, __namespace)) return FALSE

    if (nnam_ll_in(name, GLOBAL_NAMESPACE) &&
        flag_alltrue_p((code = nnam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL) &&
        flag_allfalse_p(code, FLAG_READONLY))
        return TRUE
    if (nnam_ll_in(name, GLOBAL_NAMESPACE)) return FALSE

    # Can't shadow a system symbol
    if (nnam_ll_in(name, GLOBAL_NAMESPACE) &&
        flag_alltrue_p((code = nnam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL FLAG_SYSTEM))
        return FALSE

    if (double_underscores_p(name))
        return FALSE

    # You can redefine a symbol, but not a cmd, function, or sequence
    # if (!name_available_in_all_p(name, TYPE_USER TYPE_FUNCTION TYPE_SEQUENCE))
    #     error("Name '" name "' not available:" $0)
    return TRUE
}


# Throw an error if symbol IS protected
function assert_nsym_unprotected(sym)
{
    if (nsym_protected_p(sym))
        error("Symbol '" sym "' protected:" $0)
}


# Throw an error if the symbol name is NOT valid
function assert_nsym_valid_name(sym)
{
    if (! nsym_valid_p(sym))
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
function ship_out__text(text,
                        dstblk, stream, s)
{
    dstblk = curr_dstblk()
    dbg_print("ship_out", 3, sprintf("(ship_out__text) START dstblk=%d, mode=%s, text='%s'",
                                     dstblk, ppf_mode(curr_atmode()), text))

    if (dstblk < 0) {
        dbg_print("ship_out", 3, "(ship_out__text) END, because dstblk <0")
        return
    }
    if (dstblk > MAX_STREAM) {
        # Block
        dbg_print("ship_out", 5, sprintf("(ship_out__text) END Appending text to block %d", dstblk))
        nblk_append(dstblk, SLOT_TEXT, text)
        return
    }
    if (dstblk != TERMINAL)
        error(sprintf("(ship_out__text) dstblk is %d, not zero!", dstblk))

    if ((stream = divnum()) > TERMINAL) {
        dbg_print("ship_out", 5, sprintf("(ship_out__text) END Appending text to stream %d", stream))
        nblk_append(stream, SLOT_TEXT, text)
        return
    }
    # dstblk is definitely zero, so text must be executed (printed)
    if (curr_atmode() == MODE_AT_PROCESS)
        text = dosubs(text)
    dbg_print("ship_out", 5, sprintf("(ship_out__text) CALLING execute__text()"))
    execute__text(text)
    dbg_print("ship_out", 5, sprintf("(ship_out__text) RETURNED FROM execute__text()"))

    dbg_print("ship_out", 3, sprintf("(ship_out__text) END"))
}


function execute__text(text)
{
    if (__loop_ctl != LOOP_NORMAL) {
        dbg_print("xeq", 3, "(execute__text) NOP due to loop_ctl=" __loop_ctl)
        return
    }
    dbg_print("xeq", 3, sprintf("(execute__text) START; text='%s'", text))

    if (__print_mode == MODE_TEXT_PRINT) {
        printf("%s\n", text)
        flush_stdout(2)
    } else if (__print_mode == MODE_TEXT_STRING)
        __textbuf = sprintf("%s%s\n", __textbuf, text)
    else
        error("(execute__text) Bad __print_mode " __print_mode)
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
    assert_nsym_okay_to_define(arr)
    if (nnam_ll_in(arr, __namespace))
        error("Array '" arr "' already defined")
    nnam_ll_write(arr, __namespace, TYPE_ARRAY)
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
                        level, block, blk_type)
{
    # Logical check
    if (__loop_ctl != LOOP_NORMAL)
        error("(xeq_cmd__break) __loop_ctl is not normal, how did that happen?")

    __loop_ctl = LOOP_BREAK
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  C A S E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function scan__case(                case_block, preamble_block, scanstat)
{
    dbg_print("case", 3, sprintf("(scan__case) START dstblk=%d, $0='%s'", curr_dstblk(), $0))

    # Create a new block for case_block
    case_block = nblk_new(BLK_CASE)
    dbg_print("case", 5, "(scan__case) New block # " case_block " type " ppf_block_type(nblk_type(case_block)))
    preamble_block = nblk_new(BLK_AGG)
    dbg_print("case", 5, "(scan__case) New block # " case_block " type " ppf_block_type(nblk_type(preamble_block)))

    $1 = ""
    nblktab[case_block, "casevar"]        = $2
    nblktab[case_block, "preamble_block"] = preamble_block
    nblktab[case_block, "nof"]            = 0
    nblktab[case_block, "seen_otherwise"] = FALSE
    nblktab[case_block, "dstblk"]         = preamble_block
    nblktab[case_block, "valid"]          = FALSE
    dbg_print_block("case", 7, case_block, "(scan__case) case_block")
    nstk_push(__scan_stack, case_block) # Push it on to the scan_stack

    dbg_print("case", 5, "(scan__case) CALLING scan()")
    scanstat = scan() # scan() should return after it encounters @endcase
    dbg_print("case", 5, "(scan__case) RETURNED FROM scan() => " ppf_bool(scanstat))
    if (!scanstat)
        error("(scan__case) Scan failed")

    dbg_print("case", 5, "(scan__case) END; => " case_block)
    return case_block
}


function scan__of(                case_block, of_block, of_val)
{
    dbg_print("case", 3, sprintf("(scan__of) START dstblk=%d, mode=%s, $0='%s'",
                                 curr_dstblk(), ppf_mode(curr_atmode()), $0))

    assert_scan_stack_okay(BLK_CASE)
    case_block = nstk_top(__scan_stack)

    # Create a new block for the new Of branch and make it current
    of_block = nblk_new(BLK_AGG)
    sub(/^@of[ \t]+/, "")
    of_val = $0
    if ( (case_block, "of", of_val) in nblktab)
        error("(scan__of) Duplicate '@of' values not allowed:@of " $0)

    nblktab[case_block, "of", of_val] = of_block
    nblktab[case_block, "dstblk"]  = of_block
    return of_block
}


function scan__otherwise(                case_block, otherwise_block)
{
    dbg_print("case", 3, sprintf("(scan__otherwise) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf_mode(curr_atmode())))

    assert_scan_stack_okay(BLK_CASE)

    # Check if already seen @else
    case_block = nstk_top(__scan_stack)
    if (nblktab[case_block, "seen_otherwise"] == TRUE)
        error("(scan__otherwise) Cannot have more than one @otherwise")

    # Create a new block for the False branch and make it current
    nblktab[case_block, "seen_otherwise"] = TRUE
    otherwise_block = nblk_new(BLK_AGG)
    nblktab[case_block, "otherwise_block"] = otherwise_block
    nblktab[case_block, "dstblk"]  = otherwise_block
    return otherwise_block
}


function scan__endcase(                case_block)
{
    dbg_print("case", 3, sprintf("(scan__endcase) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf_mode(curr_atmode())))
    # if (nstk_emptyp(__scan_stack))
    #     error("(scan__endcase) Scan stack is empty!")
    # case_block = nstk_pop(__scan_stack)
    # if ((nblktab[case_block, "type"] != BLK_CASE) ||
    #     (nblktab[case_block, "depth"] != nstk_depth(__scan_stack)))
    #     error("(scan__endcase) Corrupt scan stack")
    assert_scan_stack_okay(BLK_CASE)

    case_block = nstk_pop(__scan_stack)
    nblktab[case_block, "valid"] = TRUE

    return case_block
}


function xeq_blk__case(case_block,
                       blk_type, casevar, caseval, preamble_block)
{
    blk_type = nblktab[case_block , "type"]
    dbg_print("case", 3, sprintf("(xeq_blk__case) START dstblk=%d, case_block=%d, type=%s",
                                 curr_dstblk(), case_block, ppf_block_type(blk_type)))

    dbg_print_block("case", 7, case_block, "(xeq_blk__case) case_block")
    if ((nblktab[case_block, "type"] != BLK_CASE) || \
        (nblktab[case_block, "valid"] != TRUE))
        error("(xeq_blk__case) Bad config")

    # Check if the case variable value matches any @of values
    casevar = nblktab[case_block, "casevar"]
    dbg_print("case", 5, sprintf("(xeq_blk__case) casevar '%s'", casevar))
    assert_nsym_defined(casevar)
    caseval = nsym_fetch(casevar)
    dbg_print("case", 5, sprintf("(xeq_blk__case) caseval '%s'", caseval))

    if ( (case_block, "of", caseval) in nblktab) {
        # See if there's a preamble which is non-empty.  By the way,
        # preambles DO NOT get their own namespace.
        preamble_block = nblktab[case_block, "preamble_block"]
        if (nblktab[preamble_block, "count"]+0 > 0) {
            dbg_print("case", 5, sprintf("(xeq_blk__case) CALLING execute__block(%d)",
                                         nblktab[case_block, "preamble_block"]))
            execute__block(nblktab[case_block, "preamble_block"])
            dbg_print("case", 5, sprintf("(xeq_blk__case) RETURNED FROM execute__block()"))
        }

        # But the @of branch DOES get a new namespace
        raise_namespace()
        dbg_print("case", 5, sprintf("(xeq_blk__case) CALLING execute__block(%d)",
                                     nblktab[case_block, "of", caseval]))
        execute__block(nblktab[case_block, "of", caseval])
        dbg_print("case", 5, sprintf("(xeq_blk__case) RETURNED FROM execute__block()"))
        lower_namespace()
    } else if (nblktab[case_block, "seen_otherwise"] == TRUE) {
        # NB - @otherwise branches DO NOT execute the preamble (if any)
        raise_namespace()
        dbg_print("case", 5, sprintf("(xeq_blk__case) CALLING execute__block(%d)",
                                     nblktab[case_block, "otherwise_block"]))
        execute__block(nblktab[case_block, "otherwise_block"])
        dbg_print("case", 5, sprintf("(xeq_blk__case) RETURNED FROM execute__block()"))
        lower_namespace()
    }

    dbg_print("case", 3, sprintf("(xeq_blk__case) END"))
}


function prt_blk__case(blknum)
{
    return ""
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
    # Follow scan stack upwards to make sure there's a @for or @while
    # loop to break out of

    # Logical check
    if (__loop_ctl != LOOP_NORMAL)
        error("(xeq_cmd__continue) __loop_ctl is not normal, how did that happen?")

    __loop_ctl = LOOP_CONTINUE
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
    assert_nsym_okay_to_define(sym)
    if (nsym_defined_p(sym)) {
        if (nop_if_defined)
            return
        if (error_if_defined)
            error("Symbol '" sym "' already defined:" $0)
    }

    #sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")
    sub(/^[ \t]*[^ \t]+[ \t]*/, "")
    if ($0 == EMPTY) $0 = "1"
    # XXX No checking, dangerous!!
    nsym_store(sym, append_flag ? nsym_fetch(sym) $0 \
                                : $0)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D I V E R T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
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
        error(sprintf("Value '%s' must be integer:", new_stream) $0)
    if (new_stream > MAX_STREAM)
        error("Bad parameters:" $0)

    nsym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, int(new_stream))
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
                       what)
{
    all_flag = $1 == "@dumpall"

    $0 = cmdline
    if (NF >= 1) {
        if (NF >= 2) {
            $1 = ""
            dumpfile = cmdline
            print_stderr(sprintf("dumpfile = '%s'", dumpfile))
        }
    }
    # if (NF > 1) {
    #     $1 = ""
    #     sub("^[ \t]*", "")
    #     dumpfile = rm_quotes(dosubs($0))
    # }
    # Count and sort the keys from the symbol and sequence tables
    cnt = 0

    if (NF == 0)
        $1 = "symbols"
    $1 = tolower($1)
    if ($1 ~ /sym(bol)?s?/) {
        nnam_dump_nnamtab(TYPE_SYMBOL FLAG_SYSTEM)
        nsym_dump_nsymtab(what)
    } else if ($1 ~ /seq(uence)?s?/) {
        nnam_dump_nnamtab(TYPE_SEQUENCE FLAG_SYSTEM)
        nseq_dump_nseqtab(what)
    } else if ($1 ~ /(cmd|command)s?/) {
        nnam_dump_nnamtab(TYPE_COMMAND FLAG_SYSTEM)
    } else if ($1 ~ /\*|any/) {
        error("@dump any not supported yet")
    } else if ($1 ~ /name?s?/) {
        nnam_dump_nnamtab(TYPE_ANY FLAG_SYSTEM)
    } else if ($1 ~ /bl(oc)?ks?/) {
        nblk_dump_nblktab()
    } else
        error("Invalid dump argument " $1)

    return

    # for (key in nsymtab) {
    #     if (all_flag || ! nnam_system_p(key))
    #         keys[++cnt] = key
    # }

    # for (key in nseqtab) {
    #     split(key, fields, SUBSEP)
    #     if (fields[2] == "defined")
    #         keys[++cnt] = fields[1]
    # }
    # for (key in ncmdtab) {
    #     split(key, fields, SUBSEP)
    #     if (fields[2] == "defined")
    #         keys[++cnt] = fields[1]
    # }
    qsort(keys, 1, cnt)

    # Format definitions
    buf = EMPTY
    for (i = 1; i <= cnt; i++) {
        key = keys[i]
        if (nsym_defined_p(key))
            buf = buf nsym_definition_pp(key)
        else if (nseq_defined_p(key))
            buf = buf nseq_definition_pp(key)
        else if (ncmd_defined_p(key))
            buf = buf ncmd_definition_pp(key)
        else                    # Can't happen
            error("Name '" key "' not available:" $0)
    }
    buf = chop(buf)
    if (emptyp(buf)) {
        # I don't usually condone chatty programs, but it seems to me
        # that if the user asks for the symbol table and there's nothing
        # to print, she'd probably like to know.  Perhaps a config file
        # was not read properly...
        warn("Empty symbol table:" $0)
    } else if (dumpfile == EMPTY)  # No FILE arg provided to @dump command
        print_stderr(buf)
    # else {
    #     print buf > dumpfile
    #     close(dumpfile)
    # }
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

    if      (fs1 == "" && fs2 == "") error("Comparison operator invalid [_less_than]")
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
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E R R O R
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @debug, @echo, @error, @stderr, @warn TEXT
# debug, error and warn format the message with file & line, etc.
# echo and stderr do no additional formatting.
#
# @debug only prints its message if debugging is enabled.  The user can
# control this since __DEBUG__ is an unprotected symbol.  @debug is
# purposefully not given access to the various dbg() keys and levels.
#
#       | Cmd    | Format? | Exit? | Notes              |
#       |--------+---------+-------+--------------------|
#       | debug  | Format  | No    | Only if __DEBUG __ |
#       | echo   | Raw     | No    | Same as @stderr    |
#       | error  | Format  | Yes   |                    |
#       | secho  | Raw     | No    | No newline         |
#       | stderr | Raw     | No    | Same as @echo      |
#       | warn   | Format  | No    |                    |
function xeq_cmd__error(name, cmdline,
                       m2_will_exit, do_format, do_print, message)
{
    m2_will_exit = (name == "error")
    do_format = (name == "debug" || name == "error" || name == "warn")
    do_print  = (name != "debug" || debugp())
    if (cmdline == EMPTY) {
        message = format_message(name)
    } else {
        message = dosubs(cmdline)
        if (do_format)
            message = format_message(message)
    }
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
#       @  E X I T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @exit                 [CODE]
function xeq_cmd__exit(name, cmdline,
                       silent)
{
    silent = substr(name, 2, 1) == "s" # silent discards any pending streams
    __exit_code = (!emptyp(cmdline) && integerp(cmdline)) ? cmdline+0 : EX_OK
    end_program(silent ? MODE_STREAMS_DISCARD : MODE_STREAMS_SHIP_OUT)
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
function scan__for(                  for_block, body_block, scanstat, incr, info, nparts, level)
{
    dbg_print("for", 5, sprintf("(scan__for) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf_mode(curr_atmode()), $0))
    if (NF < 3)
        error("(scan__for) Bad parameters")

    # Create two new blocks: "for_block" for loop control (for_block),
    # and "body_block" for the loop code definition.
    for_block = nblk_new(BLK_FOR)
    dbg_print("for", 5, "(scan__for) for_block # " for_block " type " ppf_block_type(nblk_type(for_block)))
    body_block = nblk_new(BLK_AGG)
    dbg_print("for", 5, "(scan__for) body_block # " body_block " type " ppf_block_type(nblk_type(body_block)))

    nblktab[for_block, "body_block"] = body_block
    nblktab[for_block, "dstblk"] = body_block
    nblktab[for_block, "valid"] = FALSE
    nblktab[for_block, "loopvar"] = $2

    if ($1 == "@for") {
        #print_stderr("(scan__for) Found FOR: " $0)
        nblktab[for_block, "each"] = FALSE
        nblktab[for_block, "start"] = $3 + 0
        nblktab[for_block, "end"] = $4 + 0
        nblktab[for_block, "incr"] = incr = NF >= 5 ? ($5 + 0) : 1
        if (incr == 0)
            error("(scan__for) Increment value cannot be zero!")

    } else if ($1 == "@foreach") {
        #print_stderr("(scan__for) Found FOREACH: " $0)
        if ((nparts = nnam_parse($3, info)) != 1)
            error("(scan__for) Parse error: " $3)
        level = nnam_lookup(info)
        if (level == ERROR)
            error(sprintf("(scan__for) Name '%s' not found", info["name"]))
        if (! info["isarray"])
            error(sprintf("(scan__for) Name '%s' is not an array", info["name"]))
        nblktab[for_block, "each"] = TRUE
        nblktab[for_block, "arrname"] = $3
        nblktab[for_block, "level"] = level

    } else
        error("(scan__for) How did I get here?")

    dbg_print_block("for", 7, for_block, "(scan__for) for_block")
    nstk_push(__scan_stack, for_block) # Push it on to the scan_stack

    dbg_print("for", 5, "(scan__for) CALLING scan()")
    scanstat = scan() # scan() should return after it encounters @next
    dbg_print("for", 5, "(scan__for) RETURNED FROM scan() => " ppf_bool(scanstat))
    if (!scanstat)
        error("(scan__for) Scan failed")

    dbg_print("for", 5, "(scan__for) END => " for_block)
    return for_block
}


# @next VAR                       # end normal FOR loop
function scan__next(                   for_block)
{
    dbg_print("for", 3, sprintf("(scan__next) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf_mode(curr_atmode()), $0))

    # if (nstk_emptyp(__scan_stack))
    #     error("(scan__next) Scan stack is empty!")
    # for_block = nstk_pop(__scan_stack)
    # if ((nblktab[for_block, "type"] != BLK_FOR) ||
    #     (nblktab[for_block, "depth"] != nstk_depth(__scan_stack)))
    #     error("(scan__next) Corrupt scan stack")
    assert_scan_stack_okay(BLK_FOR)

    for_block = nstk_pop(__scan_stack)
    # dbg_print_block("for", 7, for_block, "(scan__next) for_block")
    if (nblktab[for_block, "loopvar"] != $2)
        error(sprintf("(scan__next) Variable mismatch; '%s' specified, but '%s' was expected",
                      $2, nblktab[for_block, "loopvar"]))
    nblktab[for_block, "valid"] = TRUE

    dbg_print("for", 3, sprintf("(scan__next) END => %d", for_block))
    return for_block
}


function xeq_blk__for(for_block,
                      blk_type)
{
    blk_type = nblktab[for_block, "type"]
    dbg_print("for", 3, sprintf("(xeq_blk__for) START dstblk=%d, for_block=%d, type=%s",
                                curr_dstblk(), for_block, ppf_block_type(blk_type)))
    dbg_print_block("for", 7, for_block, "(xeq_blk__for) for_block")
    if ((nblktab[for_block, "type"] != BLK_FOR) || \
        (nblktab[for_block, "valid"] != TRUE))
        error("(xeq_blk__for) Bad config")

    if (nblktab[for_block, "each"] == TRUE)
        execute__foreach(for_block)
    else
        execute__for(for_block)
}


function execute__for(for_block,
                      loopvar, start, end, incr, done, counter, body_block, new_level)
{
    # if (__loop_ctl != LOOP_NORMAL) {
    #     dbg_print("xeq", 3, "(execute__for) NOP due to loop_ctl=" __loop_ctl)
    #     return
    # }
    # Evaluate loop
    loopvar    = nblktab[for_block, "loopvar"]
    start      = nblktab[for_block, "start"] + 0
    end        = nblktab[for_block, "end"]   + 0
    incr       = nblktab[for_block, "incr"]  + 0
    done       = FALSE
    counter    = start
    body_block = nblktab[for_block, "body_block"]

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
        nnam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY)
        nsym_ll_write(loopvar, "", new_level, counter)
        dbg_print("for", 5, sprintf("(execute__for) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg_print("for", 5, sprintf("(execute__for) RETURNED FROM execute__block()"))
        lower_namespace()
        done = (incr > 0) ? (counter +=     incr ) > end \
                          : (counter -= abs(incr)) < end

        # Check for break or continue
        if (__loop_ctl == LOOP_BREAK) {
            __loop_ctl = LOOP_NORMAL
            break
        }
        if (__loop_ctl == LOOP_CONTINUE) {
            __loop_ctl = LOOP_NORMAL
            # Actual "continue" wouldn't do anything here since we're
            # about to re-iterate the loop anyway
        }
    }
    dbg_print("for", 1, "(execute__for) END")
}


function execute__foreach(for_block,
                          loopvar, arrname, level, keys, x, k, body_block, new_level)
{
    # if (__loop_ctl != LOOP_NORMAL) {
    #     dbg_print("xeq", 3, "(execute__foreach) NOP due to loop_ctl=" __loop_ctl)
    #     return
    # }
    loopvar = nblktab[for_block, "loopvar"]
    arrname = nblktab[for_block, "arrname"]
    level = nblktab[for_block, "level"]
    body_block = nblktab[for_block, "body_block"]
    dbg_print("for", 4, sprintf("(execute__foreach) loopvar='%s', arrname='%s'",
                                loopvar, arrname))
    # Find the keys
    for (k in nsymtab) {
        split(k, x, SUBSEP)
        if (x[1] == arrname && x[3] == level && x[4] == "symval")
            keys[x[2]] = 1
    }

    # Run the loop
    for (k in keys) {
        new_level = raise_namespace()
        nnam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_READONLY)
        nsym_ll_write(loopvar, "", new_level, k)
        dbg_print("for", 5, sprintf("(execute__foreach) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg_print("for", 5, sprintf("(execute__foreach) RETURNED FROM execute__block()"))
        lower_namespace()

        # Check for break or continue
        if (__loop_ctl == LOOP_BREAK) {
            __loop_ctl = LOOP_NORMAL
            break
        }
        if (__loop_ctl == LOOP_CONTINUE) {
            __loop_ctl = LOOP_NORMAL
            # Actual "continue" wouldn't do anything here since we're
            # about to re-iterate the loop anyway
        }
    }
    dbg_print("for", 1, "(execute__foreach) END")
}


function prt_blk__for(blknum)
{
    return sprintf("  valid   : %s\n" \
                   "  loopvar : %s\n"       \
                   "  start   : %d\n"       \
                   "  end     : %d\n"       \
                   "  incr    : %d\n"       \
                   "  body    : %d",
                   ppf_bool(nblktab[blknum, "valid"]),
                   nblktab[blknum, "loopvar"],
                   nblktab[blknum, "start"],
                   nblktab[blknum, "end"],
                   nblktab[blknum, "incr"],
                   nblktab[blknum, "body_block"])
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
function scan__if(                 name, if_block, true_block, scanstat)
{
    dbg_print("if", 3, sprintf("(scan__if) START dstblk=%d, $0='%s'", curr_dstblk(), $0))
    name = $1
    $1 = ""
    sub("^[ \t]*", "")

    # Create two new blocks: one for if_block, other for true branch
    if_block = nblk_new(BLK_IF)
    dbg_print("if", 5, "(scan__if) New block # " if_block " type " ppf_block_type(nblk_type(if_block)))
    true_block = nblk_new(BLK_AGG)
    dbg_print("if", 5, "(scan__if) New block # " true_block " type " ppf_block_type(nblk_type(true_block)))

    if (name ~ /@ifn?def/) {
        assert_nsym_valid_name($0)
        nblktab[if_block, "condition"] = "defined(" $0 ")"
    } else
        nblktab[if_block, "condition"] = $0

    nblktab[if_block, "init_negate"] = (name == "@unless" || name == "@ifndef")
    nblktab[if_block, "seen_else"]  = FALSE
    nblktab[if_block, "true_block"] = true_block
    nblktab[if_block, "dstblk"] = true_block
    nblktab[if_block, "valid"]      = FALSE
    dbg_print_block("if", 7, if_block, "(scan__if) if_block")
    nstk_push(__scan_stack, if_block) # Push it on to the scan_stack

    dbg_print("if", 5, "(scan__if) CALLING scan()")
    scanstat = scan() # scan() should return after it encounters @endif
    dbg_print("if", 5, "(scan__if) RETURNED FROM scan() => " ppf_bool(scanstat))
    if (!scanstat)
        error("(scan__if) Scan failed")

    dbg_print("if", 5, "(scan__if) END; => " if_block)
    return if_block
}


# @else
function scan__else(                   if_block, false_block)
{
    dbg_print("if", 3, sprintf("(scan__else) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf_mode(curr_atmode())))

    if (nstk_emptyp(__scan_stack))
        error("(scan__else) Scan stack is empty!")
    if_block = nstk_top(__scan_stack)
    if (nblktab[if_block, "type"] != BLK_IF)
        error("(scan__else) Scan error: top != IF")

    # Check if already seen @else
    if (nblktab[if_block, "seen_else"] == TRUE)
        error("(scan__else) Cannot have more than one @else")

    # Create a new block for the False branch and make it current
    nblktab[if_block, "seen_else"] = TRUE
    false_block = nblk_new(BLK_AGG)
    nblktab[if_block, "false_block"] = false_block
    nblktab[if_block, "dstblk"]  = false_block
    return false_block
}


# @endif
function scan__endif(                    if_block)
{
    dbg_print("if", 3, sprintf("(scan__endif) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf_mode(curr_atmode())))
    # if (nstk_emptyp(__scan_stack))
    #     error("(scan__endif) Scan stack is empty!")
    # if_block = nstk_pop(__scan_stack)
    # if ((nblktab[if_block, "type"] != BLK_IF) ||
    #     (nblktab[if_block, "depth"] != nstk_depth(__scan_stack)))
    #     error("(scan__endif) Corrupt scan stack")
    assert_scan_stack_okay(BLK_IF)

    if_block = nstk_pop(__scan_stack)
    nblktab[if_block, "valid"] = TRUE

    return if_block
}


function xeq_blk__if(if_block,
                     blk_type, condition, condval)
{
    blk_type = nblktab[if_block , "type"]
    dbg_print("if", 3, sprintf("(xeq_blk__if) START dstblk=%d, if_block=%d, type=%s",
                               curr_dstblk(), if_block, ppf_block_type(blk_type)))

    dbg_print_block("if", 7, if_block, "(xeq_blk__if) if_block")
    if ((nblktab[if_block, "type"] != BLK_IF) || \
        (nblktab[if_block, "valid"] != TRUE))
        error("(xeq_blk__if) Bad config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    condition = nblktab[if_block, "condition"]
    condval = evaluate_condition(condition, nblktab[if_block, "init_negate"])
    dbg_print("if", 1, sprintf("(xeq_blk__if) evaluate_condition('%s') => %s", condition, ppf_bool(condval)))
    if (condval == ERROR)
        error("@if: Uncaught error")

    raise_namespace()
    if (condval) {
        dbg_print("if", 5, sprintf("(xeq_blk__if) [true branch] CALLING execute__block(%d)",
                                   nblktab[if_block, "true_block"]))
        execute__block(nblktab[if_block, "true_block"])
        dbg_print("if", 5, sprintf("(xeq_blk__if) RETURNED FROM execute__block()"))
    } else if (nblktab[if_block, "seen_else"] == TRUE) {
        dbg_print("if", 5, sprintf("(xeq_blk__if) [false branch] CALLING execute__block(%d)",
                                   nblktab[if_block, "false_block"]))
        execute__block(nblktab[if_block, "false_block"])
        dbg_print("if", 5, sprintf("(xeq_blk__if) RETURNED FROM execute__block()"))
    }
    lower_namespace()

    dbg_print("if", 3, sprintf("(xeq_blk__if) END"))
}


# Returns TRUE, FALSE, or ERROR
#           @if NAME
#           @if SOMETHING <OP> TEXT
#           @if defined(NAME)
#           @if env(VAR)
#           @if exists(FILE)
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
    dbg_print("if", 4, sprintf("(evaluate_condition) After dosubs, cond='%s'", cond))

    if (cond ~ /^[0-9]+$/) {
        dbg_print("if", 6, sprintf("(evaluate_condition) Found simple integer '%s'", cond))
        retval = (cond+0) != 0

    } else if (cond ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
        dbg_print("if", 6, sprintf("(evaluate_condition) Found simple name '%s'", cond))
        assert_nsym_valid_name(cond)
        retval = nsym_true_p(cond)

    } else if (match(cond, "^defined(.*)$")) {
        name = substr(cond, RSTART+8, RLENGTH-9)
        dbg_print("if", 6, sprintf("(evaluate_condition) Found condition defined(%s)", name))
        if (name == EMPTY) return ERROR
        assert_nsym_valid_name(name)
        retval = nsym_defined_p(name)

    } else if (match(cond, "^env(.*)$")) {
        name = substr(cond, RSTART+4, RLENGTH-5)
        dbg_print("if", 6, sprintf("(evaluate_condition) Found condition env(%s)", name))
        if (name == EMPTY) return ERROR
        assert_valid_env_var_name(name)
        retval = name in ENVIRON

    } else if (match(cond, "^exists(.*)$")) {
        name = substr(cond, RSTART+7, RLENGTH-8)
        dbg_print("if", 6, sprintf("(evaluate_condition) Found condition exists(%s)", name))
        if (name == EMPTY) return ERROR
        retval = path_exists_p(name)
        #print_stderr(sprintf("File '%s' exists?  %s", name, ppf_bool(retval)))

    } else if (match(cond, ".* (in|IN) .*")) { # poor regexp, fragile
        # This whole section is pretty easy to confound....
        dbg_print("if", 5, sprintf("(evaluate_condition) Found IN expression"))
        # Find name
        sp = index(cond, " ")
        key = substr(cond, 1, sp-1)
        cond = substr(cond, sp+1)
        # Find the condition
        match(cond, " *(in|IN) *")
        arr = substr(cond, RSTART+3)
        dbg_print("if", 5, sprintf("key='%s', op='%s', arr='%s'", key, "IN", arr))

        if (nnam_parse(arr, info) == ERROR)
            error("Name '" arr "' not found")
        level = nnam_lookup(info)
        if (level == ERROR)
            error("Name '" arr "' lookup failed")
        if (info["isarray"] == FALSE)
            error(sprintf("'%s' is not an array", arr))
        
        retval = nsym_ll_in(arr, key, info["level"])

    } else if (match(cond, ".* (<|<=|==|!=|>=|>) .*")) { # poor regexp, fragile
        # This whole section is pretty easy to confound....
        dbg_print("if", 6, sprintf("(evaluate_condition) Found expression"))
        # Find name
        sp = index(cond, " ")
        lhs = substr(cond, 1, sp-1)
        cond = substr(cond, sp+1)
        # Find the condition
        match(cond, "[<>=!]*")
        op = substr(cond, RSTART, RLENGTH)
        rhs = substr(cond, RLENGTH+2)

        if (nsym_valid_p(lhs) && nsym_defined_p(lhs))
            lval = nsym_fetch(lhs)
        else if (nseq_defined_p(lhs))
            lval = nseq_ll_read(lhs)
        else
            lval = lhs

        if (nsym_valid_p(rhs) && nsym_defined_p(rhs))
            rval = nsym_fetch(rhs)
        else if (nseq_defined_p(rhs))
            rval = nseq_ll_read(rhs)
        else
            rval = rhs

        dbg_print("if", 6, sprintf("(evaluate_condition) lhs='%s'[%s], op='%s', rhs='%s'[%s]", lhs, lval, op, rhs, rval))

        if      (op == "<")                 retval = lval <  rval
        else if (op == "<=")                retval = lval <= rval
        else if (op == "="  || op == "==")  retval = lval == rval
        else if (op == "!=" || op == "<>")  retval = lval != rval
        else if (op == ">=")                retval = lval >= rval
        else if (op == ">")                 retval = lval >  rval
        else
            error("Comparison operator '" op "' invalid")
    }

    if (negate && retval != ERROR)
        retval = !retval
    dbg_print("if", 3, sprintf("(evaluate_condition) END retval=%s", (retval == ERROR) ? "ERROR" \
                                                                   : ppf_bool(retval)))
    return retval
}


function prt_blk__if(blknum)
{
    return sprintf("  valid       : %s\n" \
                   "  condition   : '%s'\n" \
                   "  true_block  : %d\n" \
                   "  seen_else   : %s\n" \
                   "  false_block : %s",
                   ppf_bool(nblktab[blknum, "valid"]),
                   nblktab[blknum, "condition"],
                   nblktab[blknum, "true_block"],
                   ppf_bool(nblktab[blknum, "seen_else"]),
                   ((blknum, "false_block") in nblktab) \
                     ? nblktab[blknum, "false_block"]     \
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
                         readstat)
{
    dbg_print("scan", 5, sprintf("(xeq_cmd__ignore) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf_mode(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)

    dbg_print("scan", 5, "(xeq_cmd__ignore) CALLING read_lines_until()")
    readstat = read_lines_until(cmdline, DISCARD)
    dbg_print("scan", 5, "(xeq_cmd__ignore) RETURNED FROM read_lines_until() => " ppf_bool(readstat))
    if (!readstat)
        error("(xeq_cmd__ignore) Scan failed")
    dbg_print("scan", 5, "(xeq_cmd__ignore) END")
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
    dbg_print("scan", 5, sprintf("(xeq_cmd__include) name='%s', cmdline='%s'",
                                 name, cmdline))
    if (cmdline == EMPTY)
        error("Bad parameters:" $0)
    # paste does not process macros
    silent   = (first(name) == "s") # silent mutes file errors, even in strict mode

    # $1 = ""
    # sub("^[ \t]*", "")
    filename = rm_quotes(cmdline) # dosubs($0)
    file_block = prep_file(filename)
    nblktab[file_block, "dstblk"] = curr_dstblk()
    nblktab[file_block, "atmode"] = substr(name, length(name)-4) == "paste" \
                                      ? MODE_AT_LITERAL : MODE_AT_PROCESS
    # prep_file doesn't push the BLK_FILE onto the __scan_stack,
    # so we have to do that ourselves due to customization
    dbg_print("scan", 7, sprintf("(xeq_cmd__include) Pushing file block %d (%s) onto scan_stack", file_block, filename))
    nstk_push(__scan_stack, file_block)

    dbg_print("scan", 5, "(xeq_cmd__include) CALLING scan__file()")
    rc = scan__file()
    dbg_print("scan", 5, "(xeq_cmd__include) RETURNED FROM scan__file()")
    if (!rc) {
        if (silent) return
        error_text = "File '" filename "' does not exist:" $0
        if (strictp("file"))
            error(error_text)
        else
            warn(error_text)
    }
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
    assert_nsym_okay_to_define(sym)
    assert_nsym_defined(sym, "incr")
    if (NF >= 2 && ! integerp($2))
        error("Value '" $2 "' must be numeric:" $0)
    incr = (NF >= 2) ? $2 : 1
    nsym_increment(sym, (name == "incr") ? incr : -incr)
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
    assert_nsym_okay_to_define(sym)

    getstat = getline input < "/dev/tty"
    if (getstat == ERROR) {
        warn("Error reading file '/dev/tty' [input]:" $0)
        input = EMPTY
    }
    nsym_store(sym, input)
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
# @local FOO adds to nnamtab (as a scalar) in the current namespace, does not define it
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
    if (!nnam_valid_with_strict_as(sym, strictp("symbol")))
        error("@local: Invalid name")
    assert_nsym_okay_to_define(sym)
    if (nnam_ll_in(sym, __namespace))
        error("Symbol '" sym "' already defined")
    nnam_ll_write(sym, __namespace, TYPE_SYMBOL)
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
function scan__longdef(    sym, nsym_block, body_block, scanstat)
{
    dbg_print("nsym", 5, "(scan__longdef) START dstblk=" curr_dstblk() ", mode=" ppf_mode(curr_atmode()) "; $0='" $0 "'")

    # Create two new blocks: one for the "longdef" block, other for definition body
    nsym_block = nblk_new(BLK_LONGDEF)
    dbg_print("nsym", 5, "(scan__longdef) New block # " nsym_block " type " ppf_block_type(nblk_type(nsym_block)))
    body_block = nblk_new(BLK_AGG)
    dbg_print("nsym", 5, "(scan__longdef) New block # " body_block " type " ppf_block_type(nblk_type(body_block)))

    $1 = ""
    sym = $2
    assert_nsym_okay_to_define(sym)

    nblktab[nsym_block, "name"] = sym
    nblktab[nsym_block, "body_block"] = body_block
    nblktab[nsym_block, "dstblk"] = body_block
    nblktab[nsym_block, "valid"] = FALSE
    dbg_print_block("nsym", 7, nsym_block, "(scan__longdef) nsym_block")
    nstk_push(__scan_stack, nsym_block) # Push it on to the scan_stack

    dbg_print("nsym", 5, "(scan__longdef) CALLING scan()")
    scanstat = scan() # scan() should return after it encounters @endcmd
    dbg_print("nsym", 5, "(scan__longdef) RETURNED FROM scan() => " ppf_bool(scanstat))
    if (!scanstat)
        error("(scan__longdef) Scan failed")

    dbg_print("nsym", 5, "(scan__longdef) END => " nsym_block)
    return nsym_block
}


function scan__endlongdef(    nsym_block)
{
    dbg_print("nsym", 3, sprintf("(scan__endlongdef) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf_mode(curr_atmode())))

    # if (nstk_emptyp(__scan_stack))
    #     error("(scan__endlongdef) Scan stack is empty!")
    # nsym_block = nstk_pop(__scan_stack)
    # if ((nblktab[nsym_block, "type"] != BLK_LONGDEF) ||
    #     (nblktab[nsym_block, "depth"] != nstk_depth(__scan_stack)))
    #     error("(scan__endlongdef) Corrupt scan stack")
    assert_scan_stack_okay(BLK_LONGDEF)
    nsym_block = nstk_pop(__scan_stack)
    nblktab[nsym_block, "valid"] = TRUE
    dbg_print("nsym", 3, sprintf("(scan__endlongdef) END => %d", nsym_block))
    return nsym_block
}


function xeq_blk__longdef(longdef_block,
                          blk_type, name, body_block, opm)
{
    blk_type = nblktab[longdef_block, "type"]
    dbg_print("nsym", 3, sprintf("(xeq_blk__longdef) START dstblk=%d, longdef_block=%d, type=%s",
                                 curr_dstblk(), longdef_block, ppf_block_type(blk_type)))
    dbg_print_block("nsym", 7, longdef_block, "(xeq_blk__longdef) longdef_block")
    if ((nblktab[longdef_block, "type"] != BLK_LONGDEF) ||
        (nblktab[longdef_block, "valid"] != TRUE))
        error("(xeq_blk__longdef) Bad config")

    name = nblktab[longdef_block, "name"]
    assert_nsym_okay_to_define(name)

    body_block = nblktab[longdef_block, "body_block"]
    dbg_print_block("nsym", 3, body_block, "(xeq_blk__longdef) body_block")
    nsym_store(name, nblk_to_string(body_block))
    dbg_print("nsym", 1, "(xeq_blk__longdef) END")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  M 2
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

# Undocumented - Reserved for internal use
# @m2                   ARGS
function xeq_cmd__m2(name, cmdline,
                     x)
{
    $0 = cmdline
    dbg_print("xeq", 1, sprintf("(xeq_cmd__m2) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    if (NF == 0)
        error("Bad parameters:" $0)
    x = int($1)
    if (x == 0)
        clear_debugging()
    else if (x == 1) {
        # Debug namespaces
        dbg_set_level("for",        5)
        dbg_set_level("namespace",  5)
        dbg_set_level("ncmd",       5)
        dbg_set_level("nnam",       3)
        dbg_set_level("nsym",       5)

    } else if (x == 2)
        dump_scan_stack()

    else
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
function scan__newcmd(                     name, newcmd_block, body_block, scanstat, nparam, p, pname)
{
    nparam = 0
    dbg_print("ncmd", 5, "(scan__newcmd) START dstblk=" curr_dstblk() ", mode=" ppf_mode(curr_atmode()) "; $0='" $0 "'")

    # Create two new blocks: one for the "new command" block, other for command body
    newcmd_block = nblk_new(BLK_USER)
    dbg_print("ncmd", 5, "(scan__newcmd) New block # " newcmd_block " type " ppf_block_type(nblk_type(newcmd_block)))
    body_block = nblk_new(BLK_AGG)
    dbg_print("ncmd", 5, "(scan__newcmd) New block # " body_block " type " ppf_block_type(nblk_type(body_block)))

    $1 = ""
    name = $2
    while (match(name, "{.*}")) {
        p = ++nparam
        pname = substr(name, RSTART+1, RLENGTH-2)
        dbg_print("ncmd", 5, sprintf("(scan__newcmd) Parameter %d : %s",
                                     p, pname))
        nblktab[newcmd_block, "param", p] = pname
        name = substr(name, 1, RSTART-1) substr(name, RSTART+RLENGTH)
    }
    assert_ncmd_okay_to_define(name)

    nblktab[newcmd_block, "name"] = name
    nblktab[newcmd_block, "body_block"] = body_block
    nblktab[newcmd_block, "dstblk"] = body_block
    nblktab[newcmd_block, "valid"] = FALSE
    nblktab[newcmd_block, "nparam"] = nparam
    dbg_print_block("ncmd", 7, newcmd_block, "(scan__newcmd) newcmd_block")
    nstk_push(__scan_stack, newcmd_block) # Push it on to the scan_stack

    dbg_print("ncmd", 5, "(scan__newcmd) CALLING scan()")
    scanstat = scan() # scan() should return after it encounters @endcmd
    dbg_print("ncmd", 5, "(scan__newcmd) RETURNED FROM scan() => " ppf_bool(scanstat))
    if (!scanstat)
        error("(scan__newcmd) Scan failed")

    dbg_print("ncmd", 5, "(scan__newcmd) END => " newcmd_block)
    return newcmd_block
}


function scan__endcmd(                     newcmd_block)
{
    dbg_print("ncmd", 3, sprintf("(scan__endcmd) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf_mode(curr_atmode())))

    # if (nstk_emptyp(__scan_stack))
    #     error("(scan__endcmd) Scan stack is empty!")
    # newcmd_block = nstk_pop(__scan_stack)
    # if ((nblktab[newcmd_block, "type"] != BLK_USER) ||
    #     (nblktab[newcmd_block, "depth"] != nstk_depth(__scan_stack)))
    #     error("(scan__endcmd) Corrupt scan stack")
    assert_scan_stack_okay(BLK_USER)
    newcmd_block = nstk_pop(__scan_stack)
    nblktab[newcmd_block, "valid"] = TRUE
    dbg_print("ncmd", 3, sprintf("(scan__endcmd) END => %d", newcmd_block))
    return newcmd_block
}


function ship_out__user(cmdline,
                        dstblk, stream, name)
{
    dstblk = curr_dstblk()
    dbg_print("ship_out", 3, sprintf("(ship_out__user) START dstblk=%d, cmdline='%s'",
                                     dstblk, cmdline))
    name = extract_cmd_name(cmdline)

    if (dstblk < 0) {
        dbg_print("ship_out", 3, "(ship_out__user) END, because dstblk <0")
        return
    }
    if (dstblk > MAX_STREAM) {
        # Block
        dbg_print("ship_out", 5, sprintf("(ship_out__user) END Appending user cmd %s to block %d", name, dstblk))
        nblk_append(dstblk, SLOT_USER, cmdline)
        return
    }
    if (dstblk != TERMINAL)
        error(sprintf("(ship_out__user) dstblk is %d, not zero!", dstblk))

    if ((stream = divnum()) > TERMINAL) {
        dbg_print("ship_out", 3, sprintf("(ship_out__user) stream=%d", stream))
        # Name is known to be a command, therefore its code must be in the symbol table
        sub(/^[ \t]*[^ \t]+[ \t]*/, "", cmdline)
        dbg_print("ship_out", 3, sprintf("(ship_out__user) name='%s', cmdline now '%s'",
                                         name, cmdline))
        dbg_print("ship_out", 5, sprintf("(ship_out__user) END Appending user cmd %s to stream %d", name, stream))
        nblk_append(stream, SLOT_USER, cmdline)
        return
    }

    # dstblk is definitely zero, so execute the command
    dbg_print("ship_out", 3, sprintf("(ship_out__user) CALLING execute__user('%s', '%s')",
                                     name, cmdline))
    #sub(/^[ \t]*[^ \t]+[ \t]*/, "", cmdline)
    execute__user(name, cmdline) # dosubs(cmdline))
    dbg_print("ship_out", 3, sprintf("(ship_out__user) RETURNED FROM execute__user('%s', ...)",
                                     name))
    dbg_print("ship_out", 3, sprintf("(ship_out__user) END"))
}


function xeq_blk__user(newcmd_block,
                       blk_type, name)
{
    blk_type = nblktab[newcmd_block, "type"]
    dbg_print("ncmd", 3, sprintf("(xeq_blk__user) START dstblk=%d, newcmd_block=%d, type=%s",
                                 curr_dstblk(), newcmd_block, ppf_block_type(blk_type)))
    dbg_print_block("ncmd", 7, newcmd_block, "(xeq_blk__user) newcmd_block")
    if ((nblktab[newcmd_block, "type"] != BLK_USER) ||
        (nblktab[newcmd_block, "valid"] != TRUE))
        error("(xeq_blk__user) Bad config")

    # Instantiate command, but do not run.  "@newcmd FOO" is just declaring FOO.
    # @FOO{...} actually ships it out (and is done under ship_out/xeq_user).
    name = nblktab[newcmd_block, "name"]
    dbg_print("ncmd", 3, sprintf("(xeq_blk__user) name='%s', level=%d: TYPE_USER, value=%d",
                                 name, __namespace, newcmd_block))
    nnam_ll_write(name, __namespace, TYPE_USER)
    ncmd_ll_write(name, __namespace, newcmd_block)

    dbg_print("ncmd", 1, "(xeq_blk__user) END")
}


function execute__user(name, cmdline,
                       level, info, code,
                       old_level,
                       user_block,
                       args, arg, narg, argval)
{
    if (__loop_ctl != LOOP_NORMAL) {
        dbg_print("xeq", 3, "(execute__user) NOP due to loop_ctl=" __loop_ctl)
        return
    }
    dbg_print("xeq", 3, sprintf("(execute__user) START name='%s', cmdline='%s'",
                                name, cmdline))

    old_level = __namespace

    if (nnam_parse(name, info) == ERROR)
        error("(execute__user) Parse error on '" name "' -- should not happen")
    if ((level = nnam_lookup(info)) == ERROR)
        error("(execute__user) nnam_lookup failed -- should not happen")

    # See if it's a user command
    if (flag_1false_p((code = nnam_ll_read(name, level)), TYPE_USER))
        error("(execute__user) " name " seems to no longer be a command")

    user_block = ncmd_ll_read(name, level)

    dbg_print_block("xeq", 7, user_block, "(execute__user) user_block")
    dbg_print_block("xeq", 7, nblktab[user_block, "body_block"], "(execute__user) body_block")

    # Check for cmd arguments
    narg = 0
    while (match(cmdline, "{.*}")) {
        arg = ++narg
        argval = substr(cmdline, RSTART+1, RLENGTH-2)
        dbg_print("scan", 5, sprintf("(scan) Arg %d : %s",
                                     arg, argval))
        #print_stderr("args[" arg "] = " argval)
        args[arg] = argval
        cmdline = substr(cmdline, 1, RSTART-1) substr(cmdline, RSTART+RLENGTH)
    }

    execute__user_body(user_block, args)

    if (__namespace != old_level)
        error("(execute__user) @%s %s: Namespace level mismatch")
}


function execute__user_body(user_block, args,
                       blk_type, new_level, i, p, body_block)
{
    blk_type = nblktab[user_block , "type"]
    dbg_print("ncmd", 3, sprintf("(execute__user_body) START dstblk=%d, user_block=%d, type=%s",
                                 curr_dstblk(), user_block, ppf_block_type(blk_type)))
    dbg_print_block("ncmd", 7, user_block, "(execute__user_body) user_block")
    if ((nblktab[user_block, "type"] != BLK_USER) ||
        (nblktab[user_block, "valid"] != TRUE))
        error("(execute__user_body) Bad config")

    # Always raise namespace level, even if nparam == 0
    # because user-mode might run @local
    new_level = raise_namespace()
    body_block = nblktab[user_block, "body_block"]
    dbg_print_block("ncmd", 7, body_block, "(execute__user_body) body_block")

    # Instantiate parameters
    for (i = 1; i <= nblktab[user_block, "nparam"]; i++) {
        p = nblktab[user_block, "param", i]
        nnam_ll_write(p, new_level, TYPE_SYMBOL)
        nsym_ll_write(p, "", new_level, args[i])
        #print_stderr("Setting param " p " to '" args[i] "'")
    }

    dbg_print("ncmd", 5, sprintf("(execute__user_body) CALLING execute__block(%d)", body_block))
    execute__block(body_block)
    dbg_print("ncmd", 5, sprintf("(execute__user_body) RETURNED FROM execute__block()"))

    lower_namespace()
    dbg_print("ncmd", 1, "(execute__user_body) END")
}


function prt_blk__user(blknum,
                       slotinfo, count, x)
{
    slotinfo = ""
    count = nblktab[blknum, "nparam"]
    if (count > 0 ) {
        slotinfo = "  Parameters:\n"
        for (x = 1; x <= count; x++)
            slotinfo = slotinfo sprintf("  [%d]=%s\n",
                                        x, nblktab[blknum, "param", x])
    }
    return sprintf("  name    : %s\n" \
                   "  valid   : %s\n" \
                   "  nparam  : %d\n" \
                   "  body    : %d\n" \
                   "%s",
                   nblktab[blknum, "name"],
                   ppf_bool(nblktab[blknum, "valid"]),
                   nblktab[blknum, "nparam"],
                   nblktab[blknum, "body_block"],
                   chomp(slotinfo))
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
                           readstat)
{
    dbg_print("scan", 5, sprintf("(xeq_cmd__nextfile) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf_mode(curr_atmode()), $0))

    dbg_print("scan", 5, "(xeq_cmd__nextfile) CALLING read_lines_until()")
    readstat = read_lines_until("", DISCARD)
    dbg_print("scan", 5, "(xeq_cmd__nextfile) RETURNED FROM read_lines_until() => " ppf_bool(readstat))
    if (!readstat)
        error("(xeq_cmd__nextfile) Scan failed")
    dbg_print("scan", 5, "(xeq_cmd__nextfile) END")
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
    if ((nparts = nnam_parse(arr, info)) == ERROR)
        error(sprintf("(xeq_cmd__readarray) nnam_parse('%s') failed", arr))
    if (nparts == 2)
        error(sprintf("(xeq_cmd__readarray) Array name cannot have subscripts: '%s'", arr))

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
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
    nnamtab[arr, level] = code = flag_set_clear(code, FLAG_BLKARRAY, "")
    dbg_print("xeq", 5, sprintf("(xeq_cmd__readarray) nnamtab[%s,%d] = %s", arr, level, code))
    assert_nsym_okay_to_define(arr)

    # check if variable name available

    # create a new Agg block
    agg_block = nblk_new(BLK_AGG)
    dbg_print("scan", 5, sprintf("nsymtab['%s','%s',%d,'agg_block'] = %d",
                                 arr, key, level, agg_block))
    nsymtab[arr, key, level, "agg_block"] = agg_block

    # create a new file scanner : dstblk = agg, mode=literal
    file_block = prep_file(filename)
    nblktab[file_block, "dstblk"] = agg_block
    nblktab[file_block, "atmode"] = MODE_AT_LITERAL
    # Push scanner manually because prep_file doesn't do that
    dbg_print("scan", 7, sprintf("(xeq_cmd__readarray) Pushing file block %d (%s) onto scan_stack", file_block, filename))
    nstk_push(__scan_stack, file_block)

    dbg_print("scan", 5, "(xeq_cmd__readarray) CALLING scan__file()")
    rc = scan__file()
    dbg_print("scan", 5, "(xeq_cmd__readarray) RETURNED FROM scan__file()")
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
    # This is not intended to be a full-blown file inputter (use @readarray
    # for that) but rather just to read short snippets like a file path
    # or username.  As usual, multi-line values are accepted but the final
    # trailing newline, if any, is stripped.
    #
    # We could play games and use fancy file blocks and literal atmode, but we
    # really just want to read in a file and assign its contents to a symbol.

    $0 = cmdline
    if (NF < 2)
        error("(xeq_cmd__readfile) Bad parameters:" $0)
    silent = first(name) == "s" # silent mutes file errors, even in strict mode
    sym  = $1
    assert_nsym_okay_to_define(sym)
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
        val = val line "\n"
    }
    close(filename)
    nsym_store(sym, chomp(val))
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

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("(xeq_cmd__readonly) nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    if (level == ERROR)
        error("(xeq_cmd__readonly) nnam_lookup(info) failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # nsymtab because NAME[KEY] might not be defined.
    code = info["code"]

    assert_nsym_okay_to_define(sym)
    assert_nsym_defined(sym, "readonly")

    # if (flag_allfalse_p(code, TYPE_ARRAY TYPE_SYMBOL))
    #     error("@readonly: name must be symbol or array")
    if (flag_1true_p(code, FLAG_SYSTEM))
        error("@readonly: name protected")
    nnam_ll_write(name, level, flag_set_clear(code, FLAG_READONLY))
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
    dbg_print("nseq", 1, sprintf("(xeq_cmd__sequence) START dstblk=%d, name=%s, cmdline='%s'",
                                curr_dstblk(), name, cmdline))
    if (NF == 0)
        error("Bad parameters: Missing sequence name:" $0)
    id = $1
    assert_nseq_valid_name(id)
    if (NF == 1)
        $2 = "create"
    action = $2
    if (action != "create" && !nseq_defined_p(id))
        error("Name '" id "' not defined [sequence]:" $0)
    if (NF == 2) {
        if (action == "create") {
            assert_nseq_okay_to_define(id)
            nnam_ll_write(id, GLOBAL_NAMESPACE, TYPE_SEQUENCE FLAG_INTEGER)
            nseqtab[id, "incr"] = SEQ_DEFAULT_INCR
            nseqtab[id, "init"] = SEQ_DEFAULT_INIT
            nseqtab[id, "fmt"]  = nsym_ll_read("__FMT__", "seq", GLOBAL_NAMESPACE)
            nseq_ll_write(id, SEQ_DEFAULT_INIT)
        } else if (action == "delete") {
            nseq_destroy(id)
        } else if (action == "next") { # Increment counter only, no output
            nseq_ll_incr(id, nseqtab[id, "incr"])
        } else if (action == "prev") { # Decrement counter only, no output
            nseq_ll_incr(id, -nseqtab[id, "incr"])
        } else if (action == "restart") { # Set current counter value to initial value
            nseq_ll_write(id, nseqtab[id, "init"])
        } else
            error("Bad parameters:" $0)
    } else {    # NF >= 4
        saveline = $0
        dbg_print("nseq", 2, sprintf("(xeq_cmd__sequence) cmdline was '%s'", cmdline))
        #sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/, "") # a + this time because ARG is required
        sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+/, "", cmdline) # a + this time because ARG is required
        dbg_print("nseq", 2, sprintf("(xeq_cmd__sequence) cmdline now '%s'", cmdline))
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
            dbg_print("nseq", 2, sprintf("(xeq_cmd__sequence) fmt now '%s'", arg))
            nseqtab[id, "fmt"] = arg
        } else if (action == "incr") {
            # incr N :: Set increment value to N.
            if (!integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            if (arg+0 == 0)
                error(sprintf("Bad parameters in 'incr':%s", saveline))
            nseqtab[id, "incr"] = int(arg)
        } else if (action == "init") {
            # init N :: Set initial  value to N.  If current
            # value == old init value (i.e., never been used), then set
            # the current value to the new init value also.  Otherwise
            # current value remains unchanged.
            if (!integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            if (nseq_ll_read(id) == nseqtab[id, "init"])
                nseq_ll_write(id, int(arg))
            nseqtab[id, "init"] = int(arg)
        } else if (action == "set") {
            # set N :: Set counter value directly to N.
            if (!integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            nseq_ll_write(id, int(arg))
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
    save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    delim = $1
    if (NF == 1) {              # @shell DELIM
        sendto = default_shell()
    } else {                    # @shell DELIM /usr/ucb/mail
        $1 = ""
        sub("^[ \t]*", "")
        sendto = rm_quotes(dosubs($0))
    }

    shell_data_blk = nblk_new(BLK_AGG)
    readstat = read_lines_until(delim, shell_data_blk)
    if (readstat != TRUE)
        error("Delimiter '" delim "' not found:" save_line, "", save_lineno)

    # Don't check security level until now so we can properly read to
    # the delimiter.
    if (secure_level() >= 1) {
        warn("(xeq_cmd__shell) @shell - Security violation")
        return
    }

    shell_text_in = nblk_to_string(shell_data_blk)
    dbg_print("scan", 5, sprintf("(xeq_cmd__shell) shell_text_in='%s'", shell_text_in))
    
    path_fmt    = sprintf("%sm2-%d.shell-%%s", tmpdir(), nsym_fetch("__PID__"))
    input_file  = sprintf(path_fmt, "in")
    output_file = sprintf(path_fmt, "out")
    print dosubs(shell_text_in) > input_file
    close(input_file)

    # Don't tell me how fragile this is, we're whistling past the graveyard
    # here.  But it suffices to run /bin/sh, which is enough for now.
    shell_cmdline = sprintf("%s < %s > %s", sendto, input_file, output_file)
    nsym_ll_write("__SHELL__", "", GLOBAL_NAMESPACE, system(shell_cmdline))
    while (TRUE) {
        getstat = getline line < output_file
        if (getstat == ERROR)
            warn("Error reading file '" output_file "' [shell]")
        if (getstat != OKAY)
            break
        output_text = output_text line "\n" # Read a line
    }
    close(output_file)

    exec_prog_cmdline("rm", ("-f " input_file))
    exec_prog_cmdline("rm", ("-f " output_file))
    ship_out__text(chomp(output_text))
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
                          i, scanner)
{
    if (nstk_emptyp(__scan_stack))
        error("(xeq_cmd__typeout) Scan stack is empty")

    for (i = nstk_depth(__scan_stack); i > 0; i--) {
        dbg_print_block("scan", -1, __scan_stack[i], sprintf("(xeq_cmd__typeout) __scan_stack[%d]", i))
        scanner = __scan_stack[i]
        if (nblk_type(scanner) == BLK_FILE) {
            dbg_print_block("scan", 7, scanner, "(xeq_cmd__typeout) scanner")
            dbg_print("scan", 5, sprintf("(xeq_cmd__typeout) Changing block %d file '%s' mode to Literal",
                                         scanner, nblktab[scanner, "filename"]))
            nblktab[scanner, "atmode"] = MODE_AT_LITERAL
            return
        }
    }
    error("(xeq_cmd__typeout) Could not find FILE scanner")
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

    dbg_print("nsym", 4, sprintf("(xeq_cmd__undefine) START; sym=%s", sym))

    # This is the old way:
    # if (nseq_valid_p(sym) && nseq_defined_p(sym))
    #     nseq_destroy(sym)
    # else if (ncmd_valid_p(sym) && ncmd_defined_p(sym)) {
    #     ncmd_destroy(sym)
    # } else {
    #     assert_nsym_valid_name(sym)
    #     assert_nsym_unprotected(sym)
    #     # System symbols, even unprotected ones -- despite being subject
    #     # to user modification -- cannot be undefined.
    #     if (nnam_system_p(sym))
    #         error("Name '" sym "' not available:" $0)
    #     dbg_print("symbol", 3, ("About to sym_destroy('" sym "')"))
    #     nsym_destroy(sym)
    # }

    # A better way:
    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("(xeq_cmd__undefine) ERROR nnam_parse('" sym "') failed")
    }
    if ((level = nnam_lookup(info)) == ERROR) {
        error("(xeq_cmd__undefine) '" sym "' not found")
    }
    if ((type = info["type"]) == TYPE_SYMBOL)
        nsym_destroy(info["name"], info["key"], info["level"])
    else if (type == TYPE_SEQUENCE)
        nseq_destroy(sym)
    else if (type == TYPE_USER)
        ncmd_destroy(sym)
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
                           i, stream, dst)
{
    $0 = cmdline
    dbg_print("divert", 1, sprintf("(xeq_cmd__undivert) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    #dbg_print_block("ship_out", 7, curr_dstblk(), "(xeq_cmd__undivert) curr_dstblk()")
    if (NF == 1)
        undivert_all()
    else {
        i = 1
        while (++i <= NF) {
            stream = dosubs($i)
            if (!integerp(stream))
                error(sprintf("Value '%s' must be numeric:", stream) $0)
            if (stream > MAX_STREAM)
                error("Bad parameters:" $0)
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
function scan__while(                 name, while_block, body_block, scanstat)
{
    dbg_print("while", 3, sprintf("(scan__while) START dstblk=%d, $0='%s'", curr_dstblk(), $0))
    name = $1
    $1 = ""
    sub("^[ \t]*", "")

    # Create two new blocks: one for while_block, other for true branch
    while_block = nblk_new(BLK_WHILE)
    dbg_print("while", 5, "(scan__while) New block # " while_block " type " ppf_block_type(nblk_type(while_block)))
    body_block = nblk_new(BLK_AGG)
    dbg_print("while", 5, "(scan__while) New block # " body_block " type " ppf_block_type(nblk_type(body_block)))

    nblktab[while_block, "condition"] = $0
    nblktab[while_block, "init_negate"] = FALSE
    nblktab[while_block, "body_block"] = body_block
    nblktab[while_block, "dstblk"] = body_block
    nblktab[while_block, "valid"]      = FALSE
    dbg_print_block("while", 7, while_block, "(scan__while) while_block")
    nstk_push(__scan_stack, while_block) # Push it on to the scan_stack

    dbg_print("while", 5, "(scan__while) CALLING scan()")
    scanstat = scan() # scan() should return after it encounters @endif
    dbg_print("while", 5, "(scan__while) RETURNED FROM scan() => " ppf_bool(scanstat))
    if (!scanstat)
        error("(scan__while) Scan failed")

    dbg_print("while", 5, "(scan__while) END; => " while_block)
    return while_block
}


# @endwhile
function scan__endwhile(                    while_block)
{
    dbg_print("while", 3, sprintf("(scan__endwhile) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf_mode(curr_atmode())))
    # if (nstk_emptyp(__scan_stack))
    #     error("(scan__endwhile) Scan stack is empty!")
    # while_block = nstk_pop(__scan_stack)
    # if ((nblktab[while_block, "type"] != BLK_WHILE) ||
    #     (nblktab[while_block, "depth"] != nstk_depth(__scan_stack)))
    #     error("(scan__endwhile) Corrupt scan stack")
    assert_scan_stack_okay(BLK_WHILE)

    while_block = nstk_pop(__scan_stack)
    nblktab[while_block, "valid"] = TRUE

    return while_block
}


function xeq_blk__while(while_block,
                        blk_type, body_block, condition, condval)
{
    # if (__loop_ctl != LOOP_NORMAL) {
    #     dbg_print("while", 3, "(xeq_blk__while) NOP due to loop_ctl=" __loop_ctl)
    #     return
    # }

    blk_type = nblktab[while_block , "type"]
    dbg_print("while", 3, sprintf("(xeq_blk__while) START dstblk=%d, while_block=%d, type=%s",
                               curr_dstblk(), while_block, ppf_block_type(blk_type)))

    dbg_print_block("while", 7, while_block, "(xeq_blk__while) while_block")
    if ((nblktab[while_block, "type"] != BLK_WHILE) || \
        (nblktab[while_block, "valid"] != TRUE))
        error("(xeq_blk__while) Bad config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    body_block = nblktab[while_block, "body_block"]
    condition = nblktab[while_block, "condition"]
    condval = evaluate_condition(condition, nblktab[while_block, "init_negate"])
    dbg_print("while", 1, sprintf("(xeq_blk__while) Initial evaluate_condition('%s') => %s", condition, ppf_bool(condval)))
    if (condval == ERROR)
        error("@while: Uncaught error")

    while (condval) {
        raise_namespace()
        dbg_print("while", 5, sprintf("(xeq_blk__while) CALLING execute__block(%d)",
                                   body_block))
        execute__block(body_block)
        dbg_print("while", 5, sprintf("(xeq_blk__while) RETURNED FROM execute__block()"))
        lower_namespace()

        condval = evaluate_condition(condition, nblktab[while_block, "init_negate"])
        dbg_print("while", 1, sprintf("(xeq_blk__while) Repeat evaluate_condition('%s') => %s", condition, ppf_bool(condval)))
        if (condval == ERROR)
            error("@while: Uncaught error")

        # Check for break or continue
        if (__loop_ctl == LOOP_BREAK) {
            __loop_ctl = LOOP_NORMAL
            break
        }
        if (__loop_ctl == LOOP_CONTINUE) {
            __loop_ctl = LOOP_NORMAL
            # Actual "continue" wouldn't do anything here since we're
            # about to re-iterate the loop anyway
        }
    }

    dbg_print("while", 3, sprintf("(xeq_blk__while) END"))
}


function prt_blk__while(blknum)
{
    return sprintf("  valid       : %s\n"       \
                   "  condition   : '%s'\n"     \
                   "  body_block  : %d",
                   ppf_bool(nblktab[blknum, "valid"]),
                   nblktab[blknum, "condition"],
                   nblktab[blknum, "body_block"])
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
        return nsym_ll_read("__EXPR__", "", GLOBAL_NAMESPACE)

    _c3__f = 1
    e = _c3_expr()
    if (_c3__f <= length(_c3__Sexpr))
        error(sprintf("Math expression error at '%s':", substr(_c3__Sexpr, _c3__f)) $0)
    else if (match(e, /^[-+]?(nan|inf)/))
        error(sprintf("Math expression error:'%s' returned \"%s\":", s, e) $0)
    else
        return e
}


# rel | rel relop rel
function _c3_expr(    var, e, op1, op2, m2)
{
    if (match(substr(_c3__Sexpr, _c3__f), /^[A-Za-z#_][A-Za-z#_0-9]*=[^=]/)) {
        var = _c3_advance()
        sub(/=.*$/, "", var)
        assert_nsym_okay_to_define(var)
        # match() sets RLENGTH which includes the match character [^=].
        # But that's the start of the value -- I need to back up over it
        # to read the value properly.
        _c3__f--
        return nsym_store(var, _c3_expr()+0)
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
            e = nsym_defined_p(e2) ? TRUE : FALSE
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
        else if (nsym_valid_p(e2) && nsym_defined_p(e2))
            return nsym_fetch(e2)
        else if (nseq_valid_p(e2) && nseq_defined_p(e2))
            return nseq_ll_read(e2)
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
function dosubs(s,    expand, i, j, l, m, nparam, p, param, r, fn, cmdline,
                at_brace, x, y, inc_dec, pre_post, subcmd, silent, off_by)
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

        if ((i = index(r, "@")) == IDX_NOT_FOUND)
            break

        dbg_print("dosubs", 7, (sprintf("(dosubs) Top of loop: l='%s', r='%s', expand='%s'", l, r, expand)))
        l = l substr(r, 1, i-1)
        r = substr(r, i+1)      # Currently scanning @

        # Look for a second "@" beyond the first one.  If not found,
        # this can't be a valid m2 substitution.  Ignore it, we're done.
        if ((i = index(r, "@")) == IDX_NOT_FOUND) {
            l = l "@"
            break
        }

        # A lone "@" followed by whitespace is not valid syntax.  Ignore it,
        # but keep processing the line.
        if (isspace(first(r))) {
            l = l "@"
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
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            # basename in Awk, assuming Unix style path separator.
            # return filename portion of path
            expand = rm_quotes(nsym_fetch(p))
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
                # In a bid to spread a bit more chaos in the universe,
                # if you don't give an argument to boolval then you get
                # True 50% of the time and False the other 50%.
                r = nsym_ll_read("__FMT__", rand() < 0.50) r # XXXXXX
            else {
                p = param[1 + off_by]
                # Always accept your current representation of True or False
                # to actually be true or false without further evaluation.
                if (p == nsym_ll_read("__FMT__", TRUE) ||
                    p == nsym_ll_read("__FMT__", FALSE))
                    r = p r
                else if (nsym_valid_p(p)) {
                    # It's a valid name -- now see if it's defined or not.
                    # If not, check if we're in strict mode (error) or not.
                    if (nsym_defined_p(p))
                        r = nsym_ll_read("__FMT__", nsym_true_p(p)) r
                    else if (strictp("bool"))
                        error("Name '" p "' not defined [boolval]:" $0)
                    else
                        r = nsym_ll_read("__FMT__", FALSE) r
                } else
                    # It's not a symbol, so use its value interpreted as a boolean
                    r = nsym_ll_read("__FMT__", !!p) r
            }

        # chr SYM : Output character with ASCII code SYM
        #   @chr 65@ => A
        } else if (fn == "chr") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            if (nsym_valid_p(p)) {
                assert_nsym_defined(p, "chr")
                x = sprintf("%c", nsym_fetch(p)+0)
                r = x r
            } else if (integerp(p) && p >= 0 && p <= 255) {
                x = sprintf("%c", p+0)
                r = x r
            } else
                error("Bad parameters in '" m "':" $0)

        # date     : Current date as YYYY-MM-DD
        # epoch    : Number of seconds since Epoch
        # strftime : User-specified date format, see strftime(3)
        # time     : Current time as HH:MM:SS
        # tz       : Current time zone name
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
                : nsym_ll_read("__FMT__", fn)
            gsub(/"/, "\\\"", y)
            cmdline = build_prog_cmdline("date", "+\"" y "\"", MODE_IO_CAPTURE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # dirname SYM: Directory name of path, in Awk
        } else if (fn == "dirname") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            # dirname in Awk, assuming Unix style path separator.
            # return directory portion of path
            y = rm_quotes(nsym_fetch(p))
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
            nsym_ll_write("__EXPR__", "", GLOBAL_NAMESPACE, x+0)
            if (!silent)
                r = x r

        # getenv : Get environment variable
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

        # lc : Lower case
        # len : Length.        @len SYM@ => N
        # uc SYM: Upper case
        } else if (fn == "lc" ||
                   fn == "len" ||
                   fn == "uc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            r = ((fn == "lc")  ? tolower(nsym_fetch(p)) : \
                 (fn == "len") ?  length(nsym_fetch(p)) : \
                 (fn == "uc")  ? toupper(nsym_fetch(p)) : \
                 error("Name '" m "' not defined [can't happen]:" $0)) \
                r   # ^^^ This error() bit can't happen but I need something
                    # to the right of the :, and error() will abend.

        # left : Left (substring)
        #   @left ALPHABET 7@ => ABCDEFG
        } else if (fn == "left") {
            if (nparam < 1 || nparam > 2) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            x = 1
            if (nparam == 2) {
                x = param[2 + off_by]
                if (!integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(nsym_fetch(p), 1, x) r

        # mid : Substring ...  SYMBOL, START[, LENGTH]
        #   @mid ALPHABET 15 5@ => OPQRS
        #   @mid FOO 3@
        #   @mid FOO 2 2@
        } else if (fn == "mid" || fn == "substr") {
            if (nparam < 2 || nparam > 3)
                error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            x = param[2 + off_by]
            if (!integerp(x))
                error("Value '" x "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(nsym_fetch(p), x) r
            } else if (nparam == 3) {
                y = param[3 + off_by]
                if (!integerp(y))
                    error("Value '" y "' must be numeric:" $0)
                r = substr(nsym_fetch(p), x, y) r
            }

        # obasename SYM: Base (i.e., file name) of path, using external program
        } else if (fn == "obasename") {
            if (secure_level() >= 2)
                error("(obasename) Security violation")
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            cmdline = build_prog_cmdline(fn, rm_quotes(nsym_fetch(p)), MODE_IO_CAPTURE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # odirname SYM: Directory name of path, using external program
        } else if (fn == "odirname") {
            if (secure_level() >= 2)
                error("(odirname) Security violation")
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            cmdline = build_prog_cmdline(fn, rm_quotes(nsym_fetch(p)), MODE_IO_CAPTURE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # ord SYM : Output character with ASCII code SYM
        #   @define B *Nothing of interest*
        #   @ord A@ => 65
        #   @ord B@ => 42
        } else if (fn == "ord") {
            if (! __ord_initialized)
                initialize_ord()
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            if (nsym_valid_p(p) && nsym_defined_p(p))
                p = nsym_fetch(p)
            r = __ord[first(p)] r

        # rem : Remark
        #   @rem STUFF@ is considered a comment and ignored
        #   @srem STUFF@ like @rem, but preceding whitespace is also discarded
        } else if (fn == "rem" || fn == "srem") {
            if (first(fn) == "s")
                sub(/[ \t]+$/, "", l)

        # right : Right (substring)
        #   @right ALPHABET 20@ => TUVWXYZ
        } else if (fn == "right") {
            if (nparam < 1 || nparam > 2) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            x = length(nsym_fetch(p))
            if (nparam == 2) {
                x = param[2 + off_by]
                if (!integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(nsym_fetch(p), x) r

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
                expand = expand " "
            r = expand r

        # trim  SYM: Remove both leading and trailing whitespace
        # ltrim SYM: Remove leading whitespace
        # rtrim SYM: Remove trailing whitespace
        } else if (fn == "trim" || fn == "ltrim" || fn == "rtrim") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            expand = nsym_fetch(p)
            if (fn == "trim" || fn == "ltrim")
                #sub(/^[ \t]+/, "", expand)
                expand = ltrim(expand)
            if (fn == "trim" || fn == "rtrim")
                expand = rtrim(expand)
            r = expand r

        # uuid : Something that resembles but is not a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (fn == "uuid") {
            r = uuid() r

        # Old code for macro processing
        # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
        } else if (nsym_valid_p(fn) && (nsym_defined_p(fn) || nsym_deferred_p(fn))) {
            expand = nsym_fetch(fn)
            # Expand $N parameters (includes $0 for macro name)
            j = MAX_PARAM   # but don't go overboard with params
            # Count backwards to get around $10 problem.
            while (j-- >= 0) {
                if (index(expand, "${" j "}") > 0) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$\\{" j "\\}", param[j + off_by], expand)
                 }
                if (index(expand, "$" j) > 0) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$" j, param[j + off_by], expand)
                }
            }
            r = expand r

        # Check if it's a sequence
        } else if (nseq_valid_p(fn) && nseq_defined_p(fn)) {
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
                if (pre_post == 0)
                    # normal call : insert current value with formatting
                    r = sprintf(nseqtab[fn, "fmt"], nseq_ll_read(fn)) r
                else {
                    # Handle prefix xor postfix increment/decrement
                    if (pre_post == -1)    # prefix
                        if (inc_dec == -1) # decrement
                            nseq_ll_incr(fn, -nseqtab[fn, "incr"])
                        else
                            nseq_ll_incr(fn, nseqtab[fn, "incr"])
                    # Get current value with desired formatting
                    r = sprintf(nseqtab[fn, "fmt"], nseq_ll_read(fn)) r
                    if (pre_post == +1)    # postfix
                        if (inc_dec == -1)
                            nseq_ll_incr(fn, -nseqtab[fn, "incr"])
                        else
                            #nseq_ll_incr(fn, nseqtab[fn, "incr"])
                            nseq_ll_incr(fn)
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
                        r = nseq_ll_read(fn) r
                    } else if (subcmd == "nextval") {
                        # - nextval :: Increment and return new value of
                        # counter.  No prefix/suffix.
                        nseq_ll_incr(fn, nseqtab[fn, "incr"])
                        r = nseq_ll_read(fn) r
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
            l = l "@" m
            r = "@" r
        }
        i = index(r, "@")
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
#*****************************************************************************

# Nothing in this function is user-customizable, so don't touch
function initialize(    get_date_cmd, d, dateout, array, elem, i, date_ok)
{
    E                    = exp(1)
    IDX_NOT_FOUND        = 0
    LOG10                = log(10)
    MAX_DBG_LEVEL        = 10
    MAX_PARAM            = 20
    MAX_STREAM           = 9
    PI                   = atan2(0, -1)
    SEQ_DEFAULT_INCR     = 1
    SEQ_DEFAULT_INIT     = 0
    TAU                  = 8 * atan2(1, 1) # 2 * PI
    TERMINAL             = 0    # Block zero means standard output

    MODE_AT_LITERAL       = "L" # atmode - scan literally
    MODE_AT_PROCESS       = "P" # atmode - scan with "@" macro processing
    MODE_IO_CAPTURE       = "C" # build command for getline
    MODE_IO_SILENT        = "X" # redirect >/dev/null 2>/dev/null
    MODE_TEXT_PRINT       = "P" # executed text is printed
    MODE_TEXT_STRING      = "S" # executed text is stored in a string
    MODE_STREAMS_DISCARD  = "D" # diverted streams final disposition
    MODE_STREAMS_SHIP_OUT = "O" # diverted streams final disposition

    # BLKS
    # Block types
    BLK_AGG       = "A";                __blk_label[BLK_AGG]      = "AGG"
      SLOT_BLKNUM = "b";                __blk_label[SLOT_BLKNUM]  = "BLKNUM"
      SLOT_CMD    = "c";                __blk_label[SLOT_CMD]     = "CMD"
      SLOT_TEXT   = "t";                __blk_label[SLOT_TEXT]    = "TEXT"
      SLOT_USER   = "u";                __blk_label[SLOT_USER]    = "USER"
    BLK_CASE      = "C";                __blk_label[BLK_CASE]     = "CASE"
    BLK_FILE      = "F";                __blk_label[BLK_FILE]     = "FILE"
    BLK_IF        = "I";                __blk_label[BLK_IF]       = "IF"
    BLK_FOR       = "R";                __blk_label[BLK_FOR ]     = "FOR"
    BLK_LONGDEF   = "L";                __blk_label[BLK_LONGDEF]  = "LONGDEF"
    BLK_REGEXP    = "X";                __blk_label[BLK_REGEXP]   = "REGEXP"
    BLK_TERMINAL  = "T";                __blk_label[BLK_TERMINAL] = "TERMINAL"
    BLK_USER      = "U";                __blk_label[BLK_USER]     = "USER"
    BLK_WHILE     = "W";                __blk_label[BLK_WHILE]    = "WHILE"

    LOOP_NORMAL   = 0
    LOOP_BREAK    = 1
    LOOP_CONTINUE = 2

    __block_cnt          = 0
    __buffer             = EMPTY
    __init_files_loaded  = FALSE # Becomes True in load_init_files()
    __loop_ctl           = LOOP_NORMAL
    __namespace          = GLOBAL_NAMESPACE
    __ord_initialized    = FALSE # Becomes True in initialize_ord()
    __print_mode         = MODE_TEXT_PRINT
    __scan_stack[0]      = 0

    srand()                     # Seed random number generator
    initialize_prog_paths()

    if (secure_level() < 2) {
        # Set up some symbols that depend on external programs

        # Current date & time
        if ("date" in PROG) {
            # Capture m2 run start time.                 1  2  3  4  5  6  7  8
            get_date_cmd = build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z %s'", MODE_IO_CAPTURE)
            get_date_cmd | getline dateout
            close(get_date_cmd)
            split(dateout, d)

            nsym_ll_fiat("__DATE__",         "", FLAGS_READONLY_INTEGER, d[1] d[2] d[3])
            nsym_ll_fiat("__EPOCH__",        "", FLAGS_READONLY_INTEGER, d[8])
            nsym_ll_fiat("__TIME__",         "", FLAGS_READONLY_INTEGER, d[4] d[5] d[6])
            nsym_ll_fiat("__TIMESTAMP__",    "", FLAGS_READONLY_SYMBOL,  d[1] "-" d[2] "-" d[3] \
                                                                     "T" d[4] ":" d[5] ":" d[6] d[7])
            nsym_ll_fiat("__TZ__",           "", FLAGS_READONLY_SYMBOL,  d[7])
        }

        # Deferred symbols
        if ("id" in PROG) {
            nsym_deferred_symbol("__GID__",      FLAGS_READONLY_INTEGER, "id", "-g")
            nsym_deferred_symbol("__UID__",      FLAGS_READONLY_INTEGER, "id", "-u")
            nsym_deferred_symbol("__USER__",     FLAGS_READONLY_SYMBOL,  "id", "-un")
        }
        if ("hostname" in PROG) {
            nsym_deferred_symbol("__HOST__",     FLAGS_READONLY_SYMBOL,  "hostname", "-s")
            nsym_deferred_symbol("__HOSTNAME__", FLAGS_READONLY_SYMBOL,  "hostname", "-f")
        }
        if ("uname" in PROG) {
            nsym_deferred_symbol("__OSNAME__",   FLAGS_READONLY_SYMBOL,  "uname", "-s")
        }
        if ("sh" in PROG) {
            nsym_deferred_symbol("__PID__",      FLAGS_READONLY_INTEGER, "sh", "-c 'echo $PPID'")
        }
    }

    nnam_ll_write("__FMT__",    GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)
    nnam_ll_write("__STRICT__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)

    if ("PWD" in ENVIRON)
      nsym_ll_fiat("__CWD__",        "", FLAGS_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["PWD"]))
    else if (secure_level() < 2 && ("pwd" in PROG))
      nsym_deferred_symbol("__CWD__",    FLAGS_READONLY_SYMBOL,  "pwd", "")
    nsym_ll_fiat("__DIVNUM__",       "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__EXPR__",         "", FLAGS_READONLY_NUMERIC, 0.0)
    nsym_ll_fiat("__FILE__",         "", FLAGS_READONLY_SYMBOL,  "")
    nsym_ll_fiat("__FILE_UUID__",    "", FLAGS_READONLY_SYMBOL,  "")
    nsym_ll_fiat("__FMT__",        TRUE, "",                     "1")
    nsym_ll_fiat("__FMT__",       FALSE, "",                     "0")
    nsym_ll_fiat("__FMT__",      "date", "",                     "%Y-%m-%d")
    nsym_ll_fiat("__FMT__",     "epoch", "",                     "%s")
    nsym_ll_fiat("__FMT__",    "number", "",                     CONVFMT)
    nsym_ll_fiat("__FMT__",       "seq", "",                     "%d")
    nsym_ll_fiat("__FMT__",      "time", "",                     "%H:%M:%S")
    nsym_ll_fiat("__FMT__",        "tz", "",                     "%Z")
    if ("HOME" in ENVIRON)
      nsym_ll_fiat("__HOME__",       "", FLAGS_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["HOME"]))
    nsym_ll_fiat("__INPUT__",        "", FLAGS_WRITABLE_SYMBOL,  EMPTY)
    nsym_ll_fiat("__LINE__",         "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__M2_UUID__",      "", FLAGS_READONLY_SYMBOL,  uuid())
    nsym_ll_fiat("__M2_VERSION__",   "", FLAGS_READONLY_SYMBOL,  M2_VERSION)
    nsym_ll_fiat("__NFILE__",        "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__NLINE__",        "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__STRICT__",   "bool", "",                     TRUE)
    nsym_ll_fiat("__STRICT__",    "cmd", "",                     FALSE)
    nsym_ll_fiat("__STRICT__",    "env", "",                     TRUE)
    nsym_ll_fiat("__STRICT__",   "file", "",                     TRUE)
    nsym_ll_fiat("__STRICT__",   "func", "",                     TRUE)
    nsym_ll_fiat("__STRICT__", "symbol", "",                     TRUE)
    nsym_ll_fiat("__STRICT__",  "undef", "",                     TRUE)
    nsym_ll_fiat("__SYNC__",         "", FLAGS_WRITABLE_INTEGER, 1)

    # FUNCS
    # Functions cannot be used as symbol or sequence names.
    split("basename boolval chr date dirname epoch expr getenv lc left len" \
          " ltrim mid obasename odirname ord rem right rtrim sexpr sgetenv spaces srem strftime" \
          " substr time trim tz uc uuid",
          array, " ")
    for (elem in array)
        nnam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_FUNCTION FLAG_SYSTEM)

    # CMDS
    # Built-in commands
    # Also need to add entry in execute__command()  [search: DISPATCH]
    split("append array break continue debug decr default define divert dump" \
          " echo error exit ignore" \
          " include incr initialize input local m2 nextfile paste readfile" \
          " readarray readonly secho sequence sexit shell sinclude" \
          " spaste sreadfile sreadarray stderr typeout undefine undivert warn", array, " ")
    for (elem in array)
        nnam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_COMMAND FLAG_SYSTEM)


    # IMMEDS
    # These commands are Immediate
    split("break case continue dump! else endcase endcmd endif endlong" \
          " endlongdef endwhile esac fi for foreach if ifdef ifndef longdef" \
          " newcmd next of otherwise unless while",
          array, " ")
    for (elem in array)
        nnam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_COMMAND FLAG_SYSTEM FLAG_IMMEDIATE)

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
        nblk_new(BLK_AGG)       # initialize to empty agg block
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


# It is important that __PROG__ remain a read-only symbol.  Otherwise,
# some bad person could entice you to evaluate:
#       @define __PROG__[stat]  /bin/rm
#       @include my_precious_file
function initialize_prog_paths()
{
    nsym_ll_fiat("__TMPDIR__", "",       FLAGS_WRITABLE_SYMBOL,  "/tmp/")

    nnam_ll_write("__PROG__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_READONLY FLAG_SYSTEM)
    if ("basename" in PROG)
        nsym_ll_fiat("__PROG__", "basename", FLAGS_READONLY_SYMBOL, PROG["basename"])
    if ("date" in PROG)
        nsym_ll_fiat("__PROG__", "date",     FLAGS_READONLY_SYMBOL, PROG["date"])
    if ("dirname" in PROG)
        nsym_ll_fiat("__PROG__", "dirname",  FLAGS_READONLY_SYMBOL, PROG["dirname"])
    if ("hostname" in PROG)
        nsym_ll_fiat("__PROG__", "hostname", FLAGS_READONLY_SYMBOL, PROG["hostname"])
    if ("id" in PROG)
        nsym_ll_fiat("__PROG__", "id",       FLAGS_READONLY_SYMBOL, PROG["id"])
    if ("pwd" in PROG)
        nsym_ll_fiat("__PROG__", "pwd",      FLAGS_READONLY_SYMBOL, PROG["pwd"])
    if ("rm" in PROG)
        nsym_ll_fiat("__PROG__", "rm",       FLAGS_READONLY_SYMBOL, PROG["rm"])
    if ("sh" in PROG)
        nsym_ll_fiat("__PROG__", "sh",       FLAGS_READONLY_SYMBOL, PROG["sh"])
    if ("stat" in PROG)
        nsym_ll_fiat("__PROG__", "stat",     FLAGS_READONLY_SYMBOL, PROG["stat"])
    if ("uname" in PROG)
        nsym_ll_fiat("__PROG__", "uname",    FLAGS_READONLY_SYMBOL, PROG["uname"])
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
    # baked into nsym_ll_write().
    old_debug = nsymtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"]
    nsymtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = FALSE

    if ("M2RC" in ENVIRON && path_exists_p(ENVIRON["M2RC"]))
        dofile(ENVIRON["M2RC"])
    else if ("HOME" in ENVIRON)
        dofile(ENVIRON["HOME"] "/.m2rc")
    dofile("./.m2rc")

    # Don't count init files in total line/file tally - it's better to
    # keep them in sync with the files from the command line.
    nsym_ll_write("__NFILE__", "", GLOBAL_NAMESPACE, 0)
    nsym_ll_write("__NLINE__", "", GLOBAL_NAMESPACE, 0)

    # Restore debugging, if any, and we're done
    nsymtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = old_debug
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
                if (_name == "debug")
                    _name = "__DEBUG__"
                else if (_name == "secure")
                    _name = "__SECURE__"
                else if (_name == "strict")
                    warn("Special processing for '" _arg "' does not function", "ARGV", _i)
                if (!nsym_valid_p(_name))
                    error("Name '" _name "' not valid:" _arg, "ARGV", _i)
                if (nsym_protected_p(_name))
                    error("Symbol '" _name "' protected:" _arg, "ARGV", _i)
                if (!nnam_ll_in(_name, GLOBAL_NAMESPACE))
                    error("Name '" _name "' not available:" _arg, "ARGV", _i)
                nsym_store(_name, _val)

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

    # All blocks should have been popped from the scan stack
    if (! nstk_emptyp(__scan_stack)) {
        warn("(main) Scan stack not is empty!")
        dump_scan_stack()
    }

    end_program(MODE_STREAMS_SHIP_OUT)
}


# Prepare to exit.  Normally, diverted_streams_final_disposition is
# MODE_STREAMS_SHIP_OUT, so we usually undivert all pending streams.
# When diverted_streams_final_disposition is MODE_STREAMS_DISCARD, any
# diverted data is dropped.  Standard output is always flushed, and
# program exits with value from global variable __exit_code.
function end_program(diverted_streams_final_disposition,
                     stream)
{
    # In the normal case of MODE_STREAMS_SHIP_OUT, ship out any remaining
    # diverted data.  See "STREAMS & DIVERSIONS" documentation above
    # to see how the user can prevent this, if desired.
    if (diverted_streams_final_disposition == MODE_STREAMS_SHIP_OUT) {
        # Regardless of whether the scan stack is empty or not, streams
        # which ship out when m2 ends must go to standard output.  So
        # always create a TERMINAL block to receive this data.  Since
        # the program is about to terminate anyway, we don't care about
        # managing the scan stack from here on out.
        nstk_push(__scan_stack, nblk_new(BLK_TERMINAL))
        nsym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, TERMINAL)
        undivert_all()
    }

    flush_stdout(0)
    if (debugp())
        print_stderr("m2:END M2")
    exit __exit_code
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
