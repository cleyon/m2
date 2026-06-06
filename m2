#!/usr/bin/awk -f
#!/usr/local/bin/mawk -f
#!/usr/local/bin/gawk -f
#
#*********************************************************** -*- mode: Awk -*-
#
#  File:        m2
#  Time-stamp:  <2026-06-06 14:32:38 cleyon>
#  Author:      Christopher Leyon <cleyon@gmail.com>
#  Created:     <2020-10-22 09:32:23 cleyon>
#  SPDX-License-Identifier: BSD-2-Clause
#
#  USAGE
#       m2 [NAME=[VALUE] ...] [file ...]
#
#  DESCRIPTION
#       Line-oriented macro processor
#
#  Copyright (c) 2025-2026 Christopher Leyon
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions, and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions, and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE
#  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
#  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
#  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#*****************************************************************************

BEGIN {
    M2_VERSION = "6.0.0-beta1"

    # Specify a shell for m2 to use for running utility programs.
    # It is expected to be compatible with Bourne shell syntax.
    #   - Honor the <, >, and 2> redirection operators
    #   - Accept a "-c" option to specify a command to execute
    #   - Support "command -v" to check if program would execute
    #
    # Regardless of the program executable name (sh, bash, dash, ksh, etc),
    # the PROG array key MUST be "sh".
    _safe_shell = "/bin/sh"     # Customize me
    if (awk_stat(_safe_shell))
        PROG["sh"] = _safe_shell
    else
        print_stderr("m2:External program '" _safe_shell "' not found")

    # Customize these paths as needed for correct operation on your
    # system.  They are assumed to be safe to run even at secure level
    # SECURE (but not PARANOID).  If a program is not available, simply
    # remove the entry entirely.
    split(                    \
          "/usr/bin/basename" \
             " /bin/date"     \
         " /usr/bin/dirname"  \
             " /bin/hostname" \
         " /usr/bin/id"       \
             " /bin/pwd"      \
             " /bin/rm"       \
         " /usr/bin/stat"     \
         " /usr/bin/tput"     \
         " /usr/bin/uname"    \
         , _progs, " ")
    for (_p in _progs)
        if (awk_stat(_progs[_p]))
            PROG[awk_basename(_progs[_p])] = _progs[_p]
        else
            print_stderr("m2:External program '" _progs[_p] "' not found")

    # See the "SECURITY CONSIDERATIONS" section of the manual for more info:
    SEC_STANDARD     = 0 # Default secure level allows m2 to run normal
                         # programs for the user; this allows the @shell
                         # command to function and @undivert to a file.
    SEC_SQUASHROOT   = 1 # Secure level 1 is not a real level.  Rather,
                         # for the root user (uid==0), secure level 2 is
                         # chosen.  For all other users/uids level 0
                         # (standard) security is selected.
    SEC_SECURE       = 2 # Secure level 2 prevents this, but does allow
                         # m2 to utilize the (presumably secure)
                         # utilities specified in the PROG array.
    SEC_PARANOID     = 3 # Secure level 3 prevents invoking any programs,
                         # and will terminate if any attempt is made.
                         # At level 3, m2 does not know the current time
                         # or date, host or user name, etc.
    __secure_level   = SEC_STANDARD
}

# DO NOT CHANGE anything below this line

BEGIN {
    TRUE  = OKAY     =  1;              NULL     = "/dev/null"
    FALSE = EOF      =  0;              STDIN    = "/dev/stdin"
    ERROR = VOID     = -1;              STDOUT   = "/dev/stdout"
    EMPTY = NOKEY    = "";              STDERR   = "/dev/stderr"
    ROOT_LEVEL       =  0;              TTY      = "/dev/tty"
    M2_NS            = "m2";            M2_SYSNS = "__m2__"
                                        M2_ENVNS = "ENV"
    # Exit codes
    EX_OK            =  0
    EX_M2_ERROR      =  1
    EX_USER_REQUEST  =  2       # @error
    EX_NOINPUT       = 66       # failure to process any files
    EX_SOFTWARE      = 70       # panic()
    EX_NOPERM        = 77       # security violation

    # Master char list
    #    Letters & Numerals (listed means available):
    #           V g 6 7 8 9
    #
    #    Symbols (listed means allocated):
    #           ? ! @ _ ~ * > ' . # <
    #
    # See also doc/char-list.org
    FLAG_BOOLEAN     = "B"; __label[FLAG_BOOLEAN]   = "Boolean"
    FLAG_DEFERRED    = "D"; __label[FLAG_DEFERRED]  = "Deferred"
    FLAG_IMMEDIATE   = "!"; __label[FLAG_IMMEDIATE] = "Immediate"
    FLAG_INTEGER     = "I"; __label[FLAG_INTEGER]   = "Integer"
    FLAG_KEY_NO      = "Z"; __label[FLAG_KEY_NO]    = "Key_No"  # Key element (and brackets) must not be present
    FLAG_KEY_YES     = "y"; __label[FLAG_KEY_YES]   = "Key_Yes" # Key element to index Array or List is required
    FLAG_NUMERIC     = "m"; __label[FLAG_NUMERIC]   = "Numeric"
    FLAG_READONLY    = "R"; __label[FLAG_READONLY]  = "Read_Only"
    FLAG_SYSTEM      = "Y"; __label[FLAG_SYSTEM]    = "System"
    FLAG_WRITABLE    = "W"; __label[FLAG_WRITABLE]  = "Writable"

    # Real types
    TYPE_ARRAY       = "A"; __label[TYPE_ARRAY]     = "Array";     __base_type[TYPE_ARRAY   ] = TYPE_ARRAY
    TYPE_COMMAND     = "C"; __label[TYPE_COMMAND]   = "Command";   __base_type[TYPE_COMMAND ] = TYPE_COMMAND
    TYPE_FUNCTION    = "F"; __label[TYPE_FUNCTION]  = "Function";  __base_type[TYPE_FUNCTION] = TYPE_FUNCTION
    TYPE_INTERNAL    = "_"; __label[TYPE_INTERNAL]  = "Internal";  __base_type[TYPE_INTERNAL] = TYPE_INTERNAL
    TYPE_LIST        = "L"; __label[TYPE_LIST]      = "List";      __base_type[TYPE_LIST    ] = TYPE_LIST
    TYPE_SEQUENCE    = "Q"; __label[TYPE_SEQUENCE]  = "Sequence";  __base_type[TYPE_SEQUENCE] = TYPE_SEQUENCE
    TYPE_SYMBOL      = "S"; __label[TYPE_SYMBOL]    = "Symbol";    __base_type[TYPE_SYMBOL  ] = TYPE_SYMBOL
    TYPE_USER        = "U"; __label[TYPE_USER]      = "User";      __base_type[TYPE_USER    ] = TYPE_USER
    #
    # used to include TYPE_INTERNAL but seeing how things work without it
    VALID_TYPES      = TYPE_ARRAY  TYPE_COMMAND   TYPE_FUNCTION  \
                       TYPE_LIST   TYPE_SEQUENCE  TYPE_SYMBOL    TYPE_USER
    # Pseudo-types
    PTYPE_ANY        = "*"; __label[PTYPE_ANY]      = "Any";       __base_type[PTYPE_ANY    ] = VALID_TYPES
    PTYPE_ENV_VAR    = "E"; __label[PTYPE_ENV_VAR]  = "Env_Var";   __base_type[PTYPE_ENV_VAR] = EMPTY
    PTYPE_IDXABLE    = "J"; __label[PTYPE_IDXABLE]  = "Indexable"; __base_type[PTYPE_IDXABLE] = TYPE_ARRAY  TYPE_LIST
    PTYPE_KEY        = "k"; __label[PTYPE_KEY]      = "Key";       __base_type[PTYPE_KEY    ] = EMPTY
    PTYPE_NAME       = "M"; __label[PTYPE_NAME]     = "Name";      __base_type[PTYPE_NAME   ] = EMPTY
    PTYPE_NS         = "N"; __label[PTYPE_NS]       = "Namespace"; __base_type[PTYPE_NS     ] = EMPTY
    PTYPE_NUMBER     = "n"; __label[PTYPE_NUMBER]   = "Number";    __base_type[PTYPE_NUMBER ] = TYPE_SYMBOL  TYPE_ARRAY  TYPE_LIST  FLAG_KEY_YES  TYPE_SEQUENCE
    PTYPE_PARAM      = "P"; __label[PTYPE_PARAM]    = "Param";     __base_type[PTYPE_PARAM  ] = EMPTY
    PTYPE_SCALAR     = "l"; __label[PTYPE_SCALAR]   = "Scalar";    __base_type[PTYPE_SCALAR ] = TYPE_SYMBOL  TYPE_ARRAY  TYPE_LIST  FLAG_KEY_YES
    PTYPE_UNDEF      = "?"; __label[PTYPE_UNDEF]    = "Undef";     __base_type[PTYPE_UNDEF  ] = EMPTY # Undef ::= type of a not-found namtab lookup
    #
    PTYPE_READONLY_SYMBOL  = TYPE_SYMBOL FLAG_SYSTEM FLAG_READONLY
    PTYPE_READONLY_INTEGER = TYPE_SYMBOL FLAG_SYSTEM FLAG_READONLY FLAG_INTEGER
    PTYPE_READONLY_NUMERIC = TYPE_SYMBOL FLAG_SYSTEM FLAG_READONLY FLAG_NUMERIC
    #
    PTYPE_WRITABLE_SYMBOL  = TYPE_SYMBOL FLAG_SYSTEM FLAG_WRITABLE
    PTYPE_WRITABLE_INTEGER = TYPE_SYMBOL FLAG_SYSTEM FLAG_WRITABLE FLAG_INTEGER
    PTYPE_WRITABLE_BOOLEAN = TYPE_SYMBOL FLAG_SYSTEM FLAG_WRITABLE FLAG_BOOLEAN

    # TRACE_* letters are user-visible, and advertised in the manual.
    # Not part of master char list!
    # For __TRACEMODE__   see also: xeq_cmd__tracemode()
    TRACE_ARGUMENTS             = "a" # show actual arguments in each call
    TRACE_BLOCKS                = "b" # show block create/destroy
   #TRACE_MULTI_LINE            = "c" # show multiple trace lines for each call
    TRACE_EXPANSION             = "e" # show macro expansion
    TRACE_ENV_VAR               = "E" # show ENV::var read/write
    TRACE_INPUT_FILE_CHG        = "i" # trace when input file changes
    TRACE_SHOW_FILE_NAME        = "f" # show file name
    TRACE_SHOW_LINE_NUM         = "l" # show line number
    TRACE_COMMAND               = "m" # trace when a command is executed
    TRACE_PATH_SEARCH           = "p" # trace when search path search succeeds
    TRACE_QUALIFICATION         = "q" # trace ns qualification during parse()
    TRACE_READLINE              = "r" # trace readline() text
    TRACE_SYMBOL_READ_WRITE     = "s" # trace symbol low-level read & write
    TRACE_ALL                   = "t" # trace internal macros too
    TRACE_SET_ON                = "T" # Set __TRACE__ to true
   #TRACE_SHOW_CALL_ID          = "x" # show unique call id (may not be used)
    TRACE_WILDCARD_ALL_FLAGS    = "V" # shorthand for all of above options
    #
    TRACE_DEFAULT_SET           = TRACE_ARGUMENTS       TRACE_EXPANSION         \
                                  TRACE_SHOW_FILE_NAME  TRACE_SHOW_LINE_NUM
    TRACE_VALID_EVENTS          = TRACE_COMMAND         TRACE_EXPANSION         \
                                  TRACE_INPUT_FILE_CHG  TRACE_PATH_SEARCH       \
                                  TRACE_BLOCKS          TRACE_SYMBOL_READ_WRITE \
                                  TRACE_QUALIFICATION   TRACE_READLINE          \
                                  TRACE_ENV_VAR
    TRACE_ALL_SET               = TRACE_ARGUMENTS       TRACE_EXPANSION         \
                                  TRACE_INPUT_FILE_CHG  TRACE_SHOW_FILE_NAME    \
                                  TRACE_SHOW_LINE_NUM   TRACE_COMMAND           \
                                  TRACE_PATH_SEARCH     TRACE_SYMBOL_READ_WRITE \
                                  TRACE_SET_ON          TRACE_ALL               \
                                  TRACE_BLOCKS          TRACE_QUALIFICATION     \
                                  TRACE_READLINE        TRACE_ENV_VAR

    # Fields
    CFN_COUNT = BFN_BNUM = NFN_NS    = SFN_NS    = 1
    CFN_NS    = BFN_SLOT = NFN_NAME  = SFN_NAME  = 2
    CFN_NAME  = BFN_TAG  = NFN_LEVEL = SFN_KEY   = 3
                                       SFN_LEVEL = 4
                                       SFN_TAG   = 5

    # Check for and resolve SEC_SQUASHROOT.  Must get uid manually,
    # since __PROG__ and much else is not defined yet.
    if (__secure_level == SEC_SQUASHROOT) {
        #print_stderr("(BEGIN) squashroot: Checking uid")
        __secure_level = SEC_SECURE     # default secure

        if ("id" in PROG) {
            _output = 0
            # Get effective uid via "id -u"
            _uid_cmdline = sprintf("%s %s", PROG["id"], "-u")
            _uid_cmdline | getline _output
            close(_uid_cmdline)
            # Only non-zero will get standard
            if (0 + _output != 0)
                __secure_level = SEC_STANDARD
            # May as well define it now that we know it
            namtab[M2_SYSNS, "__UID__", ROOT_LEVEL] = PTYPE_READONLY_INTEGER
            symtab[M2_SYSNS, "__UID__", NOKEY, ROOT_LEVEL, "symval"] = 0 + _output
        }
    }

    # Set up critical symbols early
    namtab[M2_SYSNS, "__DEBUG__",     ROOT_LEVEL] = PTYPE_WRITABLE_BOOLEAN
    namtab[M2_SYSNS, "__EXIT__",      ROOT_LEVEL] = PTYPE_READONLY_INTEGER
    namtab[M2_SYSNS, "__SECURE__",    ROOT_LEVEL] = PTYPE_WRITABLE_INTEGER
    namtab[M2_SYSNS, "__TRACE__",     ROOT_LEVEL] = PTYPE_WRITABLE_BOOLEAN
    namtab[M2_SYSNS, "__TRACEMODE__", ROOT_LEVEL] = PTYPE_READONLY_SYMBOL
    #
    symtab[M2_SYSNS, "__DEBUG__",     NOKEY, ROOT_LEVEL, "symval"] = FALSE
    symtab[M2_SYSNS, "__EXIT__",      NOKEY, ROOT_LEVEL, "symval"] = EX_OK
    symtab[M2_SYSNS, "__SECURE__",    NOKEY, ROOT_LEVEL, "symval"] = __secure_level
    symtab[M2_SYSNS, "__TRACE__",     NOKEY, ROOT_LEVEL, "symval"] = FALSE
    symtab[M2_SYSNS, "__TRACEMODE__", NOKEY, ROOT_LEVEL, "symval"] = TRACE_DEFAULT_SET
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
    return s == ""      # length(s) == 0
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
# trim() - Remove whitespace on left & right
function trim(s)
{
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}


# Return N character
function repeated(n, c,
                  s)
{
    if (c == EMPTY) {
        warn("(repeated) Empty c")
        c = TOK_SPACE
    }
    s = ""
    while (n-- > 0)
        s = s c
    return s
}

# Return N spaces
function spaces(n)
{
    return repeated(n, TOK_SPACE)
}


# If s is surrounded by quotes, remove them.
function rm_quotes(s)
{
    if (length(s) >= 2 && first(s) == TOK_QUOTE && last(s) == TOK_QUOTE)
        s = substr(s, 2, length(s) - 2)
    return s
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       J U L I A N   D A Y   F U N C T I O N S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       https://aa.usno.navy.mil/data/JulianDate
#
#       https://quasar.as.utexas.edu/BillInfo/JulianDatesG.html
#
#       Return value is for 00:00h GMT, which means 0.5 fractional part.
#
#*****************************************************************************
#
# ALGORITHM:
# 1) Express the date as Y M D, where Y is the year, M is the month
# number (Jan = 1, Feb = 2, etc.), and D is the day in the month.
#
# 2) If the month is January or February, subtract 1 from the year to
# get a new Y, and add 12 to the month to get a new M.  (Thus, we are
# thinking of January and February as being the 13th and 14th month of
# the previous year).
#
# 3) Dropping the fractional part of all results of all multiplications
# and divisions, let:
#   A = Y/100
#   B = A/4
#   C = 2-A+B
#   E = 365.25x(Y+4716)
#   F = 30.6001x(M+1)
#   JD= C+D+E+F-1524.5
#
# This is the Julian Day Number for the beginning of the date in
# question at 0 hours, Greenwich time.  Note that this always gives you
# a half day extra.  That is because the Julian Day begins at noon,
# Greenwich time.  This is convenient for astronomers (who until
# recently only observed at night), but it is confusing.
#
# Example: If the date is 1582 October 15,
#   Y = 1582
#   M = 10
#   D = 15
#   A = 15
#   B = 3
#   C = -10
#   E = 2300344
#   F = 336
#   JD = 2299160.5
#*****************************************************************************
function jd(Y, M, D,
            A, B, C, E, F, JD)
{
    if (M == 1 || M == 2) {
        Y = Y - 1
        M = M + 12
    }
    A = int(Y / 100)
    B = int(A / 4)
    C = 2 - A + B
    E = int(365.25 * (Y + 4716))
    F = int(30.6001 * (M + 1))
    JD = C + D + E + F - 1524.5
    return JD
}


# Modified Julian Day
# Return the number of days since midnight on November 17, 1858.
function mjd(y, m, d)
{
    return int(jd(y, m, d) - JD_MJD_DIFF)
}


# To convert a Julian Day Number to a Gregorian date, assume that it is
# for 0 hours, Greenwich time, so that it ends in xxxx.5.  Argument "jd"
# is assumed to be this way, so its value should therefore end in ".5"
# [jd() gives you this .5.]
#
# NOTE: This method will not give dates accurately on the Gregorian
# Proleptic Calendar, i.e., the calendar you get by extending the
# Gregorian calendar backwards to years earlier than 1582. using the
# Gregorian leap year rules. In particular, the method fails if Y<400.
#
# Do the following calculations, again dropping the fractional part of
# all multiplications and divisions:
#   Q = JD+0.5
#   Z = Integer part of Q
#   W = (Z - 1867216.25)/36524.25
#   X = W/4
#   A = Z+1+W-X
#   B = A+1524
#   C = (B-122.1)/365.25
#   D = 365.25xC
#   E = (B-D)/30.6001
#   F = 30.6001xE
#   Day of month = B-D-F+(Q-Z)
#   Month = E-1 or E-13 (must get number less than or equal to 12)
#   Year = C-4715 (if Month is January or February) or C-4716 (otherwise)
#
# Example: Check the first calculation by starting with JD = 2299160.5
#   Q = 2299161
#   Z = 2299161
#   W = 11
#   X = 2
#   A = 2299171
#   B = 2300695
#   C = 6298
#   D = 2300344
#   E = 11
#   F = 336
#   Day of Month = 15
#   Month = 10
#   Year = 1582
function greg(JD,
              Q,Z,W,X,A,B,C,D,E,F,DOM,MON,YEAR,
              dbg)
{
    #dbg = FALSE
    Q = JD + 0.5;                         #if (dbg) printf("Q = %d\n", Q)
    Z = int(Q);                           #if (dbg) printf("Z = %d\n", Z)
    W = int( (Z - 1867216.25)/36524.25 ); #if (dbg) printf("W = %d\n", W)
    X = int( W/4 );                       #if (dbg) printf("X = %d\n", X)
    A = Z + 1 + W - X;                    #if (dbg) printf("A = %d\n", A)
    B = A + 1524;                         #if (dbg) printf("B = %d\n", B)
    C = int( (B-122.1)/365.25 );          #if (dbg) printf("C = %d\n", C)
    D = int( 365.25 * C);                 #if (dbg) printf("D = %d\n", D)
    E = int( (B-D)/30.6001 );             #if (dbg) printf("E = %d\n", E)
    F = int( 30.6001 * E );               #if (dbg) printf("F = %d\n", F)
    DOM = B - D - F + (Q - Z)
    #if (dbg) printf("Day of Month = %d\n", DOM)
    if (E > 13) # MON = E-1 or E-13 (must get number less than or equal to 12)
        MON = E - 13
    else
        MON = E - 1
    #if (dbg) printf("Month = %d\n", MON)
    if (MON == 1 || MON == 2)   # if Month is January or February
        YEAR = C - 4715
    else
        YEAR = C - 4716
    #if (dbg) printf("Year = %d\n", YEAR)
    return sprintf("%04d-%02d-%02d", YEAR, MON, DOM)
}


function date_valid_p(year, month, day,
                      leap)
{
    if (   year  < 1858 || year  > 2099 \
        || month <    1 || month >   12 \
        || day   <    1)
        return FALSE
    leap = leap_year_p(year)
    if (day > __monthdays[month, leap])
        return FALSE
    # Reject dates prior to MJD 0
    if (year == 1858 &&
        (month < 11 || (month == 11 && day < 17)))
        return FALSE

    return TRUE
}


function leap_year_p(year)
{
    # NB This algorithm is only valid for the Gregorian calendar.
    # For the Julian version, uncomment the following line:
    #return year % 4 == 0

    # 1. If the year is evenly divisible by 400, it is a leap year
    if (year % 400 == 0) return TRUE

    # 2. If the year is not divisible by 400, but is divisible by 100,
    #    it is not a leap year
    if (year % 100 == 0) return FALSE

    # 3. If the year is not divisible by 400, and also not divisible by
    #    100, but is divisible by 4, it is a leap year
    if (year % 4 == 0) return TRUE

    # 4. Otherwise it is not a leap year
    return FALSE
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
    return (s >= "A" && s <= "Z" ||
            s >= "a" && s <= "z")
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


function to_bool(x)
{
    return !! (0 + x)
}


function ppf__bool(x)
{
    return (x == FALSE || x == "") ? "False" : "True"
}


# Just like sprintf() except it supports %r and %R for Roman numerals.
function m2_sprintf(format, value)
{
    if (index(format, "%R") > 0) {
        gsub(/%R/, to_roman(value), format)
        return format
    } else if (index(format, "%r") > 0) {
        gsub(/%r/, tolower(to_roman(value)), format)
        return format
    } else
        return sprintf(format, value)
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
    return s ((last(s) != TOK_SLASH) ? TOK_SLASH : EMPTY)
}


function split_subsep(s, item_arr,
                      nitem, i, ss, retval)
{
    while ((ss = index(s, SUBSEP)) > 0) {
        item_arr[++nitem] = substr(s, 1, ss-1)
        s = substr(s, ss+1)
    }
    if (! emptyp(s))
        panic("(split_subsep) junk remaining in s: " s)

    return nitem
}


# function ppf__sepstr(s,
#                      i, ss, retval)
# {
#     while ((ss = index(s, SUBSEP)) > 0) {
#         retval = retval "ELEM: '" substr(s, 1, ss-1) "'" TOK_NEWLINE
#         retval = retval "SUBSEP" TOK_NEWLINE
#         s = substr(s, ss+1)
#     }
#     if (! emptyp(s))
#         panic("(ppf__sepstr) junk remaining in s: " s)
#
#     return chop(retval)
# }


function extract_cmd_name(text,
                          name)
{
    # Add ":" here because cmd name might be qualified
    if (!match(text, "^@[a-zA-Z0-9_:]+"))
        error("(extract_cmd_name) Could not understand command '" text "'")
    name = substr(text, 2, RLENGTH-1)
    dbg__print("xeq", 7, "(extract_cmd_name) '" text "' => '" name "'")
    return name
}


# Warning - Do not use this in the general case if you want to know if a
# string is "system" or not.  This code only checks for underscores in
# its argument, but there do exist system symbols which do not match
# this naming pattern.  (Well, there *were*, but not currently.)
function double_underscores_p(text)
{
    if (first(text) != "_")
        return FALSE
    return text ~ /^__.*__(\[.*\])?$/
}


# See if a file exists with pure Awk, no external program.
# WARNING: this code does not distinguish between non-existent and
# unreadable files.
function awk_stat(path,
                  status, not_used)
{
    status = (getline not_used < path)

    # Use literal numbers; TRUE/FALSE might not be defined yet
    if (status >= 0) {          #  > 0 -> Found
        close(path)             # == 0 -> Empty but readable
        return 1                #  < 0 -> Non-existent or unreadable
    }
    return 0
}


function path_exists_p(path)
{
    #print_stderr("(path_exists_p) START; path=" path)
    if (path == STDIN)
        return TRUE
    if (secure_level() < SEC_PARANOID && ("stat" in PROG))
        return exec_prog_cmdline("stat", path) == EX_OK

    # At security level 2+, exec_prog_cmdline() is disallowed,
    # so we'll use this workaround.
    return awk_stat(path)
}


function mktemp(path_template,
                leading_elements, file_path, tries, rp, i, letters_numbers)
{
    letters_numbers = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" # 36
    if (match(path_template, "X+$") == NOT_FOUND)
        error("(mktemp) Invalid template '" path_template "': missing 1 or more Xs")
    # Leading elements are everything up to but not including trailing "X"s
    leading_elements = substr(path_template, 1, RSTART - 1)
    tries = 10
    while (tries-- > 0) {
        #file_path = leading_elements  hex_digits(RLENGTH)
        for (i = 1; i <= RLENGTH; i++)
            rp = rp substr(letters_numbers, randint2(1, 36), 1)
        file_path = leading_elements  rp
        if (! path_exists_p(file_path))
            return file_path
    }
    panic("(mktemp) Could not create temporary file name from template '" path_template "'")
}


function min(m, n)
{
    return m < n ? m : n
}

function max(m, n)
{
    return m > n ? m : n
}


function mth__sign(x)
{
    return (x > 0) - (x < 0)
    # See _The Elements of Programming Style, 2ed_,
    # Kernighan & Plauger, 1974, pp. 1--2.
}

# Compute "machine epsilon" - the smallest number which when added to 1,
# produces a sum != 1.
# function mth__epsilon(    eps)
# {
#     eps = 1
#     while ((1 + eps / 2) != 1)
#         eps /= 2
#     #print sprintf("epsilon = %42.40e", eps)
# }


# do normal rounding
# https://www.gnu.org/software/gawk/manual/html_node/Round-Function.html
function mth__round(x,   ival, aval, fraction)
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


# Return value:         LOWER <= ri2() <= UPPER
# To generate a hex digit (0..15), say `randint2(0,15)'
# To roll a standard die (1..6),   say `randint2(1,6)'
function randint2(lower, upper)
{
    return int( (upper-lower+1) * rand()  + lower)
}
#function randint1(n)  { return int(n*rand()) }         # 0 <= ri1() < N


# Return a string of N random hex digits [0-9A-F].
function hex_digits(n,    s)
{
    s = EMPTY
    while (n-- > 0)
        s = s sprintf("%x", randint2(0,15))
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
    # The hard-coded "4" and business with the substr()
    # should make this a valid uuidV4 string.
    return     hex_digits(8)     \
           "-" hex_digits(4)     \
           "-" "4" hex_digits(3) \
           "-" substr("89ab", randint2(1,4), 1) \
                   hex_digits(3) \
           "-" hex_digits(12)
}


function to_roman(i,
                  value, res, x)
{
    i = int(i)
    if (i <= 0 || i > 3999) {
        warn("(to_roman) Argument " i " out of range")
        return i
    }
    res = ""
    for (x = 1; x <= 13; x++) {
        value = __rv[x]
        while (i >= value) {
            res = res __roman[value]
            i -= value
        }
    }
    return res
}


# Vincenty's inverse formula (ellipsoidal model, WGS84)
# Return value: Distance in Kilometers
#               or may throw an error on failure to converge
#
# Original Javascript code (c) 2002-2022 Chris Veness, MIT licensed
# http://www.movable-type.co.uk/scripts/latlong-vincenty.html
function vincenty_distance(lat1, lon1, lat2, lon2,
                           \
                           phi1, lambda1, phi2, lambda2,
                           a, f, L,
                           sinU1, sinU2, cosU1, cosU2, tanU1, tanU2,
                           lambda, lambdaP, iterations,
                           sinLambda, cosLambda, sinSqSigma, sinSigma, cosSigma,
                           sigma, sinAlpha, cosSqAlpha,
                           cos2SigmaM, C, b, uSq, A, B, deltaSigma,
                           distance, alpha1, alpha2, antipodal, iterCheck)
{
    a = 6378137.0               # WGS84 equatorial radius in meters
    f = 1 / 298.257223563       # WGS84 flattening
    b = a * (1 - f)             # Polar radius

    phi1 = mth__deg2rad(lat1);  lambda1 = mth__deg2rad(lon1)
    phi2 = mth__deg2rad(lat2);  lambda2 = mth__deg2rad(lon2)

    L = lambda2 - lambda1       # L = Longitude difference (radians)
    antipodal = abs(L) > TAU/4 || abs(phi2 - phi1) > TAU/4
   #tan(U) = (1-f) * tan(phi)   # U = Reduced latitude
    tanU1 = (1-f) * mth__tan(phi1)
      cosU1 = 1 / sqrt((1 + tanU1*tanU1))
      sinU1 = tanU1 * cosU1
    tanU2 = (1-f) * mth__tan(phi2)
      cosU2 = 1 / sqrt((1 + tanU2*tanU2))
      sinU2 = tanU2 * cosU2

    lambda = L
    sigma = antipodal ? PI : 0 # angular distance P1..P2 on the sphere
    sinSigma = 0
      cosSigma = antipodal ? -1 : 1
    cos2SigmaM = 1
    cosSqAlpha = 1

    iterations = 0
    do {
        sinLambda = sin(lambda)
        cosLambda = cos(lambda)
        sinSqSigma = (cosU2 * sinLambda)^2 \
                   + (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)^2
        if (abs(sinSqSigma) < 1e-24)
            break      # co-incident/antipodal points (sigma < ~0.006mm)
        sinSigma = sqrt(sinSqSigma)
        if (sinSigma == 0)
            return 0            # Coordinates are the same
        cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
        sigma = atan2(sinSigma, cosSigma)
        sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
        cosSqAlpha = 1 - sinAlpha^2
        # on equatorial line cos^2 alpha = 0
        cos2SigmaM = (cosSqAlpha != 0) ? (cosSigma - 2*sinU1*sinU2/cosSqAlpha) : 0
        C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
        lambdaP = lambda
        lambda = L + (1 - C) * f * sinAlpha * \
            (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM^2)))
        iterCheck = antipodal ? abs(lambda)-PI : abs(lambda)
        if (iterCheck > PI)
            error("(vincenty_distance) lambda > PI")
    } while (abs(lambda - lambdaP) > 1e-12 && ++iterations < 1000)

    if (iterations >= 1000) {
        error("(vincenty_distance) Failed to converge on solution")
    }

    uSq = cosSqAlpha * (a^2 - b^2) / (b^2)
    A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
    B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
    deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM^2) \
                                   - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma ^2) * (-3 + 4 * cos2SigmaM^2)))
    distance = b * A * (sigma - deltaSigma) # Distance in meters

   #return distance             # meters
    return distance / 1000      # kilometers
   #return distance / 1609.344  # miles
   #return distance / 1852      # nautical miles

    # NOTREACHED

    # Note special handling of exactly antipodal points where sin^2 alpha = 0
    # (due to discontinuity atan2(0, 0) = 0 but atan2(eps, 0) = PI/2 [90 deg]).
    # In which case bearing is always meridional, due north (or due south!)
    #
    # alpha1 = azimuths of the geodesic
    alpha1 = abs(sinSqSigma) < EPSILON ?  0 \
        : atan2(cosU2 * sinLambda,  cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
    # alpha2 = the direction P1 P2 produced
    alpha2 = abs(sinSqSigma) < EPSILON ? PI \
        : atan2(cosU1 * sinLambda, -sinU1 * cosU2 + cosU1 * sinU2 * cosLambda)

    # When converting radians back to degrees, West is negative if using
    # signed decimal degrees.  For bearings, values in the range -PI to
    # +PI [-180 deg to +180 deg] need to be converted to 0 to +2PI
    # [0-360]; this can be done by (bearing+2*PI)%2*PI [bearing+360)%360]
    # where % is the modulo operator.
}


function secure_level()
{
    return sys_read("__SECURE__", NOKEY)
}

function VERBOSE()
{
    return sys_read("__VERBOSE__", NOKEY) + 0
}

function LINE()
{
    return sys_read("__LINE__", NOKEY) + 0
}


function FILE()
{
    return sys_read("__FILE__", NOKEY)
}


function strictp(ssys)
{
    if (ssys == EMPTY)
        panic("(strictp) ssys must not be empty")
    # Use low-level function here, not sym_true_p(), to prevent infinite loop
    return sys_read("__STRICT__", ssys) != FALSE
}


function build_prog_cmdline(prog, arg, mode)
{
    if (! sys_in("__PROG__", prog))
        # This should be same as assert_[n]sym_defined()
        panic(sprintf("(build_prog_cmdline) __PROG__[%s] not defined", prog))
    return sprintf("%s %s%s", \
                   sys_read("__PROG__", prog),  \
                   arg, \
                   ((mode == MODE_IO_SILENT) ? sprintf(" >%s 2>%s", NULL, NULL) : EMPTY))
}


function exec_prog_cmdline(prog, arg,
                           cmd)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation("(exec_prog_cmdline) Forbidden")
    cmd = build_prog_cmdline(prog, arg, MODE_IO_SILENT) # always silent
    return system(cmd)
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
        t = sys_read("__TMPDIR__", NOKEY)
    while (last(t) == TOK_NEWLINE)
        t = chop(t)
    return with_trailing_slash(t)
}


function user_shell()
{
    if (sym_defined_p("M2_SHELL"))
        return sym_fetch("M2_SHELL")
    if ("SHELL" in ENVIRON)
        return ENVIRON["SHELL"]
    return safe_shell()
}

function safe_shell()
{
    if ("sh" in PROG)
        return sys_read("__PROG__", "sh")
    panic("(safe_shell) No shell program found")
}


# ATMODE is a property of the source.  If there is no source, we're probably
# in the process of undiverting a stream after the program ends.  Streams
# are not processed for macros, so the default mode in this case is literal.
function curr_atmode(    src_block)
{
    if (stk_empty_p(__source_stack))
        return MODE_AT_LITERAL
    src_block = stk_top(__source_stack)
    dbg__print_block("ship_out", 7, src_block, "(curr_atmode) src_block [top of __source_stack]")
    if (! ((src_block, 0, "atmode") in blktab)) {
        panic("(curr_atmode) Top block " src_block " does not have 'atmode'")
    }
    return blktab[src_block, 0, "atmode"]
}


# DSTBLK is a property of the parser.  There should always be at least a
# pass-through TERMINAL parser because initialize() creates it and it
# gets popped at the end of main().
function curr_dstblk(    top_block)
{
    if (stk_empty_p(__parse_stack))
        panic("(curr_dstblk) Parse stack is empty")
    top_block = stk_top(__parse_stack)
    dbg__print_block("ship_out", 7, top_block, "(curr_dstblk) top_block [top of __parse_stack]")
    if (! ((top_block, 0, "dstblk") in blktab)) {
        #panic("(curr_dstblk) Top block " top_block " does not have 'dstblk'")
        return TERMINAL
    }
    return blktab[top_block, 0, "dstblk"] + 0
}


function ppf__label(code)
{
    if (code == EMPTY)
        panic("(ppf__label) code must not be empty")
    code = first(code)
    dbg__print("xeq", 7, "(ppf__label) code = " code)
    if (! (code in __label)) {
        panic("(ppf__label) Invalid type '" code "'")
    }
    return __label[code]

}


function curr_level()
{
    return __curr_level
}


function raise_level()
{
    __curr_level++
    dbg__print("level", 4, "(raise_level) Level now " __curr_level)
    return __curr_level
}


function lower_level()
{
    if (__curr_level == ROOT_LEVEL)
        panic("(lower_level) Cannot be called from root level")
    sym_purge(__curr_level)
    #print_stderr("NAM_PURGE " __curr_level)
    nam_purge(curr_ns(), __curr_level)
    __curr_level--
    dbg__print("level", 4, "(lower_level) Level now " __curr_level)
    return __curr_level
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
    if (stk_empty_p(__parse_stack)) {
        __m2_msg = "Empty parse stack"
        return ERR_PARSE_STACK
    }

    btop = stk_top(__parse_stack)
    if (blk_type(btop) != expected_block_type) {
        __m2_msg = sprintf("Expected %s but found %s",
                           ppf__label(expected_block_type), ppf__label(blk_type(btop)))
        return ERR_PARSE_MISMATCH
    }

    # We have to subtract 1 because the original "depth" was stored
    # before the block was pushed onto the __parse_stack; and at this
    # point it hasn't been popped yet...
    if (blktab[btop, 0, "depth"] != stk_depth(__parse_stack) - 1) {
        __m2_msg = sprintf("Bad depth; expected %d but found %d",
                           stk_depth(__parse_stack) - 1, blktab[btop, 0, "depth"])
        return ERR_PARSE_DEPTH
    }

    return ERR_OKAY
}


function run_hook(hook_event,
                  hook_func, user_block, info)
{
    if (flag_anyfalse_p(__m2_config_flags, INIT_DOTFILES MODE_HOOKS_ENABLED)) {
        dbg__print("hook", 7, "(run_hook) Hooks are disabled")
        return
    }

    if (hook_event != "m2_begin" &&
        hook_event != "file_open"    && hook_event != "file_close" &&
        hook_event != "file_suspend" && hook_event != "file_resume" &&
        hook_event != "m2_end"       && hook_event != "m2_exit")
          panic("(run_hook) Invalid hook '" hook_event "'")

    hook_func = "__" hook_event "_hook"
    info__create_from_text(hook_func, info)
    if (info__get(info, "type") != TYPE_USER ||
        info__get(info, "defined") == FALSE  ||
        (user_block = info__get(info, "user_block") <= 0))
    {
        dbg__print("hook", 5, "(run_hook) Hook " hook_func " does not exist")
        return
    }

    dbg__print("hook", 3, "(run_hook) CALLING " hook_func ", user_block=" user_block)
    execute__user(3 SUBSEP M2_NS SUBSEP hook_func SUBSEP)
    dbg__print("hook", 3, "(run_hook) RETURNED FROM " hook_func)
}


function expand_braces(s,
                       atbr, cb, ltext, mtext, rtext,
                       macro)
{
    dbg__print("braces", 3, (">> expand_braces(s='" s "'"))
    macro["okay"] = FALSE       # Make sure Awk knows macro[] is an array

    while ((atbr = index(s, TOK_AT_BRACE)) > 0) {
        # There's a @{ somewhere in the string.  Find the matching
        # closing brace and expand the enclosed text.
        cb = find_closing_brace(s, atbr, TOK_AT_BRACE)
        if (cb <= 0)
            error("Bad @{...} expansion:" s)
        dbg__print("braces", 5, ("   expand_braces: in loop, atbr=" atbr ", cb=" cb))

        #      atbr---v
        # s == LTEXT  @{  MTEXT  }  RTEXT
        #                        ^---cb
        ltext = substr(s, 1,      atbr-1)
        mtext = substr(s, atbr+2, cb-atbr-2)
        rtext = substr(s, cb+1)
        if (dbg__sys_level_p("braces", 7)) {
            print_debugfile("m2debug:   expand_braces: ltext='" ltext "'")
            print_debugfile("m2debug:   expand_braces: mtext='" mtext "'")
            print_debugfile("m2debug:   expand_braces: rtext='" rtext "'")
        }

        # Fix quoted right brace
        gsub(/\\}/, TOK_RBRACE, mtext)

        # If we're looking at "@something@", strip off the leading and
        # trail @ and process just "something".  This happens if someone
        # (mistakenly) writes
        #       @{@symbol@}
        # which has happened.  Be careful not to touch "@{something}".
        while (length(mtext)       >= 2          &&
               first(mtext)        == TOK_AT     &&
               substr(mtext, 2, 1) != TOK_LBRACE &&
               last(mtext)         == TOK_AT)
            mtext = substr(mtext, 2, length(mtext) - 2)

        # Process any recursive @{...} expansions.  For example:
        #       Item @i@ - @{title_text[@{i}]}
        if (index(mtext, TOK_AT_BRACE) > 0)
            mtext = expand_braces(mtext)

        # No more fooling around, do the expansion already!
        macro_initialize(macro, mtext)
        if (!emptyp(mtext)) {
            macro_expand(macro)
            if (!macro["okay"] && strictp("def"))
                error(sprintf("@%s@: Name '%s' not defined%s",
                              macro["urtext"], macro["fn"],
                              VERBOSE() ? " [(expand_braces) macro_expand() failed && __STRICT__[def] AAA]" : ""))
            if (dbg__sys_level_p("braces", 6))
                print_debugfile("m2debug:   expand_braces: expand='" macro["expansion"] "'")
        }
        s = ltext macro["expansion"] rtext
    }

    dbg__print("braces", 3, ("<< expand_braces: => '" s "'"))
    return s
}


# NAME
#     find_closing_brace
#
# DESCRIPTION
#     Given a starting point (position of @{ in string), move forward
#     and return position of closing }.  Nested @{...} are accounted for.
#     If \} is encountered, continue scanning - \} is converted to } elsewhere.
#     If closing } is not found, return EOF.  On other error, return ERROR.
#
# PARAMETERS
#     s         String to examine.
#     start     The position in s, not necessarily 1, of the "@{"
#               for which we need to find the closing brace.
#     tok_opt   (optional) Start string.  Check that we are initially
#               looking at this.  Usual values: TOK_LBRACE, TOK_AT_BRACE
#
# LOCAL VARIABLES
#     offset    Current offset, counting characters from start in s.
#               Initially offset=0.  As we scan right, offset is incremented.
#     c         The current character, at position offset from start in s.
#                   c = substr(s, start+offset, 1)
#     nc        Next character beyond c, at position offset+1 from start in s.
#                   nc = substr(s, start+offset+1, 1)
#     cb        Closing brace - position of inner "}" found via recursion.
#     slen      Length of s.  s is not modified so its length is constant.
#
# RETURN VALUE
#     If successfully found a closing brace, return its position within s.
#     The actual value returned is start+offset.  If no closing brace is
#     found, or the search proceeds beyond the end of the string (i.e.,
#     start+offset > length(s)), return EOF as a "failure code".  If the
#     initial conditions are bad, return ERROR.
#
function find_closing_brace(s, start, tok_opt,
                            offset, c, nc, cb, slen, toklen)
{
    dbg__print("braces", 3, (">> find_closing_brace(s='" s "', start=" start))

    # Check that s[start] points to the optional starting token and that
    # the size is large enough to hold it.
    slen = length(s)
    toklen = length(tok_opt)
    if (toklen > 0 && (slen - start + 1 < toklen || substr(s, start, toklen) != tok_opt))
        return ERROR

    # At this point, we've verified that we're looking at the starting token,
    # so there are at least toklen characters in the string.  Moving along...
    # Look at the character (c) in s immediately following tok_opt, and also
    # the next character (nc) after that.  One or both might be empty string.
    offset = toklen
    c  = substr(s, start+offset,   1)
    nc = substr(s, start+offset+1, 1)

    # Don't let offset proceed beyond the end (length) of s
    while (start+offset <= slen) {
        dbg__print("braces", 7, ("   find_closing_brace: offset=" offset ", c=" c ", nc=" nc))
        if (c == "") {          # end of string/error
            break
        } else if (c == TOK_RBRACE) {
            dbg__print("braces", 3, ("<< find_closing_brace: => " start+offset))
            return start+offset
        } else if (c == TOK_BACKSLASH && nc == TOK_RBRACE) {
            # "\}" in expansion text will result in a single close brace
            # without ending the expansion text parser.  Skip over }
            # and do not return yet.  "\}" is fixed in calling routine.
            offset++; nc = substr(s, start+offset+1, 1)
        } else if (c == TOK_LBRACE) {
            # In the general case, encountering an additional "{" means
            # we have to recursively scan for *its* closing brace before
            # we can resume searching for the *current* closing brace.
            # Also, we take this branch when scanning @{...} expansions.
            cb = find_closing_brace(s, start+offset, TOK_LBRACE)
            if (cb <= 0)
                return cb       # propagate failure/error

            # Since the return value is the absolute location of the "}"
            # in string s, update offset to be the value corresponding
            # to that location.  In fact, offset is exactly the distance
            # from that closing brace back to "start".
            offset = cb - start
            nc = substr(s, start+offset+1, 1)
            dbg__print("braces", 5, ("   find_closing_brace: (recursive '{') cb=" cb \
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
function format_message(text, file, line,
                        s)
{
    file = file ""
    if (file == EMPTY)
        file = FILE() ? FILE() : __dofile_name
    if (file == STDIN || file == "-")
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
    if (flushlev <= sys_read("__SYNC__", NOKEY)) {
        # One of these is bound to work, right?
        fflush(STDOUT)
        # Reputed to be more portable:
        #    system("")
        # ----------------
        # Also, fflush("") will flush ALL files and pipes.  (gawk-specific?)
        # ----------------
        # From https://wiki.alpinelinux.org/wiki/Awk
        #    "This page compares BusyBox's implementation of awk with
        #    gawk (versions >= 3.1.8) and FreeBSD 9's nawk, which is
        #    based on Bell Labs/Brian Kernighan's 2007 version of awk."
        #
        #    fflush(output "file" or "pipe command")
        #      ~~> 0 if all requested buffers successfully flushed, else -1
        #        # not in gawk --posix
        #        # if no argument is supplied, flushes stdout
        #        # if "" is supplied, flushes all open output files and pipes
    }
}


function print_stderr(text)
{
    # "All modern systems have a /dev/stderr special file to which error
    # messages may be sent directly.  gawk, mawk and Brian Kernighan's
    # awk all have "/dev/stderr" built in for I/O redirections, so even
    # on systems without a real /dev/stderr special file, you can still
    # send error messages to standard error."
    #     https://www.skeeve.com/awk-sys-prog.html    June 2024
    printf "%s\n", text > STDERR
    # Definitely more portable:
    #    print text | "cat 1>&2"
}


function warn(text, file, line)
{
    print_stderr(format_message(text, file, line))
}


# error() is used when m2 cannot continue processing due to a logical
# error, invalid syntax, math error, etc, something from user code that
# doesn't work.  The end_program() executes any wraps and exits with code 1.
function error(text, file, line)
{
    warn(text, file, line)
    sys_write("__EXIT__", EX_M2_ERROR)
    if (sys_read("__LENIENT__", NOKEY) < 0)
        abend("FATAL", EX_M2_ERROR)
    if (sys_read("__LENIENT__", NOKEY) == 0)
        end_program(MODE_STREAMS_DISCARD)
}


# abend() is more extreme than error().  It should not be possible to
# induce a panic merely by executing user code.  It is used when there
# is an internal error, a logical inconsistency, or a "can't happen"
# situation.  It prints its message and exits immediately with code 70.
function abend(id, code,
               filename, file_block)
{
    if (code == EMPTY)
        code = EX_SOFTWARE
    if (id == EMPTY)
        id = "ABEND"
    print_stderr(sprintf("m2:%s %d", id, code))

    # Try to close any open files, but don't delete any blocks
    close_open_files(FALSE)
    flush_stdout(SYNC_FORCE)
    exit code
}


# When panic() is called, m2 will print its message and a timestamp).
# It does not output any streams or wraps.
function panic(text, file, line)
{
    warn(text, file, line)
    abend("PANIC", EX_SOFTWARE)
}


# A security violation occurs when an otherwise valid opertion is denied
# due to a heightened __SECURE__ level.
function security_violation(text, file, line)
{
    warn(text, file, line)
    abend("SECURITY VIOLATION", EX_NOPERM)
}


# Put next input line into global string "__buffer".  The readline()
# function manages the "pushback."  After expanding a macro, macro
# processors examine the newly created text for any additional macro
# names.  Only after all expanded text has been processed and sent to
# the output does the program get a fresh line of input.
# Return OKAY, ERROR, or EOF.  parse() is the only caller of readline.
# That used to be true, but read_lines_until() now also calls readline.
# (later) scan__usercmd_call() can also call readline, chasing closing `}'.
function readline(    retval, i, s, done, topsrc, trim_ws)
{
    dbg__print("io", 6, "(readline) START")
    retval = OKAY               # uncharacteristically optimistic
    s = ""
    done = trim_ws = FALSE
    if (stk_empty_p(__source_stack))
        panic("(readline) Source stack is empty")
    topsrc = stk_top(__source_stack)

    if (blk_type(topsrc) == BLK_STRING) {
        dbg__print_block("io", 7, topsrc)
        s = blktab[topsrc, 0, "str"]
        if (!emptyp(s)) {
            dbg__print("io", 3, sprintf("(readline) [STRING] RETURNING %d, '%s'", retval, s))
            $0 = s
            blktab[topsrc, 0, "str"] = EMPTY    # "USED UP"
            return retval
        } else {
            dbg__print("io", 6, "(readline) [STRING] RETURNING EOF")
            return EOF
        }
    }

    do {
        if (!emptyp(__buffer)) {
            dbg__print("io", 6, "(readline) __buffer not empty so using its contents")
            # Return the buffer even if somehow it doesn't end with a newline
            if ((i = index(__buffer, TOK_NEWLINE)) == NOT_FOUND) {
                s = s __buffer
                __buffer = EMPTY
            } else {
                s = s substr(__buffer, 1, i-1)
                __buffer = substr(__buffer, i+1)
            }

        } else {
            dbg__print("io", 8, "(readline) source_stack count = " stk_depth(__source_stack))
            dbg__print_block("io", 7, topsrc, "(readline) About to call getline < FILE()...")
            retval = getline < FILE()
            dbg__print("io", 7, "(readline) retval=" retval)
            if (retval == OKAY) {
                s = s (trim_ws ? ltrim($0) : $0); trim_ws = FALSE
                sys_incr("__LINE__", 1)
                sys_incr("__NLINE__", 1)
            } else {
                done = TRUE
                if (retval == ERROR)
                    warn("(readline) getline=>Error reading file '" FILE() "'")
                else if (retval != EOF)
                    panic("(readline) getline returned strange value: " retval)
            }
        }
        if (retval == OKAY && curr_atmode() == MODE_AT_PROCESS) {
            if (substr(s, length(s) - 2, 3) == "@\\n") {
                # Remove @\n and replace it with newline
                s = substr(s, 1, length(s) - 3) TOK_NEWLINE
                continue
            } else if (substr(s, length(s) - 2, 3) == "@\\-") {
                # Remove @\- and remember to eat upcoming leading whitespace
                s = substr(s, 1, length(s) - 3)
                trim_ws = TRUE
                continue
            } else if (substr(s, length(s) - 1, 2) == "@\\") {
                # Remove @\
                s = substr(s, 1, length(s) - 2)
                continue
            }
        }
        done = TRUE
    } while (!done)

    dbg__print("io", 3, sprintf("(readline) RETURNING %d, '%s'", retval, s))
    $0 = s
    return retval
}


# Read multiple lines until regexp is seen on a line and return TRUE.  If is not found,
# return FALSE.  The lines are always read literally.  Special case if
# regexp is "": read until end of file and return whatever is found,
# without error.
function read_lines_until(regexp, dstblk,
                          readstat)
{
    dbg__print("parse", 3, sprintf("(read_lines_until) START; regexp='%s', dstblk=%d",
                                 regexp, dstblk))
    if (dstblk == TERMINAL)
        panic("(read_lines_until) dstblk must not be 0")

    while (TRUE) {
        readstat = readline()   # OKAY, EOF, ERROR
        if (readstat == ERROR) {
            # Whatever just happened, the read didn't finish properly
            dbg__print("parse", 2, "(read_lines_until) readline()=>ERROR")
            return FALSE
        }
        if (readstat == EOF) {
            dbg__print("parse", 5, "(read_lines_until) readline()=>EOF")
            return regexp == EMPTY
        }

        dbg__print("parse", 5, "(read_lines_until) readline()=>OKAY; $0='" $0 "'")
        if (regexp != EMPTY && match($0, regexp)) {
            dbg__print("parse", 5, "(read_lines_until) END => TRUE")
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

    namtab[M2_SYSNS, "__DBG__", ROOT_LEVEL] = TYPE_ARRAY FLAG_SYSTEM
    split("args block bool braces case cmd del divert dosubs dump expr for " \
          "gate hook if io level nam ns parse qual read seq ship_out stk sym trace " \
          "while xeq",  _dbg_sys_array, TOK_SPACE)
    for (_dsys in _dbg_sys_array) {
        __dbg_sysnames[_dbg_sys_array[_dsys]] = TRUE
    }
}


# This function is called automagically (it's baked into sym_ll_write_ns())
# every time __DEBUG__ transitions from zero to a non-zero value.
function dbg__all_lev_standard()
{
    dbg__set_level("args",       0)
    dbg__set_level("block",      0)
    dbg__set_level("bool",       5)
    dbg__set_level("braces",     0)
    dbg__set_level("case",       5)
    dbg__set_level("cmd",        6)
    dbg__set_level("del",        5)
    dbg__set_level("divert",     7)
    dbg__set_level("dosubs",     6)
    dbg__set_level("dump",       5)
    dbg__set_level("expr",       3)
    dbg__set_level("for",        5)
    dbg__set_level("gate",       7)
    dbg__set_level("hook",       3)
    dbg__set_level("if",         5)
    dbg__set_level("io",         3)
    dbg__set_level("level",      5)
    dbg__set_level("nam",        3)
    dbg__set_level("parse",      7)
    dbg__set_level("qual",       7)
    dbg__set_level("read",       0)
    dbg__set_level("seq",        3)
    dbg__set_level("ship_out",   5)
    dbg__set_level("stk",        5)
    dbg__set_level("sym",        5)
    dbg__set_level("trace",      5)
    dbg__set_level("while",      5)
    dbg__set_level("xeq",        5)
}


function dbg__all_lev_zero(    dsys)
{
    for (dsys in __dbg_sysnames)
        sym_ll_write_ns(M2_SYSNS, "__DBG__", dsys, ROOT_LEVEL, 0)
}


# NB - This function writes directly to the symbol table.  It does not
# use sym_ll_write_ns(), and does not trigger special __DEBUG__ handling.
function enable_debugging()
{
    symtab[M2_SYSNS, "__DEBUG__", NOKEY,  ROOT_LEVEL, "symval"] = TRUE
}


function debugging_enabled_p()
{
    return sys_read("__DEBUG__", NOKEY)+0 > 0
}


# Predicate: TRUE if debug system level >= provided level (lev).
# Example:
#     if (dbg__sys_level_p("sym", 3))
#         warn("Debugging sym at level 3 or higher")
# NB - do NOT call sym_defined_p() here, you will get infinite recursion
function dbg__sys_level_p(dsys, lev)
{
    if (lev == EMPTY)           lev = 1
    if (dsys == EMPTY)          panic("(dbg) dsys must not be empty")
    if (! (dsys in __dbg_sysnames)) panic("(dbg) Unknown dsys name '" dsys "' (lev=" lev "): " $0)
    if (lev < 0)                return TRUE
    if (!debugging_enabled_p()) return FALSE
    if (lev == 0)               return TRUE # Don't combine with .-2; this allows negative levels to print regardless of __DEBUG__
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    if (!sys_in("__DBG__", dsys))
        return FALSE
    return dbg__get_level(dsys) >= lev
}


# Return the debug level for a given dsys.  If debugging is not enabled,
# return its negative value (i.e., multiply by -1) to indicate this.
# See additional comments in dbg__set_level for why this is useful.
#
# Caller can easily call abs() to get the correct value.  Currently,
# dbg__sys_level_p() is the only caller of this, and negative values are always
# going to be less than any LEV.
function dbg__get_level(dsys)
{
    if (dsys == EMPTY) panic("(dbg__get_level) dsys must not be empty")
    if (! (dsys in __dbg_sysnames)) panic("(dbg__get_level) Unknown dsys name '" dsys "'")
    if (!sys_in("__DBG__", dsys)) {
        warn("(dbg__get_level(" dsys "} not defined, returning 0")
        return 0
    }
    return (sys_read("__DBG__", dsys)+0) \
         * (debugging_enabled_p() ? 1 : -1)
}


# Set the level (lev) for the debug dsys
function dbg__set_level(dsys, lev)
{
    if (dsys == EMPTY)           panic("(dbg__set_level) dsys must not be empty")
    if (! (dsys in __dbg_sysnames)) panic("(dbg__set_level) Unknown dsys name '" dsys "'")
    if (lev == EMPTY)           lev = 1
    # Formerly, negative levels were automagically set to zero.
    # Now, the new level is the absolute value.  Since dbg__get_level()
    # returns a negative level when not debugging, this new version
    # allows the following:
    #           foo_old_level = dbg__get_level("foo")	# save old level
    #           dbg__set_level("foo", 7)			# raise level
    #           # ... foo stuff with temporarily raised debug level
    #           dbg__set_level("foo", foo_old_level)	# return orig
    # regardless of whether debugging is enabled or not.  It does mean
    # dbg__set_level("foo", -4) doesn't quite do what you say, but that
    # idiom was never supported before anyway.
    if (lev < 0)                lev = abs(lev)
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    sym_ll_write_ns(M2_SYSNS, "__DBG__", dsys, ROOT_LEVEL, lev+0)
}


function print_debugfile(text,
                         debugfile)
{
    debugfile = secure_level() == SEC_STANDARD \
        ? sys_read("__DEBUGFILE__", NOKEY) \
        : STDERR
    printf "%s\n", text > debugfile
}


function dbg__print(dsys, lev, text,
                   retval)
{
    if (dbg__sys_level_p(dsys, lev))
        print_debugfile("m2debug:" text)
}


function dbg__print_block(dsys, lev, blknum, description,
                          block_type, blk_label, text, body_block)
{
    if (! dbg__sys_level_p(dsys, lev))
        return
##    blknum = blknum+0
    # print_debugfile("m2debug:(dbg__print_block) blknum = " blknum)
    if (! ((blknum, 0, "type") in blktab))
        panic("(dbg__print_block) No 'type' field for block " blknum)
    block_type = blk_type(blknum)
    # print_debugfile("m2debug:(dbg__print_block) block_type = " block_type)
    blk_label = ppf__label(block_type)

    print_debugfile(sprintf("m2debug:Block # %d, Type=%s: %s", blknum, blk_label, description))
    print_debugfile(ppf__BLK(blknum))
    if (((blknum, 0, "body_block") in blktab)) {
        body_block = blktab[blknum, 0, "body_block"]
        print_debugfile(sprintf("m2debug:Block # %d, %s", body_block, blk_label, "body_ block from above"))
        print_debugfile(ppf__BLK(body_block))
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       T R A C E   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function trace_prefix(    prefix,
                          trace_mode)
{
    prefix = "M2Trace:"
    trace_mode = sys_read("__TRACEMODE__", NOKEY)
    if (flag_1true_p(trace_mode, TRACE_SHOW_FILE_NAME))
        prefix = prefix (FILE() ? FILE() : __dofile_name) ":"
    if (flag_1true_p(trace_mode, TRACE_SHOW_LINE_NUM))
        prefix = prefix LINE() ":"
    return prefix
}


function trace_ll_on(sym,
                     q)
{
    if (! nam__valid_p(sym, TYPE_SYMBOL, TRUE))
        error("(trace_ll_on) Invalid name '" sym "'")
    q = nam__qualify(sym)
    #print_stderr("(trace_ll_on) '" sym "' => '" q "'")
    tracetab[q] = OKAY
}

function trace_ll_off(sym,
                      q)
{
    if (! nam__valid_p(sym, TYPE_SYMBOL, TRUE))
        error("(trace_ll_off) Invalid name '" sym "'")
    q = nam__qualify(sym)
    #print_stderr("(trace_ll_off) '" sym "' => '" q "'")
    delete tracetab[q]
}

function tracing_symbol_p(sym,
                          q)
{
    if (! nam__valid_p(sym, TYPE_SYMBOL, TRUE)) {
        #error("(tracing_symbol_p) Invalid name '" sym "'")
        return FALSE
    }
    q = qualify(sym)
    return q in tracetab
}


function tracing_event_p(event,
                         trace_mode)
{
    if (index(TRACE_VALID_EVENTS, event) == NOT_FOUND)
        panic("(tracing_event_p) Unrecognized trace event '" event "'")
    trace_mode = sys_read("__TRACEMODE__", NOKEY)
    return flag_anytrue_p(trace_mode, event TRACE_ALL)
}


function trace(event, sym, message,
               trace_mode)
{
    if (sys_read("__TRACE__", NOKEY) == FALSE ||
        !tracing_event_p(event))
        return
    if (event == TRACE_COMMAND || event == TRACE_EXPANSION || event == TRACE_SYMBOL_READ_WRITE) {
        if (sym == EMPTY)
            panic("(trace) sym must not be empty")
        if (double_underscores_p(sym) ||
            !tracing_symbol_p(sym))
            return
    }
    print_debugfile(trace_prefix() TOK_SPACE message)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       G A T E
#
#       If it doesn't exit due to assertion, returns TRUE or FALSE.
#
#*****************************************************************************
function info__gate(opcode,      # OP_xxx operation
                    optype,      # OBJ_TYPE, might be repeated
                    info,        # info[] array from info__create_from_text()
                    opns,        # String containing proposed namespace
                    oplevel,     # Integer containing proposed level
                                 # (might differ from info["level"], often called ilevel)
                    caller,      # caller tag shown in errors
                    assert_true_or_exit, # True if this function behaves like assert()
             retval)                     # assert() and exits if condition is not met;
{                                        # If False, meekly return boolean.
    if (caller == EMPTY)
        panic("(info__gate) Empty caller")
    if (opns == EMPTY)
        panic(sprintf("(info__gate) Empty ns; name='%s', opcode=%s, optype=%s",
                      info__get(info, "name"), ppf__label(opcode), ppf__label(optype)))
    if (info__get(info, "errorp"))
        # If it starts out being bad, we're not going to touch it and leave
        # the error message alone.  It's probably a scan error.
        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit, EMPTY)

    if (info__get(info, "lexvalid") != TRUE)
        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                  sprintf("Name '%s' not valid [%d]",
                                          info__get(info, "urtext"),
                                          info__get(info, "lexvalid")))

    if (optype == PTYPE_ANY || optype == PTYPE_UNDEF)
        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                  sprintf("Type '%s' is not allowed here",
                                          ppf__label(optype)))

    retval = info["nparts"] == 1 ? info__gate_1part(opcode, optype, info, opns, oplevel, caller, assert_true_or_exit) \
                                 : info__gate_2parts(opcode, optype, info, opns, oplevel, caller, assert_true_or_exit)
    dbg__print("gate", 3, sprintf("(info__gate) (opcode=%s, optype=%s, text='%s', opns=%s, oplevel=%d, caller='%s' asrtTrue=%s) => %s",
                                  ppf__label(opcode), ppf__label(optype), info__get(info, "urtext"),
                                  opns, oplevel, caller, ppf__bool(assert_true_or_exit), ppf__bool(retval)))
    return retval
}


function info__gate_1part(opcode, optype, info, opns, oplevel, caller, assert_true_or_exit,
                          retval, itype, iname, icode, ilevel, ins)
{
    iname = info__get(info, "name")
    dbg__print("gate", 3, sprintf("(info__gate_1part) opcode=%s, optype=%s, name='%s', oplevel=%d",
                                  ppf__label(opcode), ppf__label(optype), iname, oplevel))
    if (optype == PTYPE_SCALAR)
        optype = TYPE_SYMBOL

    retval = FALSE
    icode  = info__get(info, "code")
    ilevel = info__get(info, "level")
    itype  = info__get(info, "type")
    ins    = info__get(info, "ns")

    do {
        #print_stderr("start 1part")
        #print_stderr("opcode=" opcode)
        if (opcode == OP_CREATE) {
            if (optype == TYPE_SEQUENCE) {
                if (! nam__valid_p(iname, optype, FALSE))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Invalid name '%s'",
                                                      iname))
                if (ilevel != NAME_NOT_FOUND)
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' already defined as a %s",
                                                      iname, ppf__label(itype)))
                # It's not found, so info[] won't be very helpful...
                if (double_underscores_p(iname))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected%s",
                                                      iname, VERBOSE() ? " [info__gate_1part:A]" : ""))
                retval = TRUE; break

          # } else if (optype == TYPE_COMMAND) {
            } else if (optype == TYPE_USER) {
                # If name starts with "__", it must be a valid hook name.
                # Double underscores are right out.
                #    name !~ /__(m2_begin|m2_end|file_open|file_close|file_suspend|file_resume)_hook/)
                if (!nam__valid_p(iname, optype, TRUE) ||
                    (substr(iname, 1, 2) == "__" &&
                     iname !~ /__((m2_(begin|end|exit))|(file_(open|close|suspend|resume)))_hook/))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Command name '%s' not valid", iname))
                # FIXME This is not quite sufficient (I think).  I probably need
                # to do a full nam__scan() / nam__lookup() because I don't want
                # to shadow a system symbol.  At least I need to be more careful
                # than "it's not in the current level, looks good!!"
                if (nam_ll_in_ns(ins, iname, curr_level()) ||
                    nam_ll_in_ns(ins, iname, ROOT_LEVEL))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Command name '%s' not available", iname))
                retval = TRUE; break

            } else if (optype == TYPE_SYMBOL ||
                       optype == TYPE_LIST   ||
                       optype == TYPE_ARRAY) {
                if (ilevel == NAME_NOT_FOUND) {
                    # It's a new, not-found symbol
                    if (double_underscores_p(iname))
                        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                                  sprintf("Name '%s' is protected%s",
                                                          iname, VERBOSE() ? " [info__gate_1part:B]" : ""))
                    #print_stderr("should be true")
                    retval = TRUE; break
                } else {
                    # It was found
                    #print_stderr("Found sym " name " at ilevel=" ilevel ", oplevel=" oplevel)
                    if (info__get(info, "protected"))
                        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                                  sprintf("Name '%s' is protected%s",
                                                          iname, VERBOSE() ? " [info__gate_1part:C]" : ""))

                    # For arrays or lists, don't let them be redefined at the current level.
                    #
                    # LATER: This code detects duplicate arrays or lists
                    # at @array or @list run-time.  But as part of
                    # namespaces upgrade, I declare things (in namtab
                    # only) at parse time, so I think this check should
                    # have already been performed.  It's okay if there's
                    # an entry in namtab.
                    #
                    # if ((optype == TYPE_ARRAY || optype == TYPE_LIST) &&
                    #     ilevel == curr_level())    # if (nam_ll_in(name, curr_level()))
                    #     return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                    #                               sprintf("%s '%s' already defined",
                    #                                       ppf__label(icode), iname))
                    retval = TRUE; break
                }
            }

        } else if (opcode == OP_READ) {
            #print_stderr("1 part read, optype=" optype)
            # Name must always be found for a read to be successful
            if (ilevel == NAME_NOT_FOUND)
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' not defined%s", iname,
                                                  VERBOSE() ? " [(info__gate_1part) OP_READ]" : ""))

            # # SCALAR must be checked before IDXABLE because the latter
            # # is a subset of the former
            # # if (flag_alltrue_p(optype, PTYPE_SCALAR)) {
            # if (optype == PTYPE_SCALAR) {
            #     if (itype != TYPE_SYMBOL && itype != TYPE_ARRAY && itype != TYPE_LIST)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("A Name '%s' has type %s, not Scalar",
            #                                           iname, ppf__label(itype)))
            #     retval = TRUE; break
            #
            # # } else if (flag_alltrue_p(optype, PTYPE_IDXABLE)) {
            # } else if (optype == PTYPE_IDXABLE) {
            #     if (itype != TYPE_ARRAY && itype != TYPE_LIST)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("B Name '%s' has type %s, not Array or List",
            #                                           iname, ppf__label(itype)))
            #     retval = TRUE; break
            #
            # } else if (optype == TYPE_ARRAY) {
            #     if (itype != optype)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("C Name '%s' has type %s, not %s",
            #                                           iname, ppf__label(itype), ppf__label(optype)))
            #     retval = TRUE; break
            # }
            if (! info__satisfies_type(info, optype))
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' has type %s, not %s",
                                                  iname, ppf__label(itype), ppf__label(optype)))
            retval = TRUE; break

        } else if (opcode == OP_UPDATE) {
            #print_stderr("op_update, optype=" optype)
            if (ilevel == NAME_NOT_FOUND)
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' not defined%s", iname,
                                                  VERBOSE() ? " [(info__gate_1part) OP_UPDATE]" : ""))

            if (optype == TYPE_SYMBOL || optype == TYPE_LIST || optype == TYPE_ARRAY || optype == PTYPE_NUMBER) {
                # if (itype != optype)
                if (! info__satisfies_type(info, optype))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' has type %s, not %s",
                                                      iname, ppf__label(itype), ppf__label(optype)))
                # So it *was found, on some level...  Can it be updated?
                # Good old dynamic scoping
                if (flag_1true_p(icode, FLAG_WRITABLE))
                    { retval = TRUE; break }
                if (flag_anytrue_p(icode, FLAG_READONLY FLAG_SYSTEM) ||
                    double_underscores_p(iname))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected%s",
                                                      iname, VERBOSE() ? " [info__gate_1part:D]" : ""))
                #print_stderr("should be true")
                retval = TRUE; break
            }
        } else if (opcode == OP_DELETE) {
            #print_stderr("OP_DELETE, optype=" optype)
            if (ilevel == NAME_NOT_FOUND)
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' not defined%s", iname,
                                                  VERBOSE() ? " [(info__gate_1part) OP_DELETE]" : ""))

            if (optype == TYPE_USER || optype == TYPE_SYMBOL) {
                if (info__get(info, "protected"))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected%s",
                                                      iname, VERBOSE() ? " [info__gate_1part:E]" : ""))
                retval = TRUE; break
            }
        }
        panic(sprintf("(info__gate_1part) UNHANDLED (opcode=%s, optype=%s, name='%s', oplevel=%d, caller='%s' assert=%s) => %s",
                      ppf__label(opcode), ppf__label(optype), iname,
                      oplevel, caller, ppf__bool(assert_true_or_exit), ppf__bool(retval)))
    } while (FALSE)

    return retval
}


function info__gate_2parts(opcode, optype, info, opns, oplevel, caller, assert_true_or_exit,
                           retval, itype, iname, ikey, icode, ilevel)
{
    iname = info__get(info, "name")
    ikey  = info__get(info, "key")
    dbg__print("gate", 3, sprintf("(info__gate_2parts) opcode=%s, optype=%s, name='%s', key='%s', oplevel=%d",
                                  ppf__label(opcode), ppf__label(optype), iname, ikey, oplevel))
    ilevel = info__get(info, "level")
    if (optype == PTYPE_SCALAR) {
        # Because Arrays and Lists must be declared before use, PTYPE_SCALAR
        # in a 2-part context can only refer to an *existing* Array or
        # List.  Therefore it is appropriate to check namtab now and
        # error if name is not declared.  Bonus: we know the exact type.
        if (ilevel == NAME_NOT_FOUND)
            return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                      sprintf("Name '%s' has not been declared", iname))

        # So it *was* found at some level - get its type
        itype = info__get(info, "type")
        #if (itype != TYPE_ARRAY && itype != TYPE_LIST)
        if (! info__satisfies_type(info, optype))
            return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                      sprintf("Type Array or List is required, not %s '%s'",
                                              ppf__label(itype), iname))
        # Pretend it was either Array or List we needed all along...
        optype = itype
    }

    retval = FALSE
    icode = info__get(info, "code")
    itype = info__get(info, "type")

    do {
        if (opcode == OP_CREATE) {
            # OLD:
            # if (optype == TYPE_ARRAY) {
            #     if (info__get(info, "protected"))
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("Name '%s' is protected [F]", iname))
            #     if (sym_ll_in_ns(M2_NS, iname, ikey, oplevel))
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("Key '%s' already found in Array '%s' at level %d", ikey, iname, oplevel))
            #     # It's not found at this level, but maybe it's at a higher level
            #     # print_stderr("Want to create " iname TOK_LBRACKET ikey TOK_RBRACKET " at level " oplevel)
            #     # print_stderr("  info[code]=" icode "   info_level=" info__get(info, "level"))
            #     if (ilevel != oplevel)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("Name '%s' is at a different level", iname))
            #     retval = TRUE; break
            # }
            if (info__satisfies_type(info, PTYPE_IDXABLE)) {
                if (info__get(info, "protected"))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected%s",
                                                      iname, VERBOSE() ? " [info__gate_2parts:G]" : ""))
                if (idx__key_exists_p(info, ikey))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Key '%s' already found in %s '%s'",
                                                      ikey, ppf__label(itype), iname))
                # It's not found at this level, but maybe it's at a higher level
                # print_stderr("Want to create " iname TOK_LBRACKET ikey TOK_RBRACKET " at level " oplevel)
                # print_stderr("  info[code]=" icode "   info_level=" info__get(info, "level"))
                #
                # LATER - I think this is okay, to allow updates to different levels.
                # if (ilevel != oplevel)
                #     return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                #                               sprintf("Name '%s' is at a different level", iname))
                retval = TRUE; break
            }
        } else if (opcode == OP_UPDATE) {
            #print_stderr("op_update; optype=" optype)

            if (! info__satisfies_type(info, optype))
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' has type %s, not %s",
                                                  iname, ppf__label(itype), ppf__label(optype)))
            if (info__get(info, "protected"))
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' is protected%s",
                                                  iname, VERBOSE() ? " [info__gate_2parts:H]" : ""))

            # We actually don't handle 2part PTYPE_NUMBER quite yet...
            # if (optype == PTYPE_NUMBER) {
            #     #print_stderr("ptype_number")
            #     print_stderr("OP_UPDATE : PTYPE_NUMBER : name='" iname "'; code='" icode "'; now what?")
            #     # if (! info__satisfies_type(info, optype))
            #     #     # return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #     #     #                           sprintf("Name '%s' has type %s, not %s",
            #     #     #                                   iname, ppf__label(itype), ppf__label(optype)))
            #     #     print_stderr("Type NOT satisfied")
            #     # else
            #     #     print_stderr("Type IS satisfied")
            # } else if (optype == TYPE_ARRAY) {

            # if (optype == TYPE_ARRAY) {
            #     #print_stderr("type_array")
            #     if (! sym_ll_in_ns(NEED_NS, iname, ikey, oplevel))
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("Key '%s' not found in Array '%s'", ikey, iname))
            #     #print_stderr("in symtab")
            #     #print_stderr("should be true")
            #     retval = TRUE; break
            # }

            if (info__satisfies_type(info, PTYPE_IDXABLE)) {
                if (! idx__key_exists_p(info, ikey))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Key '%s' not found in %s '%s'",
                                                      ikey, ppf__label(itype), iname))
                retval = TRUE; break
            }
        }

        panic(sprintf("(info__gate_2parts) UNHANDLED (opcode=%s, optype=%s, name='%s', key='%s', oplevel=%d, caller='%s' assert=%s) => %s",
                      ppf__label(opcode), ppf__label(optype), iname, ikey,
                      oplevel, caller, ppf__bool(assert_true_or_exit), ppf__bool(retval)))
    } while (FALSE)

    return retval
}


function info__satisfies_type(info, type_target,
                              itype, base_types, type_array, tentry)
{
    if (type_target == PTYPE_ANY)
        return TRUE
    itype = info__get(info, "type")
    base_types = __base_type[type_target]

    if (itype == PTYPE_UNDEF || type_target == PTYPE_UNDEF)
        panic("(info__satisfies_type) Cannot handle PTYPE_UNDEF")
#    print_stderr(sprintf("(info__satisfies_type) itype=%s, type_target=%s, base_types=%s",
#                         itype, type_target, base_types))

    # Do NUMBER and SCALAR specially because it also has to match flags
    if (type_target == PTYPE_NUMBER)
        return (itype == TYPE_SYMBOL && info__get(info, "has_bracket") == FALSE) ||
               (itype == TYPE_SEQUENCE) ||
               ((itype == TYPE_ARRAY || itype == TYPE_LIST) &&
                 info__get(info, "has_bracket") == TRUE &&
                 info__get(info, "key_valid") == TRUE)
    if (type_target == PTYPE_SCALAR)
        return (itype == TYPE_SYMBOL && info__get(info, "has_bracket") == FALSE) ||
               ((itype == TYPE_ARRAY || itype == TYPE_LIST) &&
                 info__get(info, "has_bracket") == TRUE &&
                 info__get(info, "key_valid") == TRUE)

    # split(PTYPE_IDXABLE VALID_TYPES, type_array, TOK_SPACE)
    # for (tentry in type_array)
    #     if (index(base_types, type_array[tentry]))
    #         return TRUE
#    print_stderr("index(" itype ", " base_types ") => " index(base_types, itype))
    return index(base_types, itype) > 0
    #return FALSE
}


function info__gate_resolve(retval, caller, info, assert_true_or_exit, errtext)
{
    if (errtext != "") {
        info["errorp"] = TRUE
        info["errtext"] = errtext
    }
    if (assert_true_or_exit && retval == FALSE)
        error(sprintf("%s: %s", caller, info__get(info, "errtext")))
    return retval
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       A R R A Y   A P I
#
#*****************************************************************************
# TODO This needs to get folded into an info[] attribute
function arrayp(arr,
                info) # nparts, level, info, code)
{
# OLD
    # # Check namtab
    # if ((nparts = nam__scan(arr, info)) == ERROR)
    #     error("(arrayp) Scan error, " __m2_msg)
    # if (nparts == 2)
    #     return FALSE
    #
    # # Now call nam__lookup(info).  Must be TYPE_ARRAY && !FLAG_SYSTEM
    # level = nam__lookup(info)
    # if (level == NAME_NOT_FOUND)
    #     return FALSE
    # if (info["is_array"] != TRUE)
    #     return FALSE
    # code = info["code"]
    # if (flag_1true_p(code, FLAG_SYSTEM))
    #     return FALSE

# NEW
    info__create_from_text(arr, info)
    if (info["errorp"] == TRUE)
        return FALSE
    if (info__get(info, "type") != TYPE_ARRAY)
        return FALSE
    if (info["nparts"] == 2)
        return FALSE
    if (info["level"] == NAME_NOT_FOUND)
        return FALSE
    if (flag_1true_p(info["code"], FLAG_SYSTEM))
        return FALSE
    # Maybe more checks later as I think of them
    return TRUE
}


function array_deref_info(info, caller)
{
    if (info__get(info, "type") == TYPE_ARRAY)
        return arr_fetch_info(info, caller)
    else if (info__get(info, "type") == TYPE_LIST)
        return lis_fetch_info(info, caller)
    else
        panic("(array_deref_info) Bad info")
}


function arr_fetch_info(info,
                        type, iname, ikey, ilevel, ins, val, code)
{
    if ((type = info__get(info, "type")) != TYPE_ARRAY)
        panic("(arr_fetch_info) Info not an Array")
    iname = info__get(info, "name")
    ikey = info__get(info, "key")
    ilevel = info__get(info, "level")
    ins = info__get(info, "ns")
    if (! sym_ll_in_ns(ins, iname, ikey, ilevel))
        error("(arr_fetch_info) Not in symtab: NAME='" iname "', KEY='" ikey "'")
    val = sym_ll_read_ns(ins, iname, ikey, ilevel)
    code = info__get(info, "code")
    dbg__print("sym", 2, sprintf("(arr_fetch_info) END sym='%s', level=%d => %s", iname, ilevel, ppf__bool(TRUE)))
    if (flag_1true_p(code, FLAG_INTEGER))
        return 0 + val
    else if (flag_1true_p(code, FLAG_NUMERIC))
        return 0.0 + val
    else if (flag_1true_p(code, FLAG_BOOLEAN))
        return sys_read("__FMT__", to_bool(val)) # !! (0 + val))
    else
        return val
}

function lis_fetch_info(info, caller,
                        type, ins, iname, ikey, ilevel, agg_block, count, val)
{
    if (caller == EMPTY)
        panic("(lis_fetch_info) Empty caller!")
    if ((type = info__get(info, "type")) != TYPE_LIST)
        panic("(lis_fetch_info) Info not a List")
    if (! integerp(ikey = info__get(info, "key")))
        error(sprintf("%s: Invalid List index '%s'", caller, ikey))
    ins = info__get(info, "ns")
    if (! ((ins, iname = info__get(info, "name"), NOKEY, ilevel = info__get(info, "level"), "agg_block") in symtab))
        panic(sprintf("(lis_fetch_info) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                      ins, iname, NOKEY, ilevel))
    agg_block = symtab[ins, iname, NOKEY, ilevel, "agg_block"]
    count = blktab[agg_block, 0, "count"]+0
    if (ikey+0 < 1 || ikey+0 > count)
        if (strictp("key"))
            error(sprintf("%s: Index '%s' out of bounds", caller, ikey))
        else
            return EMPTY

    # Make sure slot holds text, which it pretty much has to
    if (blk_ll_slot_type(agg_block, ikey) != OBJ_TEXT)
        panic(sprintf("(lis_fetch_info) Block # %d slot %d is not OBJ_TEXT", agg_block, ikey))
    val = blk_ll_slot_value(agg_block, ikey)
    return val
}


function lis_clear(ns, lis, level,
                   agg_block, count, i)
{
    # Clear List
    if (! ((ns, lis, NOKEY, level, "agg_block") in symtab))
        panic(sprintf("(lis_clear) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                      ns, lis, NOKEY, level))
    agg_block = symtab[ns, lis, NOKEY, level, "agg_block"]
    count = blktab[agg_block, 0, "count"]+0
    if (count > 0) {
        for (i = 1; i <= count; i++) {
            delete blktab[agg_block, i, "slot_type"]
            delete blktab[agg_block, i, "slot_value"]
        }
        blktab[agg_block, 0, "count"] = 0
    }
}

function idx__key_exists_p(info, key,
                           itype, iname, ins, ilevel)
{
    itype  = info__get(info, "type")
    iname  = info__get(info, "name")
    ilevel = info__get(info, "level")
    ins    = info__get(info, "ns")
    if (itype == TYPE_ARRAY)
        return sym_ll_in_ns(ins, iname, key, ilevel)
    else if (itype == TYPE_LIST)
        return lis__key_exists_p(ins, iname, key, ilevel)
    else
        panic("(idx__key_exists_p) Cannot handle type " ppf__label(itype))
}


# function arr_clear(arr, level, code,
#                      k, x, del_list, agg_block, count, i)
# {
#     if (code == EMPTY)
#         panic("(arr_clear) code must not be empty")
#     if (flag_1true_p(code, FLAG_BLKARRAY)) {
#         # # Clear block array
#         # if (! ((M2_NS, arr, NOKEY, level, "agg_block") in symtab))
#         #     panic(sprintf("(arr_clear) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
#         #                   M2_NS, arr, NOKEY, level))
#         # agg_block = symtab[M2_NS, arr, NOKEY, level, "agg_block"]
#         # count = blktab[agg_block, 0, "count"]+0
#         # if (count > 0) {
#         #     for (i = 1; i <= count; i++) {
#         #         delete blktab[agg_block, i, "slot_type"]
#         #         delete blktab[agg_block, i, "slot_value"]
#         #     }
#         #     blktab[agg_block, 0, "count"] = 0
#         # }
#     } else {
#         # Clear regular array
#         for (k in symtab) {
#             split(k, x, SUBSEP)
#             if (x[2] == arr && x[4]+0 == level)
#                 del_list[x[1], x[2], x[3], x[4], x[5]] = TRUE
#         }
#         for (k in del_list) {
#             split(k, x, SUBSEP)
#             dbg__print("sym", 3, sprintf("(arr_clear) Delete symtab[%s, '%s', '%s', %d, %s]",
#                                         x[1], x[2], x[3], x[4], x[5]))
#             delete symtab[x[1], x[2], x[3], x[4], x[5]]
#         }
#     }
# }


function lis__size(ns, lis, level,
                   agg_block)
{
    # Size block array
    if (! ((ns, lis, NOKEY, level, "agg_block") in symtab))
        panic(sprintf("(lis__size) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                      ns, lis, NOKEY, level))
    agg_block = symtab[ns, lis, NOKEY, level, "agg_block"]
    return blktab[agg_block, 0, "count"] + 0
}

function lis__key_exists_p(ns, lis, key, level)
{
    key = 0 + key
    return key > 0 && key <= lis__size(ns, lis, level)
}

function lis__assign(ns, name, key, level, new_val,
                     agg_block, count)
{
    # print_stderr(sprintf("List: %s[%s] = %s",
    #                      name, key, new_val))
    if (! integerp(key))
        error(sprintf("(lis__assign) Invalid List index '%s'", key))
    if (key < 1)
        error(sprintf("(lis_assign) Index '%s' out of bounds", key))
    if (! ((ns, name, NOKEY, level, "agg_block") in symtab))
        panic(sprintf("(lis__assign) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                      ns, name, NOKEY, level))
    agg_block = symtab[ns, name, NOKEY, level, "agg_block"]
    count = blktab[agg_block, 0, "count"]+0
    if (key > count+1)
        error(sprintf("(lis_assign) Index '%s' out of bounds", key))
    if (key == count+1)
        # Extend list by appending new element
        blk_append(agg_block, OBJ_TEXT, new_val)
    else
        # 1 <= key <= count
        blk_ll_write(agg_block, key, OBJ_TEXT, new_val)
}

function arr__size(ns, arr, level,
                   s, f, count)
{
    count = 0
    for (s in symtab) {
        split(s, f, SUBSEP)
        if (f[SFN_NS] == ns &&
            f[SFN_NAME] == arr &&
            f[SFN_LEVEL]+0 == level)
            count++
    }
    return count
}

function idx__size(info, # arr, level, code,
                   icode, ilevel, iname, ins, agg_block, count, k, x)
{
    if ((ins = info__get(info, "ns")) == EMPTY)
        panic("(idx__size) 'ns' must not be empty")
    if ((icode = info__get(info, "code")) == EMPTY)
        panic("(idx__size) 'code' must not be empty")

    iname  = info__get(info, "name")
    ilevel = info__get(info, "level")
    count = 0
    if (flag_1true_p(icode, TYPE_LIST)) {
        # # Size block array
        # if (! ((M2_NS, arr, NOKEY, level, "agg_block") in symtab))
        #     panic(sprintf("(idx__size) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
        #                   M2_NS, arr, NOKEY, level))
        # agg_block = symtab[M2_NS, arr, NOKEY, level, "agg_block"]
        # count = blktab[agg_block, 0, "count"]+0
        count = lis__size(ins, iname, ilevel)
    } else {
        # Size regular array
        # for (k in symtab) {
        #     split(k, x, SUBSEP)
        #     if (x[SFN_NAME] == arr && x[SFN_LEVEL]+0 == level)
        #         count++
        # }
        count = arr__size(ins, iname, ilevel)
    }
    dbg__print("sym", 7, sprintf("(idx__size) arr='%s', level=%d, RETURNING %d",
                                iname, ilevel, count))
    return count
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       B L O C K   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

# Return the newly allocated block number, strictly greater than zero.
# Block 0 does not exist -- it is the terminal.
function blk_new(block_type,
                 new_blknum, msg)
{
    if (block_type == EMPTY)
        panic("(blk_new) block_type must not be empty")
    new_blknum = ++__block_cnt

    blktab[new_blknum, 0, "depth"] = stk_depth(__parse_stack)
    blktab[new_blknum, 0, "type"] = block_type
    blktab[new_blknum, 0, "refcnt"] = 1

    if (block_type == BLK_AGG) {
        blktab[new_blknum, 0, "count"] = 0
        blktab[new_blknum, 0, "line"]  = LINE()
    } else if (block_type == BLK_CASE) {
        blktab[new_blknum, 0, "terminator"] = "^@__m2__::(endcase|esac)"
    } else if (block_type == BLK_FILE) {
        blktab[new_blknum, 0, "open"] = FALSE
        blktab[new_blknum, 0, "ever_opened"] = FALSE
        blktab[new_blknum, 0, "terminator"] = ""
        blktab[new_blknum, 0, "oob_terminator"] = "EOF"
    } else if (block_type == BLK_FOR) {
        # [0, "array_type"]     *       either @for or @foreach
        # [0, "blkvalid"]       *
        # [0, "body_block"]     *
        # [0, "dstblk"]         *
        # [0, "level"]          @foreach
        # [0, "loop_array_name] @foreach
        # [0, "loop_end"]       @for
        # [0, "loop_incr"]      @for
        # [0, "loop_start"]     @for
        # [0, "loop_type"]      *       @for, @foreach, @sforeach
        # [0, "loop_var"]       *
        blktab[new_blknum, 0, "terminator"] = "^@__m2__::next"
    } else if (block_type == BLK_IF) {
        blktab[new_blknum, 0, "terminator"] = "^@__m2__::(endif|fi)"
    } else if (block_type == BLK_LONGDEF) {
        blktab[new_blknum, 0, "terminator"] = "^@__m2__::endlong(def)?"
    } else if (block_type == BLK_STRING) {
        blktab[new_blknum, 0, "terminator"] = ""
        blktab[new_blknum, 0, "oob_terminator"] = "EOS"
    } else if (block_type == BLK_TERMINAL) {
        blktab[new_blknum, 0, "dstblk"] = TERMINAL
        blktab[new_blknum, 0, "terminator"] = ""
    } else if (block_type == BLK_USER) {
        # [0, "blkvalid"]
        # [0, "body_block"]
        # [0, "dstblk"]
        # [0, "name"]
        # [0, "nparam"]
        # [N, "param_name"]
        blktab[new_blknum, 0, "terminator"] = "^@__m2__::endcmd"
    } else if (block_type == BLK_WHILE) {
        blktab[new_blknum, 0, "terminator"] = "^@__m2__::(endwhile|wend)"
    } else
        panic("(blk_new) Uncaught block_type '" block_type "'")

    msg = sprintf("[Block Create] %s => %d",
                  ppf__label(block_type), new_blknum)
    #print_stderr(msg)
    trace(TRACE_BLOCKS, EMPTY, msg)
    dbg__print("ship_out", 2, "(block_new) " msg)
    return new_blknum
}


function blk_walk_delete(blknum, seen,
                         block_type, msg)
{
    if (--blktab[blknum, 0, "refcnt"] > 0)
        warn("(blk_walk_delete) Block " blknum " has refcnt " blktab[blknum, 0, "refcnt"] ", continuing...")

    block_type = blk_type(blknum)
    if      (block_type == BLK_AGG)      blk_walk_AGG(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_CASE)     blk_walk_CASE(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_FILE)     blk_walk_FILE(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_FOR)      blk_walk_FOR(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_IF)       blk_walk_IF(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_LONGDEF)  blk_walk_LONGDEF(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_STRING)   blk_walk_STRING(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_TERMINAL) blk_walk_TERMINAL(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_USER)     blk_walk_USER(OP_DELETE, blknum, seen, 0)
    else if (block_type == BLK_WHILE)    blk_walk_WHILE(OP_DELETE, blknum, seen, 0)
    else
        panic(sprintf("(blk_walk_delete) Can't handle type '%s' for block %d",
                      block_type, blknum))

    msg = sprintf("[Block Delete] %d %s",
                  blknum, ppf__label(block_type))
    trace(TRACE_BLOCKS, EMPTY, msg)
    dbg__print("ship_out", 2, "(blk_walk_delete) " msg)

    delete blktab[blknum, 0, "depth"]
    delete blktab[blknum, 0, "refcnt"]
    delete blktab[blknum, 0, "terminator"]
    delete blktab[blknum, 0, "type"]

    seen[blknum] = TRUE
    blk_lint(blknum)
}
function blk_master_delete(blknum,
                           block_type, seen)
{
    block_type = blk_type(blknum)

    if (block_type == BLK_FILE &&
        blktab[blknum, 0, "open"] == TRUE) {
        warn("(blk_master_delete) Refusing to delete open BLK_FILE " blknum)
        return
    }
    if (--blktab[blknum, 0, "refcnt"] > 0) {
        # Don't touch if someone else is still holding ref
        warn("(blk_master_delete) Refusing to delete blk " blknum " refcnt > 0")
        return
    }
    seen[VOID] = TRUE
    blk_walk_delete(blknum, seen)
}
function blk_lint(blknum,
                  b, f, blk, val, foundp)
{
    foundp = FALSE
    for (b in blktab) {
        split(b, f, SUBSEP)
        blk = f[1] + 0
        if (blk == blknum) {
            if (!foundp)        # first hit?
                # This is clumsy because I don't want to print a message
                # in the (hopefully) normal case of no hits.
                print_stderr(">>> BEGIN LINT blknum=" blknum)
            foundp = TRUE
            val = blktab[blk, f[BFN_SLOT], f[BFN_TAG]]
            warn(sprintf("(blk_lint) Found blktab[%d, %s, '%s'] with Val '%s'",
                         blk, f[BFN_SLOT], f[BFN_TAG], val))
        }
    }
    if (foundp)
        print_stderr("<<< END LINT")
}


function blk_type(blknum,
                  bt)
{
    if (! ((blknum, 0, "type") in blktab)) {
        if (sys_read("__LENIENT__", NOKEY) <= 0)
            panic("(blk_type) Block # " blknum " has no type!")
        warn("(blk_type) Block # " blknum " has no type => UNDEF")
        return PTYPE_UNDEF
    }
    bt = blktab[blknum, 0, "type"]
    #print_stderr(sprintf("BLK_TYPE:bt=%s, label=%s", bt, ppf__label(bt)))
    if (index(VALID_BLOCK_TYPES, bt) == NOT_FOUND)
        panic("(blk_type) Block # " blknum " has invalid block type '" bt "'")
    return bt
}


function blk_ll_slot_type(blknum, slot)
{
    if ((blknum, slot, "slot_type") in blktab)
        return blktab[blknum, slot, "slot_type"]
    panic("(blk_ll_slot_type) Not found: blknum=" blknum ", slot=" slot)
}


function blk_ll_slot_value(blknum, slot)
{
    if ((blknum, slot, "slot_value") in blktab)
        return blktab[blknum, slot, "slot_value"]
    panic("(blk_ll_slot_value) Not found: blknum=" blknum ", slot=" slot)
}


function blk_ll_write(blknum, slot, type, new_val)
{
    # print_stderr(sprintf("(blk_ll_write) blktab[%d, %d]; slot_type=%s, slot_value=%s",
    #                      blknum, slot, type, new_val))
    blktab[blknum, slot, "slot_type"]  = type
    blktab[blknum, slot, "slot_value"] = new_val
    return new_val
}


function blk_append(blknum, slot_type, value,
                    slot)
{
    if (!integerp(blknum))
        panic(sprintf("(blk_append) Block '%s' is not an integer", blknum))
    if (blk_type(blknum) != BLK_AGG)
        panic(sprintf("(blk_append) Block %d has type %s, not AGG",
                      blknum, ppf__label(blk_type(blknum))))

    if (slot_type != OBJ_CMD  && slot_type != OBJ_BLKNUM &&
        slot_type != OBJ_TEXT && slot_type != OBJ_USER)
        panic(sprintf("(blk_append) Argument has bad type %s; should be OBJ_{CMD,BLKNUM,TEXT,USER}", ppf__label(slot_type)))

    slot = ++blktab[blknum, 0, "count"]
    dbg__print("ship_out", 3,
              sprintf("(blk_append) blknum=%d, slot=%d, slot_type=%s, value='%s'",
                      blknum, slot, ppf__label(slot_type), value))
    blk_ll_write(blknum, slot, slot_type, value)
}


function blk_dump_blktab(    f, b, blknum, seen, type)
{
    for (b in blktab) {
        split(b, f, SUBSEP)
        blknum = f[BFN_BNUM] + 0
        if (! (blknum in seen)) {
            type = blk_type(blknum)
            dbg__print("xeq", 5, "(blk_dump_blktab) type=" type)
            dbg__print_block("xeq", -1, blknum, "(blk_dump_blktab)")
        }
        seen[blknum]++
    }
    return "(blk_dump_blktab)"
}


# function blk_nicer_dump_blktab( \
#                                x, k, blknum, seen, type,
#                                cnt, blks, i)
# {
#     cnt = 0
#     for (k in blktab) {
#         split(k, x, SUBSEP)
#         blks[++cnt] = x[1]+0  # block #
#     }
#     qsort(SORT_INTEGER, blks, 1, cnt)
#
#     # # "Touching the Void" (2003 movie)  True story of mountaineers on the
#     # # west face of Siula Grande.  https://www.imdb.com/title/tt0379557/
#     # seen[VOID] = TRUE
#     # seen[TERMINAL] = TRUE
#     for (i = 1; i <= cnt; i++) {
#         blknum = blks[i]
#         if ((! (blknum in seen))) {
#             print_stderr("================================")
#             blk_nicer_print_block(blknum, seen, 0) # 0 <-- indent level
#             # print_stderr("Lint(" blknum "):")
#             # blk_lint(blknum)
#         }
#     }
# }
function blk_nicer_print_block(blknum, seen, indent,
                               block_type)
{
    block_type = blk_type(blknum)
    if      (block_type == BLK_AGG)      blk_walk_AGG(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_CASE)     blk_walk_CASE(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_FILE)     blk_walk_FILE(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_FOR)      blk_walk_FOR(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_IF)       blk_walk_IF(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_LONGDEF)  blk_walk_LONGDEF(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_STRING)   blk_walk_STRING(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_TERMINAL) blk_walk_TERMINAL(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_USER)     blk_walk_USER(OP_PRINT, blknum, seen, indent)
    else if (block_type == BLK_WHILE)    blk_walk_WHILE(OP_PRINT, blknum, seen, indent)
    else
        panic(sprintf("(blk_nicer_print_block) Can't handle type '%s' for block %d",
                      block_type, blknum))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
function blk_walk_AGG(opcode, blknum, seen, indent,
                      i, count, slot_type, slot_value)
{
    count = blktab[blknum, 0, "count"] + 0
    if (opcode == OP_PRINT)
        print_debugfile(sprintf("%s%2d %s[%d]:",
                                spaces(3*indent), blknum,
                                "AGG", count))
    for (i = 1; i <= count; i++)
        if (opcode == OP_PRINT)
            blk_nicer_print__obj(blknum, i, seen, indent)
        else if (opcode == OP_DELETE) {
            slot_type   = blktab[blknum, i, "slot_type"]
            slot_value = blktab[blknum, i, "slot_value"]
            if (slot_type == OBJ_BLKNUM) {
                #print_stderr("(blk_walk_AGG) Slot " i " is type AGG, recursively deleting block " slot_value)
                blk_walk_delete(slot_value, seen)
            }
            delete blktab[blknum, i, "slot_type"]
            delete blktab[blknum, i, "slot_value"]
        }
    if (opcode == OP_DELETE) {
        delete blktab[blknum, 0, "count"]
        delete blktab[blknum, 0, "line"]
        if ((blknum, 0, "dstblk") in blktab)
            delete blktab[blknum, 0, "dstblk"]
    }
    seen[blknum] = TRUE
}
function blk_nicer_print__obj(blknum, slot, seen, indent,
                              slot_type, value)
{
    if (blk_type(blknum) != BLK_AGG)
        panic(sprintf("(blk_nicer_print__obj) Block %d has type %s, not AGG",
                      blknum, ppf__label(blk_type(blknum))))
    slot_type = blk_ll_slot_type(blknum, slot)
    value = blk_ll_slot_value(blknum, slot)
    print_stderr(sprintf("(blk_nicer_print__obj) block %d slot %d type %s => %s",
                         blknum, slot, slot_type, value))

    if (slot_type == OBJ_BLKNUM)
        blk_nicer_print_block(value, seen, indent)
    else if (slot_type == OBJ_TEXT)
        print_debugfile(sprintf("%s%2d [TEXT] %s",
                                spaces(3*indent), blknum, value))
    else if (slot_type == OBJ_CMD)
        print_debugfile(sprintf("%s%2d [CMD] %s",
                                spaces(3*indent), blknum, value))
    else if (slot_type == OBJ_USER)
        print_debugfile(sprintf("%s%2d [USER] %s",
                                spaces(3*indent), blknum, value))
    else
        # ? no other types?
        panic(sprintf("(blk_nicer_print__obj) Block # %d slot %d type %s not handled",
                      blknum, slot, slot_type))
}
function blk_walk_CASE(opcode, blknum, seen, indent,
                       b, d, f, del_list)
{
    if (opcode == OP_DELETE) {
        #print_stderr("OP_DELETE CASE begin:")
        #print_stderr("Deleting PREAMBLE block " blktab[blknum, 0, "preamble_block"])
        blk_walk_delete(blktab[blknum, 0, "preamble_block"], seen)

        # Delete the OF cases
        for (b in blktab) {
            split(b, f, SUBSEP)
            if (f[BFN_BNUM] == blknum && f[BFN_TAG] == "of_block") {
                del_list[f[BFN_BNUM], f[BFN_SLOT]] = TRUE
            }
        }
        for (d in del_list) {
            split(d, f, SUBSEP)
            #print_stderr("Deleting OF '" f[BFN_SLOT] "' block " blktab[f[BFN_BNUM], f[BFN_SLOT], "of_block"])
            blk_walk_delete(blktab[f[BFN_BNUM], f[BFN_SLOT], "of_block"], seen)
            delete blktab[f[BFN_BNUM], f[BFN_SLOT], "of_block"]
        }
        if (blktab[blknum, 0, "seen_otherwise"]) {
            #print_stderr("Deleting OTHERWISE block " blktab[blknum, 0, "otherwise_block"])
            blk_walk_delete(blktab[blknum, 0, "otherwise_block"], seen)
        }

        delete blktab[blknum, 0, "casevar"]
        delete blktab[blknum, 0, "dstblk"]
        delete blktab[blknum, 0, "otherwise_block"]
        delete blktab[blknum, 0, "preamble_block"]
        delete blktab[blknum, 0, "seen_otherwise"]
        delete blktab[blknum, 0, "blkvalid"]
        #print_stderr("OP_DELETE CASE end : Deleted CASE block " blknum)
    }
    seen[0 + blknum] = 1
}
function blk_walk_FILE(opcode, blknum, seen, indent)
{
    if (opcode == OP_PRINT)
        print_debugfile(sprintf("%2d (%1d ref) %s%s %s",
                                blknum, blktab[blknum, 0, "refcnt"],
                                spaces(3*indent),
                                "FILE", blktab[blknum, 0, "filename"]))
    if (opcode == OP_DELETE) {
        if (blktab[blknum, 0, "ever_opened"]) {
            delete blktab[blknum, 0, "old.buffer"]
            delete blktab[blknum, 0, "old.file"]
            delete blktab[blknum, 0, "old.file_uuid"]
            delete blktab[blknum, 0, "old.line"]
            delete blktab[blknum, 0, "old.ns"]
        }
        delete blktab[blknum, 0, "atmode"]
        delete blktab[blknum, 0, "ever_opened"]
        delete blktab[blknum, 0, "filename"]
        delete blktab[blknum, 0, "oob_terminator"]
        delete blktab[blknum, 0, "open"]
    }
    seen[blknum] = TRUE
}

function blk_walk_FOR(opcode, blknum, seen, indent)
{
    if (opcode == OP_DELETE) {
        #print_stderr("walk_FOR: type=" blktab[blknum, 0, "loop_type"])
        blk_walk_delete(blktab[blknum, 0, "body_block"], seen)

        if (blktab[blknum, 0, "loop_type"] == "@__m2__::for") {
            delete blktab[blknum, 0, "loop_end"]
            delete blktab[blknum, 0, "loop_incr"]
            delete blktab[blknum, 0, "loop_start"]

        } else if (blktab[blknum, 0, "loop_type"] == "@__m2__::foreach") {
            delete blktab[blknum, 0, "level"]
            delete blktab[blknum, 0, "loop_array_name"]
        }

        delete blktab[blknum, 0, "body_block"]
        delete blktab[blknum, 0, "dstblk"]
        delete blktab[blknum, 0, "loop_type"]
        delete blktab[blknum, 0, "loop_type"]
        delete blktab[blknum, 0, "loop_var"]
        delete blktab[blknum, 0, "blkvalid"]
    }
    seen[0 + blknum] = 1
}

function blk_walk_IF(opcode, blknum, seen, indent)
{
    if (opcode == OP_PRINT) {
        print_debugfile(sprintf("%s%2d %s %s%s",
                                spaces(3*indent), blknum,
                                "IF" , (blktab[blknum, 0, "init_negate"] ? "! " : ""),
                                blktab[blknum, 0, "condition"]))
        blk_nicer_print_block(blktab[blknum, 0, "true_block"], seen, indent+1)
    } else if (opcode == OP_DELETE)
        blk_walk_delete(blktab[blknum, 0, "true_block"], seen)
    if (blktab[blknum, 0, "seen_else"]) {
        if (opcode == OP_PRINT) {
            print_debugfile(sprintf("%s%2d %s",
                                    spaces(3*indent), blknum,
                                    "ELSE"))
            blk_nicer_print_block(blktab[blknum, 0, "false_block"], seen, indent+1)
        } else if (opcode == OP_DELETE)
            blk_walk_delete(blktab[blknum, 0, "false_block"], seen)
    }
    if (opcode == OP_PRINT) {
        print_debugfile(sprintf("%s%2d %s",
                                spaces(3*indent), blknum,
                                "ENDIF"))
    } else if (opcode == OP_DELETE) {
        delete blktab[blknum, 0, "condition"]
        delete blktab[blknum, 0, "dstblk"]
        delete blktab[blknum, 0, "false_block"]
        delete blktab[blknum, 0, "init_negate"]
        delete blktab[blknum, 0, "seen_else"]
        delete blktab[blknum, 0, "true_block"]
        delete blktab[blknum, 0, "blkvalid"]
    }
    seen[0 + blknum] = 1
}
function blk_walk_LONGDEF(opcode, blknum, seen, indent)
{
    if (opcode == OP_DELETE) {
        blk_walk_delete(blktab[blknum, 0, "body_block"], seen)
        delete blktab[blknum, 0, "body_block"]
        delete blktab[blknum, 0, "dstblk"]
        delete blktab[blknum, 0, "name"]
        delete blktab[blknum, 0, "ns"]
        delete blktab[blknum, 0, "blkvalid"]
    }
    seen[0 + blknum] = 1
}
function blk_walk_STRING(opcode, blknum, seen, indent)
{
    if (opcode == OP_DELETE) {
        delete blktab[blknum, 0, "oob_terminator"]
    }
    seen[0 + blknum] = 1
}
function blk_walk_TERMINAL(opcode, blknum, seen, indent)
{
    if (opcode == OP_PRINT) {
        print_debugfile(sprintf("%s%2d %s",
                                spaces(3*indent), blknum,
                                "TERMINAL"))
    } else if (opcode == OP_DELETE) {
        delete blktab[blknum, 0, "dstblk"]
    }
    seen[0 + blknum] = 1
}
function blk_walk_USER(opcode, blknum, seen, indent,
                       i)
{
    if (opcode == OP_DELETE) {
        #print_stderr("(blk_walk_USER) Recursively deleting body_block " blktab[blknum, 0, "body_block"])
        blk_walk_delete(blktab[blknum, 0, "body_block"], seen)

        for (i = 1; i <= blktab[blknum, 0, "nparam"]; i++)
            delete blktab[blknum, i, "param_name"]
        delete blktab[blknum, 0, "body_block"]
        delete blktab[blknum, 0, "dstblk"]
        delete blktab[blknum, 0, "name"]
        delete blktab[blknum, 0, "ns"]
        delete blktab[blknum, 0, "nparam"]
        delete blktab[blknum, 0, "blkvalid"]
        #print_stderr("(blk_walk_USER) DONE Deleted USER " blknum)
    }
    seen[0 + blknum] = 1
}
function blk_walk_WHILE(opcode, blknum, seen, indent)
{
    if (opcode == OP_DELETE) {
        #print_stderr("(blk_walk_WHILE) Recursively deleting body_block " blktab[blknum, 0, "body_block"])
        blk_walk_delete(blktab[blknum, 0, "body_block"], seen)

        delete blktab[blknum, 0, "body_block"]
        delete blktab[blknum, 0, "condition"]
        delete blktab[blknum, 0, "dstblk"]
        delete blktab[blknum, 0, "init_negate"]
        delete blktab[blknum, 0, "blkvalid"]
    }
    seen[0 + blknum] = 1
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =


function blk_dump_block_raw(blknum,
                            f, b, blk, type, slot_type_str)
{
    type = blk_type(blknum)
    dbg__print("xeq", 5, "(blk_dump_block_raw) type=" type)
    dbg__print_block("xeq", -1, blknum, "(blk_dump_block_raw)")

    for (b in blktab) {
        split(b, f, SUBSEP)
        blk = f[BFN_BNUM] + 0
        if (blk == blknum) {
            dbg__print("xeq", 9, "(blk_dump_block_raw) b=" b)
            slot_type_str = ""
            if (f[BFN_TAG] == "slot_type")
                slot_type_str = " (" ppf__label(blktab[f[1], f[2], f[3]]) ")"
            print_debugfile("m2debug:blknum=" f[BFN_BNUM] \
                            ", slot=" f[BFN_SLOT] \
                            ", tag=" f[BFN_TAG] \
                            " => '" blktab[f[1], f[2], f[3]] "'" slot_type_str)
        }
    }
}


function blk_to_string(blknum,
                        string, old_print_mode, old_textbuf)
{
    # Save original settings
    old_textbuf = __textbuf
    __textbuf = EMPTY

    # Temporarily force print mode to STRING output, will be restored
    old_print_mode = flag_1true_p(__m2_config_flags, MODE_TEXT_PRINT)
    __m2_config_flags = flag_set_clear(__m2_config_flags, MODE_TEXT_STRING, MODE_TEXT_PRINT)

    execute__block(blknum)
    string = __textbuf

    # Restore old settings
    __m2_config_flags = flag_set_clear(__m2_config_flags,
                                    old_print_mode ? MODE_TEXT_PRINT : MODE_TEXT_STRING, # set one of old print mode
                                    MODE_TEXT_STRING MODE_TEXT_PRINT) # after clearing both
    __textbuf = old_textbuf

    return chomp(string)
}


function ppf__block(blknum,
                    block_type, buf)
{
    block_type = blk_type(blknum)
    dbg__print("xeq", 3, sprintf("(ppf__block) START blknum=%d, type=%s",
                                blknum, ppf__label(block_type)))

    if      (block_type == BLK_AGG)       buf = ppf__agg(blknum)
    else if (block_type == BLK_CASE)      buf = ppf__case(blknum)
    else if (block_type == BLK_FILE)      buf = EMPTY
    else if (block_type == BLK_FOR)       buf = ppf__for(blknum)
    else if (block_type == BLK_IF)        buf = ppf__if(blknum)
    else if (block_type == BLK_LONGDEF)   buf = ppf__longdef(blknum)
    else if (block_type == BLK_STRING)    buf = blktab[blknum, 0, "str"]
    else if (block_type == BLK_TERMINAL)  buf = EMPTY
    else if (block_type == BLK_USER)      buf = ppf__user(blknum)
    else if (block_type == BLK_WHILE)     buf = ppf__while(blknum)
    else
        panic(sprintf("(ppf__block) Block # %d: type %s (%s) not handled",
                      blknum, block_type, ppf__label(block_type)))
    return buf
}


function ppf__BLK(blknum,
                  block_type, text)
{
    block_type = blk_type(blknum)
    dbg__print("xeq", 3, sprintf("(ppf__BLK) START blknum=%d, type=%s",
                                blknum, ppf__label(block_type)))

    if      (block_type == BLK_AGG)      text = ppf__BLK_AGG(blknum)
    else if (block_type == BLK_CASE)     text = ppf__BLK_CASE(blknum)
    else if (block_type == BLK_FILE)     text = ppf__BLK_FILE(blknum)
    else if (block_type == BLK_FOR)      text = ppf__BLK_FOR(blknum)
    else if (block_type == BLK_IF)       text = ppf__BLK_IF(blknum)
    else if (block_type == BLK_LONGDEF)  text = ppf__BLK_LONGDEF(blknum)
    else if (block_type == BLK_STRING)   text = ppf__BLK_STRING(blknum)
    else if (block_type == BLK_TERMINAL) text = EMPTY
    else if (block_type == BLK_USER)     text = ppf__BLK_USER(blknum)
    else if (block_type == BLK_WHILE)    text = ppf__BLK_WHILE(blknum)
    else
        panic(sprintf("(ppf__BLK) Can't handle type '%s' for block %d",
                      block_type, blknum))

    return text
}


function execute__block(blknum,
                        block_type, old_level)
{
    block_type = blk_type(blknum)
    dbg__print("xeq", 1, sprintf("(execute__block) START blknum=%d, type=%s",
                                blknum, ppf__label(block_type)))
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL)) {
        dbg__print("xeq", 3, "(execute__block) NOP !MODE_XEQ_NORMAL")
        return
    }

    old_level = curr_level()
    if      (block_type == BLK_AGG)       xeq__BLK_AGG(blknum)
    else if (block_type == BLK_CASE)      xeq__BLK_CASE(blknum)
    # BLK_FILE
    else if (block_type == BLK_FOR)       xeq__BLK_FOR(blknum)
    else if (block_type == BLK_IF)        xeq__BLK_IF(blknum)
    else if (block_type == BLK_LONGDEF)   xeq__BLK_LONGDEF(blknum)
    # BLK_STRING
    # BLK_TERMINAL
    else if (block_type == BLK_USER)      xeq__BLK_USER(blknum)
    else if (block_type == BLK_WHILE)     xeq__BLK_WHILE(blknum)
    else
        panic(sprintf("(execute__block) Block # %d: type %s (%s) not handled",
                      blknum, block_type, ppf__label(block_type)))

    if (curr_level() != old_level)
        panic(sprintf("(execute__block) blknum=%d, type=%s: %s; old_level=%d, curr_level()=%d",
                      blknum, ppf__label(block_type), "Level mismatch", old_level, curr_level()))
    dbg__print("xeq", 1, "(execute__block) END")
}


function xeq__BLK_AGG(agg_block,
                      i, lim, slot_type, value, block_type, name,
                      hack_line, line, old_line)
{
    hack_line = FALSE
    block_type = blk_type(agg_block)
    dbg__print("xeq", 3, sprintf("(xeq__BLK_AGG) START dstblk=%d, agg_block=%d, type=%s",
                                curr_dstblk(), agg_block, ppf__label(block_type)))
    dbg__print_block("xeq", 7, agg_block, "(xeq__BLK_AGG) agg_block")

    lim = blktab[agg_block, 0, "count"]

    # Hack __LINE__
    if ((agg_block, 0, "line") in blktab) {
        line = blktab[agg_block, 0, "line"]
        #print_stderr(sprintf("(xeq__BLK_AGG) Block %d had 'line' = %d", agg_block, line))
        hack_line = TRUE
        old_line = LINE()
        sys_write("__LINE__", line)
    }

    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(agg_block, i)
        value = blk_ll_slot_value(agg_block, i)
        dbg__print("xeq", 7, sprintf("(xeq__BLK_AGG) LOOP; dstblk=%d, agg_block=%d, slot=%d, slot_type=%s, value='%s'",
                                    curr_dstblk(), agg_block, i, ppf__label(slot_type), value))
        dbg__print("xeq", 3, sprintf("(xeq__BLK_AGG) TOP OF LOOP: ________ BLOCK %d  SLOT %d ________",
                                     agg_block, i))

        if (hack_line)
            sys_incr("__LINE__", 1)
        dbg__print("xeq", 3, sprintf("(xeq__BLK_AGG) CALLING ship_out(%s, '%s')", ppf__label(slot_type), value))
        ship_out(slot_type, value)
        dbg__print("xeq", 3, "(xeq__BLK_AGG) RETURNED FROM ship_out()")
    }
    if (hack_line)
        sys_write("__LINE__", old_line)
}


function ppf__agg(agg_block,
                  lim, i, slot_type, value, buf)
{
    if (blk_type(agg_block) != BLK_AGG)
        panic(sprintf("(ppf__agg) Block %d type != AGG",
                      agg_block))
    lim = blktab[agg_block, 0, "count"]
    buf = ""
    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(agg_block, i)
        value = blk_ll_slot_value(agg_block, i)

        if (slot_type == OBJ_BLKNUM)
            buf = buf ppf__block(value) TOK_NEWLINE
        else if (slot_type == OBJ_USER)
            buf = buf ppf__user_call(value) TOK_NEWLINE
        else if (slot_type == OBJ_CMD || slot_type == OBJ_TEXT)
            buf = buf value TOK_NEWLINE
        else
            panic(sprintf("(ppf__agg) Bad slot type %s", slot_type))
    }

    return chomp(buf)
}


function ppf__BLK_AGG(blknum,
                      slotinfo, count, x)
{
    slotinfo = ""
    count = blktab[blknum, 0, "count"]
    if (count > 0 ) {
        slotinfo = "  Slots:" TOK_NEWLINE
        for (x = 1; x <= count; x++)
            slotinfo = slotinfo sprintf("  [%d]=%s: %s\n",
                                        x,
                                        ppf__label(blk_ll_slot_type(blknum, x)),
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
function cmd_definition_ppf(name,
                            info, ns, level, user_block)
{
    if (nam__scan(name, info) == ERROR)
        error(sprintf("Scan error: %s%s", __m2_msg, VERBOSE() ? " [cmd_definition_ppf]" : ""))
    if ((level = nam__lookup(info)) == NAME_NOT_FOUND)
        error("(cmd_definition_ppf) nam__lookup failed")
    if ((ns = info__get(info, "ns")) == EMPTY)
        error("(cmd_definition_ppf) Empty ns")
    # See if it's a user command
    if (flag_1false_p(nam_ll_read_ns(ns, name, level), TYPE_USER))
        panic("(cmd_definition_ppf) " name " is no longer a user command")

    user_block = cmd_ll_read_ns(ns, name, level)
    return ppf__user(user_block)
}


# s is the encoded version (3) of the invocation:
#       <nitem> SUBSEP <ns> SUBSEP <name> SUBSEP [ { <arg-N> SUBSEP } ... ]
# nitem includes itself, so for a minimal case of calling a command with
# no arguments, nitem would be 3: one for itself, one for <ns>, and one
# for <name>.  Note this is also the number of SUBSEPs expected.
# When arguments are supplied, nitem = # args + 3.
#       5 SUBSEP <ns> SUBSEP <name> SUBSEP <arg1> SUBSEP <arg2> SUBSEP
# Note: SUBSEP is a field *terminator*; previously it was a separator.
function ppf__user_call(s,
                        nitem, citem, arg, retval)
{
    # print_stderr(ppf__sepstr(s))
    nitem = split_subsep(s, citem)

    retval = TOK_AT
    if (citem[CFN_NS] != curr_ns())
        retval = retval citem[CFN_NS] TOK_NS_QUAL
    retval = retval citem[CFN_NAME]
    for (arg = 1; arg <= nitem-3; arg++)
        retval = retval TOK_LBRACE citem[3+arg] TOK_RBRACE
    return retval
}


function ppf__user(user_block,
                   name, ns, params, i)
{
    if ((blk_type(user_block) != BLK_USER) ||
        (blktab[user_block, 0, "blkvalid"] != TRUE))
        panic("(ppf__user) Bad user_block config")

    name = blktab[user_block, 0, "name"]
    ns   = blktab[user_block, 0, "ns"]
    params = ""
    for (i = 1; i <= blktab[user_block, 0, "nparam"]; i++)
        params = params TOK_LBRACE blktab[user_block, i, "param_name"] TOK_RBRACE
    dbg__print("cmd", 5, "params='" params "'") # probably 7 or 8

    return "@newcmd " (ns != curr_ns() ? ns TOK_NS_QUAL : "") name params TOK_NEWLINE \
              ppf__agg(blktab[user_block, 0, "body_block"]) TOK_NEWLINE \
           "@endcmd"
}


function cmd_destroy(info,
                     user_block)
{
    #print_stderr("cmd_destroy:")
    if (flag_1false_p(info__get(info, "code"), TYPE_USER))
        panic("(cmd_destroy) " info__get(info, "name") " is no longer a user command")

    user_block = cmd_ll_read_ns(info__get(info, "ns"),
                                info__get(info, "name"),
                                info__get(info, "level"))
    blk_master_delete(user_block)
    # delete namtab[M2_NS, id, ROOT_LEVEL]
    # delete symtab[M2_NS, name, NOKEY, level, "user_block"]
}


function cmd_ll_read_ns(ns, name, level)
{
    return symtab[ns, name, NOKEY, level, "user_block"]
}


function cmd_ll_write_ns(ns, name, level, user_block)
{
    return symtab[ns, name, NOKEY, level, "user_block"] = user_block
}


function execute__command(name, cmdline,
                          old_level)
{
    dbg__print("xeq", 3, sprintf("(execute__command) START name='%s', cmdline='%s'",
                                name, cmdline))
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL)) {
        dbg__print("xeq", 3, "(execute__command) NOP !MODE_XEQ_NORMAL")
        return
    }

    if (substr(name, 1, 8) != M2_SYSNS TOK_NS_QUAL)     # __m2__::<cmd>
        panic(sprintf("(execute__command) Namespace !M2_SYSNS in '%s'", name))
    name = substr(name, 9)

    trace(TRACE_COMMAND, name, sprintf("[Execute] @%s %s", name, cmdline))
    old_level = curr_level()

    # DISPATCH
    # Also need an array entry to initialize command name.  [search: CMDS]
    # NB - immediate commands are not listed here; instead, [search: IMMEDS]
    if      (name ==  "append")         xeq_cmd__define(name, cmdline)
    else if (name ==  "array")          xeq_cmd__array(name, cmdline)
    else if (name ==  "break")          xeq_cmd__break(name, cmdline)
    else if (name ==  "cleardivert")    xeq_cmd__cleardivert(name, cmdline)
    else if (name ==  "continue")       xeq_cmd__continue(name, cmdline)
    else if (name ==  "data")           xeq_cmd__data(name, cmdline)
    else if (name ==  "debug")          xeq_cmd__error(name, cmdline)
    else if (name ==  "decr")           xeq_cmd__incr(name, cmdline)
    else if (name ==  "default")        xeq_cmd__define(name, cmdline)
    else if (name ==  "define")         xeq_cmd__define(name, cmdline)
    else if (name ==  "divert")         xeq_cmd__divert(name, cmdline)
    else if (name ==  "divpop")         xeq_cmd__divpop(name, cmdline)
    else if (name ==  "divpush")        xeq_cmd__divpush(name, cmdline)
    else if (name ==  "dumpdef")        xeq_cmd__dumpdef(name, cmdline)
    else if (name ~   /dump(all)?/)     xeq_cmd__dump(name, cmdline)
    else if (name ~ /s?echo/)           xeq_cmd__error(name, cmdline)
    else if (name ~   /enddata|eod/)    error(sprintf("@%s: Parse error; Not in a @data block", name))
    else if (name ~ /s?error/)          xeq_cmd__error(name, cmdline)
    else if (name ==  "errprint")       xeq_cmd__error(name, cmdline)
    else if (name ==  "esyscmd")        xeq_cmd__esyscmd(name, cmdline)
    else if (name ==  "eval")           xeq_cmd__eval(name, cmdline)
    else if (name ~ /s?exit/)           xeq_cmd__exit(name, cmdline)
    else if (name ~ /s?filedata/)       xeq_cmd__filedata(name, cmdline)
    else if (name ~ /s?filedef(ine)?/)  xeq_cmd__filedefine(name, cmdline)
    else if (name ==  "ignore")         xeq_cmd__ignore(name, cmdline)
    else if (name ~ /s?import/)         xeq_cmd__include(name, cmdline)
    else if (name ~ /s?(ns)?include/)   xeq_cmd__include(name, cmdline)
    else if (name ==  "incr")           xeq_cmd__incr(name, cmdline)
    else if (name ==  "initialize")     xeq_cmd__define(name, cmdline)
    else if (name ==  "input")          xeq_cmd__input(name, cmdline)
    else if (name ==  "list")           xeq_cmd__list(name, cmdline)
    else if (name ==  "literal")        xeq_cmd__literal(name, cmdline)
    else if (name ==  "local")          xeq_cmd__local(name, cmdline)
    else if (name ==  "m2ctl")          xeq_cmd__m2ctl(name, cmdline)
    else if (name ==  "namespace")      xeq_cmd__namespace(name, cmdline)
    else if (name ==  "nextfile")       xeq_cmd__nextfile(name, cmdline)
    else if (name ~ /s?paste/)          xeq_cmd__include(name, cmdline)
    else if (name ==  "readonly")       xeq_cmd__readonly(name, cmdline)
    else if (name ==  "return")         xeq_cmd__return(name, cmdline)
    else if (name ==  "sequence")       xeq_cmd__sequence(name, cmdline)
    else if (name ==  "set")            xeq_cmd__define(name, cmdline)
    else if (name ==  "shell")          xeq_cmd__shell(name, cmdline)
    else if (name ==  "split")          xeq_cmd__split(name, cmdline)
    else if (name ==  "syscmd")         xeq_cmd__syscmd(name, cmdline)
    else if (name ==  "tracemode")      xeq_cmd__tracemode(name, cmdline)
    else if (name ==  "traceoff")       xeq_cmd__traceoff(name, cmdline)
    else if (name ==  "traceon")        xeq_cmd__traceon(name, cmdline)
    else if (name ==  "typeout")        xeq_cmd__typeout(name, cmdline)
    else if (name ~   /undef(ine)?/)    xeq_cmd__undefine(name, cmdline)
    else if (name ==  "undivert")       xeq_cmd__undivert(name, cmdline)
    else if (name ==  "warn")           xeq_cmd__error(name, cmdline)
    else if (name ==  "wrap")           xeq_cmd__wrap(name, cmdline)
    else
        panic("(execute__command) Unrecognized command '" name "' in '" cmdline "'")

    if (curr_level() != old_level)
        panic(sprintf("(execute__command) [@%s] Level mismatch; old_level=%d, curr_level()=%d",
                      name, old_level, curr_level()))
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
    print_debugfile("m2debug:(dump_parse_stack) BEGIN")
    if (stk_depth(__parse_stack) == 0)
        print_debugfile("m2debug:(dump_parse_stack) Parse stack is empty")
    else
        for (level = stk_depth(__parse_stack); level > 0; level--) {
            block = __parse_stack[level]
            block_type = blk_type(block)
            print_debugfile("m2debug:(dump_parse_stack) Level " level ", block # " block ", type=" ppf__label(block_type) )
            dbg__print_block("xeq", -1, block)
        }
    print_debugfile("m2debug:(dump_parse_stack) END")
}


function prep_file(filename,
                   file_block, retval)
{
    dbg__print("parse", 7, "(prep_file) START filename='" filename "'")
    # create and return a BLK_FILE set up for the terminal
    file_block = blk_new(BLK_FILE)
    if (filename == "-")
        filename = STDIN
    blktab[file_block, 0, "filename"] = filename
    blktab[file_block, 0, "atmode"] = MODE_AT_PROCESS

    dbg__print("parse", 7, "(prep_file) END; file_block => " file_block)
    return file_block
}


function dofile(filename,
                file_block, retval, p)
{
    __dofile_name = filename
    dbg__print("parse", 5, "(dofile) START filename='" filename "'")

    # Prepare to read filename; set up a BLK_FILE block to manage input
    # and a BLK_TERMINAL to receive output
    file_block = prep_file(filename)
    trace(TRACE_BLOCKS, EMPTY, sprintf("[Block Update] %d FILE, filename='%s'",
                                       file_block, filename))

    dbg__print("parse", 7, sprintf("(dofile) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)
    stk_push(__parse_stack, __terminal)

    dbg__print("parse", 5, "(dofile) CALLING parse__file()")
    retval = parse__file(M2_NS)
    # parse_file() pops the source stack and deletes the BLK_FILE block
    dbg__print("parse", 5, "(dofile) RETURNED FROM parse__file()")

    # Clean up
    p = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(dofile) popped parse_stack => " p)
    dbg__print("parse", 5, "(dofile) END => " ppf__bool(retval))
    return retval
}


# Create a File block and read the file.
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
function parse__file(default_ns,
                     filename, file_block, pstat, d)
{
    if (stk_empty_p(__source_stack))
        panic("(parse__file) Source stack is empty")
    file_block = stk_top(__source_stack)

    filename = blktab[file_block, 0, "filename"]
    dbg__print("parse", 2, sprintf("(parse__file) filename='%s', dstblk=%d, mode=%s",
                                  filename, curr_dstblk(),
                                  ppf__label(blktab[file_block, 0, "atmode"])))
    if (!path_exists_p(filename)) {
        dbg__print("parse", 2, sprintf("(parse__file) END File '%s' does not exist => %s",
                                     filename, ppf__bool(FALSE)))
        stk_pop(__source_stack) # Remove BLK_FILE for non-existent file
        blk_master_delete(file_block)
        return FALSE
    }
    if (filename in __active_files)
        error("Cannot recursively read '" filename "':" $0)

    if (sys_read("__DEPTH__", NOKEY) > 0)
        run_hook("file_suspend")

    __active_files[filename] = file_block
    sys_incr("__NFILE__", 1); __rnf++
    blktab[file_block, 0, "open"]          = TRUE
    blktab[file_block, 0, "ever_opened"]   = TRUE
    blktab[file_block, 0, "old.buffer"]    = __buffer
    blktab[file_block, 0, "old.file"]      = FILE()
    blktab[file_block, 0, "old.file_uuid"] = sys_read("__FILE_UUID__", NOKEY)
    blktab[file_block, 0, "old.line"]      = LINE()
    blktab[file_block, 0, "old.ns"]        = curr_ns()
    dbg__print_block("ship_out", 7, file_block, "(parse__file) file_block")

    # Set up new file context
    __buffer = EMPTY
    sys_incr( "__DEPTH__",     1)
    sys_write("__FILE__",      filename)
    sys_write("__FILE_UUID__", uuid())
    sys_write("__LINE__",      0)

    # Read the file and process each line
    run_hook("file_open")

    stk_replace_top(__ns_stack, default_ns)
    dbg__print("parse", 5, "(parse__file) CALLING parse()")
    pstat = parse()
    dbg__print("parse", 5, "(parse__file) RETURNED FROM parse() => " ppf__bool(pstat))
    stk_replace_top(__ns_stack, blktab[file_block, 0, "old.ns"])

    # Reached end of file
    flush_stdout(SYNC_FILE)
    run_hook("file_close")

    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != STDIN)
        close(filename)
    blktab[file_block, 0, "open"] = FALSE
    delete __active_files[filename]

    if (stk_pop(__source_stack) != file_block)
        panic("(parse__file) File block mismatch")
    __buffer = blktab[file_block, 0, "old.buffer"]
    sys_incr( "__DEPTH__",     -1);
    sys_write("__FILE__",      blktab[file_block, 0, "old.file"])
    sys_write("__FILE_UUID__", blktab[file_block, 0, "old.file_uuid"])
    sys_write("__LINE__",      blktab[file_block, 0, "old.line"])
    blk_master_delete(file_block)

    if (sys_read("__DEPTH__", NOKEY) > 0)
        run_hook("file_resume")

    dbg__print("parse", 2, sprintf("(parse__file) END '%s' => %s",
                                 filename, ppf__bool(pstat)))
    return pstat
}


# PARSE
function parse(    code, terminator, rstat, cmd, retval, new_block, fc,
                   info, level, parser, parser_type, parser_label, i, scnt, found, s,
                   new_cmd_name, call_details, src_block, l2, _, ns, uname, nparts,
                   orig, info2, type2, code2, level2, new_type, name, qname, new_level, new_scan_name)
{
    dbg__print("parse", 3, "(parse) START dstblk=" curr_dstblk() ", mode=" ppf__label(curr_atmode()))

    # The "parser" is the topmost element of the __parse_stack
    # which we wish to access a few times
    if (stk_empty_p(__parse_stack))
        panic("Parse error; Empty parse stack")
    parser = stk_top(__parse_stack)
    parser_type = blk_type(parser)
    parser_label = ppf__label(parser_type)

    if (stk_empty_p(__source_stack))
        panic("Parse error; Empty source stack")
    src_block = stk_top(__source_stack)

    # terminator is a regular expression, and we call
    # match($1, terminator) to see if terminator is seen.
    terminator = blktab[parser, 0, "terminator"]
    retval = FALSE

    while (TRUE) {
        dbg__print("parse", 4, sprintf("(parse) [%s] TOP OF LOOP: ________ %s  LINE %d ________",
                                     parser_label, FILE(), LINE()+1)) # LINE will be +1 after upcoming readline()

        rstat = readline()   # OKAY, EOF, ERROR
        dbg__print("parse", 4, "(parse) [" parser_label "] readline() returned " rstat)
        if (rstat == ERROR) {
            # Whatever just happened, the parse didn't finish properly
            dbg__print("parse", 5, "(parse) [" parser_label "] readline()=>ERROR")
            trace(TRACE_READLINE, EMPTY, "[Readline] ERROR")
            break          # out of entire parsing loop, to then return
        }
        if (rstat == EOF) {
            # End of file BLK_FILE is fine, just return a TRUE to say so.
            # EOF on any other block type means the parse didn't find
            # a terminator, so return FALSE.
            dbg__print("parse", 5, sprintf("(parse) [%s] readline() detected EOF on '%s' FILENAME '%s'",
                                           parser_label, blktab[src_block, 0, "filename"], FILENAME))
            if ((src_block, 0, "oob_terminator") in blktab &&
                blktab[src_block, 0, "oob_terminator"] == "EOF")
                retval = TRUE
            trace(TRACE_READLINE, EMPTY, "[Readline] EOF")
            break          # out of entire parsing loop, to then return
        }
        dbg__print("parse", 5, "(parse) [" parser_label "] readline() okay; $0='" $0 "'")
        trace(TRACE_READLINE, EMPTY, "[Readline] OK Line " LINE() "='" $0 "'")
        orig = $0

        # Maybe short-circuit and ship line out now
        if (curr_atmode() == MODE_AT_LITERAL ||
            index($0, TOK_AT) == NOT_FOUND ||
            first($0) != TOK_AT) {
            s = $0
            if (!emptyp($0)) {
                dbg__print("parse", 3, sprintf("(parse) [%s, short circuit] CALLING qualify('%s')",
                                               parser_label, $0))
                # Don't worry about qualify modifying lines in LITERAL mode - it won't
                s = qualify($0)
                dbg__print("qual", 3, sprintf("(parse) [%s, short circuit] qualify('%s')=>'%s'",
                                              parser_label, $0, s))
            }
            dbg__print("parse", 3, sprintf("(parse) [%s, short circuit] CALLING ship_out(TEXT, '%s')",
                                         parser_label, s))
            ship_out(OBJ_TEXT, s)
            dbg__print("parse", 3, "(parse) [" parser_label ", short circuit] RETURNED FROM ship_out()")
            continue           # text shipped out, continue to next line
        }

        # Quickly skip comments
        if ($1 == "@@" || $1 == "@c" || $1 == "@comment")
            continue
        # @; and @# need not be followed immediately by whitespace,
        # but @@, @c, and @comment must have whitespace.
        l2 = substr($1, 1, 2)
        if (l2 == "@;" || l2 == "@#")
            continue

        # See if it's a command of some kind.
        #print("$0='" $0 "'")
        if (match($1, "^@[A-Za-z#_]")) {        # skip "@{"
            # Looks like it might be a command.
            # Winnow out the primary name.  Be sure to handle
            # "@myfn{aaa}{ccc ddd}".  (Naive old code name=$1 resulted
            # in $1 being "@myfn{aaa}{ccc" which wrecks havoc.)
            # However, we need to keep $1 intact in order for upcoming
            # match($1,terminator) checks to work.  This takes advantage
            # of the fact that all commands must have strict names.
            # NB - strict names normally don't include : but I do here
            # so I can read ns
            for (i = 2; substr($0, i, 1) ~ /[A-Za-z#_0-9:]/; i++)
                ;
            uname = substr($0, 2, i-2)
            dbg__print("parse", 7, "(parse) [" parser_label "] uname='" uname "'")

            if ((nparts = nam__scan(uname, info)) != 1)
                panic("(parse) Scan error: " uname)
            cmd = info__get(info, "name")
            ns  = info__get(info, "ns") # May be empty!

            # See if it's a built-in command
            if (nam_ll_in_ns(M2_SYSNS, cmd, ROOT_LEVEL) &&
                flag_1true_p((code = nam_ll_read_ns(M2_SYSNS, cmd, ROOT_LEVEL)),
                             TYPE_COMMAND)) {
                if (ns == EMPTY) {
                    ns = info["ns"] = M2_SYSNS
                    sub(/^@/, TOK_AT M2_SYSNS TOK_NS_QUAL)
                    trace(TRACE_QUALIFICATION, EMPTY,
                          sprintf("[Qualify] '%s' => '%s'", orig, $0))
                } else if (ns != M2_SYSNS)
                    error(sprintf("%s: Parse error; Command name conflicts with built-in",
                                          "@" cmd))

                # See if it's immediate
                if (flag_1true_p(code, FLAG_IMMEDIATE)) {
                    # This command is immediate, so we must run it right now.
                    # Some are known to create and return new blocks,
                    # which must be shipped out.

                    if (cmd == "break" || cmd == "continue") {
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
                            error(sprintf("%s: Parse error; FOR or WHILE loop not found %s",
                                          "@" cmd, parser_label))
                        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else if (cmd == "case") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__case(dstblk=" curr_dstblk() ")"))
                        new_block = parse__case()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__case() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (cmd == "else") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__else(dstblk=" curr_dstblk() ")"))
                        _ = parse__else()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__else() : dstblk => " curr_dstblk()))

                    } else if (cmd == "endcase" || cmd == "esac") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endcase(dstblk=" curr_dstblk() ")"))
                        _ = parse__endcase()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endcase() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endcase matched terminator => TRUE")
                            return TRUE
                        }
                        error(sprintf("%s: Parse error; Missing terminator; expected '%s' but found '@endcase'",
                                      "@" cmd, terminator))

                    } else if (cmd == "endcmd") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endcmd(dstblk=" curr_dstblk() ")"))
                        new_block = parse__endcmd()
                        dbg__print_block("parse", 7, new_block, sprintf("newcmd block returned from parse__endcmd"))
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endcmd() : dstblk => " curr_dstblk()))

                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endcmd matched terminator => TRUE")
                            if (dbg__sys_level_p("parse", 7)) {
                                print_debugfile("m2debug:(parse) [" parser_label "] new_block=" new_block)
                                ppf__block(new_block)
                            }

                            # Create an entry for the new command name.
                            # We do this at Parse time so that future
                            # invocations of new command @FOO will
                            # immediately be recognized as an available
                            # user command.  All we need to do is create
                            # a namtab entry with correct TYPE_USER.
                            # NOTE - we don't have an entry in symtab[]
                            # yet.  That's okay because the command is
                            # only being declared, not defined, and it's
                            # not ready to run yet.  (That next bit
                            # happens in xeq__BLK_USER.)
                            #
                            # OLDTHINK: There should be a gate here.  It should
                            # not be possible to shadow an existing name, unless
                            # you are re-defining a command.
                            #
                            # NEW HOTNESS: parse__newcmd() already passed
                            #   info__gate(OP_CREATE, TYPE_COMMAND, ..., TRUE)
                            # so presumably the name is safe to declare.
                            new_cmd_name = blktab[new_block, 0, "name"]
                            ns = blktab[new_block, 0, "ns"]
                            dbg__print("parse", 3, sprintf("(parse) [" parser_label "] Declaring new user command '%s::%s' at level %d",
                                                           ns, new_cmd_name, curr_level()))
                            nam_ll_write_ns(ns, new_cmd_name, curr_level(), TYPE_USER)
                            return TRUE
                        }
                        error(sprintf("%s: Parse error; Missing terminator; expected '%s' but found '@endcmd'",
                                      "@" cmd, terminator))

                    } else if (cmd == "endif" || cmd == "fi") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endif(dstblk=" curr_dstblk() ")"))
                        _ = parse__endif()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endif() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endif matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endif but expecting '" terminator "'")

                    } else if (cmd == "endlong" || cmd == "endlongdef") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endlongdef(dstblk=" curr_dstblk() ")"))
                        _ = parse__endlongdef()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endlongdef() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endlongdef matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endlongdef but expecting '" terminator "'")

                    } else if (cmd == "endwhile" || cmd == "wend") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endwhile(dstblk=" curr_dstblk() ")"))
                        _ = parse__endwhile()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endwhile() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endwhile matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endwhile but expecting '" terminator "'")

                    } else if (cmd == "for" || cmd == "foreach") {
                        dbg__print("parse", 5, sprintf("(parse) [%s] curr_dstblk()=%d CALLING parse__for()",
                                                     parser_label, curr_dstblk()))
                        new_block = parse__for()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__for() : new_block is " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (cmd == "if" || cmd == "unless") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__if(dstblk=" curr_dstblk() ")"))
                        new_block = parse__if()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__if() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (cmd == "longdef") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__longdef(dstblk=" curr_dstblk() ")"))
                        new_block = parse__longdef()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__longdef() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (cmd == "sm2ctl") { # Undocumented: @sm2ctl is an immediate version of @m2ctl
                        #print_stderr("(parse) [@sm2ctl] I see '" $0 "'")
                        if ($1 == "dump_parse_stack") {
                            dump_parse_stack()

                        } else
                            error("@sm2ctl: Unrecognized parameter: " $1)

                    } else if (cmd == "newcmd") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__newcmd(dstblk=" curr_dstblk() ")"))
                        new_block = parse__newcmd()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__newcmd() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (cmd == "next") {
                        dbg__print("parse", 5, sprintf("(parse) [%s] dstblk=%d; CALLING parse__next()",
                                                     parser_label, curr_dstblk()))
                        _ = parse__next()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__next() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END Matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @next but expecting '" terminator "'")

                    } else if (cmd == "of") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__of(dstblk=" curr_dstblk() ")"))
                        _ = parse__of()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__of() : dstblk => " curr_dstblk()))

                    } else if (cmd == "otherwise") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__otherwise(dstblk=" curr_dstblk() ")"))
                        _ = parse__otherwise()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__otherwise() : dstblk => " curr_dstblk()))

                    } else if (cmd == "return") {
                        found = FALSE
                        for (i = stk_depth(__parse_stack); i > 0; i--) {
                            dbg__print("parse", 2, sprintf("i=%d, __parse_stack[i])=%d", i, __parse_stack[i]))
                            dbg__print_block("parse", 2, __parse_stack[i], "Parsing @return:")
                            scnt = blk_type(__parse_stack[i])
                            if (scnt == BLK_USER) {
                                found = TRUE
                                break
                            }
                        }
                        if (! found)
                            error("@return: Not executing a user command")
                        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else if (cmd == "while" || cmd == "until") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__while(dstblk=" curr_dstblk() ")"))
                        new_block = parse__while()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__while() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (cmd == "array" || cmd == "define" || cmd == "list" ||
                               cmd == "local" || cmd == "set") {
                        # print_stderr(sprintf("before, $0='%s'; $2='%s'", $0, $2))
                        if (index($2, TOK_NS_QUAL) > 0)
                            new_scan_name = $2
                        else
                            new_scan_name = (double_underscores_p($2) ? M2_SYSNS : curr_ns()) TOK_NS_QUAL $2
                        qname = nam__qualify(new_scan_name)
                        #print_stderr(sprintf("qname='%s'", qname))

                        level2 = info__create_from_text(qname, info2)
                        #print_stderr(sprintf("parse: qname='%s', code=%s", qname, info__get(info2, "code")))
                        if (level2 == ERR_SCAN_INVALID_NAME)
                            error($0 ": Invalid name '" qname "'")
                        if (info__get(info2, "protected"))
                            error(sprintf("@%s: Name '%s' is protected%s", cmd, qname, VERBOSE() ? " [parse:K]" : ""))

                        if (cmd == "define" || cmd == "set") {
                            # Define will auto-vivify Symbols, but not Arrays or Lists.
                            # print_stderr(sprintf("Found @define: ns='%s', cmd='%s', code='%s'\n   $0='%s'",
                            #                      info__get(info2, "ns"), info__get(info2, "name"), ppf__flags(info__get(info2, "code")), $0))
                            if (! nam__valid_p($2, PTYPE_SCALAR, TRUE))
                                error(sprintf("@%s: Name '%s' is not valid%s", cmd, $2, VERBOSE() ? " [parse:A]" : ""))

                            code2 = info__get(info2, "code")
                            # print_stderr("(parse) from qname '" qname "', code2=" ppf__label(code2))
                            type2 = first(code2)
                            if (type2 == PTYPE_UNDEF)
                                if (info__get(info2, "has_bracket")) # undeclared Array or List
                                    error(sprintf("@%s: Name '%s' has not been declared", cmd, info__get(info2, "name")))
                                else
                                    new_type = TYPE_SYMBOL
                            else if (type2 == TYPE_SYMBOL)
                                if (info__get(info2, "has_bracket")) # undeclared Array or List
                                    error(sprintf("@%s: Cannot use brackets on %s '%s'",
                                                  cmd, ppf__label(code2), $2))
                                else
                                    new_type = code2
                            else if (type2 == TYPE_ARRAY || type2 == TYPE_LIST)
                                if (! info__get(info2, "has_bracket")) # missing required bracket
                                    error(sprintf("@%s: Must use brackets on %s '%s'",
                                                  cmd, ppf__label(code2), $2))
                                else
                                    new_type = code2
                            else
                                panic(sprintf("(parse) Cannot handle '%s' of type %s",
                                              $2, ppf__label(code2)))

                            new_level = nam_system_p(info__get(info2, "name")) ? ROOT_LEVEL : curr_level()
                            if (! nam_ll_in_ns(info__get(info2, "ns"),
                                               info__get(info2, "name"),
                                               new_level)) {
                                if (dbg__sys_level_p("nam", 5) ||
                                    dbg__sys_level_p("parse", 3))
                                    print_debugfile(sprintf("m2debug:(parse) [%s] Declaring '%s'::'%s' (lev=%d) as type %s",
                                                            parser_label,
                                                            info__get(info2, "ns"), info__get(info2, "name"),
                                                            new_level, ppf__label(new_type)))

                                nam_ll_write_ns(info__get(info2, "ns"), info__get(info2, "name"),
                                                new_level, new_type)
                            }
                        } else {
                            if (index($2, TOK_NS_QUAL) > 0)
                                error(sprintf("%s: Parameter '%s' must not be qualified%s", $0, $2, VERBOSE() ? " [parse:K]" : ""))

                            # array, list, or local - These commands all
                            # define local variables and cannot be qualified.
                            if (! nam__valid_p($2, PTYPE_PARAM, TRUE))
                                error(sprintf("@%s: Name '%s' is not valid%s", cmd, $2, VERBOSE() ? " - [parse:B]" : ""))

                            if (level2 == ROOT_LEVEL && curr_level() != level2 &&
                                flag_1true_p(info__get(info2, "code"), FLAG_SYSTEM))
                                error($0 ": Cannot shadow '" $2 "'")

                            # All these declare new names in namtab.
                            # Regardless of type, names must be unique
                            # at this (current) level, but it's okay if
                            # same name is declared at a lower level.
                            # if (curr_level() >= ROOT_LEVEL && curr_level() != level2)
                            #     error($0 ": '" $2 "' already defined")

                            if      (cmd == "array") new_type = TYPE_ARRAY
                            else if (cmd == "list")  new_type = TYPE_LIST
                            else if (cmd == "local") new_type = TYPE_SYMBOL

                            if (dbg__sys_level_p("nam", 5) ||
                                dbg__sys_level_p("parse", 3))
                                print_debugfile(sprintf("m2debug:(parse) [%s] Declaring '%s'::'%s' (lev=%d) as type %s",
                                                        parser_label,
                                                        info__get(info2, "ns"), info__get(info2, "name"),
                                                        curr_level(), ppf__label(new_type)))
                            nam_ll_write_ns(info__get(info2, "ns"), info__get(info2, "name"),
                                            curr_level(), new_type)
                        }
                        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else
                        panic("(parse) [" parser_label "] Found immediate command " cmd " but no handler")

                } else {
                    # It's a non-immediate built-in command -- ship it
                    # out as a command to be executed later.
                    dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(CMD, '%s')", parser_label, $0))
                    ship_out(OBJ_CMD, $0)
                    dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
                }
                continue
            } else {
                # Look up user command
                #if (nam__scan(rest(cmd), info) != ERROR) {
                    level = nam__lookup(info)
                    #print_stderr("level = " level)
                    if (level != NAME_NOT_FOUND) {
                        # A value of NAME_NOT_FOUND would mean a valid name wasn't
                        # found, in which case name is definitely not a user
                        # command, so we do nothing for the moment in that
                        # case and let normal text ship out.  But since it's
                        # *not* NAME_NOT_FOUND, something *was* found at "level".  See
                        # if it's a user command and ship it out if so.
                        ns = info__get(info, "ns")
                        name = info__get(info, "name")
                        dbg__print("parse", 7, sprintf("(parse) Looking for user, using ns='%s', name='%s'",
                                                       ns, name))
                        code = nam_ll_read_ns(ns, name, level)
                        if (flag_1true_p(code, TYPE_USER)) {
                            call_details = scan__usercmd_call($0, info)
                            dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(USER, '%s')", parser_label, call_details))
                            ship_out(OBJ_USER, call_details)
                            dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
                            continue
                        }
                    }
                #}
            }
            # It's okay to reach here with no actions taken.  In this
            # case, just process the line as normal text.
        }
        # doesn't look like a command - ship it out as text
        s = $0
        if (!emptyp($0)) {
            dbg__print("parse", 3, sprintf("(parse) [%s] CALLING qualify('%s')",
                                           parser_label, $0))
            s = qualify($0)
            dbg__print("qual", 3, sprintf("(parse) [%s] qualify('%s')=>'%s'",
                                          parser_label, $0, s))
        }
        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(TEXT, '%s')",
                                       parser_label, s))
        ship_out(OBJ_TEXT, s)
        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
    } # continue loop again, reading next line
    dbg__print("parse", 5, "(parse) END => " ppf__bool(retval))
    return retval
}


# Returns an encoded version of the user command call:
#     <narg> SUBSEP <ns> SUBSEP <name> SUBSEP [ { <argN> SUBSEP } ... ]
# Note: narg always >= 3, and equal to # of SUBSEPs expected
# When the call details are eventually decoded in execute__user(), the
# OBJ_USER value is passed to split_subsep() to access individual items.
function scan__usercmd_call(s, info,
                            uname, obj, i, oldi, c, nc, narg, nlbr,
                            readstat, arg, inarg, thisi, retval, j,
                            brpos, cb)
{
    dbg__print("parse", 5, "(scan__usercmd_call) s='" s "'")
    if (emptyp(s))
        panic("(scan__usercmd_call) s must not be empty")
    if (first(s) != TOK_AT)
        error(sprintf("(scan__usercmd_call) Doesn't start with @: s='%s'", s))
    if (info__get(info, "nparts") != 1)
        panic("(scan__usercmd_call) Scan error: " s)
    if (info__get(info, "ns") == EMPTY)
        panic("(scan__usercmd_call) Empty ns!" s)

    if ((brpos = index(s, TOK_LBRACE)) == NOT_FOUND) {
        #uname = substr(s, 2)
        dbg__print("parse", 3, sprintf("(scan__usercmd_call) RETURNING ns='%s', name='%s'",
                                       info__get(info, "ns"), info__get(info, "name")))
        # if (info__get(info, "ns") == EMPTY)
        #     info["ns"] = curr_ns()
        return 3 SUBSEP info__get(info, "ns") SUBSEP info__get(info, "name") SUBSEP
    }

    # Read cmd name between @ and {
    # uname = substr(s, 2, brpos - 2)
    # dbg__print("parse", 3, sprintf("(scan__usercmd_call) uname='%s'", uname))

    # Remove everything that came before.  We are now left with (hopefully)
    # a series of brace-enclosed arguments.
    narg = 0
    s = substr(s, brpos)        # s == "{..."
    while (substr(s, 1, 1) == TOK_LBRACE) {
        cb = find_closing_brace(s, 1, TOK_LBRACE)
        if (cb == ERROR || cb == EOF)
            error("(scan__usercmd_call) Could not find closing brace: " s)
        else {
            # Found a }
            dbg__print("parse", 5, ("(scan__usercmd_call) in loop, cb=" cb))
            inarg = substr(s, 2, cb - 2)
            gsub(/\\}/, TOK_RBRACE, inarg) # Fix quoted brace
            arg[++narg] = inarg
            s = substr(s, cb + 1)
        }
    }
    dbg__print("parse", 2, sprintf("(scan__usercmd_call) END 3: narg=%d, s='%s'", narg, s))
    # if (info__get(info, "ns") == EMPTY)
    #     info["ns"] = curr_ns()
    dbg__print("parse", 3, sprintf("(scan__usercmd_call) RETURNING ns='%s', name='%s' with %d args",
                                   info__get(info, "ns"), info__get(info, "name"), narg))
    retval = narg+3 SUBSEP info__get(info, "ns") SUBSEP info__get(info, "name") SUBSEP
    for (j = 1; j <= narg; j++)
        retval = retval arg[j] SUBSEP
    return retval
}


function ppf__BLK_FILE(blknum)
{
    return sprintf("  filename: %s (%s)\n" \
                   "  atmode  : %s",
                   blktab[blknum, 0, "filename"],
                   blktab[blknum, 0, "open"] ? "OPEN" : "CLOSED",
                   ppf__label(blktab[blknum, 0, "atmode"]))
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
#           TYPE_ARRAY          A : Awk array refs, must use subscripts
#           TYPE_COMMAND        C : Built-in "@" command; root level
#           TYPE_FUNCTION       F : Root level
#           TYPE_INTERNAL       _ : Awk function tracing, not reachable by user
#           TYPE_LIST           L : Agg block lists; integer keys
#           TYPE_SEQUENCE       Q : Root level
#           TYPE_SYMBOL         S
#           TYPE_USER           U : User-defined command; current level
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
    if (single_f == PTYPE_ANY) return FALSE
    return index(code, single_f) == NOT_FOUND
}


# TRUE if the one lone flag single_f is present in code,
# else FALSE indicating its absence.
function flag_1true_p(code, single_f)
{
    if (single_f == PTYPE_ANY) return TRUE
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


# function flag_allfalse_p(code, multi_fs)
# {
#     return !flag_anytrue_p(code, multi_fs)
# }


function flag_anyfalse_p(code, multi_fs)
{
    return !flag_alltrue_p(code, multi_fs)
}


function valid_type_p(char)
{
    return index(VALID_TYPES, char) > 0
}


# Return a new code string (NB - old one is NOT updated in place!)
# with corresponding flags either set or cleared.
function flag_set_clear(code, set_fs, clear_fs,
                        flag, idx, type, x)
{
    type = EMPTY
    if (valid_type_p(first(code))) {
        type = first(code)
        code = rest(code)
    }
    # First, clear flags listed in clear_fs
    for (x = 1; x <= length(clear_fs); x++) {
        if ((flag = substr(clear_fs, x, 1)) == FLAG_READONLY)
            continue            # can't clear read-only  :-(
        if (flag_1true_p(code, flag)) {
            idx = index(code, flag)
            code = substr(code, 1, idx-1) \
                   substr(code, idx+1)
        }
    }

    # Now set the ones in set_fs
    for (x = 1; x <= length(set_fs); x++) {
        flag = substr(set_fs, x, 1)
        if (flag_1false_p(code, flag)) {
            code = code flag
        }
    }

    return (type != EMPTY) ? type code : code
}


function ppf__flags(code,
                    l, s, desc, x, type)
{
    s = desc = EMPTY
    if ((l = length(code)) == 0)
        error("(ppf__flags) Did not specify code")
    if (valid_type_p(type = first(code))) {
        s = ppf__label(type)
        code = rest(code); l--
    }
    if (l > 0) {
        for (x = 1; x <= l; x++)
            desc = desc ppf__label(substr(code, x, 1)) ","
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
#       Info[] is an array with following entries created in nam__scan():
#             errorp      : TRUE if an error condition was encountered
#             errtext     : Text relating to any error condition.
#                           Errtext NEVER includes ``caller'' information:
#                           that bit is added on when m2 errors & exits.
#             has_bracket : TRUE if text matches CHARS[CHARS..]
#                           It is normal for plain "NAME" to be FALSE here.
#             has_qual    : TRUE if text has ns qualification glyph ::
#             key         : Key, part[2] of NAME[KEY]; may be empty.
#             key_valid   : TRUE if KEY is valid according to non-strict.
#                           This restricts it to most printable characters.
#             name        : Name, part[1] of NAME[KEY].
#             name_valid  : TRUE if NAME is valid
#             nparts      : 1 or 2 depending if text is NAME or NAME[KEY]
#             ns          : Namespace.  May be empty.  See also "has_qual".
#             urtext      : Original text string
#             valid       : TRUE if both name_valid && key_valid are TRUE
#
#       After a successful nam__lookup(), the following entries are added:
#       (assuming TYPE_SYMBOL).
#             code        : String holding the type and any flags (from namtab)
#             idxable     : TRUE if type == TYPE_ARRAY or TYPE_LIST.
#                           Means this incantation can support NAME[KEY].
#                           Useful for PTYPE_IDXABLE and FLAG_KEY_YES.
#             level       : Level number where this object was found.
#                           0 => ROOT_LEVEL; NAME_NOT_FOUND => symbol not found
#             type        : Char encoding obj type, also in code; one of TYPE_*
#       If the entry is a TYPE_LIST:
#             agg_block   : Block # of agg block
#*****************************************************************************
function nam__valid_p(text, type, allow_double_underscores)
{
    if (emptyp(text))
        panic("(nam__valid_p) Empty text!  type=" ppf__label(type))
    if (!allow_double_underscores &&
        double_underscores_p(text))
        return FALSE
    if (type == TYPE_COMMAND || type == TYPE_FUNCTION || type == TYPE_INTERNAL)
        return text ~ /^[a-z][a-z]*$/
    else if (type == PTYPE_ENV_VAR || type == PTYPE_NS || type == PTYPE_PARAM)
        return text ~ /^[A-Za-z_][A-Za-z_0-9]*$/
    else if (type == TYPE_SYMBOL || type == TYPE_SEQUENCE || type == TYPE_USER ||
             type == TYPE_ARRAY  || type == TYPE_LIST)
        # Any of these types might be a fully qualified spec, so accept ":".
        # cf PTYPE_NAME, which is merely the symbols name only
        return text ~ /^[A-Za-z#_:][A-Za-z#_0-9:]*$/
    else if (type == PTYPE_NAME)
        return text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
    else if (type == PTYPE_KEY)
        # For keys, any printable character
        return text ~ /^[ !-~]+$/
    else if (type == PTYPE_SCALAR)
        return text ~ /^[A-Za-z#_:][A-Za-z#_0-9:]*(\[[ !-~]+\])?$/
    else
        panic("(nam__valid_p) Cannot handle type " ppf__label(type) "; text='" text "'")
}


#*****************************************************************************
#
# This code scans random string "text" into either NAME or NAME[KEY].
# Rudimentary error checking is done.
#
# Unfortunately, nam__scan() can be given *arbitrary* text, not just
# something that "ought to, hopefully" turn out to be a reasonably
# well-formed symbol reference.  For example, during parsing, a perfectly
# valid text might be
#           Byname[@{fields[1]}]
# but since it hasn't been @{expanded} yet, there are too many brackets
# which is not legal.  So now we just look to see if there are single
# brackets, and forget about splitting or counting.
#
# Return value:
#    ERROR
#       Text does not pass simple scan test.  Even so, it still
#       may be invalid depending strict, etc).
#    1 or 2
#       Text scanned.  1 is returned if it's a simple NAME,
#       2 indicates a NAME[KEY] format.
#
#*****************************************************************************
function nam__scan(text, info,
                   name, key, nparts, part, count, i,
                   qual, ns, lbrk)
{
    # dbg__print("nam", 5, sprintf("(nam__scan) START text='%s'", text))
    info["urtext"] = text
    name = key = info["name"] = info["key"] = EMPTY
    info["ns"] = info["errtext"] = EMPTY
    # NB - `text' may be syntactically correct, but info["valid"] remains
    # FALSE until an item is found in namtab[] in info__lookup_found_p().
    # At this point, info["valid"] takes on the value of info["lexvalid"].
    # To see if `text' is syntactically correct, check info["lexvalid"] but
    # be aware you may be referring to a non-existent symbol.
    info["valid"] = info["errorp"] = FALSE
    info["_key_valid"] = info["_lexvalid"] = info["declared"] = \
       info["defined"] = info["_protected"] = VOID
    info["has_qual"] = info["has_bracket"] = FALSE

    # Simple test for
    #           [ NS `::' ]  NAME  [ `[' KEY `]' ]
    # Anchored at front and back.
    # NS   ::= text ~ /^[A-Za-z_][A-Za-z_0-9]*$/
    # NAME ::= text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
    # KEY  ::= text ~ /^[ !-~]+$/       # For keys, any printable character
    if (text !~ /^([A-Za-z_][A-Za-z_0-9]*::)?[A-Za-z#_][A-Za-z#_0-9]*(\[[ !-~]+\])?$/) {
    #             <NS (opt)-----------------><NAME------------------><KEY (opt)--->
        dbg__print("nam", 2, sprintf("(nam__scan) '%s' => %d", text, ERROR))
        info["_lexvalid"] = FALSE
        info["errorp"] = TRUE
        info["errtext"] = __m2_msg = "Invalid name '" text "'"
        return ERROR            # interpret as ERR_SCAN_INVALID_NAME
    }

    # We can take advantage of the fact that text has passed the regexp
    # above, so if the last character is a right bracket then it must be
    # a key.
    lbrk = index(text, TOK_LBRACKET)
    if (lbrk > 0 && last(text) == TOK_RBRACKET) {
        info["has_bracket"] = TRUE
        info["nparts"] = nparts = 2

        key = substr(text, lbrk+1, length(text)-lbrk-1)
        if (key == EMPTY)
            panic("(nam__scan) Key must not be empty")
        #print_stderr("(nam__scan) new scan: key='" key "'")
        info["key"] = key

        # We can't check for validity yet because what we are looking at
        # might still need to be @{expanded}.
        # Get rid of key stuff
        text = substr(text, 1, lbrk - 1)
    } else                      # no [...] found
        info["nparts"] = nparts = 1

    # Check for namespace
    qual = index(text, TOK_NS_QUAL)
    if (qual > 0) {
        info["has_qual"] = TRUE
        ns = substr(text, 1, qual - 1)
        if (emptyp(ns) ||
            !nam__valid_p(ns, PTYPE_NS, TRUE) ||
            ns == "awk") {
            info["_lexvalid"] = FALSE
            info["errorp"] = TRUE
            info["errtext"] = __m2_msg = "Invalid namespace '" ns "'"
            return ERROR            # interpret as ERR_SCAN_INVALID_NAME
        }
        info["ns"] = ns
        text = substr(text, qual + 2)
    }
    name = text
    if (name == EMPTY) {
        info["_lexvalid"] = FALSE
        info["errorp"] = TRUE
        info["errtext"] = __m2_msg = "Name cannot be empty!"
        return ERROR            # interpret as ERR_SCAN_INVALID_NAME
    }
    if (index(name, TOK_NS_QUAL) > 0) {
        info["_lexvalid"] = FALSE
        info["errorp"] = TRUE
        info["errtext"] = __m2_msg = "Invalid qualification '" name "'"
        return ERROR            # interpret as ERR_SCAN_INVALID_NAME
    }
    info["name"] = name
    info["name_valid"] = nam__valid_p(name, PTYPE_NAME, TRUE)

    dbg__print("nam", 4, sprintf("(nam__scan) '%s' => %d", info["urtext"], nparts))
    return nparts
}


#*****************************************************************************
# This will examine namtab from curr_level() downto 0, seeing if name
# exists at that level.  If so, it populates info[] with the code string
# for the item from namtab, and also sets other values.  The return
# value is the level number (0..N).
#
# If no matching name is found, return NAME_NOT_FOUND.  It also sets
# info["errorp"] to True and reports that the name was not found.
# The caller may or may not consider this a real error, depending on
# whether he expected the name to be found or not.
# *****************************************************************************
function nam__lookup(info,
                     name, level, code, type, found, i, ns)
{
    info["code"] = PTYPE_UNDEF
    info["level"] = level = NAME_NOT_FOUND
    found = FALSE
    name = info["name"]

    if (info__get(info, "errorp") || info__get(info, "lexvalid") != TRUE) {
        info["errorp"] = TRUE
        info["errtext"] = __m2_msg =            \
            sprintf("%s%s%s",
                    info["name_valid"] ? "" : "Name '" name "' not valid",
                    info["name_valid"] == FALSE && info__get(info, "key_valid") == FALSE ? "; " : "",
                    info__get(info, "key_valid") ? "" : "Key '" info__get(info, "key") "' not valid")
        return ERR_SCAN_INVALID_NAME
    }
    dbg__print("sym", 5, sprintf("(nam__lookup) name='%s' START", name))

    ns = info__get(info, "ns")
    if (ns == M2_ENVNS) {
        if (info__get(info, "key") != EMPTY ||
            ! nam__valid_p(name, PTYPE_ENV_VAR, FALSE)) {
            info["errorp"] = TRUE
            info["errtext"] = __m2_msg = \
                sprintf("Name '%s' not valid as %s", name, ppf__label(PTYPE_ENV_VAR))
            return ERR_SCAN_INVALID_NAME
        }
        found = sym_ll_in_ns(ns, name, NOKEY, ROOT_LEVEL)
        if (! found) {
            # Set the text when the name isn't found, but not the error flag itself.
            info["errtext"] = sprintf("%s '%s' not found",
                                      ppf__label(info__get(info, "type")), name)
            return NAME_NOT_FOUND
        }
        info["declared"] = info["defined"] = TRUE
        info["code"] = PTYPE_ENV_VAR
        info["idxable"] = FALSE
        info["level"] = ROOT_LEVEL
        info["valid"] = TRUE
        return ROOT_LEVEL
    }

    if (emptyp(ns) && double_underscores_p(name)) {
        #print_stderr("(nam__lookup) ns=" ns ", name='" name "'")
        info["ns"] = ns = M2_SYSNS
    }
    # In code below, if the name is actually found in the namespace:
    # 1. found == TRUE
    # 2. level is correct
    # 3. info__lookup_found_p() has the side effect, if found, of setting
    #    info[]: code, idxable, level, agg_block (List)

    # Name resolution / cases:
    # - User specified a namespace ("ns::foo"):
    #   Lookup succeeds if namespace actually contains foo at some
    #   level.  Search this namespace from current level to ROOT_LEVEL.
    if (! emptyp(ns)) {
        for (level = curr_level(); level >= ROOT_LEVEL; level--)
            if ((found = info__lookup_found_p(info, ns, name, level)))
                break
    } else {
        # - Plain name ("foo"):
        #   Look through each __ns_stack element from current level down to ROOT_LEVEL.
        for (i = stk_depth(__ns_stack); i > 0; i--) {
            ns = __ns_stack[i]
            dbg__print("nam", 7, sprintf("(nam__lookup) Checking ns '%s' from %d to 0",
                                         ns, curr_level()))
            for (level = curr_level(); level >= ROOT_LEVEL; level--) {
                if ((found = info__lookup_found_p(info, ns, name, level))) {
                    info["ns"] = ns
                    break
                }
            }
            if (found) break
        }
    }
    if (! found) {
        dbg__print("nam", 2, sprintf("(nam__lookup) END Could not find name '%s' on any level in namtab => NAME_NOT_FOUND", name))
        # Set the text when the name isn't found, but not the error flag itself.
        info["errtext"] = "Name not found: '" name "'"
        return NAME_NOT_FOUND
    }

    if (info["has_bracket"] && !info["idxable"]) {
        info["errorp"] = TRUE
        info["errtext"] = sprintf("Cannot use brackets with %s '%s'",
                                  ppf__label(info__get(info, "type")), name)
        return ERR_SCAN_INVALID_NAME
    }
    return level
}


function info__lookup_found_p(info, ns, name, level,
                              code, type)
{
    # print_stderr(sprintf("(info__lookup_found_p) ns=%s, name='%s', level=%d", ns, name, level))
    if (! nam_ll_in_ns(ns, name, level))
        return FALSE

    # name IS in namtab here, so read it
    info["declared"] = TRUE
    info["code"] = code = nam_ll_read_ns(ns, name, level)
    type = first(code)
    info["idxable"] = (type == TYPE_ARRAY || type == TYPE_LIST)
    info["level"] = level
    info["valid"] = info__get(info, "lexvalid")

    if (type == TYPE_ARRAY) {
        info["defined"] = (info["valid"] &&
                           ((ns, name, info__get(info, "key"), level, "symval") in symtab))

    } else if (type == TYPE_COMMAND  ||
               type == TYPE_FUNCTION ||
               type == TYPE_INTERNAL) {
        info["defined"] = (info["valid"] &&
                           ((M2_SYSNS, name, ROOT_LEVEL) in namtab))

    } else if (type == TYPE_LIST) {
        info["defined"] = (info["valid"] &&
                           ((ns, name, NOKEY, level, "agg_block") in symtab))
        if (info["defined"])
            info["agg_block"] = symtab[ns, name, NOKEY, level, "agg_block"]

    } else if (type == TYPE_SEQUENCE) {
        info["defined"] = (info["valid"] &&
                           ((ns, name, NOKEY, ROOT_LEVEL, "seqval") in symtab))

    } else if (type == TYPE_SYMBOL) {
        info["defined"] = (info["valid"] &&
                            ((ns, name, NOKEY, level, "symval") in symtab))

    } else if (type == TYPE_USER) {
        info["defined"] = (info["valid"] &&
                           ((ns, name, NOKEY, level, "user_block") in symtab))
        if (info["defined"])
            info["user_block"] = cmd_ll_read_ns(ns, name, level)

    } else
        panic("(info__lookup_found_p) Unhandled type: " ppf__label(type))

    dbg__print("nam", 2, sprintf("(info__lookup_found_p) Found name '%s', level=%d, code=%s=%s Found in namtab => %s",
                                 name, level, code,
                                 nam_ppf_name_level(ns, name, level),
                                 (level == 0 ? "ROOT_LEVEL" \
                                  : sprintf("Level %d", level))))
    return TRUE
}


function info__create_from_text(text, info,
                                nparts, level)
{
    split("", info)
    info["urtext"] = text
    nparts = nam__scan(text, info)
    if (nparts == ERROR)
        return ERR_SCAN_INVALID_NAME
    level = nam__lookup(info)    # level (>= 0) or NAME_NOT_FOUND
    return level
}


# Remove any name at level "level" or greater
function nam_purge(ns, level,
                   f, n, d, del_list, code, type, agg_block,
                   pns, pname, plevel)
{
    dbg__print("nam", 7, "(nam_purge) BEGIN")

    for (n in namtab) {
        split(n, f, SUBSEP)
        if (f[NFN_NS] == ns && f[NFN_LEVEL]+0 >= level)
            del_list[f[1], f[2], f[3]] = TRUE
    }

    for (d in del_list) {
        split(d, f, SUBSEP)
        pns    = f[NFN_NS]
        pname  = f[NFN_NAME]
        plevel = f[NFN_LEVEL]
        dbg__print("nam", 3, sprintf("(nam_purge) Delete namtab[%s, '%s', %d]",
                                     pns, pname, plevel))
        code = nam_ll_read_ns(pns, pname, plevel)
        type = first(code)
        if (double_underscores_p(pname) ||
            type == TYPE_FUNCTION || type == TYPE_COMMAND || type == TYPE_INTERNAL)
            continue
        #print_stderr(sprintf("(nam_purge) '%s' type %s", pname, ppf__label(type)))
        if (type == TYPE_LIST) {
            agg_block = symtab[pns, pname, NOKEY, plevel, "agg_block"]
            lis_clear(pns, pname, plevel)
            if (integerp(agg_block)) {
                #print_stderr("(nam_purge) Deleting agg_block " agg_block)
                blk_master_delete(agg_block)
            }
            delete blktab[agg_block, 0, "count"]
            delete blktab[agg_block, 0, "line"]
            delete symtab[pns, pname, NOKEY, plevel, "agg_block"]
        }
        trace(TRACE_SYMBOL_READ_WRITE, pname,
              sprintf("[Name Delete] %s (lev=%d)", pname, plevel))
        delete namtab[pns, pname, plevel]
    }
    dbg__print("nam", 7, "(nam_purge) END")
}


function dump__names(target_namespace, filter_flags, include_sys,
                     f, n, ns, code, s, desc, name, level, l,
                     include_system, buf, i, cnt, keys)
{
    if (include_sys)
        filter_flags = flag_set_clear(filter_flags, FLAG_SYSTEM, EMPTY)
    include_system = flag_1true_p(filter_flags, FLAG_SYSTEM)
    dbg__print("sym", 4, sprintf("(dump__names) BEGIN ns=%s, filter (%s%s):\n",
                                 target_namespace, ppf__flags(filter_flags),
                                 include_system ? "+System" : EMPTY))

    cnt = 0
    for (n in namtab) {
        split(n, f, SUBSEP)
        ns    = f[NFN_NS]
        name  = f[NFN_NAME]
        level = f[NFN_LEVEL] + 0
        code = nam_ll_read_ns(ns, name, level)

        if (target_namespace != PTYPE_ANY &&
            target_namespace != ns) {
            # print_debugfile(sprintf("m2debug:(dump__names) ns filter: ns=%s, name=%s, code=%s, filter=%s",
            #                         ns, name, ppf__label(code), ppf__label(filter_flags)))
            continue
        }
        if (! flag_alltrue_p(code, filter_flags)) {
            # print_debugfile(sprintf("m2debug:(dump__names) flags filter: ns=%s, name=%s, code=%s, filter=%s",
            #                         ns, name, ppf__label(code), ppf__label(filter_flags)))
            continue
        }
        if (flag_1true_p(code, FLAG_SYSTEM) && !include_system) {
            # print_debugfile(sprintf("m2debug:(dump__names) include_system filter: ns=%s, name=%s, code=%s, filter=%s",
            #                         ns, name, ppf__label(code), ppf__label(filter_flags)))
            continue
        }
        keys[++cnt] = ns TOK_NS_QUAL name TOK_NS_QUAL level
    }

    qsort(SORT_NATURAL, keys, 1, cnt)

    buf = EMPTY
    for (i = 1; i <= cnt; i++) {
        split(keys[i], f, TOK_NS_QUAL)
        buf = buf  nam_ppf_name_level(f[1], f[2], f[3])  TOK_NEWLINE
    }
    return chop(buf)
}


function nam_ll_read_ns(ns, name, level)
{
    if (level == EMPTY)
        panic("(nam_ll_read_ns) LEVEL must not be empty")
    if (ns == EMPTY)
        panic("(nam_ll_read_ns) NS must not be empty")
    return namtab[ns, name, level] # returns code
}


function nam_ll_in_ns(ns, name, level)
{
    if (level == EMPTY)
        panic("(nam_ll_in_ns) LEVEL must not be empty")
    if (ns == EMPTY)
        panic("(nam_ll_in_ns) NS must not be empty")
    #if (name != "__LINE__" && name != "__NLINE__" && name != "__DBG__")
        #dbg__print("sym", 5, sprintf("(nam_ll_in) Looking for '%s' at level %s", name, level))
    if (double_underscores_p(name))
        ns = M2_SYSNS
    # else
    #     print_stderr(sprintf("(nam_ll_in_ns) Looking for '%s' at level %s", name, level))
    return (ns, name, level) in namtab
}


function nam_ll_write_ns(ns, name, level, code,
                         retval, msg)
{
    if (level == EMPTY)
        panic("(nam_ll_write_ns) LEVEL must not be empty")
    if (ns == EMPTY)
        panic("(nam_ll_write_ns) NS must not be empty")
    if (! nam__valid_p(ns, PTYPE_NS, TRUE) ||
        ns == "awk")
        panic("(nam_ll_write_ns) Bad ns '" ns "'")
    if (! nam__valid_p(name, PTYPE_NAME, TRUE))
        panic("(nam_ll_write_ns) Bad name '" name "'")

    # It's important to use low-level functions here, and not invoke
    # dbg__* functions in this procedure, otherwise nasty loops ensue.
    if (sys_in("__DBG__", "nam") &&
        sys_read("__DBG__", "nam") >= 5)
        print_debugfile(sprintf("m2debug:(nam_ll_write_ns) namtab[%s, \"%s\", %d] = %s",
                                ns, name, level, code))

    msg = sprintf("[Name Update] '%s'::'%s' (lev=%d) := Code '%s'",
                  ns, name, level, code)
    # if (ns != M2_SYSNS)
    #     print_stderr("TEMP: " msg)
    trace(TRACE_SYMBOL_READ_WRITE, name, msg)
    return namtab[ns, name, level] = code
}


function nam_ppf_name_level(ns, name, level,
                            s, code, desc, l, x)
{
    code = nam_ll_read_ns(ns, name, level)
    s = ns TOK_NS_QUAL name (VERBOSE() ? TOK_LBRACE level TOK_RBRACE : EMPTY) TOK_TAB ppf__flags(code)
    return s
}


function info__dump(info,
                    k, x, n)
{
    for (k in info) {
        print sprintf("info[%s] = %s", k, info[k])

        # n = split(k, x, SUBSEP)
        # print n
        # #dbg__print("sym", 8, sprintf("(dump__symbtab) ['%s','%s',%d,%s]",
        # print sprintf("(dump__symbtab) ['%s','%s',%d,%s]",
        #                             x[1], x[2], x[3], x[4])
        # #)
    }
}


function info__get(info, elem)
{
    if (elem == "key_valid") {
        if (info["_key_valid"] == VOID)
            return info["_key_valid"] = \
                nam__valid_p(info__get(info, "key"), PTYPE_KEY, TRUE)
        else
            return info["_key_valid"]
    } else if (elem == "lexvalid") {
        if (info["_lexvalid"] == VOID)
            return info["_lexvalid"] = \
                info__get(info, "name_valid") &&
                (info__get(info, "nparts") == 1 ? TRUE \
                 : info__get(info, "key_valid"))
        else
            return info["_lexvalid"]
    } else if (elem == "protected") {
        if (info["_protected"] == VOID)
            return info["_protected"] = \
                sym_ll_protected(info["name"], info["code"])
        else
            return info["_protected"]
    } else if (elem == "type")
        return first(info["code"])
    else if (! (elem in info))
        panic("(info__get) Info does not contain element '" elem "'")
    else
        return info[elem]
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       N A M E S P A C E   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       TK
#
#*****************************************************************************
function curr_ns()
{
    if (stk_empty_p(__ns_stack))
        panic("(curr_ns) Empty __ns_stack")
    return stk_top(__ns_stack)
}

# Sequence names must always match strict symbol name syntax:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
#
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S E Q U E N C E   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function seq_definition_ppf_ns(qname,
                               buf, AT_SEQUENCE,
                               q, ns, name)
{
    if ((q = index(qname, TOK_NS_QUAL)) == NOT_FOUND)
        panic("(seq_definition_ppf_ns) Can only hand qualified names")
    # ns::name
    ns   = substr(qname, 1, q-1)
    name = substr(qname, q+2)
    AT_SEQUENCE = "@sequence " qname TOK_TAB
    buf =         AT_SEQUENCE "create" TOK_NEWLINE

    if (seq_ll_read_ns(ns, name) != SEQ_DEFAULT_INIT)
        buf = buf AT_SEQUENCE "setval " seq_ll_read_ns(ns, name) TOK_NEWLINE
    if (symtab[ns, name, NOKEY, ROOT_LEVEL, "init"] != SEQ_DEFAULT_INIT)
        buf = buf AT_SEQUENCE "setinit " symtab[ns, name, NOKEY, ROOT_LEVEL, "init"] TOK_NEWLINE
    if (symtab[ns, name, NOKEY, ROOT_LEVEL, "incr"] != SEQ_DEFAULT_INCR) {
        print_stderr(sprintf("(seq_definition_ppf_ns) %s != %s ?",
                             symtab[ns, name, EMPTY, ROOT_LEVEL, "incr"], SEQ_DEFAULT_INCR))
        buf = buf AT_SEQUENCE "setincr " symtab[ns, name, NOKEY, ROOT_LEVEL, "incr"] TOK_NEWLINE
    }
    if (symtab[ns, name, NOKEY, ROOT_LEVEL, "fmt"] != sys_read("__FMT__", "seq"))
        buf = buf AT_SEQUENCE "format " symtab[ns, name, NOKEY, ROOT_LEVEL, "fmt"] TOK_NEWLINE
    return chop(buf)
}


function seq_destroy_ns(ns, name)
{
    delete namtab[ns, name, ROOT_LEVEL]
    delete symtab[ns, name, EMPTY, ROOT_LEVEL, "incr"]
    delete symtab[ns, name, EMPTY, ROOT_LEVEL, "init"]
    delete symtab[ns, name, EMPTY, ROOT_LEVEL, "fmt"]
    delete symtab[ns, name, EMPTY, ROOT_LEVEL, "seqval"]
}


function seq_ll_read_ns(ns, name)
{
    return symtab[ns, name, EMPTY, ROOT_LEVEL, "seqval"]
}


function seq_ll_write_ns(ns, name, new_val)
{
    return symtab[ns, name, EMPTY, ROOT_LEVEL, "seqval"] = new_val
}


function seq_ll_incr_ns(ns, name, incr)
{
    if (incr == EMPTY)
        incr = symtab[ns, name, EMPTY, ROOT_LEVEL, "incr"]
    symtab[ns, name, EMPTY, ROOT_LEVEL, "seqval"] += incr
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


function stk_push(stack, new_elem,
                  siz)
{
    if (stack["name"] == "source_stack")
        trace(TRACE_INPUT_FILE_CHG, EMPTY,
              sprintf("[File Update] Input file now '%s'", blktab[new_elem, 0, "filename"]))
    else if (stack["name"] == "stream_stack") {
        sys_write("__DIVNUM__", new_elem)
        dbg__print("divert", 2, sprintf("(stk_push) __DIVNUM__ now %d", new_elem))
    }

    if (dbg__sys_level_p("stk", 5)) {
        siz = stack[0]
        print_debugfile(sprintf("m2debug:(stk_push) %s[%d] := %s",
                                stack["name"], siz+1, new_elem))
    }
    return stack[++stack[0]] = new_elem
}


function stk_empty_p(stack)
{
    return (stk_depth(stack) == 0)
}


function stk_top(stack)
{
    if (stk_empty_p(stack))
        panic("(stk_top) " stack["name"] ": Empty stack")
    return stack[stack[0]]
}


function stk_replace_top(stack, new_elem)
{
    if (stk_empty_p(stack))
        panic("(stk_replace_top) " stack["name"] ": Empty stack")
    if (stack["name"] == "source_stack")
        trace(TRACE_INPUT_FILE_CHG, EMPTY,
              sprintf("[File Update] Input file now '%s'", blktab[new_elem, 0, "filename"]))
    else if (stack["name"] == "stream_stack") {
        sys_write("__DIVNUM__", new_elem)
        dbg__print("divert", 2, sprintf("(stk_replace_top) __DIVNUM__ now %d", new_elem))
    }
    if (dbg__sys_level_p("stk", 5))
        print_debugfile(sprintf("m2debug:(stk_replace_top) %s[%d] := %s",
                                stack["name"], stack[0], new_elem))
    return stack[stack[0]] = new_elem
}


function stk_pop(stack,
                 old_top, new_top, siz, stkname)
{
    stkname = stack["name"]
    if (stk_empty_p(stack))
        panic("(stk_pop) " stkname ": Empty stack")
    siz = stack[0]
    old_top = stack[stack[0]--]
    # You may think the LHS clause is redundant due to the stk_empty_p() check above;
    # however, have having it here is required to keep "make lint" happy.
    if (!stk_empty_p(stack) && stack["name"] == "source_stack") {
        new_top = stk_top(stack)
        trace(TRACE_INPUT_FILE_CHG, EMPTY,
              sprintf("[File Update] Input file now '%s'", blktab[new_top, 0, "filename"]))
    } else if (stkname == "stream_stack") {
        new_top = stk_empty_p(stack) ? -1 : stk_top(stack)
        sys_write("__DIVNUM__", new_top)
        dbg__print("divert", 2, sprintf("(stk_pop) __DIVNUM__ now %d", new_top))
    }

    if (dbg__sys_level_p("stk", 5)) {
        print_debugfile(sprintf("m2debug:(stk_pop) %s[%d] => %s",
                                stkname, siz, old_top))
    }
    return old_top
}


function stk_push_2nd(stack, elem,
                      stkname, top)
{
    stkname = stack["name"]
    if (stk_empty_p(stack))
        panic("(stk_push_2nd) " stkname ": Empty stack")
    top = stk_pop(stack)
    stk_push(stack, elem)
    stk_push(stack, top)
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
#         = 0         Standard output (TERMINAL)
#         > 0         Stream # N
#
#       The div2blktab[] array maintains the mapping of stream number to
#       block number.  Accessing a new stream allocates a new agg_block,
#       which is how m2 provides an unlimited number of streams.
#
#       See @divert, @undivert
#
#*****************************************************************************
function DIVNUM()
{
    return sys_read("__DIVNUM__", NOKEY) + 0
}


# Tell me if a stream block exists or not.
function stream_block_exists_p(stream)
{
    if (! integerp(stream))
        error("(stream_exists_p) Bad stream: " stream)
    if (stream <= TERMINAL)
        return FALSE
    return (stream in div2blktab)
}

# Given a stream, return its associated block number (a BLK_AGG).
# This always returns a block number.  BEWARE, this means it will
# create a new block for an unrecognized stream number, so check
# with the exists predicate if you're just looking.
function stream_block(stream)
{
    if (!integerp(stream) || stream <= TERMINAL)
        error("(stream_block) Bad stream: " stream)
    if (! stream_block_exists_p(stream))
        # Create/initialize empty agg block
        div2blktab[stream] = blk_new(BLK_AGG)
    return div2blktab[stream]
}


# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-scanned for macros, and buffer is cleared after
# injection into target stream.
function undivert(stream,
                  count, i, dstblk, divblk)
{
    dstblk = curr_dstblk()
    dbg__print("divert", 2, sprintf("(undivert) START dstblk=%d, stream=%d",
                                   curr_dstblk(), stream))
    if (dstblk < 0) {
        dbg__print("divert", 3, "(undivert) END because dstblk <0")
        return
    }
    if (stream <= TERMINAL || stream == DIVNUM()) {
        dbg__print("divert", 3, "(undivert) END because stream <= 0 or == DIVNUM")
        return
    }
    if (! stream_block_exists_p(stream))
        return

    divblk = stream_block(stream)
    if (blk_type(divblk) != BLK_AGG)
        panic(sprintf("(undivert) Block %d has type %s, not AGG",
                      divblk, ppf__label(blk_type(stream))))
    if ((count = blktab[divblk, 0, "count"]) > 0) {
        # It is required to clear the stream immediately after undiverting.
        # This is to prevent
        #        @undivert N
        #        @undivert N
        # from producing double output.  Move each slot manually to the
        # target stream, then clear the original diversion.
        if (dstblk == TERMINAL)
            execute__block(divblk)
        else
            for (i = 1; i <= count; i++)
                blk_append(dstblk, blk_ll_slot_type(divblk, i), blk_ll_slot_value(divblk, i))
        cleardivert(stream)
    }
}


# "Inject all diversions, in numerical order, into current stream."
function undivert_all(    stream, keys, cnt, i)
{
    cnt = 0
    for (stream in div2blktab)
        keys[++cnt] = stream
    qsort(SORT_INTEGER, keys, 1, cnt)

    for (i = 1; i <= cnt; i++) {
        stream = keys[i]
        if (stream_block_exists_p(stream))
            undivert(stream)
    }
}


# Print stream to a file
# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-scanned for macros, and buffer is cleared after
# injection into target stream.
function undivert_to_file(stream, file,
                          count, i, divblk)
{
    dbg__print("divert", 2, sprintf("(undivert_to_file) START; stream=%d, file='%s'", stream, file))
    if (! stream_block_exists_p(stream))
        return
    divblk = stream_block(stream)
    if (blk_type(divblk) != BLK_AGG)
        panic(sprintf("(undivert_to_file) Block %d has type %s, not AGG",
                      divblk, ppf__label(blk_type(divblk))))
    if ((count = blktab[divblk, 0, "count"]) > 0) {
        ship_out_to_file(divblk, file)
        cleardivert(stream)
    }
}


# Remove all slots from an AGG block and return its count to zero.
function cleardivert(stream,
                     count, i, divblk)
{
    dbg__print("divert", 2, sprintf("(cleardivert) START dstblk=%d, stream=%d",
                                    curr_dstblk(), stream, divblk))
    if (stream <= TERMINAL) {
        dbg__print("divert", 3, "(cleardivert) END because stream <=0")
        return
    }
    if (! stream_block_exists_p(stream))
        return

    divblk = stream_block(stream)
    if (blk_type(divblk) != BLK_AGG)
        panic(sprintf("(cleardivert) Block %d has type %s, not AGG",
                      divblk, ppf__label(blk_type(divblk))))
    if ((count = blktab[divblk, 0, "count"]) > 0) {
        for (i = 1; i <= count; i++) {
            delete blktab[divblk, i, "slot_type"]
            delete blktab[divblk, i, "slot_value"]
        }
        blktab[divblk, 0, "count"] = 0
    }
}


function cleardivert_all(    stream, keys, cnt, i)
{
    cnt = 0
    for (stream in div2blktab)
        keys[++cnt] = stream
    qsort(SORT_INTEGER, keys, 1, cnt)

    for (i = 1; i <= cnt; i++) {
        stream = keys[i]
        if (stream_block_exists_p(stream))
            cleardivert(stream)
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       S Y M B O L   A P I
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************

# Symbol names must match the following regexp:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
# see nam__valid_p()
function sym_valid_p(sym,
                      nparts, info, retval)
{
    dbg__print("sym", 5, sprintf("(sym_valid_p) sym='%s' START", sym))

    if ((nparts = nam__scan(sym, info)) == ERROR) {
        #error("(sym_valid_p) ERROR nam__scan('" sym "') failed")
        dbg__print("sym", 4, sprintf("(sym_valid_p) END sym='%s' => %s",
                                     sym, ppf__bool(FALSE)))
        __m2_msg = "Invalid name: '" sym "'"
        return FALSE
    }
    retval = syminfo_valid_p(info)
    dbg__print("sym", 4, sprintf("(sym_valid_p) END sym='%s' => %s",
                                 sym, ppf__bool(retval)))
    return retval
}


function syminfo_valid_p(syminfo,
                         name, retval)
{
    name = info__get(syminfo, "name")
    dbg__print("sym", 5, sprintf("(syminfo_valid_p) sym='%s' START", name))

    retval = info__get(syminfo, "errorp") == FALSE &&
             info__get(syminfo, "lexvalid") == TRUE

    dbg__print("sym", 4, sprintf("(syminfo_valid_p) END sym='%s' => %s",
                                 name, ppf__bool(retval)))
    return retval
}


# This is only for internal use, to easily create and define symbols at
# program start.  Code must be correctly formatted.  No error checking is done.
# This function only creates symbols at the root level.
function sym_ll_fiat(name, key, code, new_val,
                      level)
{
    level = ROOT_LEVEL

    # Create an entry in the m2 (only) namespace table.
    if (! nam_ll_in_ns(M2_SYSNS, name, level))
        nam_ll_write_ns(M2_SYSNS, name, level, code)

    # Set its value in the symbol table
    sym_ll_write_ns(M2_SYSNS, name, key, level, new_val)
}

# function sym_ll_vivify(ns, name, key, level, code, new_val)
# {
#     nam_ll_write_ns(ns, name, level, code)
#     sym_ll_write_ns(ns, name, key, level, new_val)
# }

# Deferred symbols cannot have keys, so don't even pass anything
function sym_deferred_symbol(name, code, deferred_prog, deferred_arg,
                             level)
{
    level = ROOT_LEVEL

    # Create an entry in the name table.  Deferred symbols can
    # only be created by the system and are in the M2 namespace.
    if (nam_ll_in_ns(M2_SYSNS, name, level))
        panic("Cannot create deferred symbol when it already exists")

    nam_ll_write_ns(M2_SYSNS, name, level, code FLAG_DEFERRED)
    # It has no symbol value (yet), but we do store the two args in the
    # symbol table
    symtab[M2_SYSNS, name, NOKEY, level, "deferred_prog"] = deferred_prog
    symtab[M2_SYSNS, name, NOKEY, level, "deferred_arg"]  = deferred_arg
}


function sym_destroy_ns(ns, name, key, level)
{
    dbg__print("sym", 5, sprintf("(sym_destroy) START; name='%s', key='%s', level=%d",
                                 name, key, level))

    # Scan sym => name, key
    # if nam_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if nam_system_p(name)
    # A ::= Cond: name is array T/F
    # B ::= Cond: sym has name[key] syntax T/F
    # if A & B          delete symtab[ns, name, key, level, "symval"]
    # if A & !B         delete every symtab entry for key; delete namtab entry
    # if !A & B         syntax error: NAME is not an array and cannot be deindexed
    # if !A & !B        (normal symbol) delete symtab[ns, name, NOKEY, level, "symval"];
    #                                   delete namtab[ns, name]
    delete namtab[ns, name, level]
    trace(TRACE_SYMBOL_READ_WRITE, name,
          sprintf("[Symbol Delete] %s::%s (lev=%d)", ns, name, level))
    delete symtab[ns, name, key, level, "agg_block"]
    delete symtab[ns, name, key, level, "deferred_arg"]
    delete symtab[ns, name, key, level, "deferred_prog"]
    delete symtab[ns, name, key, level, "symval"]
}


# DO NOT require CODE parameter.  Instead, look up NAME and
# find its code as normal.  NAME might not even be defined!
function nam_system_p(name)
{
    if (name == EMPTY)
        panic("nam_system_p: NAME must not be empty")
    return nam_ll_in_ns(M2_SYSNS, name, ROOT_LEVEL) &&
        flag_1true_p(nam_ll_read_ns(M2_SYSNS, name, ROOT_LEVEL), FLAG_SYSTEM)
}


# Remove any symbol at level "level" or greater
function sym_purge(level,
                   f, s, d, sym_del_list, cmd_del_list,
                   pns, pname, pkey, plevel, ptag)
{
    dbg__print("sym", 7, "(sym_purge) BEGIN")
    for (s in symtab) {
        split(s, f, SUBSEP)
        pns    = f[SFN_NS]
        pname  = f[SFN_NAME]
        pkey   = f[SFN_KEY]
        plevel = f[SFN_LEVEL]+0
        if (plevel >= level) {
            if (double_underscores_p(pname))
                continue
            ptag = f[SFN_TAG]
            if (ptag == "user_block") {
                cmd_del_list[symtab[pns, pname, pkey, plevel, ptag]] = TRUE
                sym_del_list[pns, pname, pkey, plevel, ptag] = TRUE
            } else if (ptag == "agg_block") {
                blk_master_delete(symtab[pns, pname, pkey, plevel, ptag])
                sym_del_list[pns, pname, pkey, plevel, ptag] = TRUE
            } else if (ptag == "symval" ||
                       ptag == "deferred_arg" || ptag == "deferred_prog")
                sym_del_list[pns, pname, pkey, plevel, ptag] = TRUE
            else
                panic(sprintf("(sym_purge) Unsure: symtab[%s, '%s','%s',%d,'%s']",
                              pns, pname, pkey, plevel, ptag))
        }
    }

    for (d in sym_del_list) {
        split(d, f, SUBSEP)
        dbg__print("sym", 3, sprintf("(sym_purge) Delete symtab[%s, '%s', '%s', %d, %s]",
                                     f[1], f[2], f[3], f[4], f[5]))
        delete symtab[f[1], f[2], f[3], f[4], f[5]]
    }
    dbg__print("sym", 7, "(sym_purge) END")
}


# Deferred symbols have an entry in namtab of TYPE_SYMBOL
# and FLAG_DEFERRED.  Only system symbols at the root level
# are deferred, so we don't need to be super careful
function sym_deferred_p(sym,
                        code, level)
{
    level = ROOT_LEVEL
    if (!nam_ll_in_ns(M2_SYSNS, sym, level))
        return FALSE
    code = nam_ll_read_ns(M2_SYSNS, sym, level)
    if (flag_anyfalse_p(code, TYPE_SYMBOL FLAG_DEFERRED))
        return FALSE
    # OK - deferred syms are always in M2 ns
    return ((M2_SYSNS, sym, NOKEY, level, "deferred_prog") in symtab &&
            (M2_SYSNS, sym, NOKEY, level, "deferred_arg")  in symtab &&
          !((M2_SYSNS, sym, NOKEY, level, "symval")        in symtab))
}


function sym_define_all_deferred(    f, n, def_list, sym, code)
{
    dbg__print("nam", 5, "(sym_define_all_deferred) BEGIN")
    if (secure_level() >= SEC_PARANOID)
        return

    for (n in namtab) {
        split(n, f, SUBSEP)     # [NAME, LEVEL]
        sym = f[NFN_NAME]
        code = nam_ll_read_ns(M2_SYSNS, sym, ROOT_LEVEL)
        if (flag_1true_p(code, FLAG_DEFERRED)) {
            dbg__print("nam", 7, "(sym_define_all_deferred) Defining deferred " sym)
            def_list[sym] = TRUE
        }
    }

    for (sym in def_list) {
        dbg__print("nam", 5, "(sym_define_all_deferred) Defining deferred " sym)
        sym_deferred_define_now(sym)
    }
    dbg__print("nam", 5, "(sym_define_all_deferred) END")
}


# User should have checked to make sure, so let's do it
function sym_deferred_define_now(sym,
                                 code, deferred_prog, deferred_arg, cmdline, output)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation("(sym_deferred_define_now) Forbidden")

    code = nam_ll_read_ns(M2_SYSNS, sym, ROOT_LEVEL)
    deferred_prog = symtab[M2_SYSNS, sym, NOKEY, ROOT_LEVEL, "deferred_prog"]
    deferred_arg  = symtab[M2_SYSNS, sym, NOKEY, ROOT_LEVEL, "deferred_arg"]

    # Build the command to generate the output value, then store it in the symbol table
    cmdline = build_prog_cmdline(deferred_prog, deferred_arg, MODE_IO_CAPTURE)
    cmdline | getline output
    close(cmdline)
    # Kluge to add trailing slash to pwd(1) output
    if (sym == "__CWD__")
        output = with_trailing_slash(output)
    sym_ll_write_ns(M2_SYSNS, sym, NOKEY, ROOT_LEVEL, output)

    # Get rid of any trace of FLAG_DEFERRED
    nam_ll_write_ns(M2_SYSNS, sym, ROOT_LEVEL, flag_set_clear(code, EMPTY, FLAG_DEFERRED))
    delete symtab[M2_SYSNS, sym, NOKEY, ROOT_LEVEL, "deferred_prog"]
    delete symtab[M2_SYSNS, sym, NOKEY, ROOT_LEVEL, "deferred_arg"]
}


function sym_destroy_all_deferred(    f, n, def_list, sym, code)
{
    dbg__print("nam", 5, "(sym_destroy_all_deferred) BEGIN")

    for (n in namtab) {
        split(n, f, SUBSEP)
        sym = f[NFN_NAME]
        code = nam_ll_read_ns(M2_SYSNS, sym, ROOT_LEVEL)
        if (flag_1true_p(code, FLAG_DEFERRED)) {
            dbg__print("nam", 7, "(sym_destroy_all_deferred) Want to destroy deferred " sym)
            def_list[sym] = TRUE
        }
    }

    for (sym in def_list) {
        dbg__print("nam", 5, "(sym_destroy_all_deferred) Destroying deferred " sym)
        sym_destroy_ns(M2_SYSNS, sym, NOKEY, ROOT_LEVEL)
    }
    dbg__print("nam", 5, "(sym_destroy_all_deferred) END")
}


function sym_defined_p(sym,
                       nparts, info, iname, ikey, code, ilevel, i,
                       agg_block, count, ins)
{
    dbg__print("sym", 5, sprintf("(sym_defined_p) sym='%s' START", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR) {
        dbg__print("sym", 2, sprintf("(sym_defined_p) END nam__scan('%s') failed => %s", sym, ppf__bool(FALSE)))
        __m2_msg = "Scan error, " __m2_msg
        return FALSE
    }
    iname = info["name"]
    ikey  = info["key"]

    # Now call nam__lookup(info)
    ilevel = nam__lookup(info)
    if (ilevel == NAME_NOT_FOUND) {
        #print_stderr("(sym_defined_p) nam__lookup(" info__get(info, "urtext") " => not found => FALSE")
        dbg__print("sym", 2, sprintf("(sym_defined_p) END nam__lookup('%s') failed, maybe ok? => %s", sym, ppf__bool(FALSE)))
        return FALSE
    }
    ins = info__get(info, "ns")
    if (ins == M2_ENVNS)
        return sym_ll_in_ns(ins, iname, NOKEY, ROOT_LEVEL)

    # We've found some matching name on some level, but not sure if it's a Symbol or not.
    # This step is necessary to make sure it's actually a Symbol.
    for (i = nam_system_p(iname) ? ROOT_LEVEL : curr_level(); i >= ROOT_LEVEL; i--) {
        if (info_defined_lev_p(info, i, TYPE_SYMBOL)) {
            dbg__print("sym", 2, sprintf("(sym_defined_p) END sym='%s', level=%d => %s", sym, i, ppf__bool(TRUE)))
            return TRUE
        }
    }

    # If it's not a normal symbol table entry, maybe a block-array
    if (flag_1true_p(info["code"], TYPE_LIST)) {
        if (emptyp(ikey)) {
            dbg__print("sym", 2, sprintf("(sym_defined_p) Block array bare name returns count"))
            return TRUE
        }

        if (!integerp(ikey)) {
            dbg__print("sym", 2, sprintf("(sym_defined_p) Block array indices must be integers"))
            return FALSE
        }
        if (! ((ins, iname, NOKEY, ilevel, "agg_block") in symtab))
            panic(sprintf("(sym_defined_p) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                          ins, iname, NOKEY, ilevel))

        agg_block = symtab[ins, iname, NOKEY, ilevel, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (ikey >= 1 && ikey <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, ikey) != OBJ_TEXT)
                panic(sprintf("(sym_defined_p) Block # %d slot %d is not OBJ_TEXT", agg_block, ikey))
            dbg__print("sym", 2, sprintf("(sym_defined_p) END sym='%s', level=%d => %s", sym, ilevel, ppf__bool(TRUE)))
            return TRUE
        }
    }

    dbg__print("sym", 2, sprintf("(sym_defined_p) END No symbol named '%s' on any level => %s", sym, ppf__bool(FALSE)))
    return FALSE
}

function syminfo_defined_p(info,
                           itype, ilevel, ins)
{
    if (! info__get(info, "name_valid"))
        return FALSE
    if ((ilevel = info__get(info, "level")) == NAME_NOT_FOUND)
        return FALSE
    itype = info__get(info, "type")
    if (itype == TYPE_SYMBOL)
        return info_defined_lev_p(info, ilevel, itype)
    else if (itype == TYPE_ARRAY || itype == TYPE_LIST)
        return idx__key_exists_p(info, info__get(info, "key"))
    else if (itype == TYPE_SEQUENCE)
        #return seq_defined_p(info__get(info, "name"))
        return info__get(info, "defined")
    else if (itype == PTYPE_ENV_VAR)
        # If the type is Env_Var, always use namespace ENV::
        # in case info["ns"] is compromised.
        return sym_ll_in_ns(M2_ENVNS, info__get(info, "name"), NOKEY, ROOT_LEVEL)
    else
        panic(sprintf("(syminfo_defined_p) Cannot handle '%s' type %s",
                      info__get(info, "name"), ppf__label(itype)))
}


# Caller MUST have previously called nam__scan().
# It's the only way to get the `info' parameter value.
#
# The caller is responsible for inquiring about nam_system_p(name),
# and overriding level to zero if appropriate.  This code does
# not make any assumptions about name/levels.
function info_defined_lev_p(info, level, type,
                            iname, ikey, ins)
{
    iname = info["name"]
    ikey  = info["key"]
    ins   = info__get(info, "ns")
    dbg__print("sym", 5, sprintf("(info_defined_lev_p) isn=%s, iname='%s' START", ins, iname))

    if (type == TYPE_SYMBOL && (ins, iname, ikey, 0+level, "symval") in symtab) {
        dbg__print("sym", 5, sprintf("(info_defined_lev_p) END [%s,\"%s\",\"%s\",%d,\"symval\"] Found Symbol => TRUE", ins, iname, ikey, level))
        return TRUE
    } else if (type == TYPE_USER && (ins, iname, ikey, 0+level, "user_block") in symtab) {
        dbg__print("sym", 5, sprintf("(info_defined_lev_p) END [%s, \"%s\",\"%s\",%d,\"symval\"] Found Command => TRUE", ins, iname, ikey, level))
        return TRUE
    } else {
        dbg__print("sym", 5, sprintf("(info_defined_lev_p) END [%s,\"%s\",\"%s\",%d,\"symval\"] Not found => FALSE", ins, iname, ikey, level))
        return FALSE
    }
}


#*****************************************************************************
#
#       S Y M I N F O  _  S T O R E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       if nam_system_p(name)          level = 0
#       Error if name does not exist at that level
#       Error if symbol is an array but sym doesn't have array[key] syntax
#       Error if symbol is not an array but sym has array[key] syntax
#       Error if you don't have permission to write to the symbol
#         == Error ("read-only") if (flag_true(FLAG_READONLY))
#       Error if new_val is not consistent with symbol type (haha)
#         or else coerce it to something acceptable (boolean)
#       Special processing (CONVFMT, __DEBUG__)
#
#*****************************************************************************
function syminfo_store(info, new_val,
                       iname, ikey, ilevel, good, ihasbracket, itype, icode, dbg5,
                       idxable, ins)
{
    dbg5 = dbg__sys_level_p("sym", 5)

    # This needs to be much more robust...
    iname = info__get(info, "name")
    ikey  = info__get(info, "key")
    ilevel = info__get(info, "level")
    ihasbracket = info__get(info, "has_bracket")
    if (dbg5)
        print_debugfile(sprintf("m2debug:(syminfo_store) START name='%s', level=%d",
                                iname, ilevel))

    # At this point:
    #   ilevel == NAME_NOT_FOUND             -> no matching name of any kind
    #   ilevel == ROOT_LEVEL -> found in global
    #   0 < ilevel < ns-1          -> find in other non-global frame
    #   ilevel == curr_level()      -> found in current level
    # Just because we found a namtab entry doesn't
    # mean it's okay to just muck about with symtab.

    good = FALSE
    do {
        if (ilevel == NAME_NOT_FOUND) {   # name not found in namtab
            # No namtab entry, no code : This means a normal
            # @define in the root level
            if (ihasbracket)
                error(sprintf("(syminfo_store) '%s' is not indexable; cannot use brackets here", iname))
            # Do scalar store
            ilevel = info["level"] = ROOT_LEVEL
            itype = icode  = info["code"]  = TYPE_SYMBOL
            if ((ins = info__get(info, "ns")) == EMPTY) {
                warn("(syminfo_store) Empty ns, defaulting to " curr_ns())
                ins = info["ns"] = curr_ns()
            }
            nam_ll_write_ns(ins, iname, ilevel, icode)
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if ((ins = info__get(info, "ns")) == EMPTY)
            panic("(syminfo_store) ns must not be empty")

        # At this point we know nam__lookup() found *something* because
        # ilevel != NAME_NOT_FOUND
        itype = info__get(info, "type")
        if (itype != TYPE_SYMBOL && itype != TYPE_LIST && itype != TYPE_ARRAY)
            error(sprintf("Name '%s' has type %s which is not valid here",
                          iname, ppf__label(itype)))

        icode = info__get(info, "code")
        idxable = info__satisfies_type(info, PTYPE_IDXABLE)

        # Error if we found an array without key,
        # or a plain symbol with a subscript.
        if (idxable && !ihasbracket)
            error(sprintf("(syminfo_store) '%s' is indexable, so brackets are required", iname))
        if (!idxable && ihasbracket)
            error(sprintf("(syminfo_store) '%s' is not indexable; cannot use brackets here", iname))

        if (itype == TYPE_SYMBOL &&
            !sym_ll_protected(iname, icode) &&
            ! ihasbracket &&
            flag_1false_p(icode, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (idxable &&
            !sym_ll_protected(iname, icode) &&
            ihasbracket &&
            flag_1false_p(icode, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (dbg5) {
            print_debugfile(sprintf("m2debug:(syminfo_store) LOOP BOTTOM: name='%s', key='%s', level=%d, code='%s', good=%s",
                                 iname, ikey, ilevel, icode, ppf__bool(good)))
            dump__names(ins, TYPE_SYMBOL, FALSE)
            print_debugfile(dump__symbols(M2_NS, TYPE_SYMBOL, FALSE)) # print_debugfile() adds newline.  FALSE means omit system symbols
        }
    } while (FALSE)

    # Add entry:        symtab[NS, iname, ikey, ilevel, "symval"] = new_val
    if (good) {
        dbg__print("sym", 2, sprintf("(syminfo_store) code=%s [%s, \"%s\",\"%s\",%d,\"symval\"]=%s",
                                     ppf__flags(itype), ins, iname, ikey, ilevel, new_val))
        if (! ((itype == TYPE_SYMBOL && ikey == EMPTY) ||
               ((itype == TYPE_ARRAY || itype == TYPE_LIST) && ikey != EMPTY))) {
            info__dump(info)
            panic("(syminfo_store) bad type/key combo")
        }

        if (itype == TYPE_LIST)
            lis__assign(ins, iname, ikey, ilevel, new_val)
        else
            sym_ll_write_ns(ins, iname, ikey, ilevel, new_val) # store into symtab[]
    } else {
        warn(sprintf("(syminfo_store) !good sym='%s'", iname))
    }
    if (dbg5)
        print_debugfile(sprintf("m2debug:(syminfo_store) END;"))
}


function sym_ll_read_ns(ns, name, key, level,
                        retval, i)
{
    if (level == EMPTY) # level = ROOT_LEVEL
        panic("(sym_ll_read_ns) Level must not be empty!")
    # if key  == EMPTY that's probably fine.
    # if name == EMPTY that's probably *not* fine.
    if (name == EMPTY)
        panic("(sym_ll_read_ns) Name must not be empty!")
    if (ns == EMPTY)
        panic("(sym_ll_read_ns) NS must not be empty!")

    if (ns == M2_ENVNS) {
        if (key != EMPTY)
            error(sprintf("(sym_ll_read_ns) Env var '%s' cannot have key [%s]",
                          name, key))
        retval = ENVIRON[name]  # no error if non exists, TODO check __STRICT__
        trace(TRACE_ENV_VAR, name,
              sprintf("[Env Var Read] %s => '%s'", name, retval))
        return retval
    }

    if (double_underscores_p(name)) {
        if (name == "__NSPATH__") {
            # __NSPATH__ is not a real variable -- its value is
            # constructed on the fly by walking the namespace stack.
            for (i = stk_depth(__ns_stack); i > 0; i--)
                retval = retval  (!emptyp(retval) ? TOK_COLON : EMPTY)  __ns_stack[i]
            return retval
        } else
            return symtab[M2_SYSNS, name, key, level, "symval"]
    }

    if (! sym_ll_in_ns(ns, name, key, level))
        panic(sprintf("(sym_ll_read_ns) symtab[%s, '%s','%s',%d,'symval'] does not exist",
                      ns, name, key, level))
    retval = symtab[ns, name, key, level, "symval"]

    #print_stderr("ll_read: name='" name "'")
    if (! double_underscores_p(name))
        trace(TRACE_SYMBOL_READ_WRITE, name,
              sprintf("[Symbol Read] %s (lev=%d) => '%s'",
                      sprintf("%s::%s%s", ns, name, (key ? TOK_LBRACKET key TOK_RBRACKET : "")),
                      level, retval))
    return retval
}


# Note - this only works for Symbol and Array[Key] checks.
# (It *is* low level after all.)  More esoteric look-ups
# like "deferred_prog" or such will have to be done manually.
function sym_ll_in_ns(ns, name, key, level,
                      retval)
{
    if (level == EMPTY)
        panic("(sym_ll_in_ns) LEVEL must not be empty")
    if (ns == EMPTY)
        panic("(sym_ll_in_ns) NS must not be empty")
    if (ns == M2_ENVNS) {
        if (key != EMPTY)
            error(sprintf("(sym_ll_in_ns) Env var '%s' cannot have key [%s]",
                          name, key))
        retval = name in ENVIRON
        trace(TRACE_ENV_VAR, name,
              sprintf("[Env Var Exist?] %s => %s", name, ppf__bool(retval)))
        return retval
    }
    return (ns, name, key, level, "symval") in symtab
}


function sym_ll_write_ns(ns, name, key, level, val)
{
    if (level == EMPTY)
        panic("(sym_ll_write_ns) LEVEL must not be empty")
    if (ns == EMPTY)
        panic("(sym_ll_write_ns) NS must not be empty")
    # Can't call normal dbg__*() functions here, mutually recursive
    if (sys_in("__DBG__", "sym") &&
        sys_read("__DBG__", "sym") >= 5 &&
        !nam_system_p(name))
         print_debugfile(sprintf("m2debug:(sym_ll_write_ns) symtab[%s, \"%s\", \"%s\", %d, \"symval\"] = %s",
                                ns, name, key, level, val))

    if (ns == M2_ENVNS) {
        if (key != EMPTY)
            error(sprintf("(sym_ll_write_ns) Env var '%s' cannot have key [%s]",
                          name, key))
        ENVIRON[name] = val
        trace(TRACE_ENV_VAR, name,
              sprintf("[Env Var Update] %s := Val '%s'", name, val))
        return val
    }

    # Run triggers for various special symbols
    if (name == "__DEBUG__") {
        if (val+0 >= 2) {
            # Disable hooks when super-debugging
            __m2_config_flags = flag_set_clear(__m2_config_flags, EMPTY, MODE_HOOKS_ENABLED)
            if (sys_read("__DEBUG__", NOKEY) == FALSE)
                dbg__all_lev_standard()
        }
    } else if (name == "__SECURE__") {
        val = max(secure_level(), val) # Don't allow __SECURE__ to decrease
        if (val >= SEC_PARANOID)
            sym_destroy_all_deferred()
    } else if (name == "__FMT__" &&
               key == "number" &&
               level == ROOT_LEVEL) {
        # Maintain equivalence:  __FMT__[number] === CONVFMT
        if (sys_in("__DBG__", "sym") &&
            sys_read("__DBG__", "sym") >= 7)
            print_debugfile(sprintf("m2debug:(sym_ll_write_ns) Setting CONVFMT to %s", val))
        CONVFMT = val
    }

    trace(TRACE_SYMBOL_READ_WRITE, name,
          sprintf("[Symbol Update] %s (lev=%d) := Val '%s'",
                  sprintf("%s::%s%s", ns, name, !emptyp(key) ? TOK_LBRACKET key TOK_RBRACKET : EMPTY),
                  level, val))
    return symtab[ns, name, key, level, "symval"] = val
}


function sym_ll_incr_ns(ns, name, key, level, incr)
{
    if (incr == EMPTY) incr = 1
    if (level == EMPTY)
        panic("(sym_ll_incr_ns) LEVEL must not be empty")
    if (ns == EMPTY)
        panic("(sym_ll_incr_ns) NS must not be empty")
    if (sys_in("__DBG__", "sym") &&
        sys_read("__DBG__", "sym") >= 5 &&
        !nam_system_p(name))
        print_debugfile(sprintf("m2debug:(sym_ll_incr_ns) symtab[%s, \"%s\", \"%s\", %d, \"symval\"] += %d",
                             ns, name, key, level, incr))
    return symtab[ns, name, key, level, "symval"] += incr
}


function sys_in(name,  key)
{
    return sym_ll_in_ns(M2_SYSNS, name, key, ROOT_LEVEL)
}

function sys_read(name,  key)
{
    return sym_ll_read_ns(M2_SYSNS, name, key, ROOT_LEVEL)
}

function sys_write(name, val)
{
    return sym_ll_write_ns(M2_SYSNS, name, NOKEY, ROOT_LEVEL, val)
}

function sys_incr(name, incr)
{
    return sym_ll_incr_ns(M2_SYSNS, name, NOKEY, ROOT_LEVEL, incr)
}


# NB - *Caller* is responsible for checking   integerp(idx) and
#               1 <= idx <= lis count
function lis__ll_incr_ns(ns, lis, idx, level, incr,
                         agg_block, count, val)
{
    if (incr == EMPTY) incr = 1
    if (level == EMPTY)
        panic("(lis__ll_incr) LEVEL must not be empty")

    if (sys_in("__DBG__", "sym") &&
        sys_read("__DBG__", "sym") >= 5 &&
        !nam_system_p(lis))
        print_debugfile(sprintf("m2debug:(lis__ll_incr) List %s[%s] (level %d) += %d",
                                lis, idx, level, incr))

    if (! ((ns, lis, NOKEY, level, "agg_block") in symtab))
        panic(sprintf("(lis__ll_incr) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                      ns, lis, NOKEY, level))

    agg_block = symtab[ns, lis, NOKEY, level, "agg_block"]
    count = blktab[agg_block, 0, "count"]+0
    if (idx < 1 || idx > count)
        error(sprintf("(lis__ll_incr) Index out of bounds"))

    # Make sure slot holds text, which it pretty much has to
    if (blk_ll_slot_type(agg_block, idx) != OBJ_TEXT)
        panic(sprintf("(lis__ll_incr) Block # %d slot %d is not OBJ_TEXT",
                      agg_block, idx))

    val = blk_ll_slot_value(agg_block, idx)
    if (! integerp(val) && !floatp(val))
        error(sprintf("(lis__ll_incr) Value '%s' is not numeric and cannot be incremented"))

    val = 0 + val + incr
    blk_ll_write(agg_block, idx, OBJ_TEXT, val)
    return val
}


function sym_fetch(sym,
                   info)
{
    dbg__print("sym", 5, sprintf("(sym_fetch) START; sym='%s'", sym))
    if (nam__scan(sym, info) == ERROR)
        error("(sym_fetch) Scan error, '" sym "'")
    nam__lookup(info)
    return syminfo_fetch(info)
}


function syminfo_fetch(syminfo,
                       sym, nparts, info, iname, ikey, icode, level, val, good,
                       idxable, agg_block, count, has_bracket, ins)
{
    sym = info__get(syminfo, "name")
    dbg__print("sym", 5, sprintf("(syminfo_fetch) START; sym='%s'", sym))

    iname = info__get(syminfo, "name")
    ikey  = info__get(syminfo, "key")
    level = info__get(syminfo, "level")
    ins   = info__get(syminfo, "ns")
    if (level == NAME_NOT_FOUND)
        error("(syminfo_fetch) nam__lookup(info) failed")
    if (ins == EMPTY)
        panic("(syminfo_fetch) NS empty (name='" iname "')")

    # Now we know it's a symbol, level & code.  Still need to look in
    # symtab because NAME[KEY] might not be defined.
    icode = info__get(syminfo, "code")
    dbg__print("sym", 5, sprintf("(syminfo_fetch) nam__lookup ok; level=%d, code=%s", level, icode))

    # Sanity checks
    good = FALSE

    # 0. Sequences return their value
    if (info__get(syminfo, "type") == TYPE_SEQUENCE) {
        val = seq_ll_read_ns(ins, iname)
        dbg__print("sym", 2, sprintf("(syminfo_fetch) END sym='%s', level=%d RETURNING %d",
                                     sym, level, val))
        return val
    }

    # 1. Fetching @ARRAY@ without key returns number elements in ARRAY.
    idxable = info__get(syminfo, "idxable") # 'idxable' means Array or List.
    has_bracket = info__get(syminfo, "has_bracket")
    if (idxable == TRUE && has_bracket == FALSE) {
        #val = idx__size(iname, level, icode)
        val = idx__size(syminfo)
        dbg__print("sym", 2, sprintf("(syminfo_fetch) END sym='%s', level=%d RETURNING %d",
                                    sym, level, val))
        return val
    }

    # 2. Error if symbol is not an Array or List but sym has array[key] syntax
    if (idxable == FALSE && has_bracket == TRUE)
        error("(syminfo_fetch) Name is not an Array or List but has array[key] syntax")

    # Now, either both idxable and has_bracket are TRUE
    # or both are FALSE.
    do {
        # 3. Check code for TYPE_SYMBOL
        if (idxable == FALSE &&
            has_bracket == FALSE &&
            flag_1true_p(icode, TYPE_SYMBOL) &&
            emptyp(ikey)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }
        # 4. Check code for TYPE_ARRAY
        if (idxable == TRUE &&
            has_bracket == TRUE &&
            flag_anytrue_p(icode, __base_type[PTYPE_IDXABLE]) &&
            ikey != EMPTY) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        panic(sprintf("(syminfo_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
                      sym, iname, ikey, level, icode))
    } while (FALSE)

    if (flag_1true_p(icode, FLAG_DEFERRED)) {
        #warn("(syminfo_fetch) about to define deferred symbol")
        sym_deferred_define_now(sym)
    }

    if (flag_1true_p(icode, TYPE_LIST)) {
        # Look up block
        if (!integerp(ikey))
            error(sprintf("(syminfo_fetch) Block array indices must be integers"))
        if (! ((ins, iname, NOKEY, level, "agg_block") in symtab))
            panic(sprintf("(syminfo_fetch) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                          ins, iname, NOKEY, level))

        agg_block = symtab[ins, iname, NOKEY, level, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (ikey >= 1 && ikey <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, ikey) != OBJ_TEXT)
                panic(sprintf("(syminfo_fetch) Block # %d slot %d is not OBJ_TEXT", agg_block, ikey))
            val = blk_ll_slot_value(agg_block, ikey)
        } else
            error(sprintf("(syminfo_fetch) Out of bounds"))
    } else {
        # It's a normal symbol
        if (! sym_ll_in_ns(ins, iname, ikey, level))
            error("(syminfo_fetch) Not in symtab: NAME='" iname "', KEY='" ikey "'")
        val = sym_ll_read_ns(ins, iname, ikey, level)
    }

    dbg__print("sym", 2, sprintf("(syminfo_fetch) END sym='%s', level=%d => %s", sym, level, ppf__bool(TRUE)))
    if (flag_1true_p(icode, FLAG_INTEGER))
        return 0 + val
    else if (flag_1true_p(icode, FLAG_NUMERIC))
        return 0.0 + val
    else if (flag_1true_p(icode, FLAG_BOOLEAN))
        return sys_read("__FMT__", to_bool(val)) # !! (0 + val))
    else
        return val
}


function sym_value_or_literal(s,
                              info)
{
    # return (sym_valid_p(s) && sym_defined_p(s)) \
    #     ? sym_fetch(s) : s
    info__create_from_text(s, info)
    return (info__get(info, "type") == TYPE_SYMBOL &&
            info__get(info, "defined")) \
        ? syminfo_fetch(info) : s
}


# XXX Bare bones, no checking yet
function syminfo_increment(info, incr,
                           iname, ikey, ilevel, itype, ins)
{
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

    iname  = info__get(info, "name")
    ikey   = info__get(info, "key")
    ilevel = info__get(info, "level")
    itype  = info__get(info, "type")
    ins    = info__get(info, "ns")

    if (itype == TYPE_LIST)
        lis__ll_incr_ns(ins, iname, ikey, ilevel, incr)
    else if (itype == TYPE_ARRAY || itype == TYPE_SYMBOL)
        sym_ll_incr_ns(ins, iname, ikey, ilevel, incr)
    else if (itype == TYPE_SEQUENCE)
        seq_ll_incr_ns(ins, iname, incr)
    else
        panic("(syminfo_increment) Cannot handle type " ppf__label(itype))
}




# Protected symbols cannot be changed by the user.
# Called by info__get()
function sym_ll_protected(name, code)
{
    if (flag_1true_p(code, FLAG_READONLY))
        return TRUE
    if (flag_1true_p(code, FLAG_WRITABLE))
        return FALSE
    if (flag_1true_p(code, FLAG_SYSTEM) ||
        double_underscores_p(name))
        return TRUE
    return FALSE
}


function sym_definition_ppf(sym,
                            definition)
{
    definition = sym_fetch(sym)
    if (emptyp(definition))
        return "@set "     sym
    else if (index(definition, TOK_NEWLINE) == NOT_FOUND)
        return "@define "  sym TOK_TAB definition
    else
        return "@longdef " sym TOK_NEWLINE \
               definition      TOK_NEWLINE \
               "@endlongdef"
}


function sym_true_p(sym,
                    val)
{
    return (sym_defined_p(sym) &&
            ((val = sym_fetch(sym)) != FALSE &&
              val                   != EMPTY))
}


# Throw an error if symbol is NOT defined
function assert_sym_defined(sym, caller,    s)
{
    if (caller == EMPTY)
        panic("(assert_sym_defined) Empty caller!")
    if (! sym_defined_p(sym))
        error(sprintf("%s: Symbol '%s' not defined%s",
                      caller, sym, VERBOSE() ? " [(assert_sym_defined)]" : ""))
}


# function syminfo_okay_to_define_p(syminfo,
#                                   name, code, type)
# {
#     #print_stderr("Looking at '" syminfo["name"] (!emptyp(syminfo["key"]) ? TOK_LBRACKET syminfo["key"] TOK_RBRACKET : "") "'")
#     # I believe this flag trumps all other computations
#     code = info__get(syminfo, "code")
#     if (flag_1true_p(code, FLAG_WRITABLE))
#         return TRUE
#
#     name = info__get(syminfo, "name")
#     type = info__get(syminfo, "type")
#     if (type == TYPE_SYMBOL || type == TYPE_ARRAY || type == PTYPE_UNDEF || type == TYPE_SEQUENCE)
#         return info__get(syminfo, "lexvalid") &&
#                !double_underscores_p(name) &&
#                flag_allfalse_p(code, FLAG_READONLY FLAG_SYSTEM)
#     else {
#         panic("(syminfo_okay_to_define_p) Cannot handle type '" type "'")
#         return FALSE
#     }
#
# What follows is from assert_sym_okay_to_define():
#     # assert_sym_valid_name(name)
#     # assert_sym_unprotected(name)
#
#     # if (nam_ll_in!(name, curr_level()) &&
#     #     flag_alltrue_p((code = nam_ll_read(name, curr_level())), TYPE_SYMBOL) &&
#     #     flag_allfalse_p(code, FLAG_READONLY))
#     #     return TRUE
#     # if (nam_ll_in!(name, curr_level())) return FALSE
#
#     # if (nam_ll_in!(name, ROOT_LEVEL) &&
#     #     flag_alltrue_p((code = nam_ll_read(name, ROOT_LEVEL)), TYPE_SYMBOL) &&
#     #     flag_allfalse_p(code, FLAG_READONLY))
#     #     return TRUE
#     # if (nam_ll_in!(name, ROOT_LEVEL)) return FALSE
#
#     # # Can't shadow a system symbol
#     # if (nam_ll_in!(name, ROOT_LEVEL) &&
#     #     flag_alltrue_p((code = nam_ll_read(name, ROOT_LEVEL)), TYPE_SYMBOL FLAG_SYSTEM))
#     #     return FALSE
#
#     # if (double_underscores_p(name))
#     #     return FALSE
#
#     # You can redefine a symbol, but not a command, function, or sequence
#     # if (!name_available_in_all_p(name, TYPE_USER TYPE_FUNCTION TYPE_SEQUENCE))
#     #     error("Name '" name "' not available:" $0)
#     return TRUE
# }


# Throw an error if the symbol name is NOT valid
function assert_sym_valid_name(sym, caller)
{
    if (caller == EMPTY)
        panic("(assert_sym_valid_name) Empty caller!")
    if (! sym_valid_p(sym))
        error("Symbol '" sym "' not valid:" $0)
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
                       stream, divblk)
{
    dbg__print("xeq", 1, sprintf("(execute__text) START; text='%s'", text))
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL)) {
        dbg__print("xeq", 3, "(execute__text) NOP !MODE_XEQ_NORMAL")
        return
    }

    stream = DIVNUM()
    if (stream < 0)
        return

    if (curr_atmode() == MODE_AT_PROCESS) {
        dbg__print("xeq", 5, sprintf("(execute__text) Calling dosubs('%s')", text))
        text = dosubs(text)
    }

    # Currently, ship_out() is the only caller of execute_text() -- and
    # it ensures that dstblk is == TERMINAL.  So at the moment, this
    # check can't happen.  However, in the future some other caller may
    # call execute_text() directly.  In this case, we may want to do
    # this section first, *BEFORE* dosubs().
    if (stream > TERMINAL) {
        divblk = stream_block(stream)
        dbg__print("ship_out", 1, sprintf("(execute__text) END Appending text to stream %d (block %d)",
                                          stream, divblk))
        blk_append(divblk, OBJ_TEXT, text)
        return
    }

    if (flag_1true_p(__m2_config_flags, MODE_TEXT_PRINT)) {
        printf("%s\n", text)
        flush_stdout(SYNC_LINE)
    } else if (flag_1true_p(__m2_config_flags, MODE_TEXT_STRING))
        __textbuf = sprintf("%s%s\n", __textbuf, text)
    else
        panic("(execute__text) Bad MODE_TEXT_*")
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


function bool__known_predicate_p(str,
                                 retval)
{
    return str ~ /^(canrun|defined|exists)\(/
}


function bool__tokenize_string(s,
                               slen, i, oldi, c, pcnt, name,
                               lparen, pred)
{
    dbg__print("bool", 6, "(bool__tokenize_string) START")
    slen = length(s)
    i = 1
    __bnf = 0
    c = substr(s, i, 1)
    dbg__print("bool", 5, sprintf("(bool__tokenize_string) START; slen=%d, i=%d, c=%s", slen, i, c))

    while (TRUE) {
        if (i > slen || c == "")
            break
        while (c == TOK_SPACE || c == TOK_TAB)   # skip whitespace
            c = substr(s, ++i, 1)

        if (c == TOK_NOT ||
            c == TOK_LPAREN ||
            c == TOK_RPAREN) {
            dbg__print("bool", 7, sprintf("(bool__tokenize_string) Found '%s' at i=%d", c, i))
            __btoken[++__bnf] = c
            c = substr(s, ++i, 1)
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg__print("bool", 5, sprintf("(bool__tokenize_string) %s __btoken[%d]=TOK_{NOT|LPAREN|RPAREN}, i now %d", __btoken[__bnf], __bnf, i))

        } else if (substr(s, i, 2) == "&&") {
            dbg__print("bool", 7, sprintf("(bool__tokenize_string) Found '&&' at i=%d", i))
            __btoken[++__bnf] = TOK_AND
            i += 2
            c = substr(s, i, 1)
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg__print("bool", 5, sprintf("(bool__tokenize_string) && __btoken[%d]=TOK_AND, i now %d", __bnf, i))

        } else if (substr(s, i, 2) == "||") {
            dbg__print("bool", 7, sprintf("(bool__tokenize_string) Found '||' at i=%d", i))
            __btoken[++__bnf] = TOK_OR
            i += 2
            c = substr(s, i, 1)
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg__print("bool", 5, sprintf("(bool__tokenize_string) || __btoken[%d]=TOK_OR, i now %d", __bnf, i))

        } else if (bool__known_predicate_p(substr(s, i))) {
            lparen = index(substr(s, i), TOK_LPAREN)
            pred = substr(s, i, lparen - 1)
            dbg__print("bool", 7, sprintf("(bool__tokenize_string) Found known predicate '%s' at i=%d",
                                          pred, i))
            c = substr(s, (oldi = i += lparen), 1)
            #print_stderr("top, i=" i ", c=" c)
            while (c != TOK_RPAREN && i <= slen) {
                c = substr(s, ++i, 1)
                #print_stderr("looping, i=" i ", c=" c)
            }
            if (substr(s, i, 1) != TOK_RPAREN)
                # error(sprintf("%s(): No closing paren; __btoken[%d]='%s', i now %d", pred, __bnf, __btoken[__bnf], i))
                error(sprintf("%s(): No closing parenthesis", pred))
            name = substr(s, oldi, i-oldi)
            #print_stderr("canrun parse name='" name "'")
            if (emptyp(name))
                error(sprintf("%s(): Argument cannot be empty", pred))
            __btoken[++__bnf] = __predicate_token[pred]
            __btoken[++__bnf] = dosubs(name)
            c = substr(s, ++i, 1)       # char after closing paren
            while (c == TOK_SPACE || c == TOK_TAB)
                c = substr(s, ++i, 1)
            dbg__print("bool", 5, sprintf("(bool__tokenize_string) %s() __btoken[%d]='%s', i now %d",
                                          pred, __bnf, __btoken[__bnf], i))

        } else {                # OTHER
            pcnt = 0
            oldi = i            # start pos
            dbg__print("bool", 7, sprintf("(bool__tokenize_string) Starting to scan other at i=%d, s='%s'", i, substr(s, i)))
            while (TRUE) {
                if (i > slen || c == "")
                    break
                if (c == TOK_LPAREN) {
                    pcnt++
                    c = substr(s, ++i, 1) # next char
                    dbg__print("bool", 7, "(bool__tokenize_string) other: '(', pcnt now " pcnt ", at i=" i)
                } else if (c == TOK_RPAREN) {
                    if (pcnt > 0) {
                        pcnt--
                        dbg__print("bool", 7, "(bool__tokenize_string) other: ')', but pcnt was " pcnt+1 " so just decr; pcnt now " pcnt "; at i=" i)
                    } else {
                        dbg__print("bool", 7, "(bool__tokenize_string) other: '(', all parens closed (pcnt=" pcnt "), we're done, at i=" i)
                        break
                    }
                } else if (substr(s, i, 2) == "&&" || substr(s, i, 2) == "||") {
                    # && and || cannot appear in a calc3 expression -
                    # they must separate boolean clauses here.
                    dbg__print("bool", 7, "(bool__tokenize_string) other: found '" substr(s, i, 2) "' at i=" i)
                    c = substr(s, i, 1)
                    break
                } else {
                    c = substr(s, ++i, 1) # next char
                    dbg__print("bool", 8, "(bool__tokenize_string) other: continuing, i=" i "...")
                }
            }
            __btoken[++__bnf] = rtrim(substr(s, oldi, i-oldi))
            while (c == TOK_SPACE || c == TOK_TAB)   c = substr(s, ++i, 1) # skip ws
            dbg__print("bool", 5, sprintf("(bool__tokenize_string) other __btoken[%d]='%s', i now %d", __bnf, __btoken[__bnf], i))
        }
    }
    dbg__print("bool", 7, "(bool__tokenize_string) DONE; __bnf=" __bnf)
    if (dbg__sys_level_p("bool", 3))
        for (i = 1; i <= __bnf; i++)
            print_debugfile(sprintf("m2debug:(bool__tokenize_string) __btoken[%d]='%s'", i, __btoken[i]))
}


function bool__scan_expr(    e, f, r)           # term   | term || term
{
    dbg__print("bool", 5, sprintf("(bool__scan_expr) __bf=%d, __btoken[]='%s', e='%s'", __bf, __btoken[__bf], e))
    e = bool__scan_term()
    if (e == ERROR) {
        warn("(bool__scan_expr) Initial e returned ERROR, propagating")
        return e
    }
    dbg__print("bool", 7, sprintf("(bool__scan_expr) After bool__scan_term, __bf=%d, __btoken[%d]='%s', e='%s'(%s)", __bf, __bf, __btoken[__bf], e, ppf__bool(e)))
    while (__btoken[__bf] == TOK_OR) {
        __bf++
        if (to_bool(e) == TRUE) {
            dbg__print("bool", 5, sprintf("(bool__scan_expr) TOK_OR, e known True so short-circuit, RETURNING True"))
            return TRUE
        }
        f = bool__scan_term()
        r = e || f
        dbg__print("bool", 5, sprintf("(bool__scan_expr) Found TOK_OR (__bf now %d), e'%s' || f'%s' => %s", __bf, e, f, ppf__bool(r)))
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
    dbg__print("bool", 5, sprintf("(bool__scan_term) After bool__scan_factor, __bf=%d, __btoken[]='%s', e='%s'(%s)", __bf, __btoken[__bf], e, ppf__bool(e)))
    while (__btoken[__bf] == TOK_AND) {
        __bf++
        dbg__print("bool", 7, sprintf("(bool__scan_term) Found TOK_AND, e'%s' (=> %s); f not eval yet", e, ppf__bool(e)))
        if (to_bool(e) == FALSE) {
            dbg__print("bool", 5, sprintf("(bool__scan_term) TOK_AND, e known False so short-circuit, RETURNING False"))
            return FALSE
        }
        f = bool__scan_factor()
        if (f == ERROR) {
            warn("(bool__scan_term) f returned ERROR, propagating")
            return f
        }
        r = e && f
        dbg__print("bool", 5, sprintf("(bool__scan_term) TOK_AND, e'%s' && f'%s' => %s", e, f, ppf__bool(r)))
        e = r
    }
    return e
}


function bool__scan_factor(    e, r,         # ! factor | variable | ( expression )
                               name, rc)
{
    dbg__print("bool", 5, sprintf("(bool__scan_factor) __bf=%d, __btoken[]='%s', e='%s'", __bf, __btoken[__bf], e))
    if (__btoken[__bf] ~ /^[01]$/) {
        dbg__print("bool", 5, "(bool__scan_factor) Match regexp 1")
        return 0+__btoken[__bf++]

    } else if (__btoken[__bf] == TOK_LPAREN) {
        __bf++
        e = bool__scan_expr()
        if (__btoken[__bf++] != TOK_RPAREN)
            error("(bool__scan_factor) Missing ')' at '" __btoken[__bf]) "'"
        dbg__print("bool", 5, "(bool__scan_factor) Found parens, RETURNING " ppf__bool(e))
        return e

    } else if (__btoken[__bf] == TOK_NOT) {
        __bf++
        e = bool__scan_factor()
        if (e == ERROR) {
            dbg__print("bool", 5, "(bool__scan_factor) NOT: scan_factor => ERROR, propagating")
            return ERROR
        } else {
            dbg__print("bool", 5, "(bool__scan_factor) NOT: Just read " e ", so RETURNING " ppf__bool(!e))
            return !e
        }

    } else if (__btoken[__bf] == TOK_CANRUN_P) {
        name = __btoken[++__bf]
        if (emptyp(name)) return ERROR
        if (secure_level() >= SEC_SECURE)
            security_violation("canrun(): Forbidden")
        # Check via "sh -c 'command -v ARG'"
        r = exec_prog_cmdline("sh", sprintf("-c 'command -v %s'", name)) == EX_OK
        dbg__print("bool", 5, "(bool__scan_factor) CANRUN; name='" name "', RETURNING " ppf__bool(r))
        __bf++
        return r

    } else if (__btoken[__bf] == TOK_DEFINED_P) {
        name = __btoken[++__bf]
        if (emptyp(name)) return ERROR
        assert_sym_valid_name(name, "defined()_B")
        if (sym_deferred_p(name))
            sym_deferred_define_now(name)
        r = sym_defined_p(name)
        dbg__print("bool", 5, "(bool__scan_factor) DEFINED; name='" name "', RETURNING " ppf__bool(r))
        __bf++
        return r

    } else if (__btoken[__bf] == TOK_EXISTS_P) {
        name = __btoken[++__bf]
        if (emptyp(name)) return ERROR
        r = path_exists_p(name)
        dbg__print("bool", 5, "(bool__scan_factor) EXISTS; name='" name "', RETURNING " ppf__bool(r))
        __bf++
        return r

    } else if (__btoken[__bf] ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/) { # symbol?
        name = __btoken[__bf]
        if (sym_deferred_p(name))
            sym_deferred_define_now(name)
        r = sym_true_p(name)
        dbg__print("bool", 5, "(bool__scan_factor) SYM; just read '" __btoken[__bf] "', so RETURNING " ppf__bool(r))
        __bf++
        return r

    } else {
        # Boolean evaluation would normally fail here, but we'll pass it along to 'evaluate_condition'
        dbg__print("bool", 5, sprintf("(bool__scan_factor) Did not match __bf=%d, __btoken[]='%s', e='%s'", __bf, __btoken[__bf], e))
        r = evaluate_condition(__btoken[__bf], FALSE)
        if (r == ERROR)
            warn("(bool__scan_factor) Evaluate_condition('" __btoken[__bf] "') returned ERROR")
        else
            dbg__print("bool", 5, "(bool__scan_factor) evaluate_condition('" __btoken[__bf] "') returned " ppf__bool(r))
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
# @array                NAME
function xeq_cmd__array(cmd, cmdline,
                        me, name, info, ins)
{
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    name = $1
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_CREATE, TYPE_ARRAY, info, ins, curr_level(), me, TRUE)
    nam_ll_write_ns(ins, info__get(info, "name"), curr_level(), TYPE_ARRAY)
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
function xeq_cmd__break(cmd, cmdline,
                        level, block, block_type)
{
    # Logical check
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL))
        panic("(xeq_cmd__break) !MODE_XEQ_NORMAL")

    # Set MODE_XEQ_BREAK flag
    __m2_config_flags = flag_set_clear(__m2_config_flags, MODE_XEQ_BREAK, MODE_XEQ_NORMAL)
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
    dbg__print("case", 3, sprintf("(parse__case) START dstblk=%d, $0='%s'", curr_dstblk(), $0))

    raise_level()

    # Create a new block for case_block
    case_block = blk_new(BLK_CASE)
    dbg__print("case", 5, "(parse__case) New block # " case_block " type " ppf__label(blk_type(case_block)))
    preamble_block = blk_new(BLK_AGG)
    dbg__print("case", 5, "(parse__case) New block # " case_block " type " ppf__label(blk_type(preamble_block)))

    $1 = ""
    blktab[case_block, 0, "casevar"]        = $2
    blktab[case_block, 0, "preamble_block"] = preamble_block
    blktab[case_block, 0, "seen_otherwise"] = FALSE
    blktab[case_block, 0, "dstblk"]         = preamble_block
    blktab[case_block, 0, "blkvalid"]          = FALSE
    dbg__print_block("case", 7, case_block, "(parse__case) case_block")
    stk_push(__parse_stack, case_block) # Push it on to the parse_stack

    dbg__print("case", 5, "(parse__case) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcase
    dbg__print("case", 5, "(parse__case) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@case] Parse error")

    dbg__print("case", 5, "(parse__case) END; => " case_block)
    return case_block
}


function parse__of(                case_block, of_block, of_val)
{
    dbg__print("case", 3, sprintf("(parse__of) START dstblk=%d, mode=%s, $0='%s'",
                                 curr_dstblk(), ppf__label(curr_atmode()), $0))
    if (check__parse_stack(BLK_CASE) != ERR_OKAY)
        error("[@of] Parse error; " __m2_msg)
    case_block = stk_top(__parse_stack)

    lower_level()           # trigger name/symbol purge
    raise_level()

    # Create a new block for the new Of branch and make it current
    of_block = blk_new(BLK_AGG)
    sub(/^@__m2__::of[ \t]+/, "")
    of_val = $0
    if ((case_block, of_val, "of_block") in blktab)
        error("(parse__of) Duplicate '@of' values not allowed:@of " $0)

    blktab[case_block, of_val, "of_block"] = of_block
    blktab[case_block, 0, "dstblk"]  = of_block
    return of_block
}


function parse__otherwise(                case_block, otherwise_block)
{
    dbg__print("case", 3, sprintf("(parse__otherwise) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_CASE) != ERR_OKAY)
        error("[@otherwise] Parse error; " __m2_msg)
    case_block = stk_top(__parse_stack)

    # Check if already seen @else
    if (blktab[case_block, 0, "seen_otherwise"] == TRUE)
        error("(parse__otherwise) Cannot have more than one @otherwise")

    lower_level()           # trigger name/symbol purge
    raise_level()

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
    dbg__print("case", 3, sprintf("(parse__endcase) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_CASE) != ERR_OKAY)
        error("[@endcase] Parse error; " __m2_msg)

    case_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endcase) popped parse_stack => " case_block)
    blktab[case_block, 0, "blkvalid"] = TRUE
    lower_level()
    return case_block
}


function xeq__BLK_CASE(case_block,
                       block_type, casevar, caseval, preamble_block)
{
    block_type = blk_type(case_block)
    dbg__print("case", 3, sprintf("(xeq__BLK_CASE) START dstblk=%d, case_block=%d, type=%s",
                                 curr_dstblk(), case_block, ppf__label(block_type)))

    dbg__print_block("case", 7, case_block, "(xeq__BLK_CASE) case_block")
    if ((blk_type(case_block) != BLK_CASE) ||  \
        (blktab[case_block, 0, "blkvalid"] != TRUE))
        panic("(xeq__BLK_CASE) Bad case_block config")

    # Check if the case variable value matches any @of values
    casevar = blktab[case_block, 0, "casevar"]
    dbg__print("case", 5, sprintf("(xeq__BLK_CASE) casevar '%s'", casevar))
    assert_sym_defined(casevar, "@case")
    caseval = sym_fetch(casevar)
    dbg__print("case", 5, sprintf("(xeq__BLK_CASE) caseval '%s'", caseval))

    if ((case_block, caseval, "of_block") in blktab) {
        # See if there's a preamble which is non-empty.  Preambles get
        # their own execution levels.
        preamble_block = blktab[case_block, 0, "preamble_block"]
        if (blktab[preamble_block, 0, "count"]+0 > 0) {
            dbg__print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                         blktab[case_block, 0, "preamble_block"]))
            raise_level()
            execute__block(blktab[case_block, 0, "preamble_block"])
            lower_level()
            dbg__print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        }

        # The @of branch gets a new level
        raise_level()
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                     blktab[case_block, caseval, "of_block"]))
        execute__block(blktab[case_block, caseval, "of_block"])
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        lower_level()
    } else if (blktab[case_block, 0, "seen_otherwise"] == TRUE) {
        # NB - @otherwise branches DO NOT execute the preamble (if any)
        raise_level()
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                     blktab[case_block, 0, "otherwise_block"]))
        execute__block(blktab[case_block, 0, "otherwise_block"])
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        lower_level()
    }

    dbg__print("case", 3, sprintf("(xeq__BLK_CASE) END"))
}


function ppf__case(case_block,
                   buf, i, caseval, f, b)
{
    buf = "@case " blktab[case_block, 0, "casevar"] TOK_NEWLINE
    buf = buf ppf__block(blktab[case_block, 0, "preamble_block"]) TOK_NEWLINE
    for (b in blktab) {
        split(b, f, SUBSEP)
        if (f[BFN_BNUM] == case_block && f[BFN_TAG] == "of_block")
            buf = buf "@of " f[BFN_SLOT] TOK_NEWLINE \
                ppf__block(blktab[case_block, f[BFN_SLOT], "of_block"]) TOK_NEWLINE
    }
    if (blktab[case_block, 0, "seen_otherwise"])
        buf = buf "@otherwise" TOK_NEWLINE \
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
function xeq_cmd__cleardivert(cmd, cmdline,
                              me, i, stream)
{
    $0 = cmdline
    me = "@" cmd
    dbg__print("divert", 2, sprintf("(xeq_cmd__cleardivert) START dstblk=%d, cmdline='%s'",
                                    curr_dstblk(), cmdline))
    dbg__print_block("ship_out", 8, curr_dstblk(), "(xeq_cmd__cleardivert) curr_dstblk()")
    if (NF == 0)
        cleardivert_all()
    else {
        i = 0
        while (++i <= NF) {
            stream = dosubs($i)
            if (!integerp(stream))
                error(sprintf("%s: Value '%s' must be numeric", me, stream))
            dbg__print("divert", 5, sprintf("(xeq_cmd__cleardivert) CALLING cleardivert(%d)", stream))
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
function xeq_cmd__continue(cmd, cmdline)
{
    # Logical check
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL))
        panic("(xeq_cmd__continue) !MODE_XEQ_NORMAL")

    # Set MODE_XEQ_CONTINUE flag
    __m2_config_flags = flag_set_clear(__m2_config_flags, MODE_XEQ_CONTINUE,
                                       MODE_XEQ_NORMAL)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D A T A
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @data         LIS
function xeq_cmd__data(cmd, cmdline,
                       me, save_line, save_lineno, agg_block, readstat,
                       lis, info, key, level, ins)
{
    me = "@" cmd
    dbg__print("parse", 5, sprintf("(xeq_cmd__data) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error(me ": Bad parameters")

    lis = $1
    save_line = $0
    save_lineno = LINE()

    level = info__create_from_text(lis, info)
    ins   = info__get(info, "ns")
    info__gate(OP_UPDATE, TYPE_LIST, info, ins, curr_level(), me, TRUE)
    lis_clear(ins, lis, level)

    # create a new Agg block
    agg_block = blk_new(BLK_AGG)
    dbg__print("parse", 5, sprintf("(xeq_cmd__data) symtab[%s, '%s','%s',%d,'agg_block'] = %d",
                                 ins, lis, NOKEY, level, agg_block))
    symtab[ins, lis, NOKEY, level, "agg_block"] = agg_block
    blktab[agg_block, 0, "dstblk"] = agg_block

    dbg__print("parse", 5, "(xeq_cmd__data) CALLING read_lines_until()")
    readstat = read_lines_until("^@(enddata|eod)", agg_block)
    dbg__print("parse", 5, "(xeq_cmd__data) RETURNED FROM read_lines_until() => " ppf__bool(readstat))
    if (readstat != TRUE)
        error("@data: Pattern '@enddata' not found:" save_line, "", save_lineno)

    dbg__print("parse", 5, "(xeq_cmd__data) END")
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
# @set
function xeq_cmd__define(cmd, cmdline,
                         me, name, append_flag, nop_if_defined, error_if_defined,
                         info, info2, level, ok_update, ok_create, agg_block, ins)
{
    me = "@" cmd
    $0 = cmdline
    dbg__print("xeq", 2, sprintf("(xeq_cmd__define) START cmdline='%s'",
                                  cmdline))
    if (NF == 0)
        error(me ": Bad parameters")
    append_flag = (cmd == "append")
    nop_if_defined = (cmd == "default")
    error_if_defined = (cmd == "initialize")

    name = $1
# OLD
    # assert_sym_okay_to_define(sym)
    # if (sym_defined_p(sym)) {
    #     if (nop_if_defined)
    #         return
    #     if (error_if_defined)
    #         error("Symbol '" sym "' already defined:" $0)
    # }
    #
    # #sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")
    # sub(/^[ \t]*[^ \t]+[ \t]*/, "")
    # if ($0 == EMPTY) $0 = "1"
    # # XXX No checking, dangerous!
    # sym_store(sym, append_flag ? sym_fetch(sym) $0 \
    #                            : $0)

#NEW:
    # if ((level = info__create_from_text(name, info)) == ERR_SCAN_INVALID_NAME)
    #     error(sprintf("%s: Invalid name '%s'", me, name))
    # if (syminfo_defined_p(info)) {
    #     if (nop_if_defined)
    #         return
    #     if (error_if_defined)
    #         error("Symbol '" name "' already defined:" $0)
    # }

#SO FRESH:
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    ok_update = info__gate(OP_UPDATE, PTYPE_SCALAR, info, ins, curr_level(), me, FALSE)
    if (ok_update) {
        dbg__print("gate", 5, "(@DEFINE) Symbol '" name "' update OK...")
    } else {
        dbg__print("gate", 7, "(xeq_cmd__define) gate(update) failed: " info__get(info, "errtext"))

        info__create_from_text(name, info2)
        ok_create = info__gate(OP_CREATE, PTYPE_SCALAR, info2, ins, curr_level(), me, FALSE)
        if (ok_create) {
            dbg__print("gate", 5, "(@DEFINE) Symbol '" name "' create OK...")
        } else {
            dbg__print("gate", 7, "(xeq_cmd__define) gate(create) failed: " info__get(info2, "errtext"))
            if (info__get(info2, "errorp"))
                error(sprintf("%s: %s", me, info__get(info2, "errtext")))
            panic("(@DEFINE) Could not update or create Symbol, and no error")
        }
    }

    #if (syminfo_defined_p(info)) {
    level = info__get(info, "level")
    if (level != NAME_NOT_FOUND) {
        if (nop_if_defined)
            return
        if (error_if_defined)
            error(sprintf("%s: Symbol '%s' already defined", me, name))
    }

    sub(/^[ \t]*[^ \t]+[ \t]*/, "")
    if (append_flag &&
        info__get(info, "type") == TYPE_LIST &&
        info__get(info, "has_bracket") == FALSE) {
        if ($0 == EMPTY)
            error(sprintf("%s: Bad parameters", me))
        agg_block = symtab[ins, name, NOKEY, level, "agg_block"]
        blk_append(agg_block, OBJ_TEXT, $0)
    } else {
        if ($0 == EMPTY && cmd != "set")
            $0 = "1"
        syminfo_store(info, append_flag ? syminfo_fetch(info) $0 : $0)
    }
    dbg__print("xeq", 2, "(xeq_cmd__define) END")
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
function xeq_cmd__divert(cmd, cmdline,
                         new_stream, me)
{
    me = "@" cmd
    $0 = cmdline
    dbg__print("divert", 2, sprintf("(xeq_cmd__divert) START dstblk=%d, NF=%d, cmdline='%s'",
                                   curr_dstblk(), NF, cmdline))
    new_stream = (NF == 0) ? "0" : dosubs($1)
    if (!integerp(new_stream))
        return

    new_stream = int(new_stream)
    # stk_pop(__stream_stack)
    # stk_push(__stream_stack, new_stream) # automagically sets __DIVNUM__
    stk_replace_top(__stream_stack, new_stream) # sets __DIVNUM__
    dbg__print("divert", 2, sprintf("(xeq_cmd__divert) END; __DIVNUM__ now %d", new_stream))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D I V P U S H
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#
#*****************************************************************************
# @divpush              N
function xeq_cmd__divpush(cmd, cmdline,
                          new_stream, me)
{
    me = "@" cmd
    $0 = cmdline
    if (NF != 1)
        error(me ": Bad parameters")
    new_stream = dosubs($1)
    if (!integerp(new_stream))
        error(me ": Stream '" new_stream "' not valid")

    stk_push(__stream_stack, int(new_stream))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D I V P O P
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#
#*****************************************************************************
# @divpop
function xeq_cmd__divpop(cmd, cmdline,
                         new_stream, me)
{
    me = "@" cmd
    $0 = cmdline
    if (NF != 0)
        error(me ": Bad parameters")
    if (stk_depth(__stream_stack) == 1)
        error(me ": No stream")
    stk_pop(__stream_stack)
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
function xeq_cmd__dump(cmd, cmdline,
                       buf, cnt, definition, dumpfile, i, key, keys, sym_name, all_flag,
                       what, what_type, block_type, blk_label, desc,
                       me)
{
    me = "@" cmd
    all_flag = cmd == "dumpall"
    dumpfile = EMPTY

    $0 = cmdline
    what = (NF == 0) ? "symbols" : tolower($1)
    if (NF > 1) {
        if (secure_level() >= SEC_SECURE)
            security_violation(me ": Dumpfile not allowed")
        $1 = ""
        sub("^[ \t]*", "")
        dumpfile = rm_quotes(dosubs($0))
        dbg__print("sym", 5, sprintf("dumpfile = '%s'", dumpfile))
    }

    if (what ~ /bl(oc)?ks?/) {
        what_type = PTYPE_ANY    # There is no "block" type
        buf = blk_dump_blktab()

    } else if (what ~ /(cmd|command)s?/) {
        what_type = TYPE_USER
        #buf = dump__names(all_flag ? PTYPE_ANY : curr_ns(), what_type, all_flag)
        buf = dump__commands(all_flag ? PTYPE_ANY : curr_ns(),
                             what_type, all_flag)

    } else if (what ~ /name?s?/) {
        what_type = PTYPE_ANY
        buf = dump__names(all_flag ? PTYPE_ANY : curr_ns(), # all namespaces or current
                                 what_type,                        # all types, no filter
                                 all_flag)                         # include System symbols or not

    } else if (what ~ /seq(uence)?s?/) {
        what_type = TYPE_SEQUENCE
        buf = dump__sequences(all_flag ? PTYPE_ANY : curr_ns(),
                              what_type, all_flag)

    } else if (what ~ /sym(bol)?s?/) {
        what_type = TYPE_SYMBOL
        buf = dump__symbols(all_flag ? PTYPE_ANY : curr_ns(),
                           what_type, all_flag)

    } else if (what ~ /[0-9]+/) {
        what_type = PTYPE_ANY    # There is no "block" type
        dbg__print("sym", 9, "Dump of block # " what)
        if (! ((what, 0, "type") in blktab))
            panic("(xeq_cmd__dump) No 'type' field for block " what)
        block_type = blk_type(what)
        blk_label = ppf__label(block_type)
        dbg__print("sym", 7, "(xeq_cmd__dump) block_type = " block_type)
        desc = ppf__BLK(what)
        buf = sprintf("Block # %d, Type=%s:\n", what, blk_label)
        if (!emptyp(desc))
            buf += ppf__BLK(what)
        if (all_flag)
            buf = buf "\nCode:\n" ppf__block(what)

    } else
        error(me ": Invalid dump argument '" what "'")

    # Format definitions
    if (emptyp(buf)) {
        # I don't usually condone chatty programs, but it seems to me
        # that if the user asks for the symbol table and there's nothing
        # to print, she'd probably like to know.  Perhaps a config file
        # was not read properly...
        warn(sprintf("%s: Empty %s table", me, ppf__flags(what_type)))
    } else if (emptyp(dumpfile))  # No FILE arg provided to @dump command
        print_debugfile(buf)
    else {
        dbg__print("sym", 3, sprintf("(xeq_cmd__dump) %s table dump to '%s'",
                                    ppf__flags(what_type), dumpfile))
        print buf > dumpfile
        close(dumpfile)
    }
}


# Quicksort - from "The AWK Programming Language" p. 161.
function qsort(strategy, A, left, right,    i, lastpos)
{
    if (left >= right)          # Do nothing if array contains
        return                  #   less than two elements
    _swap(A, left, left + int((right-left+1)*rand()))
    lastpos = left              # A[left] is now partition element
    for (i = left+1; i <= right; i++)
        if (strategy == SORT_NATURAL && _nat_less_than(A[i], A[left])      ||
            strategy == SORT_INTEGER && (A[i]+0 < A[left]+0))
          _swap(A, ++lastpos, i)
    _swap(A, left, lastpos)
    qsort(strategy, A, left,   lastpos-1)
    qsort(strategy, A, lastpos+1, right)
}

function _swap(A, i, j,    t)
{
    t = A[i];  A[i] = A[j];  A[j] = t
}

# Class()           = 0
# Class( [A-Za-z] ) = 1
# Class( [0-9]    ) = 2
# Class( .        ) = 3
function _nat_class(c)
{
    c = first(c)
    if (emptyp(c))       return 0
    else if (isalpha(c)) return 1
    else if (isdigit(c)) return 2
    else                 return 3 # Other
}

function _nat_scan_len(s,
                       c, slen, l)
{
    if (emptyp(s))
        return -1               # like RLENGTH when match() fails
    slen = length(s);  l = 1
    c = _nat_class(first(s))
    while (l <= slen && _nat_class(substr(s, l+1, 1)) == c)
        l++
    return l
}

# TRUE if a is "naturally less than" b.
function _nat_less_than(a, b,
                        Ca, Cb, aTk, bTk)
{
    if (a == EMPTY && b == EMPTY)
        return FALSE            # maybe not trigger a useless swap
    Ca = _nat_class(a); Cb = _nat_class(b)
    if (Ca != Cb)
        return Ca < Cb          # return item with lower class

    # At this point:
    # 1. Classes are equal, so the same comparison approach will work
    #    for both operands.  If the classes weren't equal, the above
    #    "if" statement would have returned control by now.
    # 2. *Both* a and b are non-empty, so various length and comparison
    #    functions should behave sanely.  If one *were* empty, then either:
    #    A. Both were empty, in which case topmost "if" applies, or
    #    B. Only one is empty, in which case its class code of 0 would
    #       be unequal to any *other* possible (non-zero) class code.
    #    C. QED
    a_val_len = _nat_scan_len(a);       a_val = substr(a, 1, a_val_len)
    b_val_len = _nat_scan_len(b);       b_val = substr(b, 1, b_val_len)

    # Alphabetical comparison - case insensitive
    if (Ca == 1 && toupper(a_val) != toupper(b_val))
        return toupper(a_val) < toupper(b_val)

    # Numerical comparison - integer only
    else if (Ca == 2 && 0+a_val != 0+b_val)
        return 0+a_val < 0+b_val

    # Other - ASCII order
    else if (Ca == 3 && a_val != b_val)
        return a_val < b_val

    # No relevant difference; check next class.  Parameters are always
    # successively smaller, so recursion must end.
    aTk = substr(a, a_val_len + 1)
    bTk = substr(b, b_val_len + 1)
    if (emptyp(aTk) && emptyp(bTk))
        return "" a_val < "" b_val

    return _nat_less_than(aTk, bTk)
}


# Like ppf__XX functions, last line of multi-line buffer
# *omits* newline.
function dump__symbols(target_namespace, filter_flags, include_sys, # caller names this "all_flag"
                      f, s, code, buf, cond_matched,
                      name, key, level, tag, include_system,
                      ns, keys, cnt, i, blk, count)
{
    if (include_sys)
        filter_flags = flag_set_clear(filter_flags, FLAG_SYSTEM, EMPTY)
    include_system = flag_1true_p(filter_flags, FLAG_SYSTEM)
    dbg__print("sym", 4, "(dump__symbols) BEGIN")
    if (first(filter_flags) != TYPE_SYMBOL)
        panic("(dump__symbols) Bad type " ppf__flags(first(filter_flags)))
    sym_define_all_deferred()

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (s in symtab) {
        split(s, f, SUBSEP)
        ns    = f[SFN_NS   ]    # ; print "ns    =", ns
        name  = f[SFN_NAME ]    # ; print "name  =", name
        key   = f[SFN_KEY  ]    # ; print "key   =", key
        level = f[SFN_LEVEL]    # ; print "level =", level
        tag   = f[SFN_TAG  ]    # ; print "tag   =", tag
        dbg__print("sym", 8, sprintf("(dump__symbtab) [%s,'%s','%s',%d,%s]",
                                     ns, name, key, level, tag))

        code = nam_ll_read_ns(ns, name, level) # name, level
        dbg__print("sym", 7, sprintf("(dump__symbols) name='%s', key='%s', code=%s",
                                    name, key, code))
        if (target_namespace != PTYPE_ANY &&
            target_namespace != ns) {
            # print_debugfile(sprintf("m2debug:(dump__names) ns filter: ns=%s, name=%s, code=%s, filter=%s",
            #                         ns, name, ppf__label(code), ppf__label(filter_flags)))
            continue
        }
        if (!include_system && flag_1true_p(code, FLAG_SYSTEM))
            continue

        if (tag == "agg_block") {
            if (flag_1false_p(code, TYPE_LIST))
                panic("(dump__symbols) Found type 'agg_block' but not a List")
            # It's a block array so insert all the keys.
            blk = symtab[ns, name, key, level, tag]
            count = blktab[blk, 0, "count"]
            #print_stderr("blk=" blk ", count=" count)
            if (count > 0)
                for (i = 1; i <= count; i++) {
                    #print_stderr("Adding keys[" cnt+1 "] = " name TOK_LBRACKET i TOK_RBRACKET)
                    keys[++cnt] = ns TOK_NS_QUAL name TOK_LBRACKET i TOK_RBRACKET
                }
            continue

        } else if (tag == "user_block") {
            # Ignore user commands, even though they are in symtab.
            # Instead, use "@dump cmds" to see user command definition.
            continue

        } else if (tag != "symval")
            panic(sprintf("(dump__symbols) Unexpected tag type: [%s, '%s','%s',%d,%s]",
                          ns, name, key, level, tag))

        # It's a regular symbol so process it
        if ((flag_1true_p(code, TYPE_SYMBOL) && key == EMPTY) ||
            (flag_anytrue_p(code, TYPE_ARRAY TYPE_LIST)  && key != EMPTY))
            keys[++cnt] = ns TOK_NS_QUAL name (key != EMPTY ? TOK_LBRACKET key TOK_RBRACKET : NOKEY)
        else
            panic(sprintf("(dump__symbols) Strange combo: ('%s','%s') code=%s",
                          name, key, code))
    }

    qsort(SORT_NATURAL, keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf sym_definition_ppf(keys[i]) TOK_NEWLINE
    dbg__print("sym", 4, "(dump__symbols) END")
    return chomp(buf)
}


function dump__sequences(target_namespace, type, include_sys,
                         f, n, keys, cnt, code, buf, i,
                         ns, name, level)
{
    dbg__print("seq", 4, "(dump__sequences) BEGIN")
    if (first(type) != TYPE_SEQUENCE)
        panic("(dump__sequences) Bad type " ppf__flags(first(type)))

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    include_sys = TRUE
    for (n in namtab) {
        split(n, f, SUBSEP)
        ns    = f[NFN_NS];      # print_stderr("ns    =" ns)
        name  = f[NFN_NAME];    # print_stderr("name  =" name)
        level = f[NFN_LEVEL];   # print_stderr("level =" level)
        if (0+level == ROOT_LEVEL) {
            if (target_namespace != PTYPE_ANY &&
                ns != target_namespace)
              continue
            code = nam_ll_read_ns(ns, name = f[NFN_NAME], ROOT_LEVEL)

            if (flag_1true_p(code, TYPE_SEQUENCE)) {
                # I don't think there are any system sequences yet...
                # if (!include_sys && flag_1true_p(code, FLAG_SYSTEM))
                #     continue
                # dbg__print("seq", -6, sprintf("(dump__sequences) ns=%s, Adding name='%s', code=%s",
                #                               ns, name, ppf__flags(code)))
                keys[++cnt] = ns TOK_NS_QUAL name
            }
        }
    }

    qsort(SORT_NATURAL, keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf seq_definition_ppf_ns(keys[i]) TOK_NEWLINE
    dbg__print("seq", 4, "(dump__sequences) END")
    return chomp(buf)
}


function dump__commands(target_namespace, type, include_sys,
                      f, s, keys, cnt, code, buf, i)
{
    dbg__print("cmd", 4, "(dump__commands) BEGIN")
    if (first(type) != TYPE_USER)
        panic("(dump__commands) Bad type " ppf__flags(first(type)))

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (s in symtab) {
        split(s, f, SUBSEP)
        # print_debugfile("m2debug:f[1]=" f[1])
        # print_debugfile("m2debug:f[2]=" f[2])
        # print_debugfile("m2debug:f[3]=" f[3])
        # print_debugfile("m2debug:f[4]=" f[4])
        # print_debugfile("m2debug:f[5]=" f[5])
        # print_debugfile("m2debug:value => " symtab[f[1], f[2], f[3], f[4], f[5]a])

        if (f[SFN_TAG] != "user_block") continue      # Q&D
        code = nam_ll_read_ns(f[SFN_NS], f[SFN_NAME], f[SFN_LEVEL])
        dbg__print("cmd", 5, sprintf("(dump__commands) name='%s', code=%s",
                                    f[SFN_NAME], code))
        if (flag_1true_p(code, TYPE_USER)) {
            # # I don't think there are any system sequences yet...
            # if (!include_sys && flag_1true_p(code, FLAG_SYSTEM))
            #     continue
            keys[++cnt] = f[SFN_NAME]
        }
    }

    qsort(SORT_NATURAL, keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf cmd_definition_ppf(keys[i]) TOK_NEWLINE
    dbg__print("cmd", 4, "(dump__commands) END")
    return chomp(buf)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D U M P D E F
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @dumpdef [SYM ...]
# Output format:
#       @<command>  SPACE  <name>  TAB  <stuff includes spaces...>
function xeq_cmd__dumpdef(cmd, cmdline,
                          buf, i)
{
    $0 = cmdline
    if (NF == 0) {
        # BUG  Should use curr_ns() ?
        buf = dump__symbols(M2_NS, TYPE_SYMBOL, FALSE) # normal symbols only
        if (emptyp(buf)) {
            warn("@dumpdef: Empty SYM table")
            return
        }
        buf = buf TOK_NEWLINE
    } else
        for (i = 1; i <= NF; i++)
            buf = buf sym_definition_ppf($i) TOK_NEWLINE

    print_debugfile(chop(buf))
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
# additional formatting.
# @debug only prints its message if debugging is enabled.  Note that
# this prints to debugfile directly and depends on debugging_enabled_p()
# alone, and has nothing to do with any "system" or "levels".  The user
# can control this since __DEBUG__ is an unprotected symbol; merely say:
#       @define __DEBUG__ 1
# and all of a sudden the @debug messages spring to life.
# @debug is purposefully not given access to the various __DBG__
# keys and levels.
#
#       | Cmd      | Format? | Exit? | Notes              |
#       |----------+---------+-------+--------------------|
#       | debug    | Format  | No    | Only if __DEBUG __ |
#       | echo     | Raw     | No    | Same as @errprint  |
#       | error    | Format  | Yes   |                    |
#       | errprint | Raw     | No    | Same as @echo      |
#       | secho    | Raw     | No    | No newline         |
#       | serror   | Raw     | Yes   |                    |
#       | warn     | Format  | No    |                    |
function xeq_cmd__error(cmd, cmdline,
                       m2_will_exit, do_format, do_print, message)
{
    m2_will_exit = (cmd == "error" || cmd == "serror")
    do_format = (cmd == "debug" || cmd == "error" || cmd == "warn")
    do_print  = (cmd != "debug" || debugging_enabled_p())
    message = dosubs(cmdline)
    if (do_format)
        message = format_message(message)
    if (do_print)
        if (cmd == "debug")
            print_debugfile(message)
        else if (cmd == "secho")
            printf "%s", message > STDERR
        else
            print_stderr(message) # adds newline
    if (m2_will_exit) {
        sys_write("__EXIT__", EX_USER_REQUEST)
        end_program(MODE_STREAMS_DISCARD)
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E S Y S C M D
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @esyscmd      CMDLINE ...
function xeq_cmd__esyscmd(cmd, cmdline,
                          rc, shell_cmdline, output_file, getstat, line,
                          agg_block, me)
{
    me = "@" cmd
    dbg__print("cmd", 3, sprintf("(xeq_cmd__esyscmd) START; cmdline='%s'", cmdline))
    if (secure_level() >= SEC_SECURE)
        security_violation(me ": Forbidden")
    output_file = mktemp(tmpdir() "m2EsysO.XXXXXX")
    shell_cmdline = build_prog_cmdline("sh",
                       sprintf("-c '%s' <%s >%s", cmdline, NULL, output_file),
                       MODE_IO_CAPTURE)
    flush_stdout(SYNC_FORCE)
    rc = system(shell_cmdline)
    sys_write("__SYSVAL__", rc)
    agg_block = blk_new(BLK_AGG)

    while (TRUE) {
        getstat = getline line < output_file
        if (getstat == ERROR)
            warn(me ": Error reading file '" output_file "'")
        if (getstat != OKAY)
            break
        blk_append(agg_block, OBJ_TEXT, line)
    }
    close(output_file)
    if ("rm" in PROG)
        exec_prog_cmdline("rm", ("-f " output_file))
    else if (debugging_enabled_p())
        warn(me ": PROG[rm] not defined; '" output_file "' not deleted")

    ship_out(OBJ_BLKNUM, agg_block)
    blk_master_delete(agg_block)

    dbg__print("cmd", 3, sprintf("(xeq_cmd__esyscmd) END; rc=%d", rc))
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
function xeq_cmd__eval(cmd, cmdline)
{
    # $1 = ""
    # sub("^[ \t]*", "")
    # dbg__print("parse", 5, "(xeq_cmd__eval) '" $0 "'")
    # dostring($0)
    dbg__print("parse", 5, "(xeq_cmd__eval) '" cmdline "'")
    dostring(cmdline)
}


function dostring(str,
                  string_block, term2, retval, p)
{
    dbg__print("parse", 5, "(dostring) START str='" str "'")

    # Set up a BLK_STRING parser for str, and the __terminal
    string_block = blk_new(BLK_STRING)
    blktab[string_block, 0, "str"]    = str # was dosubs(str), but that loses if you say:
                                            #   @wrap @syscmd rm @TEMPFILES@
    blktab[string_block, 0, "atmode"] = MODE_AT_PROCESS
    dbg__print("parse", 7, sprintf("(dostring) Pushing string block %d onto source_stack", string_block))
    stk_push(__source_stack, string_block)

    stk_push(__parse_stack, __terminal)
    dbg__print("parse", 5, "(dostring) CALLING parse__string()")
    retval = parse__string()
    dbg__print("parse", 5, "(dostring) RETURNED FROM parse__string()")
    p = stk_pop(__parse_stack) # Pop the terminal parser; parse_string() pops the source stack
    dbg__print("parse", 7, "(dostring) popped parse_stack => " p)
    dbg__print("parse", 5, "(dostring) END => " ppf__bool(retval))
    return retval
}


function parse__string(    str, string_block, pstat, d)
{
    if (stk_empty_p(__source_stack))
        panic("(parse__string) Source stack is empty")
    string_block = stk_top(__source_stack)
    str = blktab[string_block, 0, "str"]

    dbg__print("parse", 2, sprintf("(parse__string) str='%s', dstblk=%d, mode=%s",
                                   str, curr_dstblk(),
                                   ppf__label(blktab[string_block, 0, "atmode"])))

    blktab[string_block, 0, "old.buffer"] = __buffer
    blktab[string_block, 0, "old.ns"]     = curr_ns()
    dbg__print_block("ship_out", 7, string_block, "(parse__string) string_block")

    # Set up new file context
    __buffer = str

    # Read the file and process each line
    dbg__print("parse", 5, "(parse__string) CALLING parse()")
    pstat = parse()
    dbg__print("parse", 5, "(parse__string) RETURNED FROM parse() => " ppf__bool(pstat))

    if (stk_pop(__source_stack) != string_block)
        panic("(parse__string) String block mismatch")
    __buffer = blktab[string_block, 0, "old.buffer"]
    stk_replace_top(__ns_stack, blktab[string_block, 0, "old.ns"])

    dbg__print("parse", 2, sprintf("(parse__string) END '%s' => %s",
                                 str, ppf__bool(pstat)))
    return pstat
}


function ppf__BLK_STRING(blknum)
{
    return sprintf("  str     : '%s'\n"         \
                   "  atmode  : %s",
                   blktab[blknum, 0, "str"],
                   ppf__label(blktab[blknum, 0, "atmode"]))
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
function xeq_cmd__exit(cmd, cmdline,
                       silent, exit_code)
{
    silent = first(cmd) == "s"
    exit_code = sys_read("__EXIT__", NOKEY)
    if (! emptyp(cmdline))
        exit_code = integerp(cmdline) ? cmdline+0 : EX_M2_ERROR

    # For full portability, exit values should be between 0 and 126, inclusive.
    # Negative values, and values of 127 or greater, may not produce
    # consistent results across different operating systems.
    if (exit_code < 0 || exit_code > 126)
        exit_code = EX_M2_ERROR

    sys_write("__EXIT__", exit_code)
    end_program(!silent ? MODE_STREAMS_SHIP_OUT : MODE_STREAMS_DISCARD)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  F I L E D A T A
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @filedata            LIS FILE
# LIS must be known to be an array (regular or block).
# Any existing array entries are deleted before reading file contents.
# Yes, this implies that user code must say
#     @list A
#     @filedata A myfile
# The first is the declaration that creates an entry in the name table.
# The second command performs the block creation and file reading.
function xeq_cmd__filedata(cmd, cmdline,
                           lis, filename, line, getstat, line_cnt, silent, level,
                           nparts, info, code, key,
                           file_block, agg_block, rc, error_text, p,
                           me, ins)
{
    me = "@" cmd
    $0 = cmdline
    dbg__print("xeq", 2, sprintf("(xeq_cmd__filedata) START dstblk=%d, cmd=%s, cmdline='%s'",
                                curr_dstblk(), cmd, cmdline))

    if (NF < 2)
        error(me ": Bad parameters:" cmdline)
    # S variant mutes file errors
    silent = first(cmd) == "s"
    lis = $1
    filename = $2

    level = info__create_from_text(lis, info)
    ins   = info__get(info, "ns")
    info__gate(OP_UPDATE, TYPE_LIST, info, ins, curr_level(), me, TRUE)
    lis_clear(ins, lis, level)

    # create a new Agg block
    #agg_block = blk_new(BLK_AGG)
    # No!  I should use the agg block already allocated for lis.
    agg_block = symtab[ins, lis, NOKEY, level, "agg_block"]

    # key = NOKEY
    # dbg__print("parse", 5, sprintf("(xeq_cmd__filedata) symtab[%s, '%s','%s',%d,'agg_block'] = %d",
    #                              M2_NS, lis, key, level, agg_block))
    # not if this isn't new: symtab[M2_NS, lis, key, level, "agg_block"] = agg_block
    blktab[agg_block, 0, "dstblk"] = agg_block

    # create a new literal file parser
    stk_push(__parse_stack, agg_block)
    file_block = prep_file(filename)
    trace(TRACE_BLOCKS, EMPTY, sprintf("[Block Update] %d %s, filename='%s'",
                                       file_block, "FILE", filename))
    blktab[file_block, 0, "atmode"] = MODE_AT_LITERAL
    # Push file block manually because prep_file doesn't do that
    dbg__print("parse", 7, sprintf("(xeq_cmd__filedata) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)

    dbg__print("parse", 5, "(xeq_cmd__filedata) CALLING parse__file()")
    rc = parse__file(curr_ns())
    dbg__print("parse", 5, "(xeq_cmd__filedata) RETURNED FROM parse__file()")
    # parse__file pops the source stack
    p = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(xeq_cmd__filedata) popped parse_stack => " p)
    if (!rc) {
        if (silent) return
        error_text = me ": File '" filename "' does not exist"
        if (strictp("file"))
            error(error_text)
        else
            warn(error_text)
    }

    dbg__print("xeq", 2, sprintf("(xeq_cmd__filedata) END"))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  F I L E D E F I N E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @filedefine             NAME FILE
function xeq_cmd__filedefine(cmd, cmdline,
                             name, filename, line, val, getstat, silent, info,
                             me, ins)
{
    # We could play games and use fancy file blocks and literal atmode, but we
    # really just want to read in a file and assign its contents to a symbol.
    me = "@" cmd
    $0 = cmdline
    if (NF < 2)
        error(me ": Bad parameters:" $0)
    # S variant mutes file errors, even in strict mode
    silent = first(cmd) == "s"
    name  = $1
    info__create_from_text(name, info)
    if ((ins  = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_CREATE, PTYPE_SCALAR, info, ins, curr_level(), me, TRUE)
    # These contortions because a filename might have embedded spaces
    $1 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))

    val = EMPTY
    while (TRUE) {
        getstat = getline line < filename
        if (getstat == ERROR && !silent)
            warn(me ": Error reading file '" filename "'")
        if (getstat != OKAY)
            break
        # This concatenation becomes quite slow after more than a few
        # dozen lines, which is why @filedata exists.
        val = val line TOK_NEWLINE
    }
    close(filename)
    syminfo_store(info, chomp(val))
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
function parse__for(                  for_block, body_block, pstat, incr, info, nparts, level, cmd, me)
{
    dbg__print("for", 5, sprintf("(parse__for) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))
    cmd = $1
    if (NF < 3)
        error(sprintf("%s: Bad parameters:", cmd, $0))

    raise_level()

    # Create two new blocks: "for_block" for loop control (for_block),
    # and "body_block" for the loop code definition.
    for_block = blk_new(BLK_FOR)
    dbg__print("for", 5, "(parse__for) for_block # " for_block " type " ppf__label(blk_type(for_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("for", 5, "(parse__for) body_block # " body_block " type " ppf__label(blk_type(body_block)))

    blktab[for_block, 0, "body_block"] = body_block
    blktab[for_block, 0, "dstblk"] = body_block
    blktab[for_block, 0, "blkvalid"] = FALSE
    blktab[for_block, 0, "loop_var"] = $2

    if (cmd == "@__m2__::for") {
        dbg__print("for", 9, "(parse__for) Found FOR: " $0)
        blktab[for_block, 0, "loop_type"] = cmd
        blktab[for_block, 0, "loop_start"] = $3
        blktab[for_block, 0, "loop_end"] = $4
        blktab[for_block, 0, "loop_incr"] = incr = NF >= 5 ? $5 : 1
        if (incr == 0)
            error(cmd ": Increment value cannot be zero!")

    } else if (cmd == "@__m2__::foreach") {
        dbg__print("for", 9, "(parse__for) Found FOREACH: " $0)
        if ((nparts = nam__scan($3, info)) != 1)
            error(cmd ": Scan error, " __m2_msg)
        level = nam__lookup(info)
        if (level == NAME_NOT_FOUND)
            error(sprintf("%s: Name '%s' not found", cmd, info["name"]))
        if (! info__get(info, "idxable"))
            error(sprintf("%s: Name '%s' has type %s, not an Array or List",
                          cmd, info__get(info, "type"), info__get(info, "name")))
        blktab[for_block, 0, "loop_type"] = cmd
        blktab[for_block, 0, "loop_array_name"] = $3
        blktab[for_block, 0, "array_type"] = info__get(info, "type")
        blktab[for_block, 0, "ns"] = info__get(info, "ns")
        blktab[for_block, 0, "level"] = level

    } else
        panic("(parse__for) How did I get here?")

    dbg__print_block("for", 7, for_block, "(parse__for) for_block")
    stk_push(__parse_stack, for_block) # Push it on to the parse_stack

    dbg__print("for", 5, "(parse__for) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @next
    dbg__print("for", 5, "(parse__for) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error(cmd ": Parse error")

    dbg__print("for", 5, "(parse__for) END => " for_block)
    return for_block
}


# @next VAR                       # end normal FOR loop
function parse__next(                   for_block)
{
    dbg__print("for", 3, sprintf("(parse__next) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))
    if (check__parse_stack(BLK_FOR) != ERR_OKAY)
        error("[@next] Parse error; " __m2_msg)
    for_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__next) popped parse_stack => " for_block)

    if (blktab[for_block, 0, "loop_var"] != $2)
        error(sprintf("%s: Variable mismatch; '%s' specified, but '%s' was expected",
                      $1, $2, blktab[for_block, 0, "loop_var"]))
    blktab[for_block, 0, "blkvalid"] = TRUE

    lower_level()

    dbg__print("for", 3, sprintf("(parse__next) END => %d", for_block))
    return for_block
}


function xeq__BLK_FOR(for_block,
                      block_type)
{
    block_type = blk_type(for_block)
    dbg__print("for", 3, sprintf("(xeq__BLK_FOR) START dstblk=%d, for_block=%d, type=%s",
                                curr_dstblk(), for_block, ppf__label(block_type)))
    dbg__print_block("for", 7, for_block, "(xeq__BLK_FOR) for_block")
    if ((block_type != BLK_FOR) || \
        (blktab[for_block, 0, "blkvalid"] != TRUE))
        panic("(xeq__BLK_FOR) Bad for_block config")

    if (blktab[for_block, 0, "loop_type"] == "@__m2__::for" )
        execute__for(for_block)
    else
        execute__foreach(for_block)
}


function execute__for(for_block,
                      loopvar, start, end, incr, done, counter, body_block, new_level, want_break)
{
    # Evaluate loop
    loopvar    = blktab[for_block, 0, "loop_var"]
    start      = dosubs(blktab[for_block, 0, "loop_start"]) + 0
    end        = dosubs(blktab[for_block, 0, "loop_end"])   + 0
    incr       = dosubs(blktab[for_block, 0, "loop_incr"])  + 0
    done       = FALSE
    counter    = start
    body_block = blktab[for_block, 0, "body_block"]

    dbg__print_block("for", 7, for_block, "(execute__for) for_block")
    dbg__print_block("for", 7, body_block, "(execute__for) body_block")
    dbg__print("for", 4, sprintf("(execute__for) loopvar='%s', start=%d, end=%d, incr=%d",
                                 loopvar, start, end, incr))

    if (start > end && incr > 0)
        # error("(execute__for) Start cannot be greater than End")
        return
    if (start < end && incr < 0)
        # error("(execute__for) Start cannot be less than End")
        return

    # Run the loop
    while (!done) {
        new_level = raise_level()
        nam_ll_write_ns(curr_ns(), loopvar, new_level, TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY)
        sym_ll_write_ns(curr_ns(), loopvar, NOKEY, new_level, counter)
        dbg__print("for", 5, sprintf("(execute__for) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg__print("for", 5, sprintf("(execute__for) RETURNED FROM execute__block()"))
        lower_level()
        done = (incr > 0) ? (counter +=     incr ) > end \
                          : (counter -= abs(incr)) < end

        # Check for break or continue
        if (flag_anytrue_p(__m2_config_flags, MODE_XEQ_BREAK MODE_XEQ_CONTINUE)) {
            want_break = flag_1true_p(__m2_config_flags, MODE_XEQ_BREAK)
            __m2_config_flags = flag_set_clear(__m2_config_flags,
                                               MODE_XEQ_NORMAL,
                                               MODE_XEQ_BREAK MODE_XEQ_CONTINUE MODE_XEQ_RETURN)
            if (want_break)
                break
       }
    }
    dbg__print("for", 2, "(execute__for) END")
}


function execute__foreach(for_block,
                          arrtype)
{
    arrtype = blktab[for_block, 0, "array_type"]
    if (arrtype == TYPE_ARRAY)
        execute__foreach_array(for_block)
    else if (arrtype == TYPE_LIST)
        execute__foreach_list(for_block)
    else
        panic(sprintf("(execute__foreach) Bad array_type '%s' in each loop for_block %d",
                      arrtype, for_block))
}

function execute__foreach_array(for_block,
                                loopvar, arrname, level, keys, s, f, k, body_block, new_level, want_break,
                                ns)
{
    loopvar = blktab[for_block, 0, "loop_var"]
    arrname = blktab[for_block, 0, "loop_array_name"]
    level = blktab[for_block, 0, "level"]
    body_block = blktab[for_block, 0, "body_block"]
    ns = blktab[for_block, 0, "ns"]
    dbg__print("for", 4, sprintf("(execute__foreach_array) loopvar='%s', arrname='%s', level=%d, body_block=%d",
                                loopvar, arrname, level, body_block))
    # Find the keys
    for (s in symtab) {
        split(s, f, SUBSEP)
        dbg__print("for", 7, sprintf("symtab[%s,%s,%s,%d,%s]", f[1], f[2], f[3], f[4], f[5]))
        if (f[SFN_NS]    == ns &&
            f[SFN_NAME]  == arrname &&
            f[SFN_LEVEL] == level &&
            f[SFN_TAG]   == "symval")
            keys[f[SFN_KEY]] = 1
    }

    # Run the loop
    for (k in keys) {
        new_level = raise_level()
        nam_ll_write_ns(curr_ns(), loopvar, new_level, TYPE_SYMBOL FLAG_READONLY)
        sym_ll_write_ns(curr_ns(), loopvar, NOKEY, new_level, k)
        dbg__print("for", 5, sprintf("(execute__foreach_array) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg__print("for", 5, sprintf("(execute__foreach_array) RETURNED FROM execute__block()"))
        lower_level()

        # Check for break or continue
        if (flag_anytrue_p(__m2_config_flags, MODE_XEQ_BREAK MODE_XEQ_CONTINUE)) {
            want_break = flag_1true_p(__m2_config_flags, MODE_XEQ_BREAK)
            __m2_config_flags = flag_set_clear(__m2_config_flags,
                                               MODE_XEQ_NORMAL,
                                               MODE_XEQ_BREAK MODE_XEQ_CONTINUE MODE_XEQ_RETURN)
            if (want_break)
                break
       }
    }
    dbg__print("for", 2, "(execute__foreach_array) END")
}

function execute__foreach_list(for_block,
                               arrname, level, loopvar, start, count, done,
                               counter, body_block, new_level, agg_block, want_break,
                               ns)
{
    loopvar = blktab[for_block, 0, "loop_var"]
    arrname = blktab[for_block, 0, "loop_array_name"]
    level = blktab[for_block, 0, "level"]
    body_block = blktab[for_block, 0, "body_block"]
    ns = blktab[for_block, 0, "ns"]
    dbg__print("for", 4, sprintf("(execute__foreach_list) loopvar='%s', arrname='%s', level=%d, body_block=%d",
                                loopvar, arrname, level, body_block))

    counter = 1
    agg_block = symtab[ns, arrname, NOKEY, level, "agg_block"]
    count = blktab[agg_block, 0, "count"]

    if (count > 0 ) {
        # Run the loop
        while (!done) {
            new_level = raise_level()
            nam_ll_write_ns(curr_ns(), loopvar, new_level, TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY)
            sym_ll_write_ns(curr_ns(), loopvar, NOKEY, new_level, counter)
            dbg__print("for", 5, sprintf("(execute__for) CALLING execute__block(%d)", body_block))
            execute__block(body_block)
            dbg__print("for", 5, sprintf("(execute__for) RETURNED FROM execute__block()"))
            lower_level()
            done = (counter += 1) > count

            # Check for break or continue
            if (flag_anytrue_p(__m2_config_flags, MODE_XEQ_BREAK MODE_XEQ_CONTINUE)) {
                want_break = flag_1true_p(__m2_config_flags, MODE_XEQ_BREAK)
                __m2_config_flags = flag_set_clear(__m2_config_flags,
                                                   MODE_XEQ_NORMAL,
                                                   MODE_XEQ_BREAK MODE_XEQ_CONTINUE MODE_XEQ_RETURN)
                if (want_break)
                    break
            }
        }
    }

    dbg__print("for", 2, "(execute__foreach_list) END")
}


function ppf__for(for_block,
                  buf, ltype)
{
    ltype = blktab[for_block, 0, "loop_type"]
    buf = ltype TOK_SPACE \
          blktab[for_block, 0, "loop_var"] TOK_SPACE
    if (ltype == "@__m2__::for")
        buf = buf blktab[for_block, 0, "loop_start"] TOK_SPACE \
                  blktab[for_block, 0, "loop_end"]   TOK_SPACE \
                  blktab[for_block, 0, "loop_incr"]  TOK_NEWLINE
    else                        # foreach
        buf = buf blktab[for_block, 0, "loop_array_name"] TOK_NEWLINE
    buf = buf ppf__block(blktab[for_block, 0, "body_block"]) TOK_NEWLINE
    buf = buf "@next "  blktab[for_block, 0, "loop_var"]
    return buf
}


function ppf__BLK_FOR(blknum)
{
    return sprintf("  valid   : %s\n" \
                   "  type    : %s\n"       \
                   "  loopvar : %s\n"       \
                   "  start   : %s\n"       \
                   "  end     : %s\n"       \
                   "  incr    : %s\n"       \
                   "  body    : %d",
                   ppf__bool(blktab[blknum, 0, "blkvalid"]),
                   blktab[blknum, 0, "loop_type"],
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
    dbg__print("if", 3, sprintf("(parse__if) START dstblk=%d, $0='%s'", curr_dstblk(), $0))
    name = $1
    $1 = ""
    sub("^[ \t]*", "")

    raise_level()

    # Create two new blocks: one for if_block, other for true branch
    if_block = blk_new(BLK_IF)
    dbg__print("if", 5, "(parse__if) New block # " if_block " type " ppf__label(blk_type(if_block)))
    true_block = blk_new(BLK_AGG)
    dbg__print("if", 5, "(parse__if) New block # " true_block " type " ppf__label(blk_type(true_block)))

    blktab[if_block, 0, "condition"]   = $0
    blktab[if_block, 0, "init_negate"] = (name == "@__m2__::unless")
    blktab[if_block, 0, "seen_else"]   = FALSE
    blktab[if_block, 0, "true_block"]  = true_block
    blktab[if_block, 0, "dstblk"]      = true_block
    blktab[if_block, 0, "blkvalid"]       = FALSE
    dbg__print_block("if", 7, if_block, "(parse__if) if_block")
    stk_push(__parse_stack, if_block) # Push it on to the parse_stack

    dbg__print("if", 5, "(parse__if) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endif
    dbg__print("if", 5, "(parse__if) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@if] Parse error")

    dbg__print("if", 5, "(parse__if) END; => " if_block)
    return if_block
}


# @else
function parse__else(                   if_block, false_block)
{
    dbg__print("if", 3, sprintf("(parse__else) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_IF) != ERR_OKAY)
        error("[@else] Parse error; " __m2_msg)
    if_block = stk_top(__parse_stack)

    # Check if already seen @else
    if (blktab[if_block, 0, "seen_else"] == TRUE)
        error("(parse__else) Cannot have more than one @else")

    lower_level()           # trigger name/symbol purge
    raise_level()

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
    dbg__print("if", 3, sprintf("(parse__endif) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_IF) != ERR_OKAY)
        error("[@endif] Parse error; " __m2_msg)

    if_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endif) popped parse_stack => " if_block)
    blktab[if_block, 0, "blkvalid"] = TRUE
    lower_level()
    return if_block
}


function xeq__BLK_IF(if_block,
                     block_type, condition, condval, negate)
{
    block_type = blk_type(if_block)
    dbg__print("if", 3, sprintf("(xeq__BLK_IF) START dstblk=%d, if_block=%d, type=%s",
                               curr_dstblk(), if_block, ppf__label(block_type)))

    dbg__print_block("if", 7, if_block, "(xeq__BLK_IF) if_block")
    if ((block_type != BLK_IF) || \
        (blktab[if_block, 0, "blkvalid"] != TRUE))
        panic("(xeq__BLK_IF) Bad if_block config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    condition = blktab[if_block, 0, "condition"]
    negate = blktab[if_block, 0, "init_negate"]
    condval = evaluate_boolean(condition, negate)
    dbg__print("if", 2, sprintf("(xeq__BLK_IF) evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
    if (condval == ERROR)
        error("@if: Error evaluating condition '" condition "'")

    raise_level()
    if (condval) {
        dbg__print("if", 5, sprintf("(xeq__BLK_IF) [true branch] CALLING execute__block(%d)",
                                   blktab[if_block, 0, "true_block"]))
        execute__block(blktab[if_block, 0, "true_block"])
        dbg__print("if", 5, sprintf("(xeq__BLK_IF) RETURNED FROM execute__block()"))
    } else if (blktab[if_block, 0, "seen_else"] == TRUE) {
        dbg__print("if", 5, sprintf("(xeq__BLK_IF) [false branch] CALLING execute__block(%d)",
                                   blktab[if_block, 0, "false_block"]))
        execute__block(blktab[if_block, 0, "false_block"])
        dbg__print("if", 5, sprintf("(xeq__BLK_IF) RETURNED FROM execute__block()"))
    }
    lower_level()

    dbg__print("if", 3, sprintf("(xeq__BLK_IF) END"))
}


function ppf__if(if_block,
                 buf)
{
    buf = "@if " blktab[if_block, 0, "condition"] TOK_NEWLINE \
        ppf__block(blktab[if_block, 0, "true_block"]) TOK_NEWLINE
    if (blktab[if_block, 0, "seen_else"])
        buf = buf "@else" TOK_NEWLINE \
              ppf__block(blktab[if_block, 0, "false_block"]) TOK_NEWLINE
    return buf "@endif"
}


# Returns TRUE, FALSE, or ERROR
#           @if NAME
#           @if SOMETHING <OP> TEXT
#           @if KEY in ARR
function evaluate_condition(cond, negate,
                            retval, name, sp, op, expr,
                            nparts, arr, key, info, level, lhs, rhs, lval, rval,
                            linfo, rinfo, ltype)
{
    dbg__print("if", 7, sprintf("(evaluate_condition) START cond='%s'", cond))
    if (cond == EMPTY)
        error("@if: Condition cannot be empty")

    retval = ERROR
    if (first(cond) == "!") {
        negate = !negate
        cond = ltrim(rest(cond))
    }

    dbg__print("if", 7, sprintf("(evaluate_condition) Calling dosubs('%s')", cond))
    cond = dosubs(cond)
    dbg__print("if", 4, sprintf("(evaluate_condition) After dosubs, negate=%s, cond='%s'",
                               ppf__bool(negate), cond))

    if (cond ~ /^[0-9]+$/) {
        dbg__print("if", 6, sprintf("(evaluate_condition) Found simple integer '%s'", cond))
        retval = (cond+0) != 0

    } else if (cond ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
        dbg__print("if", 6, sprintf("(evaluate_condition) Found simple name '%s'", cond))
        assert_sym_valid_name(cond, "@if")
        if (sym_deferred_p(cond))
            sym_deferred_define_now(cond)
        retval = sym_true_p(cond)

    } else if (match(cond, ".* (in|IN) .*")) { # poor regexp, fragile
        # This whole section is pretty easy to confound....
        dbg__print("if", 5, sprintf("(evaluate_condition) Found IN expression"))
        # Find name
        sp = index(cond, TOK_SPACE)
        key = substr(cond, 1, sp-1)
        cond = substr(cond, sp+1)
        # Find the condition
        match(cond, " *(in|IN) *")
        arr = substr(cond, RSTART+3)
        dbg__print("if", 5, sprintf("key='%s', op='%s', arr='%s'", key, "IN", arr))

        if (nam__scan(arr, info) == ERROR)
            error("Scan error, " __m2_msg)
        level = nam__lookup(info)
        if (level == NAME_NOT_FOUND)
            error("Name '" arr "' lookup failed")
        if (info["idxable"] == FALSE)
            error(sprintf("IN: Name '%s' has type %s, not Array or List", arr, info__get(info, "type")))

        retval = idx__key_exists_p(info, key)

    } else if (match(cond, "[^ ]+ *(<|<=|=|==|!=|>=|>) *[^ ]+")) { # poor regexp, fragile
        # This whole section is pretty easy to confound....
        dbg__print("if", 6, sprintf("(evaluate_condition) Found comparison"))
        # Find name
        sp = index(cond, TOK_SPACE)
        lhs = substr(cond, 1, sp-1)
        cond = substr(cond, sp+1)
        # Find the condition
        match(cond, "[<>=!]*")
        op = substr(cond, RSTART, RLENGTH)
        rhs = substr(cond, RLENGTH+2)

        info__create_from_text(lhs, linfo)
        ltype = info__get(linfo, "type")
        # if (sym_valid_p(lhs) && sym_deferred_p(lhs))
        #     sym_deferred_define_now(lhs)
        # if (sym_valid_p(lhs) && sym_defined_p(lhs))
        # if (ltype == TYPE_SYMBOL && info__get(linfo, "defined"))
        #     lval = sym_fetch(lhs)
        #else if (seq_defined_p(lhs))
        # else if (ltype == TYPE_SEQUENCE && info__get(linfo, "defined"))
        #     lval = seq_ll_read_ns(info__get(info, "ns"), lhs)

        # XXX What about Arrays and Lists?
        if ((ltype == TYPE_SYMBOL || ltype == TYPE_SEQUENCE) &&
            info__get(linfo, "defined") == TRUE)
            lval = syminfo_fetch(linfo)
        else
            lval = lhs

        info__create_from_text(rhs, rinfo)
        if (sym_valid_p(rhs) && sym_deferred_p(rhs))
            sym_deferred_define_now(rhs)
        if (sym_valid_p(rhs) && sym_defined_p(rhs))
            rval = sym_fetch(rhs)
        #else if (seq_defined_p(rhs))
        else if (info__get(rinfo, "type") == TYPE_SEQUENCE &&
                 info__get(rinfo, "defined") == TRUE)
            rval = seq_ll_read_ns(info__get(info, "ns"), rhs)
        else
            rval = rhs

        dbg__print("if", 6, sprintf("(evaluate_condition) lhs='%s'[%s], op='%s', rhs='%s'[%s]", lhs, lval, op, rhs, rval))

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
    dbg__print("if", 3, sprintf("(evaluate_condition) END retval=%s", (retval == ERROR) ? "ERROR" \
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
                   ppf__bool(blktab[blknum, 0, "blkvalid"]),
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
function xeq_cmd__ignore(cmd, cmdline,
                         readstat, save_line, save_lineno)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__ignore) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = LINE()

    dbg__print("parse", 5, "(xeq_cmd__ignore) CALLING read_lines_until()")
    readstat = read_lines_until(cmdline, VOID)
    dbg__print("parse", 5, "(xeq_cmd__ignore) RETURNED FROM read_lines_until() => " ppf__bool(readstat))
    if (readstat != TRUE)
        error("[@ignore] Pattern '" cmdline "' not found:" save_line, "", save_lineno)
    dbg__print("parse", 5, "(xeq_cmd__ignore) END")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I N C L U D E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       @paste does not process macros
#
#*****************************************************************************
# @include, @paste      FILE
function xeq_cmd__include(cmd, cmdline,
                          error_text, filename, silent, file_block, rc,
                          me, sp, lib)
{
    me = "@" cmd
    rc = FALSE
    dbg__print("parse", 5, sprintf("(xeq_cmd__include) cmd='%s', cmdline='%s'",
                                   cmd, cmdline))
    if (cmdline == EMPTY)
        error(me ": Bad parameters")
    # S variants mute file errors, even in strict mode
    if ((silent = (first(cmd) == "s")) == TRUE)
        cmd = rest(cmd)

    if (cmd == "import") {
        # This was done rather slapdashedly and could use improving
        if ((sp = index(cmdline, TOK_SPACE)) == NOT_FOUND)
            error(me ": Bad parameters")
        lib = substr(cmdline, 1, sp - 1)
        cmdline = substr(cmdline, sp + 1)
        stk_push_2nd(__ns_stack, lib)
    }

    # error_text is set aggressively, but only is seen if rc is FALSE
    do {
        error_text = me ": File '" cmdline "' not found"
        filename = search_file(cmdline)
        if (emptyp(filename))
            break
        file_block = prep_file(filename)
        trace(TRACE_BLOCKS, EMPTY, sprintf("[Block Update] %d %s, filename='%s'",
                                           file_block, "FILE", filename))
        blktab[file_block, 0, "atmode"] = \
            cmd == "paste" ? MODE_AT_LITERAL : MODE_AT_PROCESS

        # prep_file doesn't push the BLK_FILE onto the __source_stack,
        # so we have to do that ourselves due to customization
        dbg__print("parse", 7, sprintf("(xeq_cmd__include) Pushing file block %d (%s) onto source_stack", file_block, filename))
        stk_push(__source_stack, file_block)

        error_text = me ": File '" filename "' not found"
        dbg__print("parse", 5, "(xeq_cmd__include) CALLING parse__file()")
        rc = parse__file(cmd == "nsinclude" ? curr_ns() : M2_NS)
        dbg__print("parse", 5, "(xeq_cmd__include) RETURNED FROM parse__file()")
    } while (FALSE)

    if (!rc && !silent) {
        if (strictp("file"))
            error(error_text)
        warn(error_text)
    }
    dbg__print("parse", 5, sprintf("(xeq_cmd__include) END"))
}


function search_file(f,
                     pe, icount, paths, p, i)
{
    f = rm_quotes(dosubs(f))
    if (f == "-")
        f = "/dev/stdin"
    if ((pe = path_exists_p(f)) == TRUE)
        return f
    if (first(f) == TOK_SLASH)
        # If path is absolute, do not invoke path search mechanism
        return pe ? f : EMPTY
    icount = split(sys_read("__INCPATH__", NOKEY),
                   paths, TOK_COLON)
    for (i = 1; i <= icount; i++) {
        p = with_trailing_slash(paths[i]) f
        if (path_exists_p(p)) {
            trace(TRACE_PATH_SEARCH, EMPTY,
                  sprintf("[Path Search] '%s' found '%s'", f, p))
            return p
        }
    }
    return EMPTY
}

function rm_INCPATH(elem,
                    i, tmpip, icount, paths)
{
    tmpip = EMPTY
    icount = split(sys_read("__INCPATH__", NOKEY),
                   paths, TOK_COLON)
    for (i = 1; i <= icount; i++)
        if (paths[i] != elem)
            # Only retain items which don't match the element we want to remove
            tmpip = tmpip paths[i] TOK_COLON
    sys_write("__INCPATH__", chop(tmpip))
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
function xeq_cmd__incr(cmd, cmdline,
                       name, incr,
                       sym, info, me, ins)
{
    me = "@" cmd
    $0 = cmdline
    if (NF == 0)
        error(me ": Bad parameters")
    name = $1
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_UPDATE, PTYPE_NUMBER, info, ins, curr_level(), me, TRUE)
    # assert_sym_defined(name, me)
    # if (!sym_defined_p(name) && !seq_defined_p(name))
    #     error(sprintf("%s: Name '%s' not defined E",
    #                   me, name))

    if (NF >= 2 && ! integerp($2))
        error(sprintf("%s: Value '%s' must be numeric",
                      me, $2))
    incr = (NF >= 2) ? $2 : 1
    incr = (cmd == "incr") ? incr : -incr
    if (syminfo_defined_p(info))
        syminfo_increment(info, incr)
    else if (info__get(info, "type") == TYPE_SEQUENCE &&
             info__get(info, "defined") == TRUE)
        seq_ll_incr_ns(info__get(info, "ns"), info__get(info, "name"), incr)
    else
        error(sprintf("%s: Name '%s' not defined%s",
                      me, name, VERBOSE() ? " [(xeq_cmd__incr)]" : ""))
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
function xeq_cmd__input(cmd, cmdline,
                        name, info, getstat, input,
                        me, ins)
{
    me = "@" cmd
    $0 = cmdline
    name = (NF == 0) ? "__INPUT__" : $1
    info__create_from_text(name, info)
    ins = info__get(info, "ns")
    info__gate(OP_CREATE, PTYPE_SCALAR, info, ins, curr_level(), me, TRUE)

    input = EMPTY
    getstat = getline input < TTY
    if (getstat == ERROR)
        warn(me ": Error reading file '" TTY "' [input]:" $0)
    syminfo_store(info, input)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  L I S T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @list                 NAME
function xeq_cmd__list(cmd, cmdline,
                       name, info, agg_block, me, ins)
{
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    name = $1
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_CREATE, TYPE_LIST, info, ins, curr_level(), me, TRUE)
    # if (nam_ll_in!(name, curr_level()))
    #     error(sprintf("%s: List '%s' already defined",
    #                   m3, name))
    nam_ll_write_ns(ins, info__get(info, "name"), curr_level(), TYPE_LIST)
    agg_block = blk_new(BLK_AGG)
    dbg__print("parse", 5, sprintf("(xeq_cmd__list) symtab[%s, '%s','',%d,'agg_block'] = %d",
                                 ins, info__get(info, "name"), curr_level(), agg_block))
    symtab[ins, info__get(info, "name"), NOKEY, curr_level(), "agg_block"] = agg_block
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  L I T E R A L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @literal   DELIM
function xeq_cmd__literal(cmd, cmdline,
                          readstat, save_line, save_lineno, lit_block)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__literal) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = LINE()
    lit_block = blk_new(BLK_AGG)

    dbg__print("parse", 5, "(xeq_cmd__literal) CALLING read_lines_until()")
    readstat = read_lines_until(cmdline, lit_block)
    dbg__print("parse", 5, "(xeq_cmd__literal) RETURNED FROM read_lines_until() => " ppf__bool(readstat))
    if (readstat != TRUE)
        error("[@literal] Pattern '" cmdline "' not found:" save_line, "", save_lineno)

    dbg__print("parse", 5, sprintf("(xeq_cmd__literal) CALLING ship_out(BLKNUM, '%s')", lit_block))
    ship_out(OBJ_BLKNUM, lit_block)
    dbg__print("parse", 5, "(xeq_cmd__literal) RETURNED FROM ship_out()")
    dbg__print("parse", 5, "(xeq_cmd__literal) END")
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
# @local FOO adds to namtab (as a scalar) in the current level, does not define it
function xeq_cmd__local(cmd, cmdline,
                        name, info, me, ins)
{
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error(me ": Bad parameters:" $0)
    if (curr_level() == ROOT_LEVEL)
        error(me ": Not usable at root level")
    name = $1
    # check for valid name
    if (!nam__valid_p(name, PTYPE_PARAM, TRUE))
        error(sprintf("%s: Invalid name '%s'", me, name))
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    name = info__get(info, "name")
    info__gate(OP_CREATE, TYPE_SYMBOL, info, ins, curr_level(), me, TRUE)
    # XXX TODO These checks should be incorporated into the gate() code
    if (flag_1true_p(info__get(info, "code"), FLAG_SYSTEM))
        error(sprintf("%s: Name '%s' is protected%s",
                      me, name, VERBOSE() ? " [xeq_cmd__local:I]" : ""))
    if (nam_ll_in_ns(ins, name, curr_level()))
        error(sprintf("%s: Name '%s' already defined as a %s",
                      me, name, ppf__label(info__get(info, "type"))))
    nam_ll_write_ns(ins, name, curr_level(), TYPE_SYMBOL)
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
function parse__longdef(    name, sym_block, body_block, pstat,
                            info, me, ins)
{
    me = "@longdef1"            # ?
    dbg__print("sym", 5, "(parse__longdef) START dstblk=" curr_dstblk() ", mode=" ppf__label(curr_atmode()) "; $0='" $0 "'")

    # Create two new blocks: one for the "longdef" block, other for definition body
    sym_block = blk_new(BLK_LONGDEF)
    dbg__print("sym", 5, "(parse__longdef) New block # " sym_block " type " ppf__label(blk_type(sym_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("sym", 5, "(parse__longdef) New block # " body_block " type " ppf__label(blk_type(body_block)))

    $1 = ""
    name = $2
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_CREATE, PTYPE_SCALAR, info, ins, curr_level(), me, TRUE)
    blktab[sym_block, 0, "name"] = info__get(info, "name")
    blktab[sym_block, 0, "ns"] = info__get(info, "ns")
    blktab[sym_block, 0, "body_block"] = body_block
    blktab[sym_block, 0, "dstblk"] = body_block
    blktab[sym_block, 0, "blkvalid"] = FALSE
    dbg__print_block("sym", 7, sym_block, "(parse__longdef) sym_block")
    stk_push(__parse_stack, sym_block) # Push it on to the parse_stack

    dbg__print("sym", 5, "(parse__longdef) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endlongdef
    dbg__print("sym", 5, "(parse__longdef) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@longdef] Parse error")

    dbg__print("sym", 5, "(parse__longdef) END => " sym_block)
    return sym_block
}


function parse__endlongdef(    sym_block)
{
    dbg__print("sym", 3, sprintf("(parse__endlongdef) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_LONGDEF) != ERR_OKAY)
        error("[@endlongdef] Parse error; " __m2_msg)
    sym_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endlongdef) popped parse_stack => " sym_block)
    blktab[sym_block, 0, "blkvalid"] = TRUE
    dbg__print("sym", 3, sprintf("(parse__endlongdef) END => %d", sym_block))
    return sym_block
}


function xeq__BLK_LONGDEF(longdef_block,
                          block_type, name, info, body_block, opm,
                          me, ins)
{
    me = "@longdef2"            # ?
    block_type = blk_type(longdef_block)
    dbg__print("sym", 3, sprintf("(xeq__BLK_LONGDEF) START dstblk=%d, longdef_block=%d, type=%s",
                                 curr_dstblk(), longdef_block, ppf__label(block_type)))
    dbg__print_block("sym", 7, longdef_block, "(xeq__BLK_LONGDEF) longdef_block")
    if ((block_type != BLK_LONGDEF) ||
        (blktab[longdef_block, 0, "blkvalid"] != TRUE))
        panic("(xeq__BLK_LONGDEF) Bad longdef_block config")

    name = blktab[longdef_block, 0, "name"]
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_CREATE, PTYPE_SCALAR, info, ins, curr_level(), me, TRUE)

    body_block = blktab[longdef_block, 0, "body_block"]
    dbg__print_block("sym", 3, body_block, "(xeq__BLK_LONGDEF) body_block")
    syminfo_store(info, blk_to_string(body_block))
    dbg__print("sym", 2, "(xeq__BLK_LONGDEF) END")
}


function ppf__longdef(longdef_block,
                      buf)
{
    return "@longdef " blktab[longdef_block, 0, "name"] TOK_NEWLINE      \
            ppf__block(blktab[longdef_block, 0, "body_block"]) TOK_NEWLINE \
            "@endlongdef"
}


function ppf__BLK_LONGDEF(longdef_block)
{
    return sprintf("  symbol      : '%s'\n" \
                   "  valid       : %s\n" \
                   "  body_block  : %d",
                   blktab[longdef_block, 0, "name"],
                   ppf__bool(blktab[longdef_block, 0, "blkvalid"]),
                   blktab[longdef_block, 0, "body_block"])
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  M 2 C T L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Undocumented - Reserved for internal use
#
#       @m2ctl booltest                 Scan boolean expr from user
#       @m2ctl dbg_max                  All 9s
#       @m2ctl dbg_level                Debug levels
#       @m2ctl dbg_nam_qual             Debug nam__qual and info_level search
#       @m2ctl dbg_params               Debug function parameters
#       @m2ctl dbg_qual                 Debug namespace qualification
#       @m2ctl dbg_ship_out
#       @m2ctl dbg_standard             Reset all dbg levels to standard
#       @m2ctl dbg_user                 Debug @newcmd, user_blocks
#       @m2ctl dbg_zero                 Clear debugging
#       @m2ctl dump_block BLOCK         Raw dump block #
#       @m2ctl dump_namtab              Dump of name table (non-system)
#       @m2ctl dump_ns_stack            Dump namespace stack
#       @m2ctl dump_parse_stack         Dump parse stack
#       @m2ctl set_dbg DSYS LEVEL       Set debug level directly
#
#*****************************************************************************
# @m2ctl                ARGS
function xeq_cmd__m2ctl(cmd, cmdline,
                        getstat, input, e, dsys, lev, blk)
{
    $0 = cmdline
    dbg__print("xeq", 2, sprintf("(xeq_cmd__m2ctl) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    if (NF == 0)
        error("Bad parameters:" $0)

    if ($1 == "booltest") { # Interactively evaluate boolean expressions
        do {
            print_stderr("Enter line to scan as boolean expr (RETURN to end):")
            getstat = getline input < TTY
            if (emptyp(input)) {
                print_stderr("Exiting boolean expr; RETURNING to regular commands!")
                break
            }

            bool__tokenize_string(input)
            __bf = 1
            e = bool__scan_expr(input)
            if (e == ERROR)
                print_stderr(sprintf("(xeq_cmd__m2ctl) bool__scan_expr('%s') returned ERROR - should exit?", input))
            else
                print_stderr(sprintf("(xeq_cmd__m2ctl) __bf=%d,__bnf=%d; FINAL ANSWER: %d == %s", __bf, __bnf, e, ppf__bool(e)))
        } while (TRUE)

    } else if ($1 == "dbg_max") {
        enable_debugging()
        for (dsys in __dbg_sysnames)
            sym_ll_write_ns(M2_SYSNS, "__DBG__", dsys, ROOT_LEVEL, 9)

    } else if ($1 == "dbg_level") {
        enable_debugging()
        # Debug levels
        dbg__all_lev_zero()
        dbg__set_level("for",       5)
        dbg__set_level("level",     5)
        dbg__set_level("cmd",       5)
        dbg__set_level("nam",       3)
        dbg__set_level("sym",       5)

    } else if ($1 == "dbg_nam_qual") {
        enable_debugging()
        dbg__all_lev_zero()
        dbg__set_level("nam",     7)
        dbg__set_level("parse",   7)
        dbg__set_level("qual",    9)

    } else if ($1 == "dbg_params") {
        enable_debugging()
        # Debug function params: help scan @foo a b c@ and @foo{a}{b}{c}@
        dbg__all_lev_zero()
        dbg__set_level("dosubs",    7)
        # dbg__set_level("level",     5)
        # dbg__set_level("cmd",       5)
        # dbg__set_level("nam",       3)
        dbg__set_level("sym",       5)

    } else if ($1 == "dbg_qual") {
        enable_debugging()
        #dbg__all_lev_zero()
        dbg__set_level("qual", 9)

    } else if ($1 == "dbg_ship_out") {
        enable_debugging()
        dbg__all_lev_zero()
        dbg__set_level("dosubs",    7)
        dbg__set_level("parse",   9)
        dbg__set_level("io",   5)
        dbg__set_level("ship_out",   9)
        dbg__set_level("stk", 5)

    } else if ($1 == "dbg_standard") {
        dbg__all_lev_standard()

    } else if ($1 == "dbg_user") {
        enable_debugging()
        dbg__all_lev_zero()
        dbg__set_level("cmd",     7)
        dbg__set_level("dosubs",  7)
        dbg__set_level("for",     8)
        dbg__set_level("parse",   9)
        dbg__set_level("ship_out",5)
        dbg__set_level("xeq",     7)

    } else if ($1 == "dbg_zero") {
        # NB - __DEBUG__ unchanged
        dbg__all_lev_zero()

    } else if ($1 == "dump_block") {
        blk = $2 + 0
        blk_dump_block_raw(blk)

    } else if ($1 == "dump_namtab") {
        dump__names(PTYPE_ANY, PTYPE_ANY, FALSE)

    } else if ($1 == "dump_ns_stack") {
        dump_ns_stack()

    } else if ($1 == "dump_parse_stack") {
        dump_parse_stack()

    } else if ($1 == "set_dbg") { # Set __DBG__[dsys] level directly
        dsys = $2                 # Note, does not affect __DEBUG__
        lev = $3
        print_stderr(sprintf("Setting __DBG__[%s] to %d", dsys, lev))
        dbg__set_level(dsys, lev)

    } else
        error("@m2ctl: Unrecognized parameter: " $1)
}

function dump_ns_stack(    n, i)
{
    if (stk_empty_p(__ns_stack)) {
        print_stderr("ns_stack is empty")
        return
    }
    n = stk_depth(__ns_stack)
    print_stderr("ns_stack has " n " elements")
    for (i = n; i > 0; i--) {
        print_stderr(sprintf("ns[%d] = %s", i, __ns_stack[i]))
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  N E W C M D
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
function parse__newcmd(    name, user_block, body_block, pstat, nparam, p, pname,
                           me, info, eq, defval, started_opt, ins, i, new_level)
{
    me = "@newcmd"
    nparam = 0
    dbg__print("cmd", 5, "(parse__newcmd) START dstblk=" curr_dstblk() ", mode=" ppf__label(curr_atmode()) "; $0='" $0 "'")

    # Create two new blocks: one for the "new command" block, other for command body
    user_block = blk_new(BLK_USER)
    dbg__print("cmd", 5, "(parse__newcmd) New block # " user_block " type " ppf__label(blk_type(user_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("cmd", 5, "(parse__newcmd) New block # " body_block " type " ppf__label(blk_type(body_block)))

    $1 = ""
    name = $2
    while (match(name, "{[^}]*}")) {
        p = ++nparam
        pname = substr(name, RSTART+1, RLENGTH-2)
        if ((eq = index(pname, "=")) > 0) {
            started_opt = TRUE
            defval = substr(pname, eq+1)
            pname = substr(pname, 1, eq-1)
        } else if (started_opt)
            error(me ": Required arguments must precede optional arguments: '" pname "'")
        if (! nam__valid_p(pname, PTYPE_PARAM, FALSE))
            error(me ": Invalid parameter name '" pname "'")
        dbg__print("cmd", 5, sprintf("(parse__newcmd) Parameter %d : %s",
                                     p, pname))
        blktab[user_block, p, "param_name"] = pname
        if (blktab[user_block, p, "optional"] = to_bool(eq))
            blktab[user_block, p, "default_value"] = defval

        name = substr(name, 1, RSTART-1) substr(name, RSTART+RLENGTH)
    }
    info__create_from_text(name, info)
    if ((ins = info__get(info, "ns")) == EMPTY)
        ins = info["ns"] = curr_ns()
    info__gate(OP_CREATE, TYPE_USER, info, ins, curr_level(), me, TRUE)

    blktab[user_block, 0, "name"] = info__get(info, "name")
    blktab[user_block, 0, "ns"]   = ins
    blktab[user_block, 0, "body_block"] = body_block
    blktab[user_block, 0, "dstblk"] = body_block
    blktab[user_block, 0, "blkvalid"] = FALSE
    blktab[user_block, 0, "nparam"] = nparam
    dbg__print_block("cmd", 7, user_block, "(parse__newcmd) user_block")
    stk_push(__parse_stack, user_block) # Push it on to the parse_stack

    new_level = raise_level()
    # Instantiate parameters just in namtab[]
    for (i = 1; i <= nparam; i++)
        nam_ll_write_ns(ins, blktab[user_block, i, "param_name"],
                        new_level, TYPE_SYMBOL)

    stk_push(__ns_stack, ins)
    dbg__print("cmd", 5, "(parse__newcmd) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcmd
    dbg__print("cmd", 5, "(parse__newcmd) RETURNED FROM parse() => " ppf__bool(pstat))
    stk_pop(__ns_stack)

    if (!pstat)
        error(me ": Parse error")

    dbg__print("cmd", 5, "(parse__newcmd) END; user_block => " user_block)
    return user_block
}


function parse__endcmd(                     newcmd_block)
{
    dbg__print("cmd", 3, sprintf("(parse__endcmd) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_USER) != ERR_OKAY)
        error("[@endcmd] Parse error; " __m2_msg)
    newcmd_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endcmd) popped parse_stack => " newcmd_block)
    blktab[newcmd_block, 0, "blkvalid"] = TRUE
    lower_level()

    dbg__print("cmd", 3, sprintf("(parse__endcmd) END => %d", newcmd_block))
    dbg__print_block("parse", 7, newcmd_block, sprintf("newcmd block:"))
    return newcmd_block
}


function xeq__BLK_USER(newcmd_block,
                       block_type, name, ns)
{
    block_type = blk_type(newcmd_block)
    dbg__print("cmd", 1, sprintf("(xeq__BLK_USER) START dstblk=%d, newcmd_block=%d, type=%s",
                                 curr_dstblk(), newcmd_block, ppf__label(block_type)))
    dbg__print_block("cmd", 7, newcmd_block, "(xeq__BLK_USER) newcmd_block")
    if ((block_type != BLK_USER) ||
        (blktab[newcmd_block, 0, "blkvalid"] != TRUE))
        panic("(xeq__BLK_USER) Bad newcmd_block config")

    # Instantiate command, but do not run.  "@newcmd FOO" is just declaring FOO.
    # @FOO{...} actually ships it out (and is done under ship_out/xeq_user).
    name = blktab[newcmd_block, 0, "name"]
    ns   = blktab[newcmd_block, 0, "ns"]
    dbg__print("cmd", 3, sprintf("(xeq__BLK_USER) ns=%s, name='%s', level=%d: TYPE_USER, value=%d",
                                 ns, name, curr_level(), newcmd_block))
    nam_ll_write_ns(ns, name, curr_level(), TYPE_USER)
    cmd_ll_write_ns(ns, name, curr_level(), newcmd_block)

    dbg__print("cmd", 1, "(xeq__BLK_USER) END")
}


function execute__user(user_invocation,
                       level, info, code, ns,
                       old_level, user_block,
                       nitem, citem, name, ins,
                       args, arg, narg, argval)
{
    dbg__print("xeq", 3, sprintf("(execute__user) START"))
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL)) {
        dbg__print("xeq", 3, "(execute__user) NOP !MODE_XEQ_NORMAL")
        return
    }

    # print_stderr(ppf__sepstr(user_invocation))
    nitem = split_subsep(user_invocation, citem)
    ns   = citem[CFN_NS]
    name = citem[CFN_NAME]

    # See if it's a user command
    if (nam__scan(ns TOK_NS_QUAL name, info) == ERROR)
        error("(execute__user) Scan error, " __m2_msg)
    if ((level = nam__lookup(info)) == NAME_NOT_FOUND)
        error("(execute__user) nam__lookup('" info__get(info, "urtext") "') failed")
    ins = info__get(info, "ns")
    code = nam_ll_read_ns(ins, name, level)
    #print("ins='" ins "', name='" name "', level=" level ", code='" code "'")

    if (flag_1false_p((code = nam_ll_read_ns(ins, name, level)), TYPE_USER))
        panic("(execute__user) " name " seems to no longer be a command")

    user_block = cmd_ll_read_ns(ins, name, level)
    dbg__print_block("xeq", 7, user_block, "(execute__user) user_block")
    dbg__print_block("xeq", 7, blktab[user_block, 0, "body_block"], "(execute__user) body_block")

    old_level = curr_level()
    execute__user_body(user_block, citem)
    if (curr_level() != old_level)
        panic(sprintf("(execute__user) [@%s] user_block=%d: Level mismatch; old_level=%d, curr_level()=%d",
                      name, user_block, old_level, curr_level()))
}


function execute__user_body(user_block, args,
                            block_type, new_level, i, j, p, body_block,
                            ns, nparam)
{
    block_type = blk_type(user_block)
    dbg__print("cmd", 3, sprintf("(execute__user_body) START dstblk=%d, user_block=%d, type=%s",
                                 curr_dstblk(), user_block, ppf__label(block_type)))
    dbg__print_block("cmd", 7, user_block, "(execute__user_body) user_block")
    if ((block_type != BLK_USER) ||
        (blktab[user_block, 0, "blkvalid"] != TRUE))
        panic("(execute__user_body) Bad user_block config")
    body_block = blktab[user_block, 0, "body_block"]
    dbg__print_block("cmd", 7, body_block, "(execute__user_body) body_block")

    # Evaluate arguments before any parameter instantiations.  It is
    # critical to do this first (and not all together in a loop as
    # before), because invoking nam_ll_write() before sym_ll_write_ns()
    # will LOSE if a parameter has the same name as a global variable
    # due to namtab[] mismatch.
    for (i = 1; i <= args[1] - 3; i++)
        # +3 to skip past first three entries (count, ns, cmd)
        args[i + 3] = dosubs(args[i + 3])

    # Always raise level (even if nparam == 0) because
    # user code might run @local.
    new_level = raise_level()

    # Instantiate parameters in the namespace specified
    ns = args[2]
    nparam = blktab[user_block, 0, "nparam"]
    for (i = 1; i <= args[1] - 3; i++) {
        if (i > nparam) break
        p = blktab[user_block, i, "param_name"]
        nam_ll_write_ns(ns, p, new_level, TYPE_SYMBOL)
        sym_ll_write_ns(ns, p, NOKEY, new_level, args[i + 3])
        dbg__print("cmd", 6, sprintf("(execute__user_body) Setting param %s to '%s'", p, args[i+3]))
    }
    # If we haven't supplied all expected parameters, see if the missing
    # ones have default values
    while (i <= nparam) {
        if (! blktab[user_block, i, "optional"])
            error("@" args[3] ": Insufficient parameters")

        p = blktab[user_block, i, "param_name"]
        nam_ll_write_ns(ns, p, new_level, TYPE_SYMBOL)
        sym_ll_write_ns(ns, p, NOKEY, new_level, blktab[user_block, i, "default_value"])
        dbg__print("cmd", 6, sprintf("(execute__user_body) Defaulting param %s to '%s'",
                                     p, blktab[user_block, i, "default_value"]))
        i++
    }

    dbg__print("cmd", 5, sprintf("(execute__user_body) CALLING execute__block(%d)", body_block))
    execute__block(body_block)
    dbg__print("cmd", 5, sprintf("(execute__user_body) RETURNED FROM execute__block()"))
    lower_level()

    # If we've been asked to return, well now we have
    if (flag_1true_p(__m2_config_flags, MODE_XEQ_RETURN)) {
        dbg__print("cmd", 7, "(execute__user_body) Found RETURN, value is '" __return_value "'")
        __m2_config_flags = flag_set_clear(__m2_config_flags,
                                           MODE_XEQ_NORMAL,
                                           MODE_XEQ_BREAK MODE_XEQ_CONTINUE MODE_XEQ_RETURN)
    }
    # If things are still not normal, that's a problem
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL))
        panic("(execute__user_body) !MODE_XEQ_NORMAL")

    dbg__print("cmd", 2, "(execute__user_body) END")
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
    return sprintf("  name       : %s::%s\n" \
                   "  valid      : %s\n" \
                   "  body_block : %d\n" \
                   "  nparam     : %d\n" \
                   "%s",
                   blktab[blknum, 0, "ns"], blktab[blknum, 0, "name"],
                   ppf__bool(blktab[blknum, 0, "blkvalid"]),
                   blktab[blknum, 0, "body_block"],
                   nparam,
                   chomp(param_desc))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  N A M E S P A C E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @namespace
function xeq_cmd__namespace(cmd, cmdline,
                            me, ns)
{
    dbg__print("ns", 5, sprintf("(xeq_cmd__namespace) START"))
    me = "@" cmd
    $0 = cmdline
    if (NF != 1)
        error(me ": Bad parameters")

    ns = rm_quotes(dosubs($1))
    if (! nam__valid_p(ns, PTYPE_NS, FALSE))
        error(me ": Invalid namespace name '" ns "'")
    if (ns == "awk")
        error(me ": Namespace 'awk' protected")

    stk_replace_top(__ns_stack, ns)
    dbg__print("ns", 1, "(xeq_cmd__namespace) Namespace now " curr_ns())
    dbg__print("ns", 5, "(xeq_cmd__namespace) END")
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
function xeq_cmd__nextfile(cmd, cmdline,
                           readstat, save_line, save_lineno)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__nextfile) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))
    save_line = $0
    save_lineno = LINE()

    dbg__print("parse", 5, "(xeq_cmd__nextfile) CALLING read_lines_until()")
    readstat = read_lines_until("", VOID)
    dbg__print("parse", 5, "(xeq_cmd__nextfile) RETURNED FROM read_lines_until() => " ppf__bool(readstat))
    if (readstat != TRUE)
        error("[@nextfile] Read error:" save_line, "", save_lineno)
    dbg__print("parse", 5, "(xeq_cmd__nextfile) END")
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
                           name, info, nparts, key, ilevel, icode,
                           me, ins, iname)
{
    me = "@" cmd
    dbg__print("xeq", 5, sprintf("(xeq_cmd__readonly) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0)
        error(me ": Bad parameters")
    name = $1

    # # Scan sym => name, key
    # if ((nparts = nam__scan(sym, info)) == ERROR)
    #     error("[@readonly] Scan error, " __m2_msg)
    # name = info["name"]
    # key  = info["key"]
    #
    # # Now call nam__lookup(info)
    # level = nam__lookup(info)
    # if (level == NAME_NOT_FOUND)
    #     error("(xeq_cmd__readonly) nam__lookup(info) failed")
    #
    # # Now we know it's a symbol, level & code.  Still need to look in
    # # symtab because NAME[KEY] might not be defined.
    # code = info["code"]
    # if ((level = info__create_from_text(name, info)) == NAME_NOT_FOUND)
    #     error(me ": " info["errtext"])
    #
    # code = info__get(info, "code")
    # if (flag_allfalse_p(code, TYPE_ARRAY TYPE_SYMBOL))
    #     error("@readonly: Name must be symbol or array")
    # if (flag_1true_p(code, FLAG_SYSTEM))
    #     error("@readonly: Name protected")
#NEW:
    info__create_from_text(name, info)
    ilevel = info__get(info, "level")
    if (ilevel == NAME_NOT_FOUND)
        panic("(xeq_cmd__readonly) gate(OP_UPDATE) passed but level was name_not_found")
    ins = info__get(info, "ns")
    iname = info__get(info, "name")
    info__gate(OP_UPDATE, PTYPE_SCALAR, info, ins, curr_level(), me, TRUE)
    icode = info__get(info, "code")
    nam_ll_write_ns(ins, iname, ilevel, flag_set_clear(icode, FLAG_READONLY))
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
function xeq_cmd__return(cmd, cmdline)
{
    # Logical check
    if (flag_1false_p(__m2_config_flags, MODE_XEQ_NORMAL))
        panic("(xeq_cmd__return) !MODE_XEQ_NORMAL")

    __return_found = TRUE
    __return_value = cmdline
    __m2_config_flags = flag_set_clear(__m2_config_flags,
                                       MODE_XEQ_RETURN,
                                       MODE_XEQ_NORMAL MODE_XEQ_BREAK MODE_XEQ_CONTINUE)
    dbg__print("cmd", 5, "(xeq_cmd__return): RETURNING '" cmdline "'")
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
function xeq_cmd__sequence(cmd, cmdline,
                           id, level, info, action, arg, saveline,
                           me, ns, name)
{
    me = "@" cmd
    $0 = cmdline
    dbg__print("seq", 2, sprintf("(xeq_cmd__sequence) START dstblk=%d, cmd=%s, cmdline='%s'",
                                curr_dstblk(), cmd, cmdline))
    if (NF == 0)
        error("Bad parameters: Sequence name required:" $0)
    id = $1
    level = info__create_from_text(id, info)
    if (info__get(info, "lexvalid") != TRUE)
        error(me ": Name '" id "' is not valid")
    name = info__get(info, "name")
    ns = info__get(info, "ns")

    if (NF == 1)
        $2 = "create"
    action = $2
    # If action is anything other than "create", then the name
    # must exist as a bound Sequence
    if (action != "create" &&
        ! (info__get(info, "type") == TYPE_SEQUENCE &&
           info__get(info, "defined") == TRUE))
        error("Name '" id "' not defined [sequence]:" $0)
    if (NF == 2) {
        if (action == "create") {
            if (level == NAME_NOT_FOUND && ns == EMPTY)
                info["ns"] = ns = curr_ns()
            info__gate(OP_CREATE, TYPE_SEQUENCE, info, ns, ROOT_LEVEL, me, TRUE)
            #
            nam_ll_write_ns(ns, name, ROOT_LEVEL, TYPE_SEQUENCE FLAG_INTEGER)
            symtab[ns, name, NOKEY, ROOT_LEVEL, "incr"] = SEQ_DEFAULT_INCR
            symtab[ns, name, NOKEY, ROOT_LEVEL, "init"] = SEQ_DEFAULT_INIT
            symtab[ns, name, NOKEY, ROOT_LEVEL, "fmt"]  = sys_read("__FMT__", "seq")
            seq_ll_write_ns(ns, name, SEQ_DEFAULT_INIT)
        } else if (action == "delete") {
            seq_destroy_ns(ns, name)
        } else if (action == "next") { # Increment counter only, no output
            seq_ll_incr_ns(ns, name, symtab[ns, name, EMPTY, ROOT_LEVEL, "incr"])
        } else if (action == "prev") { # Decrement counter only, no output
            seq_ll_incr_ns(ns, name, -symtab[ns, name, EMPTY, ROOT_LEVEL, "incr"])
        } else if (action == "restart") { # Set current counter value to initial value
            seq_ll_write_ns(ns, name, symtab[ns, name, EMPTY, ROOT_LEVEL, "init"])
        } else
            error("Bad parameters:" $0)
    } else {    # NF >= 4
        saveline = $0
        dbg__print("seq", 2, sprintf("(xeq_cmd__sequence) cmdline was '%s'", cmdline))
        #sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/, "") # a + this time because ARG is required
        sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+/, "", cmdline) # a + this time because ARG is required
        dbg__print("seq", 2, sprintf("(xeq_cmd__sequence) cmdline now '%s'", cmdline))
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
            dbg__print("seq", 2, sprintf("(xeq_cmd__sequence) fmt now '%s'", arg))
            symtab[ns, name, EMPTY, ROOT_LEVEL, "fmt"] = arg
        } else if (action == "setincr") {
            # setincr N :: Set increment value to N.
            if (!integerp(arg))
                error(sprintf("@sequence setincr: Value '%s' must be numeric", arg))
            if (arg+0 == 0)
                error(sprintf("@sequence setincr: Bad parameters: %s", saveline))
            symtab[ns, name, EMPTY, ROOT_LEVEL, "incr"] = int(arg)
        } else if (action == "setinit") {
            # setinit N :: Set initial  value to N.  If current
            # value == old init value (i.e., never been used), then set
            # the current value to the new init value also.  Otherwise
            # current value remains unchanged.
            if (!integerp(arg))
                error(sprintf("@sequence setinit: Value '%s' must be numeric", arg))
            if (seq_ll_read_ns(ns, name) == symtab[ns, name, EMPTY, ROOT_LEVEL, "init"])
                seq_ll_write_ns(ns, name, int(arg))
            symtab[ns, name, EMPTY, ROOT_LEVEL, "init"] = int(arg)
        } else if (action == "setval") {
            # setval N :: Set counter value directly to N.
            if (!integerp(arg))
                error(sprintf("@sequence setval: Value '%s' must be numeric", arg))
            seq_ll_write_ns(ns, name, int(arg))
        } else
            error("Bad parameters:" me TOK_SPACE saveline)
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
function xeq_cmd__shell(cmd, cmdline,
                        delim, save_line, save_lineno, shell_text_in, input_file,
                        agg_block, output_file, sendto, getstat,
                        shell_cmdline, line, shell_data_blk, readstat,
                        me)
{
    # The sendto program defaults to a reasonable shell but you can
    # specify where you want to send your data.  Possibly useful choices
    # would be an alternative shell, an email message reader, or
    # /usr/bin/bc.  It must be a program that functions as a filter (in
    # the Unix sense, i.e., reading from standard input and writing to
    # standard output).  Standard error is not redirected, so any errors
    # will appear on the user's terminal.
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error(me ": Bad parameters")
    save_line = $0
    save_lineno = LINE()
    delim = $1
    if (NF == 1) {              # @shell DELIM
        sendto = user_shell()
    } else {                    # @shell DELIM /usr/ucb/mail
        $1 = ""
        sub("^[ \t]*", "")
        sendto = rm_quotes(dosubs($0))
    }

    shell_data_blk = blk_new(BLK_AGG)
    readstat = read_lines_until(delim, shell_data_blk)
    if (readstat != TRUE)
        error(me ": Delimiter '" delim "' not found:" save_line, "", save_lineno)

    # Postpone checking security level until now so we can properly read
    # to the delimiter.
    if (secure_level() >= SEC_SECURE)
        security_violation(me ": Forbidden")

    shell_text_in = blk_to_string(shell_data_blk)
    dbg__print("parse", 5, sprintf("(xeq_cmd__shell) shell_text_in='%s'", shell_text_in))

    input_file  = mktemp(tmpdir() "m2ShInp.XXXXXX")
    output_file = mktemp(tmpdir() "m2ShOut.XXXXXX")
    print dosubs(shell_text_in) > input_file
    close(input_file)

    # Don't tell me how fragile this is, we're whistling past the graveyard
    # here.  But it suffices to run /bin/sh, which is enough for now.
    shell_cmdline = sprintf("%s < %s > %s", sendto, input_file, output_file)
    flush_stdout(SYNC_FORCE)    # force flush stdout
    sys_write("__SYSVAL__", system(shell_cmdline))
    agg_block = blk_new(BLK_AGG)

    while (TRUE) {
        getstat = getline line < output_file
        if (getstat == ERROR)
            warn(me ": Error reading file '" output_file "'")
        if (getstat != OKAY)
            break
        blk_append(agg_block, OBJ_TEXT, line)
    }
    close(output_file)
    if ("rm" in PROG) {
        exec_prog_cmdline("rm", ("-f " input_file))
        exec_prog_cmdline("rm", ("-f " output_file))
    } else if (debugging_enabled_p()) {
        warn(me ": PROG[rm] not defined; '"  input_file "' not deleted")
        warn(me ": PROG[rm] not defined; '" output_file "' not deleted")
    }
    ship_out(OBJ_BLKNUM, agg_block)
    blk_master_delete(agg_block)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  S P L I T
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @split        SYM LIS [FS]
function xeq_cmd__split(cmd, cmdline,
                        sym, lis, count, info, code, level,
                        val, k, tmparr, agg_block,
                        wantfs, tmpfs, me, ins)
{
    dbg__print("cmd", 3, sprintf("(xeq_cmd__split) START"))
    me = "@" cmd
    $0 = cmdline
    if (NF < 2)
        error(me ": Bad parameters")
    sym = $1
    lis = $2

    # See if there's an (optional) FS
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")
    if ($0 != EMPTY) {
        wantfs = TRUE
        tmpfs = $0
    } else if (sym_defined_p("__FS__")) {
        wantfs = TRUE
        tmpfs = sym_fetch("__FS__")
    } else
        wantfs = FALSE

    # Check array LIS.
    level = info__create_from_text(lis, info)
    ins = info__get(info, "ns")
    info__gate(OP_UPDATE, TYPE_LIST, info, ins, curr_level(), me, TRUE)
    lis_clear(ins, lis, level)

    # Create a new Agg block
    agg_block = blk_new(BLK_AGG)
    dbg__print("parse", 5, sprintf("(xeq_cmd__split) symtab[%s, '%s','%s',%d,'agg_block'] = %d",
                                 ins, lis, NOKEY, level, agg_block))
    symtab[ins, lis, NOKEY, level, "agg_block"] = agg_block
    blktab[agg_block, 0, "count"] = 0

    # Do split
    val = sym_fetch(sym)
    if (emptyp(val))
        warn(me ": Symbol '" sym "' is null")
    else {
        count = wantfs ? split(val, tmparr, tmpfs) \
                       : split(val, tmparr)
        for (k = 1; k <= count; k++)
            blk_append(agg_block, OBJ_TEXT, tmparr[k])
        blktab[agg_block, 0, "count"] = count
    }

    dbg__print("cmd", 3, sprintf("(xeq_cmd__split) END"))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  S Y S C M D
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @syscmd       CMDLINE ...
function xeq_cmd__syscmd(cmd, cmdline,
                        rc)
{
    cmdline = sprintf("%s >%s 2>%s" , cmdline, NULL, NULL)
    dbg__print("cmd", 3, sprintf("(xeq_cmd__syscmd) START; cmdline='%s'", cmdline))
    if (secure_level() >= SEC_SECURE)
        security_violation("@syscmd: Forbidden")

    flush_stdout(SYNC_FORCE)
    rc = system(cmdline)
    sys_write("__SYSVAL__", rc)
    dbg__print("cmd", 3, sprintf("(xeq_cmd__syscmd) END; rc=%d", rc))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =


#*****************************************************************************
#
#       @  T R A C E M O D E
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @tracemode    FLAG...
function xeq_cmd__tracemode(cmd, cmdline,
                            i, flag, add_rem, letters)
{
    dbg__print("trace", 3, sprintf("(xeq_cmd__tracemode) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0) {
        # Reset flags to default
        sys_write("__TRACEMODE__", TRACE_DEFAULT_SET)
        return
    }

    letters = $1
    if (!match(letters, "^[-+" TRACE_ALL_SET "][-+" TRACE_ALL_SET "]*$"))
        error("@tracemode: Bad parameters")

    add_rem = TRUE              # add_rem == TRUE  -> Adding flags
                                # add_rem == FALSE -> Removing flags
    if (first(letters) != "+" && first(letters) != "-")
        # Not a + or -, so override old flags
        sys_write("__TRACEMODE__", EMPTY)
    for (i = 1; i <= length(letters); i++) {
        flag = substr(letters, i, 1)
        if (flag == "+")
            add_rem = TRUE
        else if (flag == "-")
            add_rem = FALSE
        else {
            if (flag == TRACE_SET_ON)
                sys_write("__TRACE__", add_rem)
            else if (flag == TRACE_WILDCARD_ALL_FLAGS) {
                if (add_rem)
                    sys_write("__TRACE__", add_rem)
                sys_write("__TRACEMODE__", add_rem ? TRACE_ALL_SET : EMPTY)
            } else
                sys_write("__TRACEMODE__", flag_set_clear(sys_read("__TRACEMODE__", NOKEY),
                                                          add_rem ? flag : "",
                                                          add_rem ? ""   : flag))
        }
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  T R A C E O F F
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @traceoff     [SYM...]
function xeq_cmd__traceoff(cmd, cmdline,
                           i, info, sym, level, code, ins)
{
    dbg__print("trace", 3, sprintf("(xeq_cmd__traceoff) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0) {
        # Clear "t" trace flag
        sys_write("__TRACEMODE__", flag_set_clear(sys_read("__TRACEMODE__", NOKEY),
                                                  EMPTY, TRACE_ALL))
        # Set __TRACE__ to False
        sys_write("__TRACE__", FALSE)
    } else {
        # Clear Tracing for every symbol mentioned
        i = 0
        while (++i <= NF)
            trace_ll_off($i)
    }
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  T R A C E O N
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @traceon      [SYM...]
function xeq_cmd__traceon(cmd, cmdline,
                          i, info, sym, level, code, ins)
{
    dbg__print("trace", 3, sprintf("(xeq_cmd__traceon) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0) {
        # Set "t" trace flag
        sys_write("__TRACEMODE__", flag_set_clear(sys_read("__TRACEMODE__", NOKEY),
                                                  TRACE_ALL, EMPTY))
    } else {
        # Set Tracing for every symbol mentioned
        i = 0
        while (++i <= NF)
            trace_ll_on($i)
    }
    sys_write("__TRACE__", TRUE)
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
function xeq_cmd__typeout(cmd, cmdline,
                          src_block)
{
    if (stk_empty_p(__source_stack))
        panic("(xeq_cmd__typeout) Source stack is empty")

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
function xeq_cmd__undefine(cmd, cmdline,
                           name, info, level, code, nparts, type,
                           f, s, d, del_list,
                           me, ins)
{
    me = "@" cmd
    $0 = cmdline
    if (NF != 1)
        error(me ": Bad parameters")
    name = $1

    dbg__print("sym", 4, sprintf("(xeq_cmd__undefine) START; name=%s", name))

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
    #     dbg__print("sym", 3, ("About to sym_destroy('" sym "')"))
    #     sym_destroy(sym)
    # }

    # A better way:
    # Scan sym => name, key
    # if ((nparts = nam__scan(name, info)) == ERROR)
    #     error("[@undefine] Scan error, " __m2_msg)
    # if ((level = nam__lookup(info)) == NAME_NOT_FOUND) {
    #     error("(xeq_cmd__undefine) '" name "' not found")
    # }
    level = info__create_from_text(name, info)
    type = info__get(info, "type")
    ins  = info__get(info, "ns")
    info__gate(OP_DELETE, type, info, ins, curr_level(), me, TRUE)

    if (type == TYPE_SYMBOL) {
        name = info__get(info, "name")
        # System symbols, even unprotected ones -- despite being subject
        # to user modification -- cannot be undefined.
        # if (nam_system_p(name))
        #     error("Name '" name "' not available:" $0)
        if (info__get(info, "protected"))
            error(sprintf("%s: Name '%s' is protected%s", me, name, VERBOSE() ? " [xeq_cmd__undefine:J]" : ""))

        dbg__print("sym", 3, ("About to sym_destroy_ns(" ins ", '" name "')"))
        sym_destroy_ns(ins, name, info["key"], info["level"])

    } else if (type == TYPE_ARRAY) {
        for (s in symtab) {
            split(s, f, SUBSEP)
            if (f[SFN_NS] == ins && f[SFN_NAME] == name && f[SFN_LEVEL]+0 == info["level"])
                del_list[f[1], f[2], f[3], f[4], f[5]] = TRUE
        }
        for (d in del_list) {
            split(d, f, SUBSEP)
            dbg__print("sym", 3, sprintf("(xeq_cmd__undefine) Delete symtab[%s, '%s', '%s', %d, %s]",
                                         f[1], f[2], f[3], f[4], f[5]))
            delete symtab[f[1], f[2], f[3], f[4], f[5]]
        }

    } else if (type == TYPE_SEQUENCE)
        seq_destroy_ns(ins, name)
    else if (type == TYPE_USER)
        cmd_destroy(info)
    else
        error("(xeq_cmd__undefine) '" name "' of type " type " cannot be destroyed")
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
function xeq_cmd__undivert(cmd, cmdline,
                           i, stream)
{
    $0 = cmdline
    dbg__print("divert", 2, sprintf("(xeq_cmd__undivert) START dstblk=%d, cmdline='%s'",
                                   curr_dstblk(), cmdline))
    dbg__print_block("divert", 8, curr_dstblk(), "(xeq_cmd__undivert) curr_dstblk()")
    if (NF == 0) {
        undivert_all()
        return
    }

    if (cmdline ~ "^[-0-9 \t]+$") {
        # @undivert N1 N2... : process one or more streams (in specified, not numerical, order)
        i = 0
        while (++i <= NF) {
            stream = dosubs($i)
            if (!integerp(stream) || stream <= 0)
                # @undivert -1 or 0 => no effect
                continue
            dbg__print("divert", 5, sprintf("(xeq_cmd__undivert) CALLING undivert(%d)", stream))
            undivert(stream)
        }
    } else if (cmdline ~ "^[0-9]+[ \t]+.*[^0-9]") {
        # @undivert N FILE : process one stream, output to FILE
        if (secure_level() >= SEC_SECURE)
            security_violation("@undivert: Output file forbidden")
        stream = $1
        sub(/^[^ \t]+[ \t]+/, "", cmdline) # a + this time because ARG is required
        dbg__print("divert", 5, sprintf("(xeq_cmd__undivert) CALLING undivert_to_file(%d,'%s')", stream, cmdline))
        undivert_to_file(stream, cmdline)
    } else {
        error("@undivert: Bad form")
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
    dbg__print("while", 3, sprintf("(parse__while) START dstblk=%d, $0='%s'", curr_dstblk(), $0))
    name = $1
    $1 = ""
    sub("^[ \t]*", "")

    raise_level()

    # Create two new blocks: one for while_block, other for true branch
    while_block = blk_new(BLK_WHILE)
    dbg__print("while", 5, "(parse__while) New block # " while_block " type " ppf__label(blk_type(while_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("while", 5, "(parse__while) New block # " body_block " type " ppf__label(blk_type(body_block)))

    blktab[while_block, 0, "condition"] = $0
    blktab[while_block, 0, "init_negate"] = (name == "@__m2__::until")
    blktab[while_block, 0, "body_block"] = body_block
    blktab[while_block, 0, "dstblk"] = body_block
    blktab[while_block, 0, "blkvalid"]      = FALSE
    dbg__print_block("while", 7, while_block, "(parse__while) while_block")
    stk_push(__parse_stack, while_block) # Push it on to the parse_stack

    dbg__print("while", 5, "(parse__while) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endif
    dbg__print("while", 5, "(parse__while) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@while) Parse error")

    dbg__print("while", 5, "(parse__while) END; => " while_block)
    return while_block
}


# @endwhile
function parse__endwhile(                    while_block)
{
    dbg__print("while", 3, sprintf("(parse__endwhile) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__label(curr_atmode())))
    if (check__parse_stack(BLK_WHILE) != ERR_OKAY)
        error("[@endwhile] Parse error; " __m2_msg)
    while_block = stk_pop(__parse_stack)

    blktab[while_block, 0, "blkvalid"] = TRUE
    lower_level()
    return while_block
}


function xeq__BLK_WHILE(while_block,
                        block_type, body_block, condition, condval, negate, want_break)
{
    block_type = blk_type(while_block)
    dbg__print("while", 3, sprintf("(xeq__BLK_WHILE) START dstblk=%d, while_block=%d, type=%s",
                               curr_dstblk(), while_block, ppf__label(block_type)))

    dbg__print_block("while", 7, while_block, "(xeq__BLK_WHILE) while_block")
    if ((block_type != BLK_WHILE) || \
        (blktab[while_block, 0, "blkvalid"] != TRUE))
        panic("(xeq__BLK_WHILE) Bad while_block config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    body_block = blktab[while_block, 0, "body_block"]
    condition = blktab[while_block, 0, "condition"]
    negate = blktab[while_block, 0, "init_negate"]
    condval = evaluate_boolean(condition, negate)
    dbg__print("while", 2, sprintf("(xeq__BLK_WHILE) Initial evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
    if (condval == ERROR)
        error("@while: Error evaluating condition '" condition "'")

    while (condval) {
        raise_level()
        dbg__print("while", 5, sprintf("(xeq__BLK_WHILE) CALLING execute__block(%d)",
                                       body_block))
        execute__block(body_block)
        dbg__print("while", 5, sprintf("(xeq__BLK_WHILE) RETURNED FROM execute__block()"))
        lower_level()

        condval = evaluate_boolean(condition, negate)
        dbg__print("while", 3, sprintf("(xeq__BLK_WHILE) Repeat evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
        if (condval == ERROR)
            error("@while: Error evaluating condition '" condition "'")

        # Check for break or continue
        if (flag_anytrue_p(__m2_config_flags, MODE_XEQ_BREAK MODE_XEQ_CONTINUE)) {
            want_break = flag_1true_p(__m2_config_flags, MODE_XEQ_BREAK)
            __m2_config_flags = flag_set_clear(__m2_config_flags,
                                               MODE_XEQ_NORMAL,
                                               MODE_XEQ_BREAK MODE_XEQ_CONTINUE MODE_XEQ_RETURN)
            if (want_break)
                break
       }
    }

    dbg__print("while", 3, sprintf("(xeq__BLK_WHILE) END"))
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
                   ppf__bool(blktab[blknum, 0, "blkvalid"]),
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
function xeq_cmd__wrap(cmd, cmdline)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__wrap) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__label(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error("Bad parameters:" $0)

    __wrap_text[++__wrap_cnt] = $0
    dbg__print("parse", 5, sprintf("(xeq_cmd__wrap) END; text='%s'", $0))
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
    dbg__print("ship_out", 3, sprintf("(ship_out) START dstblk=%d, obj_type=%s, obj='%s'",
                                      dstblk, ppf__label(obj_type), obj))
    if (dstblk < 0) {
        dbg__print("ship_out", 3, "(ship_out) END, because dstblk <0")
        return
    }
    if (dstblk != TERMINAL) {
        dbg__print("ship_out", 5, sprintf("(ship_out) END Appending obj '%s' to block %d", obj, dstblk))
        blk_append(dstblk, obj_type, obj)
        return
    }

    # dstblk is zero, so obj must be executed (or text printed)
    if (obj_type == OBJ_BLKNUM) {
        dbg__print("ship_out", 5, sprintf("(ship_out) CALLING execute__block(%d)", obj))
        execute__block(obj)
        dbg__print("ship_out", 5, sprintf("(ship_out) RETURNED FROM execute__block"))

    } else if (obj_type == OBJ_CMD) {
        name = extract_cmd_name(obj)
        #print_stderr("NAME=" name)
        sub(/^[ \t]*[^ \t]+[ \t]*/, "", obj)

        # XXX By the time we are shipping out, everything should be qualfied
        #obj = qualify(obj)

        # Unlike every other command, @wrap ships out its line literally here.
        # Function end_program(), which handles wrapped text, calls dosubs().
        if (name != "__m2__::wrap") {
            dbg__print("ship_out", 7, "(ship_out) [OBJ_CMD] Calling dosubs('" obj "')")
            obj = dosubs(obj)
        }
        dbg__print("ship_out", 3, sprintf("(ship_out) CALLING execute__command('%s', '%s')",
                                         name, obj))
        execute__command(name, obj)
        dbg__print("ship_out", 3, sprintf("(ship_out) RETURNED FROM execute__command('%s', ...)",
                                         name))

    } else if (obj_type == OBJ_TEXT) {
        dbg__print("ship_out", 5, sprintf("(ship_out) CALLING execute__text(obj)"))
        execute__text(obj)
        dbg__print("ship_out", 5, sprintf("(ship_out) RETURNED FROM execute__text(obj)"))

    } else if (obj_type == OBJ_USER) {
        dbg__print("ship_out", 3, sprintf("(ship_out) CALLING execute__user(obj)"))
        # Don't care about @return value or not, since injection into
        # the output stream is not possible
        execute__user(obj)
        dbg__print("ship_out", 3, sprintf("(ship_out) RETURNED FROM execute__user(obj)"))

    } else
        panic("(ship_out) Unrecognized obj_type '" obj_type "'")

    dbg__print("ship_out", 3, sprintf("(ship_out) END"))
}


# Given an agg_block, print each of its slots to a file.
function ship_out_to_file(block, file,
                       i, lim, slot_type, value)
{
    dbg__print("ship_out", 3, sprintf("(ship_out_to_file) START; block=%d, file='%s'",
                                     block, file))
    if (blk_type(block) != BLK_AGG)
        panic(sprintf("(ship_out_to_file) Block %d has type %s, not AGG",
                      block, ppf__label(blk_type(block))))

    lim = blktab[block, 0, "count"]
    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(block, i)
        if (slot_type != OBJ_TEXT)
            panic(sprintf("(ship_out_to_file) Block %d slot %d has type %s, not TEXT",
                          block, i, ppf__label(slot_type)))

        value = blk_ll_slot_value(block, i)
        print value > file
    }
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
        return sys_read("__EXPR__", NOKEY)

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
function _c3_expr(    var, e, op1, op2, m2,
                      info)
{
    if (match(substr(_c3__Sexpr, _c3__f), /^[A-Za-z#_][A-Za-z#_0-9]*=[^=]/)) {
        var = _c3_advance()
        sub(/=.*$/, "", var)
        info__create_from_text(var, info)
        info__gate(OP_UPDATE, TYPE_SYMBOL, info, curr_ns(), curr_level(), "@expr", TRUE)
        # match() sets RLENGTH which includes the match character [^=].
        # But that's the start of the value -- I need to back up over it
        # to read the value properly.
        _c3__f--
        return syminfo_store(info, _c3_expr()+0)
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
                error("Division by zero:@expr " _c3__Sexpr "@")
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
function _c3_factor3(    e, fun, e2,
                         info, level)
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
        error(sprintf("Unknown function '%s':@expr %s@",
                      (last(fun) == "(") ? chop(fun) : fun, _c3__Sexpr))
    }

    # (expr) | function(expr) | function(expr,expr)
    if (match(e, /^([A-Za-z#_][A-Za-z#_0-9]+)?\(/)) {
        fun = _c3_advance()
        # These are for *1 argument* numeric functions only, not strings/symbols
        if (fun ~ /^(abs|acos|asin|ceil|cos|deg|exp|floor|int|lg|ln|log(10)?|odd|rad|randint|round|sign|sin|sqrt|srand|tan)?\(/) {
            e = _c3_expr()
            e = _c3_calculate_function(fun, e)
        } else if (fun ~ /^defined\(/) {
            e2 = substr(e, 9, length(e)-9)
            dbg__print("expr", 7, sprintf("defined(): e2='%s'", e2))
            _c3__f += length(e2)
            e = sym_defined_p(e2) ? TRUE : FALSE
        # These are two arg numeric functions
        } else if (fun ~ /^(atan2|gcd|hypot|lcm|max|min|pow)\(/) {
            e = _c3_expr()
            if (substr(_c3__Sexpr, _c3__f, 1) != ",")
                error(sprintf("Missing ',' at '%s'", substr(_c3__Sexpr, _c3__f)))
            _c3__f++
            e2 = _c3_expr()
            e = _c3_calculate_function2(fun, e, e2)
        } else
            error(sprintf("Unknown function '%s':@expr %s@",
                          (last(fun) == "(") ? chop(fun) : fun, _c3__Sexpr))

        if (substr(_c3__Sexpr, _c3__f++, 1) != ")")
            error(sprintf("Missing ')' at '%s'", substr(_c3__Sexpr, _c3__f)))
        return e
    }

    # predefined, symbol, or sequence name
    if (match(e, /^[A-Za-z#_][A-Za-z#_0-9]*/)) {
        e2 = _c3_advance()
        level = info__create_from_text(e2, info)
        # print_stderr("e2 => " e2)
        # print_stderr("syminfo_valid_p(info, e2) => " syminfo_valid_p(info, e2))
        # print_stderr("syminfo_defined_p(info)) => " syminfo_defined_p(info))
        if      (e2 == "e")   return EULER
        else if (e2 == "pi")  return PI
        else if (e2 == "tau") return TAU
        else if (syminfo_valid_p(info, e2) && syminfo_defined_p(info)) {
            e = sym_fetch(e2)
            dbg__print("expr", 7, sprintf("(_c3_factor3) Symbol '%s' => %s", e2, e))
            return e
        } else if (info__get(info, "type") == TYPE_SEQUENCE &&
                   info__get(info, "defined") == TRUE) {
            e = seq_ll_read_ns(info__get(info, "ns"), e2)
            dbg__print("expr", 7, sprintf("(_c3_factor3) Sequence '%s' => %s", e2, e))
            return e
        }
    }

    # error
    error(sprintf("Expected number or '(' at '%s'", substr(_c3__Sexpr, _c3__f)))
}


# Mathematical functions of one variable
function _c3_calculate_function(fun, e,
                                c)
{
    if (fun == "(")        { return e }
    if (fun == "abs(")     { return abs(e) }    # e < 0 ? -e : e
    if (fun == "acos(")    { if (e < -1 || e > 1)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return atan2(sqrt(1 - e^2), e) }
    if (fun == "asin(")    { if (e < -1 || e > 1)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return atan2(e, sqrt(1 - e^2)) }
    if (fun == "ceil(")    { c = int(e)
                             return e > c ? c+1 : c }
    if (fun == "cos(")     { return cos(e) }
    if (fun == "deg(")     { return e * (360 / TAU) }
    if (fun == "exp(")     { return exp(e) }
    if (fun == "floor(")   { c = int(e)
                             return e < c ? c-1 : c }
    if (fun == "int(")     { return int(e) }
    if (fun == "lg(")      { if (e <= 0)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return log(e) / LOG2 }
    if (fun == "log(" || fun == "ln(")
                           { if (e <= 0)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return log(e) }
    if (fun == "log10(")   { if (e <= 0)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return log(e) / LOG10 }
    if (fun == "odd(")     { return e % 2 }
    if (fun == "rad(")     { return mth__deg2rad(e) }  # e * (TAU / 360) }
    if (fun == "randint(") { if (e < 1)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return randint2(1,int(e)) }
    if (fun == "round(")   { return mth__round(e) }
    if (fun == "sign(")    { return mth__sign(e) }
    if (fun == "sin(")     { return sin(e) }
    if (fun == "sqrt(")    { if (e < 0)
                                 error(sprintf("%s%g): Math expression error", fun, e))
                             return sqrt(e) }
    if (fun == "srand(")   { return srand(e) }
    if (fun == "tan(")     { return mth__tan(e) }
    error(sprintf("@expr: Unknown function '%s'",
                  (last(fun) == "(") ? chop(fun) : fun))
}


# Functions of two variables
function _c3_calculate_function2(fun, e, e2,
                                 hmax, hmin, hr)
{
    if (fun == "atan2(")   return atan2(e, e2)
    if (fun == "gcd(")     return mth__gcd(e, e2)
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
    if (fun == "lcm(")     return mth__lcm(e, e2)
    if (fun == "max(")     return e > e2 ? e : e2
    if (fun == "min(")     return e < e2 ? e : e2
    if (fun == "pow(")     return e ^ e2
    error(sprintf("@expr: Unknown function '%s'",
                  (last(fun) == "(") ? chop(fun) : fun))
}


function _c3_advance(    tmp)
{
    tmp = substr(_c3__Sexpr, _c3__f, RLENGTH)
    _c3__f += RLENGTH
    return tmp
}

# convert degrees to radians
function mth__deg2rad(e)
{
    return e * DEG_RADIANS
}

# tangent
function mth__tan(e,    c)
{
    c = cos(e)
    if (c == 0)
        error(sprintf("tan(%g): Math expression error", e))
    return sin(e) / c
}

# greatest common divisor
function mth__gcd(e, e2)
{
    return e2 ? mth__gcd(e2, e % e2) \
              : e
}

# least common multiple
function mth__lcm(e, e2)
{
    return (e == 0 || e2 == 0) ? 0 \
        : abs(e * e2 / mth__gcd(e, e2))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       D O S U B S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       The dosubs() function actually performs the macro substitution.  It
#       processes the line left-to-right, replacing macro names with their
#       bodies.  The rescanning of the new line is left to the higher-level
#       logic that is jointly managed by readline() and dofile().  This
#       version is considerably more efficient than the brute-force approach
#       used in the m0 programs.
#
#       M2 uses a fast substitution function.  The idea is to process the
#       string from left to right, searching for the first substitution to be
#       made.  We then make the substitution, and rescan the string starting
#       at the fresh text.  We implement this idea by keeping two strings: the
#       text processed so far is in L (for Left), and unprocessed text is in R
#       (for Right).
#
#       Here is the pseudocode for dosubs:
#
#               L = Empty
#               R = Input String
#               while R contains an "@" sign do:
#                   let R = A @ B; set L = L A and R = B
#                   if R contains no "@" then:
#                       L = L "@"
#                       break ;
#                   let R = A @ B; set M = A and R = B
#                   if M is in SymTab then:
#                       R = SymTab[M] R ;
#                   else:
#                       L = L "@" M
#                       R = "@" R ;;
#               return L R
#
#       Note use of macro_*() functions, described below.
#
#*****************************************************************************
function dosubs(s,
                expand, i, j, L, M, nparam, p, pval, param, R, fn,
                x, inc_dec, pre_post, subcmd, lfn, incr, wrkm,
                fninfo, level, macro)
{
    trace(TRACE_COMMAND, "dosubs", sprintf("[Execute] dosubs('%s')", s))
    dbg__print("dosubs", 5, sprintf("(dosubs) START s='%s'", s))
    inc_dec = pre_post = 0      # track ++ or -- on sequences
    macro["okay"] = FALSE       # Make sure Awk knows macro is an array

    L = EMPTY                   # Left of current pos  - ready for output
    R = s                       # Right of current pos - as yet unexamined
    while (TRUE) {
        # Check entire string for recursive evaluation:  @{...}
        if (index(R, TOK_AT_BRACE) > 0)
            R = expand_braces(R)

        if ((i = index(R, TOK_AT)) == NOT_FOUND)
            break

        # While R contains an "@" sign
        dbg__print("dosubs", 7, sprintf("(dosubs) Top of loop: L='%s', R='%s'", L, R))
        L = L substr(R, 1, i-1)
        R = substr(R, i+1)      # Currently scanning @

        # Look for a second "@" beyond the first one.  If not found,
        # this can't be a valid m2 substitution.  Ignore it, we're done.
        if ((i = index(R, TOK_AT)) == NOT_FOUND) {
            L = L TOK_AT
            break
        }

        # A lone "@" followed by whitespace is not valid syntax.  Ignore it,
        # but keep processing the line.
        if (isspace(first(R))) {
            L = L TOK_AT
            continue
        }

        M = substr(R, 1, i-1)   # Middle
        dbg__print("dosubs", 6, sprintf("(dosubs) M='%s'", M))
        R = substr(R, i+1)

        # s == L  @  M  @  R
        #               ^---i

        macro_initialize(macro, M)
        macro_expand(macro)
        if (macro["okay"] == TRUE) {
            # Kluge for @srem ...@ to remove preceding whitespace
            if (macro["name"] == "srem") # was macro["fn"]
                sub(/[ \t]+$/, "", L)
            trace(TRACE_EXPANSION, macro["fn"], sprintf("[Expand] @%s@ => '%s'",
                                                        macro["urtext"], macro["expansion"]))
            R = macro["expansion"] R
        } else {
            # If undefined symbol, throw an error (if __STRICT__[def] is
            # True, the default) or pass through the urtext (M) unchanged.
            if (strictp("def"))
                error(sprintf("@%s@: Name '%s' not defined%s",
                              macro["urtext"], macro["fn"],
                              VERBOSE() ? " [(dosubs) macro_expand() failed && __STRICT__[def] BBB]" : ""))
            L = L TOK_AT M
            R =   TOK_AT R
        }
        i = index(R, TOK_AT)
    }

    dbg__print("dosubs", 3, sprintf("(dosubs) END; Out of loop => '%s'", L R))
    return L R
}


# macro["brace"]     = TRUE if "{" seen in urtext
# macro["expansion"] = macro expansion text
# macro["fn"]        = function name, 1st param, as in urtext, maybe qualified
# macro["okay"]      = TRUE/FALSE
# macro["name"]      = plain function name, any namespace removed
# macro["ns"]        = namespace, or "" if plain name
# macro["qual"]      = TRUE if "::" seen in fn
# macro["urtext"]    = original M text
#
# macro_expand() does the real work of transforming specific macro-invoking
# text from its original call to its expanded form.  It expects its argument
# to be something it can work on.  In contrast, dosubs() is much more
# laissez-faire -- it is given some text to scan, from somewhere, but if
# the @ signs don't quite work out, no worries.
#
# Use this macro[] array to control macro expansion results due to the
# need to track two return values: whether the expansion went "okay" and
# what the "expansion" text actually is.
function macro_initialize(macro, urtext,
                          fn, param, br, q)
{
    macro["brace"]     = index(urtext, TOK_LBRACE) > 0
    macro["expansion"] = EMPTY
    macro["okay"]      = FALSE
    macro["urtext"]    = urtext

    split(urtext, param)
    fn = param[1]
    # Check for @foo{...} -- isolate fn to scan @foo{a}{b}{c}...@ better
    if ((br = index(fn, TOK_LBRACE)) > 0)
        # was macro["brace"]); but that seems quite bogus now
        fn = substr(fn, 1, br - 1)
    if (macro["qual"] = (q = index(fn, TOK_NS_QUAL)) > 0) {
        # ns::name
        macro["ns"]   = substr(fn, 1, q-1)
        macro["name"] = substr(fn, q+2)
    } else {
        # name
        macro["ns"]   = EMPTY
        macro["name"] = fn
    }
    dbg__print("dosubs", 4, sprintf("(macro_initialize) fn='%s'", fn))
    macro["fn"] = fn            # orig; might be "func" or "ns::func"
}


function macro_set_expansion(macro, expanded_text)
{
    macro["okay"] = TRUE
    macro["expansion"] = expanded_text
}


# In the code that follows:
#
# - M :: Entire text between @'s.  Example: "mid foo 3".
# - fn :: The name of the "function" to call.  The first element
#         of M.  Example: "mid".
# - nparam :: Number of parameters supplied to the function.
#     @mid@         -> nparam == 0      param[0] == mid
#     @mid foo@     -> nparam == 1      param[1] == foo
#     @mid foo 3@   -> nparam == 2      param[2] == 3
#
# A function's parameter N is available in zero-based array param[N].
#   Consider "mid foo 3".  nparam is 2.
#   The function name is found in param[0].
#   The symbol (foo) is at param[1] and integer (3) is at param[2].
#
# After an expansion is set with macro_set_expansion(),
#   macro["okay"] becomes True, allowing dosubs() to execute
#       R = macro["expansion"] R
#   which injects the expansion text just before the current value
#   of R.  (R is local to dosubs(), not this function.)  It is what
#   is to the right of the current position and contains as yet
#   unexamined text that needs to be evaluated for possible macro
#   processing.  This is the data we were going to evaluate anyway.
#   In other words, this injects the result of "invoking" fn.
#
# Eventually the big while loop exits and dosubs() returns "L R".
function macro_expand(macro,
                      i, j, l, M, nparam, p, pval, param, r, fn,
                      x, inc_dec, pre_post, subcmd, lfn, incr, wrkM,
                      fninfo, fntype, fnname, fnns, level, args, orf, orn, orv)
{
    M = macro["urtext"]
    nparam = split(M, param)
    fn = macro["fn"]

    # Re-create nparam and param[] according to braces,
    # not split() on whitespace
    if (macro["brace"]) {
        split("", param)       # Start by deleting all entries
        param[nparam = 0] = nam__unqualify(fn) # 1st element is function name
        wrkM = substr(M, length(fn) + 1)
        dbg__print("dosubs", 6, sprintf("(macro_expand) Before loop, wrkM='%s'", wrkM))
        while (match(wrkM, "^{[^}]*}")) {
            dbg__print("dosubs", 6, sprintf("(macro_expand) Top of loop, wrkM='%s'", wrkM))
            p = ++nparam
            pval = substr(wrkM, RSTART+1, RLENGTH-2)
            dbg__print("dosubs", 6, sprintf("(macro_expand) Parameter %d : %s", p, pval))
            param[p] = pval
            wrkM = substr(wrkM, RLENGTH+1)
        }
        if (!emptyp(wrkM))
            error("(macro_expand) Text remains after scanning params")
        if (dbg__sys_level_p("dosubs", 7)) {
            print_debugfile("m2debug:(macro_expand) nparam=" nparam)
            for (x in param)
                print_debugfile(sprintf("m2debug:(macro_expand) param[%d] = '%s'", x, param[x]))
            print_debugfile("m2debug:(macro_expand) End param[]")
        }
    } else {
        dbg__print("dosubs", 5, "(macro_expand) No brace; fn='" fn "'")
        nparam--
        dbg__print("dosubs", 7, "(macro_expand) nparam=" nparam)
        for (j = 1; j <= nparam; j++)
            param[j] = param[j+1]
        delete param[nparam + 1]
        param[0] = nam__unqualify(fn)
        if (dbg__sys_level_p("dosubs", 7)) {
            for (x in param)
                print_debugfile(sprintf("m2debug:(macro_expand) param[%d] = '%s'", x, param[x]))
            print_debugfile("m2debug:(macro_expand) End param[]")
        }
    }
    lfn = length(fn)

    dbg__print("dosubs", 6, sprintf("(macro_expand) fn=%s, nparam=%d; M='%s'", fn, nparam, M))

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
    } else if (substr(fn, lfn-1, 2) == "++") {
        inc_dec  = +1
        pre_post = +1
        fn = substr(fn, 1, lfn-2)
    } else if (substr(fn, lfn-1, 2) == "--") {
        inc_dec  = -1
        pre_post = +1
        fn = substr(fn, 1, lfn-2)
    }

    # Check if it's a known function (formerly SYMFUNC)
    level = info__create_from_text(fn, fninfo)
    fntype = info__get(fninfo, "type")
    fnname = info__get(fninfo, "name")
    fnns   = info__get(fninfo, "ns")
    dbg__print("dosubs", 5, "(macro_expand) fninfo[" fnns TOK_NS_QUAL fnname "] => " fntype)

    if (fnns == M2_ENVNS) {
        if (syminfo_defined_p(fninfo)) {
            #print_stderr("(macro_expand) " info__get(fninfo, "name") " is defined: " sym_ll_read_ns(fnns, fnname, NOKEY, ROOT_LEVEL))
            macro_set_expansion(macro, sym_ll_read_ns(fnns, fnname, NOKEY, ROOT_LEVEL))
        } else if (strictp("env")) {
            error(sprintf("%s '%s' not defined%s",
                          ppf__label(PTYPE_ENV_VAR),
                          fnname, VERBOSE() ? " [(macro_expand) && __STRICT__[env]]" : EMPTY))
        } else {
            trace(TRACE_ENV_VAR, fnname,
                  sprintf("[Env Var Read] %s : Not Found => ''", fnname))
            macro_set_expansion(macro, EMPTY)
        }
    } else if (nam_ll_in_ns(M2_SYSNS, fnname, ROOT_LEVEL) &&
        flag_1true_p((nam_ll_read_ns(M2_SYSNS, fnname, ROOT_LEVEL)), TYPE_FUNCTION)) {
        # Quick check to make sure fninfo is okay
        if (fntype != TYPE_FUNCTION)
            panic("(macro_expand) not TYPE_FUNCTION?")

        if (fnname == "basename")
            macro_set_expansion(macro, xeq_fn__basename(fnname, M, nparam, param))
        else if (fnname =="boolval")
            macro_set_expansion(macro, xeq_fn__boolval(fnname, M, nparam, param))
        else if (fnname =="chr")
            macro_set_expansion(macro, xeq_fn__chr(fnname, M, nparam, param))
        else if (fnname =="comma" || fnname == "scomma")
            macro_set_expansion(macro, xeq_fn__comma(fnname, M, nparam, param))
        else if (fnname =="date"     || fnname == "epoch" ||
                 fnname == "strftime" || fnname == "time"  ||
                 fnname == "tz"       || fnname == "utc")
            macro_set_expansion(macro, xeq_fn__date(fnname, M, nparam, param))
        else if (fnname =="dirname")
            macro_set_expansion(macro, xeq_fn__dirname(fnname, M, nparam, param))
        else if (fnname =="divnl")
            macro_set_expansion(macro, xeq_fn__divnl(fnname, M, nparam, param))
        else if (fnname =="dow")
            macro_set_expansion(macro, xeq_fn__dow(fnname, M, nparam, param))
        else if (fnname == "empty")
            macro_set_expansion(macro, xeq_fn__empty(fnname, M, nparam, param))
        else if (fnname =="execpath" || fnname == "sexecpath")
            macro_set_expansion(macro, xeq_fn__execpath(fnname, M, nparam, param))
        else if (fnname =="expr" || fnname == "sexpr")
            macro_set_expansion(macro, xeq_fn__expr(fnname, M, nparam, param))
        else if (fnname =="format" || fnname == "sprintf")
            macro_set_expansion(macro, xeq_fn__format(fnname, M, nparam, param))
        else if (fnname =="geodist")
            macro_set_expansion(macro, xeq_fn__geodist(fnname, M, nparam, param))
        else if (fnname =="gregdate")
            macro_set_expansion(macro, xeq_fn__gregdate(fnname, M, nparam, param))
        else if (fnname =="hex")
            macro_set_expansion(macro, xeq_fn__hex(fnname, M, nparam, param))
        else if (fnname =="hms")
            macro_set_expansion(macro, xeq_fn__hms(fnname, M, nparam, param))
        else if (fnname =="hr")
            macro_set_expansion(macro, xeq_fn__hr(fnname, M, nparam, param))
        else if (fnname =="ifdef" || fnname == "ifndef")
            macro_set_expansion(macro, xeq_fn__ifdef(fnname, M, nparam, param))
        else if (fnname =="ifelse")
            macro_set_expansion(macro, xeq_fn__ifelse(fnname, M, nparam, param))
        else if (fnname =="ifx")
            macro_set_expansion(macro, xeq_fn__ifx(fnname, M, nparam, param))
        else if (fnname =="index")
            macro_set_expansion(macro, xeq_fn__index(fnname, M, nparam, param))
        else if (fnname =="join" || fnname == "sjoin")
            macro_set_expansion(macro, xeq_fn__join(fnname, M, nparam, param))
        else if (fnname =="left")
            macro_set_expansion(macro, xeq_fn__left(fnname, M, nparam, param))
        else if (fnname =="ljust"  || fnname == "rjust"  || fnname == "center" || \
                 fnname == "sljust" || fnname == "srjust" || fnname == "scenter")
            macro_set_expansion(macro, xeq_fn__lrc(fnname, M, nparam, param))
        else if (fnname =="mid" || fnname == "substr")
            macro_set_expansion(macro, xeq_fn__mid(fnname, M, nparam, param))
        else if (fnname =="mjd")
            macro_set_expansion(macro, xeq_fn__mjd(fnname, M, nparam, param))
        else if (fnname =="mktemp")
            macro_set_expansion(macro, xeq_fn__mktemp(fnname, M, nparam, param))
        else if (fnname =="ns")
            macro_set_expansion(macro, curr_ns())
        else if (fnname =="ord")
            macro_set_expansion(macro, xeq_fn__ord(fnname, M, nparam, param))
        else if (fnname =="rem" || fnname == "srem")
            macro_set_expansion(macro, EMPTY)
        else if (fnname =="right")
            macro_set_expansion(macro, xeq_fn__right(fnname, M, nparam, param))
        else if (fnname =="rot13")
            macro_set_expansion(macro, xeq_fn__rot13(fnname, M, nparam, param))
        else if (fnname =="space" || fnname == "spaces" ||
                 fnname == "tab"   || fnname == "tabs")
            macro_set_expansion(macro, xeq_fn__spaces(fnname, M, nparam, param))
        else if (fnname =="lc" || fnname == "len" || fnname == "uc")
            macro_set_expansion(macro, xeq_fn__str_fn(fnname, M, nparam, param))
        else if (fnname =="trim" || fnname == "ltrim" || fnname == "rtrim")
            macro_set_expansion(macro, xeq_fn__trim(fnname, M, nparam, param))
        else if (fnname =="uuid")
            macro_set_expansion(macro, uuid())
        else if (fnname =="xbasename" || fnname == "xdirname")
            macro_set_expansion(macro, xeq_fn__xname(fnname, M, nparam, param))
        else
            panic("(macro_expand) Function '" fn "' not handled")

    # Check if it's an array
    #} else if (sym_valid_p(fn) && arrayp(fn)) {
    } else if (info__get(fninfo, "valid") && arrayp(fn)) {
        macro_set_expansion(macro, sym_fetch(fn))

        # Check if it's a User Command
    } else if (fntype == TYPE_USER &&
               info__get(fninfo, "defined") == TRUE) {
        # print_stderr("(dosubs) " fn " is a user command")
        # print_stderr("(dosubs) Args: '" M "'")
        args = scan__usercmd_call(TOK_AT M, fninfo)
        # print_stderr("(dosubs) args:" ppf__sepstr(args))

        # Save & restore @return values, so that nested User calls
        # don't clobber values
        orf = __return_found; __return_found = FALSE
        orv = __return_value; __return_value = EMPTY
        execute__user(args)
        if (!__return_found && strictp("def"))
            error(TOK_AT fn ": Command did not return a value")

        macro_set_expansion(macro, __return_value)
        __return_found = orf
        __return_value = orv

    # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
    # } else if (sym_valid_p(fn) && (sym_defined_p(fn) || sym_deferred_p(fn))) {
    } else if (info__get(fninfo, "type") == TYPE_SYMBOL &&
               info__get(fninfo, "defined") == TRUE) {
        macro_set_expansion(macro, substitute_params(syminfo_fetch(fninfo), nparam, param))

    # Check if it's a sequence
    } else if (info__get(fninfo, "type") == TYPE_SEQUENCE &&
               info__get(fninfo, "defined") == TRUE) {
        dbg__print("dosubs", 3, "(macro_expand) It's a sequence")
        # Check for pre/post increment/decrement.
        # This is only performed on a bare reference.
        if (nparam == 0) {
            #   |          | pre_post | inc_dec |
            #   |----------+----------+---------|
            #   | foo      |        0 |     n/a |
            #   | --foo    |       -1 |      -1 |
            #   | ++foo    |       -1 |      +1 |
            #   | foo--    |       +1 |      -1 |
            #   | foo++    |       +1 |      +1 |
            incr = symtab[fnns, fnname, EMPTY, ROOT_LEVEL, "incr"]
            # Handle prefix increment/decrement
            if (pre_post == -1)
                seq_ll_incr_ns(fnns, fnname, incr * inc_dec)
            # Insert current value with desired formatting
            macro_set_expansion(macro, m2_sprintf(symtab[fnns, fnname, EMPTY, ROOT_LEVEL, "fmt"],
                                                  seq_ll_read_ns(fnns, fnname)))
            # Handle postfix increment/decrement
            if (pre_post == +1)
                seq_ll_incr_ns(fnns, fnname, incr * inc_dec)
        } else {
            if (pre_post != 0)
                error("Bad parameters in '" M "':" $0)
            subcmd = param[1]
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
                    macro_set_expansion(macro, seq_ll_read_ns(fnns, fnname))
                } else if (subcmd == "nextval") {
                    # - nextval :: Increment and return new value of
                    # counter.  No prefix/suffix.
                    seq_ll_incr_ns(fnns, fnname, symtab[fnns, fnname, EMPTY, ROOT_LEVEL, "incr"])
                    macro_set_expansion(macro, seq_ll_read_ns(fnns, fnname))
                } else
                    error("Bad parameters in '" M "':" $0)
            } else {
                # These take one or more params.  Nothing here!
                error("Bad parameters in '" M "':" $0)
            }
        }

    # Check fninfo for ARRAY[] or LIST[]
    } else if ( \
        info__get(fninfo, "lexvalid") == TRUE &&
        (fntype == TYPE_ARRAY || fntype == TYPE_LIST) &&
        info__get(fninfo, "nparts") == 2 &&
        length(info__get(fninfo, "key")) > 0 &&
        info__get(fninfo, "level") != NAME_NOT_FOUND) {

        macro_set_expansion(macro, array_deref_info(fninfo, "@" M "@"))

    # Check fninfo for ARRAY or LIST
    } else if ( \
        info__get(fninfo, "lexvalid") == TRUE &&
        (fntype == TYPE_ARRAY || fntype == TYPE_LIST) &&
        info__get(fninfo, "nparts") == 1 &&
        length(info__get(fninfo, "key")) == 0 &&
        info__get(fninfo, "level") != NAME_NOT_FOUND) {

        #macro_set_expansion(macro, idx__size(fnname, level, info__get(fninfo, "code")))
        macro_set_expansion(macro, idx__size(fninfo))
    }
}


function substitute_params(str, nparam, param,
                           j, x)
{
    # Expand $# => nparam
    if (index(str, "$#") > 0)
        gsub("\\$#", nparam, str)

    # Expand $* to all parameters, space separated
    if (index(str, "$*") > 0) {
        x = ""
        for (j = 1; j <= nparam; j++)
            x = x  param[j]  TOK_SPACE
        gsub("\\$\\*", chop(x), str)
    }

    # Expand $N parameters (includes $0 for macro name)
    # Re-using j, excuse me
    j = MAX_PARAM   # but don't go overboard with params
    # Count backwards to get around $10 problem.
    while (j-- >= 0) {
        if (index(str, "${" j "}") > 0)
            gsub("\\$\\{" j "\\}", (j <= nparam) ? param[j] : "", str)
        if (index(str, "$" j) > 0) {
            #print_stderr("param[" j "] is " param[j])
            gsub("\\$"    j      , (j <= nparam) ? param[j] : "", str)
            #print_stderr("str now '" str "'")
        }
    }

    return str
}


# qualify() can be given random text that it will look through.
# dosubs() and qualify_braces() expect the first arg to be an actual name.
# qualify() is NOP when curr_atmode() == MODE_AT_LITERAL
function qualify(s,
                 orig, r)
{
    dbg__print("qual", 3, sprintf("(qualify) START; s='%s'", s))
    if (curr_atmode() == MODE_AT_LITERAL) {
        trace(TRACE_QUALIFICATION, EMPTY,
              sprintf("[Qualify] NOP/LITERAL => '%s'", s))
        dbg__print("qual", 1, sprintf("(qualify) NOP/LITERAL; RETURNING '%s'", s))
        return s
    }

    orig = s
    if (index(s, TOK_AT_BRACE) > 0) {
        s = qualify_braces(s)
        dbg__print("qual", 7, "(qualify) qualify_braces, s='" s "'")
    }

    r = index(s, TOK_AT) > 0 ? qualify_normal(s) : s
    trace(TRACE_QUALIFICATION, EMPTY,
          sprintf("[Qualify] '%s' => '%s'", orig, r))
    dbg__print("qual", 1, sprintf("(qualify) END; RETURNING '%s'", r))
    return r
}

function qualify_braces(s,
                        r, atbr, ltext, rtext, sym, info, ns, name, key)
{
    dbg__print("qual", 3, "(qualify_braces) s='" s "'")
    r = ""
    while ((atbr = index(s, TOK_AT_BRACE)) > 0) {
        ltext = substr(s, 1,      atbr+1) # includes @{"
        rtext = substr(s, atbr+2)
        dbg__print("qual", 5, "(qualify_braces) ltext='" ltext "', rtext='" rtext "'")
        r = r ltext

        # look up rtext - scan.  Include "-" and "+"
        # to allow for ++ and -- on sequences.
        if (! match(rtext, /^[-+A-Za-z#_:][-+A-Za-z#_0-9:]*/))
            panic("(qualify_braces) not matched")

        sym = substr(rtext, RSTART, RLENGTH)
        dbg__print("qual", 7, sprintf("(qualify_braces) RSTART=%d, RLENGTH=%d, sym='%s'",
                                      RSTART, RLENGTH, sym))

        s = nam__qualify(sym) substr(rtext, RLENGTH+1)
        dbg__print("qual", 6, "(qualify_braces) s now='" s "'")
    }
    dbg__print("qual", 2, "(qualify_braces) RETURNING '" r s "'")
    return r s
}

function qualify_normal(s,
                        r, t, x, ltext, at,
                        sym, info, ns, name, l2, r2, pre, post)
{
    dbg__print("qual", 3, "(qualify_normal) s init='" s "'")
    r = ""
    while (match(s, /(^|[^\\])@[^ {]/)) {
        dbg__print("qual", 7, "(qualify_normal) s match RSTART=" RSTART ", RLENGTH=" RLENGTH)
        if (substr(s, RSTART, 1) == TOK_AT)
            ltext = TOK_AT
        else
            ltext = substr(s, 1, RSTART + 1)
        dbg__print("qual", 5, "(qualify_normal) ltext='" ltext "'")
        r = r ltext
        #
        t = substr(s, RSTART + RLENGTH - 1)
        dbg__print("qual", 6, "(qualify_normal) t='" t "'")
        if (index(t, TOK_AT) == NOT_FOUND)
            # No @, not something for us
            return r t

        if (match(t, /[^\\]@($|[^{])/)) {
            dbg__print("qual", 7, "(qualify_normal) t match RSTART=" RSTART ", RLENGTH=" RLENGTH)
            x = substr(t, 1, RSTART)
            dbg__print("qual", 4, "(qualify_normal) Winner? x='" x "'")

            # Look up x.  For purposes of regexp scanning, include
            # `-' and `+' as permissible characters, for sequence autoincrement
            if (! match(x, /^[-+A-Za-z#_:][-+A-Za-z#_0-9:]*/)) {
                __m2_msg = "Invalid name: '" x "'"
                error(sprintf("Scan error: %s%s", __m2_msg, VERBOSE() ? " [qualify_normal]" : ""))
            }

            # Isolate symbol name, and strip off any leading sequence ++ or --
            sym = substr(x, RSTART, RLENGTH)
            dbg__print("qual", 7, sprintf("(qualify_normal) RSTART=%d, RLENGTH=%d, sym='%s'",
                                          RSTART, RLENGTH, sym))
            r = r nam__qualify(sym)
            s = substr(t, RLENGTH + 1)
            dbg__print("qual", 6, "(qualify_normal) s now='" s "'")

            at = index(s, TOK_AT)
            if (at == NOT_FOUND)
                error("Closing '@' not found: '" s "'")
            r = r substr(s, 1, at - 1) TOK_AT
            s =   substr(s, at + 1)
        }
    }
    dbg__print("qual", 2, "(qualify_normal) RETURNING '" r s "'")
    return r s
}



function nam__qualify(text,
                      orig, info, l2, pre, r2, post, ns, name, key,
                      retval)
{
    orig = text
    pre = post = EMPTY
    l2 = substr(text, 1, 2)
    if (l2 == "++" || l2 == "--") {
        pre = l2
        text = substr(text, 3)
    }
    r2 = substr(text, length(text) - 1, 2)
    if (r2 == "++" || r2 == "--") {
        post = r2
        text = substr(text, 1, length(text) - 2)
    }

    if (nam__scan(text, info) == ERROR)
        error(sprintf("Scan error: '%s', %s%s", info__get(info, "urtext"),
                      __m2_msg, VERBOSE() ? " [nam__qualify]" : ""))
    nam__lookup(info)
    name = info__get(info, "name")
    ns   = info__get(info, "ns")
    if (ns == EMPTY)
        ns = info["ns"] = curr_ns()
    key = info__get(info, "has_bracket") ? TOK_LBRACKET info__get(info, "key") TOK_RBRACKET : EMPTY
    dbg__print("qual", 4, sprintf("(nam__qualify) text='%s' => %s ns='%s', name='%s' %s",
                                  orig, pre, ns, name, post))
    retval = pre ns TOK_NS_QUAL name key post
    return retval
}


function nam__unqualify(text,
                        q)
{
    if ((q = index(text, TOK_NS_QUAL)) > 0 &&
        match(text, "^[A-Za-z#_][A-Za-z#_0-9]*" TOK_NS_QUAL "."))
        text = substr(text, q+2)
    return text
}

# function nam__quick_find_ns(ns, name,
#                             level)
# {
#     for (level = curr_level(); level >= ROOT_LEVEL; level--)
#         if (nam_ll_in_ns(ns, name, level))
#             return nam_ll_read_ns(ns, name, level) # code
#     return EMPTY
# }
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



function awk_basename(s)
{
    sub(/^.*\//, "", s)
    return s
}


#*****************************************************************************
#
#       @  B A S E N A M E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       basename SYM: Base (i.e., file name) of path, in Awk
#
#       basename in Awk, assuming Unix style path separator.
#       Return filename portion of path.  If this is not
#       adequate, consider using @xbasename SYM@.
#
#*****************************************************************************
# @basename SYM@
function xeq_fn__basename(fn, M, nparam, param,
                          p, path)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    path = rm_quotes(sym_fetch(p))
    return awk_basename(path)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  B O O L V A L  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       boolval SYM: Print __FMT__[0 or 1], depending on SYM truthiness.
#         @boolval SYM@ => <string>
#
#*****************************************************************************
# @boolval SYM@
function xeq_fn__boolval(fn, M, nparam, param,
                         p, result, info)
{
    if (nparam == 0)
        # In an effort to spread a bit more entropy in the universe,
        # if you don't give an argument to boolval then you get
        # True 50% of the time and False the other 50%.
        result = sys_read("__FMT__", rand() < 0.50)
    else {
        p = param[1]
        # Always accept your current representation of True or False
        # to actually be true or false without further evaluation.
        if (p == sys_read("__FMT__", TRUE) || p == sys_read("__FMT__", FALSE))
            result = p
        else if (sym_valid_p(p)) {
            # It's a valid name -- now see if it's defined or not.
            # If not, check if we're in strict mode (error) or not.
            if (sym_defined_p(p))
                result = sys_read("__FMT__", sym_true_p(p))
            else if (strictp("bool"))
                error("Name '" p "' not defined (__STRICT__[bool] is True):" $0)
            else
                result = sys_read("__FMT__", FALSE)
        } else
            # It's not a symbol, so use its value interpreted as a boolean
            result = sys_read("__FMT__", to_bool(p))  # !!p)
    }

    return result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  C H R  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       chr SYM: Output character with ASCII code SYM
#         @chr 65@ => A
#
#*****************************************************************************
# @chr SYM@
function xeq_fn__chr(fn, M, nparam, param,
                     p)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    if (sym_valid_p(p)) {
        assert_sym_defined(p, "@" M "@")
        return sprintf("%c", sym_fetch(p)+0)
    } else if (integerp(p) && p >= 0 && p <= 255)
        return sprintf("%c", p+0)
    else
        error("Bad parameters in '" M "':" $0)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  C O M M A  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       comma VAL: Print number with comma separated grouping
#         @comma 87654321.1234@ => 87,654,321.1234
#
#*****************************************************************************
# @comma     VAL@
function xeq_fn__comma(fn, M, nparam, param,
                       p, silent, val)
{
    # S variant actually *removes* commas
    silent = first(fn) == "s"
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]

    if (sym_valid_p(p)) {
        assert_sym_defined(p, "@" M "@")
        p = sym_fetch(p)
    }
    return silent ? rmcomma(p) : addcomma(p)
}


# from "The AWK Programming Language", 2nd ed, p. 54.
function addcomma(x,   num)
{
    if (x < 0)
        return "-" addcomma(-x)
    while (x ~ /^[0-9][0-9][0-9][0-9]/)         # added ^
        sub(/[0-9][0-9][0-9][,.]/, ",&", x)
    return x
}

function rmcomma(x)
{
    gsub(/,/, EMPTY, x)
    if (first(x) == "$")
        x = rest(x)
    return x
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D A T E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       date    : Current date as YYYY-MM-DD
#       epoch   : Number of seconds since Epoch
#       strftime: User-specified date format, see strftime(3)
#       time    : Current time as HH:MM:SS
#       tz      : Current time zone name
#
#*****************************************************************************
# @date@
function xeq_fn__date(fn, M, nparam, param,
                      y, cmdline, output)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation(sprintf("@%s@: Forbidden", fn))
    if (! ("date" in PROG))
        error(sprintf("%s: PROG[date] not defined, cannot tell time", "@" M "@"))
    if (fn == "strftime" && nparam == 0)
        error("Bad parameters in '" M "':" $0)
    y = fn == "strftime" ? substr(M, length(fn)+2) \
        : sys_read("__FMT__", fn)
    gsub(/"/, "\\\"", y)
    cmdline = build_prog_cmdline("date", "+" TOK_QUOTE y TOK_QUOTE, MODE_IO_CAPTURE)
    if (fn == "utc")
        cmdline = "TZ=UTC " cmdline
    cmdline | getline output
    close(cmdline)
    return output
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D I R N A M E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       dirname SYM: Directory name of path, in Awka
#
#       dirname in Awk, assuming Unix style path separator.
#       Return directory portion of path.  If this is not
#       adequate, consider using @xdirname SYM@.
#
#*****************************************************************************
# @dirname SYM@
function xeq_fn__dirname(fn, M, nparam, param,
                         p, x)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")

    x = rm_quotes(sym_fetch(p))
    return sub(/\/[^\/]*$/, "", x) ? x : "."
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D I V L I N E S  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       divnl : Number of lines in a stream, or zero if empty
#
#*****************************************************************************
# @divnl STREAM@
function xeq_fn__divnl(fn, M, nparam, param,
                       stream)
{
    stream = (nparam == 0) ? DIVNUM() : param[1]
    if (! integerp(stream))
        error("Parameter must be integer: '" M "':" $0)
    if (stream <= 0 || !stream_block_exists_p(stream))
        return 0
    return blktab[stream_block(stream), 0, "count"]
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  D O W  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       dow [MJD] : Dow of Week
#
#*****************************************************************************
# @dow SYM@
function xeq_fn__dow(fn, M, nparam, param,
                     MJD, date, year, month, day)
{
    if (nparam == 0) {
        if (secure_level() >= SEC_PARANOID)
            security_violation(sprintf("@%s@: Forbidden", fn))
        date  = sym_fetch("__DATE__")
        year  = 0 + substr(date, 1, 4)
        month = 0 + substr(date, 5, 2)
        day   = 0 + substr(date, 7, 2)
        MJD = mjd(year, month, day)
    } else if (nparam == 1) {
        MJD = param[1]
    } else if (nparam == 3) {
        year  = 0 + param[1]
        month = 0 + param[2]
        day   = 0 + param[3]
        MJD = mjd(year, month, day)
    } else
        error("Bad parameters in '" M "':" $0)

    return (MJD % 7 + 2) % 7 + 1
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E M P T Y  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       empty : True if parameter symbol's value is empty string
#
#*****************************************************************************
# @empty SYM@
function xeq_fn__empty(fn, M, nparam, param,
                       p)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")

    return to_bool(sym_fetch(p) == EMPTY)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E X E C P A T H  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       execpath : Use sh command -v to return path to executable
#
#*****************************************************************************
# @execpath PROG@
function xeq_fn__execpath(fn, M, nparam, param,
                          p, silent, cmdline, output)
{
    if (secure_level() >= SEC_SECURE)
        security_violation(sprintf("@%s@: Forbidden", fn))
    # S variant won't warn about not being found
    silent = first(fn) == "s"
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]

    cmdline = build_prog_cmdline("sh", sprintf("-c 'command -v %s' 2>%s", p, NULL))
    cmdline | getline output
    close(cmdline)
    if (output == EMPTY && !silent)
        warn(sprintf("@%s %s@: Command not found", fn, p))
    return output
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  E X P R  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       expr ...: Evaluate mathematical epxression, store in __EXPR__
#
#*****************************************************************************
# @expr ...@
function xeq_fn__expr(fn, M, nparam, param,
                      silent, result)
{
    # S variant won't automatically print result
    silent = first(fn) == "s"
    sub(/^(__m2__::)?s?expr[ \t]*/, "", M) # clean up expression to evaluate
    result = calc3_eval(M)
    dbg__print("expr", 3, sprintf("(xeq_fn__expr) expr{%s} = %s", M, result))
    sys_write("__EXPR__", result+0)
    return silent ? "" : result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  F O R M A T  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       format: Format value(s) according for sprintf format string
#
#*****************************************************************************
# @format, @sprintf     FMT SYM...@
function xeq_fn__format(fn, M, nparam, param,
                        fmt, i, arg, result)
{
    if (nparam < 1 || nparam > 6)
        error("Bad parameters in '" M "':" $0)
    fmt = sym_value_or_literal(param[1])
    for (i = 2; i <= 6; i++)
        arg[i] = sym_value_or_literal(param[i])
    if      (nparam == 1) result = sprintf(fmt)
    else if (nparam == 2) result = sprintf(fmt, arg[2])
    else if (nparam == 3) result = sprintf(fmt, arg[2], arg[3])
    else if (nparam == 4) result = sprintf(fmt, arg[2], arg[3], arg[4])
    else if (nparam == 5) result = sprintf(fmt, arg[2], arg[3], arg[4], arg[5])
    else if (nparam == 6) result = sprintf(fmt, arg[2], arg[3], arg[4], arg[5], arg[6])

    return result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  G E O D I S T  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       geodist : Compute Earth surface distance between two points
#
#*****************************************************************************
# @geodist LAT1 LON1 LAT2 LON2@
function xeq_fn__geodist(fn, M, nparam, param,
                         d, s)
{
    if (nparam != 4 || !floatp(param[1]) || !floatp(param[2]) ||
                       !floatp(param[3]) || !floatp(param[4]))
        error("Bad parameters in '" M "':" $0)

    d = vincenty_distance(param[1], param[2],
                          param[3], param[4])
    s = sprintf("%10.4f", d)
    return trim(s)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  G R E G D A T E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       gregdate : Convert MJD number to Gregorian calendar YYYY-MM-DD
#
#*****************************************************************************
# @gregdate MJD@
function xeq_fn__gregdate(fn, M, nparam, param,
                          p, JD)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    if (! integerp(p))
        error("Parameter must be integer: '" M "':" $0)
    JD = 0 + p + JD_MJD_DIFF
    return greg(JD)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  H E X  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       hex: Print numeric value(s) in hexadecimal
#
#*****************************************************************************
# @hex SYM...@
function xeq_fn__hex(fn, M, nparam, param,
                     p)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    if (sym_valid_p(p)) {
        assert_sym_defined(p, "@" M "@")
        return sprintf("%x", sym_fetch(p)+0)
    } else if (integerp(p))
        return sprintf("%x", p+0)
    else
        error("Bad parameters in '" M "':" $0)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  H M S  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       hms : Convert decimal HR.DDDDD to HOUR, MIN, SEC
#
#*****************************************************************************
# @hms HR.DDDDD@
function xeq_fn__hms(fn, M, nparam, param,
                     hr, hours, mn, mins, secs, sgn, retval, frc_s)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    if (! floatp(hr = param[1]))
        error("Parameter HR invalid: '" M "':" $0)
    if ((sgn = mth__sign(hr)) < 0)
        hr = -hr

    hours = int(hr)
    mins  = int(mn = ((hr - hours) * 60))
    secs  =           (mn - mins ) * 60
    frc_s = sprintf("%10.6f", secs)
    gsub(/[ .]*/, "", frc_s)
    retval = sprintf("%s%d.%02d%s",
                     (sgn < 0 ? "-" : ""),
                     hours, mins, substr(frc_s, 1, 7))
    return retval
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  H R  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       hr : Convert (HOUR,MIN,SEC) to HR.DECIMAL
#
#*****************************************************************************
# @hr HOUR MIN SEC@
# @hr HOUR.MMSSsssss@
function xeq_fn__hr(fn, M, nparam, param,
                    hours, mins, secs, sgn, retval,
                    h, dot)
{
    if (nparam == 1) {
        h = param[1]
        if (! floatp(h))
            error("Bad parameters in '" M "':" $0)
        dot = index(h, ".")
        hours = substr(h, 1, dot-1) + 0
        mins  = substr(h, dot+1, 2) + 0
        secs  = substr(h, dot+3)
        if (length(secs) > 2)
            secs = substr(secs, 1, 2) "." substr(secs, 3)
        secs = secs + 0.0
    } else if (nparam == 3) {
        hours = param[1] + 0
        mins  = param[2] + 0
        secs  = param[3] + 0.0
    } else
        error("Bad parameters in '" M "':" $0)

    if (! integerp(hours))
        error("Parameter HOURS invalid: '" M "':" $0)
    if ((sgn = mth__sign(hours)) < 0)
        hours = -hours
    else if (sgn == 0)
        sgn = 1
    if ((! integerp(mins)) || mins < 0 || mins >= 60)
        error("Parameter MINS invalid: '" M "':" $0)
    if ((! floatp(secs)) || secs < 0 || secs >= 60)
        error("Parameter SECS invalid: '" M "':" $0)

    retval = sgn * (hours + mins/60.0 + secs/3600.0)
    return trim(sprintf("%12.8f", retval))
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I F D E F  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       ifdef/ifndef: Expand text if symbol is defined
#
#*****************************************************************************
# @ifdef{FOO}{True text}{False text}@
function xeq_fn__ifdef(fn, M, nparam, param,
                       x, ifcond, init_negate, true_text, false_text, result)
{
    M = nam__unqualify(M)
    if (   match(M, "^ifdef{[^}][^}]*}{[^}]*}{[^}]*}$") \
        || match(M, "^ifndef{[^}][^}]*}{[^}]*}{[^}]*}$"))
        ;          # Three-brace expr is well-formed
    else if (   match(M, "^ifdef{[^}][^}]*}{[^}]*}$") \
             || match(M, "^ifndef{[^}][^}]*}{[^}]*}$"))
        M = M "{}" # Two-brace expr can be fixed to use empty FALSE string
    else
        error("(ifdef) Bad ifdef in '" M "':" $0)

    # Get symbol name (x) which will be handed to defined()
    M = substr(M, index(M, TOK_LBRACE)) # strip fn name
    if (!match(M, "^{[^}]*}"))
        error("(ifdef) Bad ifdef symbol in '" M "':" $0)
    x = substr(M, RSTART+1, RLENGTH-2)
    assert_sym_valid_name(x, "@" M "@")
    ifcond = "defined(" x ")"
    init_negate = fn == "ifndef"
    dbg__print("dosubs", 7, "(ifdef) ifcond='" ifcond "'")
    M = substr(M, RSTART+RLENGTH)

    # Get true_text
    if (!match(M, "^{[^}]*}"))
        error("(ifdef) Bad true_text in '" M "':" $0)
    true_text = substr(M, RSTART+1, RLENGTH-2)
    dbg__print("dosubs", 7, "(ifdef) true_text='" true_text "'")
    M = substr(M, RSTART+RLENGTH)

    # Get false_text
    if (!match(M, "^{[^}]*}"))
        error("(ifdef) Bad false_text in '" M "':" $0)
    false_text = substr(M, RSTART+1, RLENGTH-2)
    dbg__print("dosubs", 7, "(ifdef) if_false='" false_text "'")
    M = substr(M, RSTART+RLENGTH)
    if (!emptyp(M))
        error("(ifdef) Extra text in ifdef: M='" M "'")

    result = evaluate_boolean(ifcond, init_negate) ? true_text : false_text
    dbg__print("dosubs", 7, "(xeq_fn__ifdef) Calling dosubs('" result "')")
    return dosubs(result)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I F E L S E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       ifelse: Evaluate argument pairs for equality.
#
#       @ifelse@ has three or more arguments.
#       If the first argument is equal to the second,
#          then the value is the third argument.
#       If not, and if there are more than four arguments,
#          the process is repeated with arguments 4, 5, 6, and 7.
#       Otherwise, the value is either the fourth argument, or void if omitted.
#
#       NOTE: All of the {} clauses must be on the same line,
#       since dosubs CANNOT call readline().
#
#*****************************************************************************
# @ifelse{S1}{S2}{True text}{False text}...@
function xeq_fn__ifelse(fn, M, nparam, param,
                        arg, j, result)
{
    M = substr(nam__unqualify(M), 7)    # strip away "ifelse"
    arg[1] = arg[2] = arg[3] = ""
    while (TRUE) {
        dbg__print("dosubs", 5, "(ifelse) TOP; M=" M)

        # Check that at least three pairs of braces are present,
        # and whatever remains are also well-formed brace pairs.
        # Pathological syntax (like {..\}..} will cause problems.
        if (! match(M, "^{[^}][^}]*}{[^}]*}{[^}]*}")) # used to include ({[^}]*})*$ at end of regexp but Busybox Awk doesn't like that
            error("(ifelse) Bad parameters in '" M "':" $0)

        # Grab the first three arguments
        for (j = 1; j <= 3; j++) {
            match(M, "{[^}]*}")
            arg[j] = substr(M, RSTART+1, RLENGTH-2)
            M = substr(M, RSTART+RLENGTH)
            dbg__print("dosubs", 7, sprintf("(ifelse) arg[%d]='%s'",
                                           j, arg[j]))
        }

        # Check arg1 & arg2 for equality...  TODO integer check -> 0+n
        # If the first argument is equal to the second,
        #    then the value is the third argument.
        if (arg[1] == arg[2]) {
            result = arg[3]
            break
        }
        # At this point, the three required args have been
        # stripped out of M.  What remains in M could be:
        # 1. Empty - no fourth argument, so use empty string.
        if (emptyp(M)) {
            result = ""
            break
        }
        # 2. Exactly one brace clause remains; it is the fourth
        # (last) argument, so use it.
        if (match(M, "^{[^}]*}$")) {
            result = substr(M, 2, length(M) - 2)
            break
        }
        # 3. If there are more than four args, there have to be a
        # minimum number to allow the cycle to continue.
        # You need  {1}{2}{3}  ||  {4}{5}{6} [ {7} ]
        #                      ||  {1}{2}{3}
        # which means that just one or two pairs of braces
        # constitute invalid syntax.  The one pair case was
        # caught in choice 2 just above, so we check for two pairs
        if (match(M, "^{[^}][^}]*}{[^}]*}$"))   # Busybox Awk does not support +
            error("(ifelse) Bad parameters in '" M "':" $0)

        # # If not, and if there are more than four arguments,
        #    the process is repeated with arguments 4, 5, 6, and 7.
    }

    dbg__print("dosubs", 7, "(xeq_fn__ifelse) Calling dosubs('" result "')")
    return dosubs(result)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I F X  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       ifx: If Expression : Evaluate boolean expression to choose result text
#         A and B are @ifx{A == B}{Equal}{Not equal}@
#
#*****************************************************************************
# @ifx{Boolean expr}{True text}{False text}@
function xeq_fn__ifx(fn, M, nparam, param,
                     ifcond, init_negate, true_text, false_text, result)
{
    M = nam__unqualify(M)
    if (!match(M, "^ifx{[^}][^}]*}{[^}]*}{[^}]*}$"))   # Busybox Awk does not support +
        error("(ifx) Bad ifx in '" M "':" $0)
    M = substr(M, index(M, TOK_LBRACE)) # strip fn name
    init_negate = FALSE

    # Get if_clause
    if (!match(M, "^{[^}]*}"))
        error("(ifx) Bad if_clause in '" M "':" $0)
    ifcond = substr(M, RSTART+1, RLENGTH-2)
    dbg__print("dosubs", 7, "(ifx) ifcond='" ifcond "'")
    M = substr(M, RSTART+RLENGTH)

    # Get true_text
    if (!match(M, "^{[^}]*}"))
        error("(ifx) Bad true_text in '" M "':" $0)
    true_text = substr(M, RSTART+1, RLENGTH-2)
    dbg__print("dosubs", 7, "(ifx) true_text='" true_text "'")
    M = substr(M, RSTART+RLENGTH)

    # Get false_text
    if (!match(M, "^{[^}]*}"))
        error("(ifx) Bad false_text in '" M "':" $0)
    false_text = substr(M, RSTART+1, RLENGTH-2)
    dbg__print("dosubs", 7, "(ifx) if_false='" false_text "'")
    M = substr(M, RSTART+RLENGTH)
    if (!emptyp(M))
        error("(ifx) Extra text in ifx: M='" M "'")

    result = evaluate_boolean(ifcond, init_negate) ? true_text : false_text
    dbg__print("dosubs", 7, "(xeq_fn__ifx) Calling dosubs('" result "')")
    return dosubs(result)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  I N D E X  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       index: Location of substring
#         NB - Awk index() returns 1-based values and so do we.
#              Different from m4 which is zero-based.
#
#*****************************************************************************
# @index SYM SUBSTR@
function xeq_fn__index(fn, M, nparam, param,
                       p, x)
{
    if (nparam != 2)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    x = param[2]
    return index(sym_fetch(p), x)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  J O I N  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @join     LIS [FS]
function xeq_fn__join(fn, M, nparam, param,
                      info, nparts, level, retval, lis, fs, fslen, silent,
                      code, size, s, f, k, keys, i, agg_block, me, ins)
{
    me = "@" M "@"
    # S variant appends a final separator as a terminator
    silent = first(fn) == "s"
    if (nparam == 0)
        error(sprintf("%s: Bad parameters", me))
    lis = param[1]

    level = info__create_from_text(lis, info)
    ins = info__get(info, "ns")
    info__gate(OP_READ, PTYPE_IDXABLE, info, ins, level, me, TRUE)

    # # TODO Need real checks here!
    # assert_sym_valid_name(lis, me)

    if (nparam > 1) {
        fs = param[2]        # too simple
    } else if (sym_defined_p("__FS__")) {
        fs = sym_fetch("__FS__")
    } else {
        fs = TOK_SPACE
    }
    fslen = length(fs)

    # Check namtab
    # level = info__create_from_text(lis, info)
    # XXX - isn't this part just a duplication of info__create_from_text() above???
    if ((nparts = nam__scan(lis, info)) == ERROR)
        error("(xeq_fn__join) Scan error, " __m2_msg)
    if (nparts == 2)
        error(sprintf("%s: Array name '%s' cannot have subscripts",
                      "@" M "@", lis))

    # Now call nam__lookup(info).  Must be TYPE_ARRAY && !FLAG_SYSTEM
    level = nam__lookup(info)
    if (level == NAME_NOT_FOUND)
        error(sprintf("%s: Name '%s' not found", "@" M "@", lis))
    if (info__get(info, "idxable") == FALSE)
        error(sprintf("%s: Name '%s' has type %s, not Array or List", "@" M "@", lis, info__get(info, "type")))
    code = info["code"]
    ins  = info__get(info, "ns")
    size = idx__size(info)

    retval = ""
    if (size > 0) {
        # Build return string
        if (info__get(info, "type") == TYPE_LIST) {
            # It's a block array - Get its agg_block
            if (! ((ins, lis, NOKEY, level, "agg_block") in symtab))
                panic(sprintf("(xeq_fn__join) Could not find [%s, '%s','%s',%d,'agg_block'] in symtab",
                              ins, lis, NOKEY, level))
            agg_block = symtab[ins, lis, NOKEY, level, "agg_block"]
            # Inject the values
            for (i = 1; i <= size; i++) {
                # Make sure slot holds text, which it pretty much has to
                if (blk_ll_slot_type(agg_block, i) != OBJ_TEXT)
                    panic(sprintf("(xeq_fn__join) Block # %d slot %d is not OBJ_TEXT", agg_block, i))
                retval = retval  blk_ll_slot_value(agg_block, i)  fs
            }
        } else {
            # It's a normal array - Find the keys
            for (s in symtab) {
                split(s, f, SUBSEP)
                # NS ?
                if (f[SFN_NS] == ins &&
                    f[SFN_NAME] == lis &&
                    f[SFN_LEVEL] == level &&
                    f[SFN_TAG] == "symval") {
                    #print f[SFN_KEY]
                    keys[f[SFN_KEY]] = 1
                }
            }
            # Inject the values
            for (k in keys) {
                # print_stderr("JOIN: arr[" k "] = " sym_ll_read_ns(ins, lis, k, level))
                retval = retval sym_ll_read_ns(ins, lis, k, level) fs
            }
        }

        # Remove trailing field separator if need be
        if (!silent)
            retval = substr(retval, 1, length(retval)-fslen)
    }
    return retval
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  L E F T  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       left: Left (substring)
#         @left ALPHABET 7@ => ABCDEFG
#
#*****************************************************************************
# @left SYMBOL[, LENGTH]@
function xeq_fn__left(fn, M, nparam, param,
                      p, x)
{
    if (nparam < 1 || nparam > 2)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    x = 1
    if (nparam == 2) {
        x = param[2]
        if (!integerp(x))
            error("Value '" x "' must be numeric:" $0)
    }
    return substr(sym_fetch(p), 1, x)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  L J U S T   /   R J U S T   /   C E N T E R  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       ljust: Left justify string
#       rjust: Right justify string
#       center: Center string
#
#*****************************************************************************
# @ljust  SYM [WID]@
# @rjust  SYM [WID]@
# @center SYM [WID]@
function xeq_fn__lrc(fn, M, nparam, param,
                     silent, p, width, s, slen, x, sp)
{
    if (nparam < 1 || nparam > 2)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    if (nparam == 2) {
        width = param[2]
        if (!integerp(width))
            error("Value '" width "' must be numeric:" $0)
    } else {
        width = sym_fetch("__COLUMNS__")
        if (!integerp(width) || width <= 0)
            width = 80
    }
    width = 0 + width
    if ((slen = length(s = sym_fetch(p))) == width)
        return s

    # S variants do not truncate output
    if (silent = first(fn) == "s")
        fn = rest(fn)
    if (fn == "ljust") {
        if (slen > width)
            return silent ? s : substr(s, 1, width)
        else
            return s spaces(width-slen)
    } else if (fn == "rjust") {
        if (slen > width)
            return silent ? s : substr(s, slen-width+1, width)
        else
            return spaces(width-slen) s
    } else if (fn == "center") {
        if (slen > width)
            return silent ? s : substr(s, 1+int((slen-width)/2), width)
        else {
            sp = int((width-slen)/2)
            return spaces(sp) s spaces(width-sp-slen)
        }
    } else
        panic("Function '" fn "' not defined:" $0)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  M I D  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       mid: Substring ...  SYMBOL, START[, LENGTH]
#         @mid ALPHABET 15 5@ => OPQRS
#         @mid FOO 3@
#         @mid FOO 2 2@
#
#*****************************************************************************
# @mid SYMBOL, START[, LENGTH]
function xeq_fn__mid(fn, M, nparam, param,
                     sym, str, param_Begin, param_Length, result,
                     B, L, symlen, altB, substr_Begin, substr_Length)
{
    if (nparam < 2 || nparam > 3)
        error("Bad parameters in '" M "':" $0)
    sym = param[1]
    assert_sym_valid_name(sym, "@" M "@")
    assert_sym_defined(sym, "@" M "@")
    symlen = length(str = sym_fetch(sym))
    param_Begin = param[2]
    if (!integerp(param_Begin))
        error("Value '" param_Begin "' must be numeric:" $0)
    B = abs(param_Begin)
    if (nparam == 2) {          # param_Length absent
        substr_Begin = (param_Begin >= 0) ? B : symlen-B+1
        result = substr(str, substr_Begin)
        #print_stderr("MID: substr('" str "', " substr_Begin ")=>'" result "'")
        return result
    }

    # nparam must be 3
    param_Length = param[3]
    if (!integerp(param_Length))
        error("Value '" param_Length "' must be numeric:" $0)
    if (param_Length == 0)
        return EMPTY
    if (param_Begin == 0)
        B = abs(param_Begin = mth__sign(param_Length))
    L = abs(param_Length)
    if (param_Length >= 0)
        substr_Length = L
    if (param_Begin >= 0) {
        substr_Begin = B
        if (param_Length < 0)
            substr_Length = ((substr_Begin -= L) <= 0) ? min(L, B - 1) : L
    } else {
        substr_Begin = symlen - B + 1
        if (param_Length < 0)
            substr_Length = ((substr_Begin -= L) <= 0) ? min(L, symlen - B) : L
    }
    result = substr(str, substr_Begin, substr_Length)
    # Double substr() call here because sometimes (in pathological
    # cases), mawk(1) returns a string longer than substr_Length.
    result = substr(result, 1, substr_Length)
    #print_stderr("MID: substr('" str "', " substr_Begin ", " substr_Length ")=>'" result "'")
    return result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  M J D  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Modified Julian Day
#
#*****************************************************************************
# @mjd [YYYY MM DD]@
function xeq_fn__mjd(fn, M, nparam, param,
                        year, month, day, monthdays, i, n, date)
{
    if (nparam == 3) {
        year  = 0 + param[1]
        month = 0 + param[2]
        day   = 0 + param[3]
    } else if (nparam == 0) {
        if (secure_level() >= SEC_PARANOID)
            security_violation(sprintf("@%s@: Forbidden", fn))
        date  = sym_fetch("__DATE__")
        year  = 0 + substr(date, 1, 4)
        month = 0 + substr(date, 5, 2)
        day   = 0 + substr(date, 7, 2)
    } else
        error("Bad parameters in '" M "':" $0)

    dbg__print("dosubs", 7, "(xeq_fn__mjd) year=" year ", month=" month ", day=" day)
    if (! date_valid_p(year, month, day))
        error(sprintf("%s: Bad date; Year=%d, Month=%d, Day=%d",
                      "@" M "@", year, month, day))
    return "" mjd(year, month, day)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  M K T E M P  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       Return a temporary path based on a template.
#       NOTE:  Does not actually create the file!
#       Template must end in at least six X characters.
#
#*****************************************************************************
# @mktemp SYM | templateXXXXXX
function xeq_fn__mktemp(fn, M, nparam, param,
                        p, template, info)
{
    if (nparam == 0)
        # Skip the rigamarole and give me a random file name
        return mktemp(tmpdir() "m2Tmp.XXXXXXXX")  # eight X's
    p = param[1]
    info__create_from_text(p, info)
#                sym_valid_p(p) && sym_defined_p(p)) \
    template = (info__get(info, "type") == TYPE_SYMBOL &&
                info__get(info, "defined") == TRUE) \
             ? syminfo_fetch(info) : substr(M, length(fn)+2)
    if (match(template, "XXXXXX+$") == NOT_FOUND)
        error("@mktemp@: Invalid template '" template "': missing 6 or more X")
    if (index(template, TOK_SLASH) == NOT_FOUND)
        template = tmpdir() template
    return mktemp(template)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  O R D  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       ord SYM: Output character with ASCII code SYM
#         @define B *Nothing of interest*
#         @ord A@ => 65
#         @ord B@ => 42
#
#*****************************************************************************
# @ord SYM@
function xeq_fn__ord(fn, M, nparam, param,
                     p)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    if (flag_1false_p(__m2_config_flags, INIT_ORD))
        initialize_ord()
    p = param[1]
    if (sym_valid_p(p) && sym_defined_p(p))
        p = sym_fetch(p)
    return __ord[first(p)]
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  R I G H T  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       right: Right (substring)
#         @right ALPHABET 20@ => TUVWXYZ
#
#*****************************************************************************
# @right SYM N@
function xeq_fn__right(fn, M, nparam, param,
                       x, p)
{
    if (nparam < 1 || nparam > 2)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    x = length(sym_fetch(p))
    if (nparam == 2) {
        x = param[2]
        if (!integerp(x))
            error("Value '" x "' must be numeric:" $0)
    }
    return substr(sym_fetch(p), x)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  R O T 1 3  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       rot13 SYM: Output value of symbol with rot13 text
#         @define aRealSymbol *With 6, you get value!*
#         @rot13 aRealSymbol@    => *Jvgu 6, lbh trg inyhr!*
#         @rot13 NotaRealSymbol@ => AbgnErnyFlzoby
#
#*****************************************************************************
# @rot13 SYM | Text@
function xeq_fn__rot13(fn, M, nparam, param,
                       p, i, c, result, info)
{
    if (flag_1false_p(__m2_config_flags, INIT_ROT13))
        initialize_rot13()
    if (nparam == 0)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    info__create_from_text(p, info)
#    p = (sym_valid_p(p) && sym_defined_p(p)) \
#        ? sym_fetch(p) : substr(M, length(fn)+2)
    p = (info__get(info, "type") == TYPE_SYMBOL &&
         info__get(info, "defined") == TRUE) \
        ? syminfo_fetch(info) : substr(nam__unqualify(M), length(fn)+2)
    result = ""

    for (i = 1; i <= length(p); i++) {
        c = substr(p, i, 1)
        result = result  (match(c, "[a-zA-Z]") ? __rot13[c] : c)
    }
    return result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  S P A C E S  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       spaces [N]: N spaces
#       tabs [N]: N tabs
#
#*****************************************************************************
# @spaces N@
# @tabs N@
function xeq_fn__spaces(fn, M, nparam, param,
                        n, c)
{
    if (nparam > 1)
        error("Bad parameters in '" M "':" $0)
    if (nparam == 1) {
        n = param[1]
        if (!integerp(n))
            error("Value '" n "' must be numeric:" $0)
    } else
        n = 1
    if (substr(fn, 1, 5) == "space")
        return spaces(n)
    if (substr(fn, 1, 3) == "tab")
        return repeated(n, TOK_TAB)
    # Alternate reality
    return repeated(n, "?")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  (string function)  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       lc : Lower case
#       len: Length
#       uc : Upper case
#         @len ALPHABET@ => 26
#
#*****************************************************************************
function xeq_fn__str_fn(fn, M, nparam, param,
                        p, result)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    if (fn == "lc")
        result = tolower(sym_fetch(p))
    else if (fn == "len")
        result = length(sym_fetch(p))
    else if (fn == "uc")
        result = toupper(sym_fetch(p))
    else
        panic("Function '" fn "' not defined:" $0)

    return result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  T R I M  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       trim  SYM: Remove both leading and trailing whitespace
#       ltrim SYM: Remove leading whitespace
#       rtrim SYM: Remove trailing whitespace
#
#*****************************************************************************
function xeq_fn__trim(fn, M, nparam, param,
                      p, result)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    result = ""
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    result = sym_fetch(p)
    if (fn == "trim" || fn == "ltrim")
        result = ltrim(result)
    if (fn == "trim" || fn == "rtrim")
        result = rtrim(result)
    return result
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  X _ _ _ N A M E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       xbasename SYM: Base (i.e., file name) of path, using external program
#       xdirname SYM : Directory name of path, using external program
#
#*****************************************************************************
# @xbasename SYM@
# @xdirname SYM@
function xeq_fn__xname(fn, M, nparam, param,
                       p, cmdline, output)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation(sprintf("@%s@: Forbidden", fn))
    if (nparam != 1)
        error("(" fn ") Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    cmdline = build_prog_cmdline(fn, rm_quotes(sym_fetch(p)), MODE_IO_CAPTURE)
    cmdline | getline output
    close(cmdline)

    return output
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
function initialize(    get_date_cmd, d, dateout, array, elem, i, date_ok,
                        monthdays, month, leap)
{
    # Constants
   #EPSILON                     = mth__epsilon()
    EULER                       = exp(1)
    JD_MJD_DIFF                 = 2400000.5
    LOG2                        = log(2)
    LOG10                       = log(10)
    MAX_DBG_LEVEL               = 10
    MAX_PARAM                   = 20
    NOT_FOUND                   = 0     # index() when search fails
    PI                          = atan2(0, -1)
    SEQ_DEFAULT_INCR            = 1
    SEQ_DEFAULT_INIT            = 0
    TAU                         = 8 * atan2(1, 1) # 2 * PI
      DEG_RADIANS               = TAU / 360
    TERMINAL                    = 0     # Block zero means standard output

    # Block types and labels
    BLK_AGG                     = "a"; __label[BLK_AGG]               = "AGG"
      OBJ_BLKNUM                = "K"; __label[OBJ_BLKNUM]            = "obj_BLKNUM"
      OBJ_CMD                   = "c"; __label[OBJ_CMD]               = "obj_CMD"
      OBJ_TEXT                  = "t"; __label[OBJ_TEXT]              = "obj_TEXT"
      OBJ_USER                  = "j"; __label[OBJ_USER]              = "obj_USER"
    BLK_CASE                    = "e"; __label[BLK_CASE]              = "CASE"
    BLK_FILE                    = "f"; __label[BLK_FILE]              = "FILE"
    BLK_FOR                     = "O"; __label[BLK_FOR ]              = "FOR"
    BLK_IF                      = "i"; __label[BLK_IF]                = "IF"
    BLK_LONGDEF                 = "d"; __label[BLK_LONGDEF]           = "LONGDEF"
    BLK_STRING                  = "q"; __label[BLK_STRING]            = "STRING"
    BLK_TERMINAL                = "T"; __label[BLK_TERMINAL]          = "TERMINAL"
    BLK_USER                    = "u"; __label[BLK_USER]              = "USER"
    BLK_WHILE                   = "w"; __label[BLK_WHILE]             = "WHILE"
    #
    VALID_BLOCK_TYPES = BLK_AGG     BLK_CASE   BLK_FILE     BLK_FOR  BLK_IF \
                        BLK_LONGDEF BLK_STRING BLK_TERMINAL BLK_USER BLK_WHILE

    # CRUDP
    OP_CREATE                   = "1"; __label[OP_CREATE]             = "CREATE"
    OP_READ                     = "2"; __label[OP_READ]               = "READ"
    OP_UPDATE                   = "3"; __label[OP_UPDATE]             = "UPDATE"
    OP_DELETE                   = "4"; __label[OP_DELETE]             = "DELETE"
    OP_PRINT                    = "5"; __label[OP_PRINT]              = "PRINT"

    # Various modes
    MODE_AT_LITERAL             = "'"; __label[MODE_AT_LITERAL]       = "Literal"
    MODE_AT_PROCESS             = "@"; __label[MODE_AT_PROCESS]       = "ProcessAt"
    MODE_HOOKS_ENABLED          = "h"; __label[MODE_HOOKS_ENABLED]    = "HooksEnabled"
    MODE_IO_CAPTURE             = "v"; __label[MODE_IO_CAPTURE]       = "CaptureIO"
    MODE_IO_SILENT              = "z"; __label[MODE_IO_SILENT]        = "SilentIO"
    MODE_TEXT_PRINT             = "p"; __label[MODE_TEXT_PRINT]       = "PrintText"
    MODE_TEXT_STRING            = "s"; __label[MODE_TEXT_STRING]      = "StringText"
    MODE_STREAMS_DISCARD        = "X"; __label[MODE_STREAMS_DISCARD]  = "DiscardStream"
    MODE_STREAMS_SHIP_OUT       = ">"; __label[MODE_STREAMS_SHIP_OUT] = "ShipOutStream"
    MODE_XEQ_NORMAL             = "x"; __label[MODE_XEQ_NORMAL]       = "XeqNormal"
    MODE_XEQ_BREAK              = "b"; __label[MODE_XEQ_BREAK]        = "XeqBreak"
    MODE_XEQ_CONTINUE           = "o"; __label[MODE_XEQ_CONTINUE]     = "XeqContinue"
    MODE_XEQ_RETURN             = "r"; __label[MODE_XEQ_RETURN]       = "XeqReturn"
    SORT_NATURAL                = "G"; __label[SORT_NATURAL]          = "SortNatural"
    SORT_INTEGER                = "H"; __label[SORT_INTEGER]          = "SortInteger"

    # Initialization status
    INIT_DOTFILES               = "."; __label[INIT_DOTFILES  ]       = "Dotfiles" # load_init_files()
    INIT_ORD                    = "#"; __label[INIT_ORD       ]       = "Ord"      # initialize_ord()
    INIT_ROT13                  = "<"; __label[INIT_ROT13     ]       = "Rot13"    # initialize_rot13()

    # When to flush standard output
    SYNC_FORCE                  = 0 # only on request or end of job
    SYNC_FILE                   = 1 # at end of each processed file; default.
    SYNC_LINE                   = 2 # after every printed line

    # Tokens used in boolean expression evaluation
    TOK_AND                     = "&&"
    TOK_AT                      = "@"
    TOK_AT_BRACE                = "@{"
    TOK_BACKSLASH               = "\\"
    TOK_CANRUN_P                = "?R"; __predicate_token["canrun"]  = TOK_CANRUN_P
    TOK_COLON                   = ":"
    TOK_DEFINED_P               = "?D"; __predicate_token["defined"] = TOK_DEFINED_P
    TOK_EXISTS_P                = "?X"; __predicate_token["exists"]  = TOK_EXISTS_P
    TOK_LBRACE                  = "{"
    TOK_LBRACKET                = "["
    TOK_LPAREN                  = "("
    TOK_NEWLINE                 = "\n"
    TOK_NOT                     = "!"
    TOK_NS_QUAL                 = TOK_COLON TOK_COLON
    TOK_OR                      = "||"
    TOK_QUOTE                   = "\""
    TOK_RBRACE                  = "}"
    TOK_RBRACKET                = "]"
    TOK_RPAREN                  = ")"
    TOK_SLASH                   = "/"
    TOK_TAB                     = "\t"

    # Errors
    ERR_OKAY                    =    0
    NAME_NOT_FOUND              =  -10 # nam__{lookup,find} no result - not considered an error
    ERR_FENCE                   = -100 # if (ret < ERR_FENCE) error(...)
    ERR_PARSE_STACK             = -101
    ERR_PARSE_MISMATCH          = -102
    ERR_PARSE_DEPTH             = -103
    ERR_SCAN_INVALID_NAME       = -104

    # Global variables
    __buffer                    = EMPTY
    __curr_level                = ROOT_LEVEL
    __ns_stack[0]               = 0;    __ns_stack["name"]     = "ns_stack"
    __parse_stack[0]            = 0;    __parse_stack["name"]  = "parse_stack"
    __source_stack[0]           = 0;    __source_stack["name"] = "source_stack"
    __stream_stack[0]           = 0;    __stream_stack["name"] = "stream_stack"
    __wrap_cnt                  = 0

    srand()                     # Seed random number generator
    stk_push(__ns_stack, M2_SYSNS)
    stk_push(__ns_stack, M2_NS)
    __m2_config_flags = flag_set_clear(PTYPE_ANY,
                                       # Set these:
                                       MODE_HOOKS_ENABLED MODE_TEXT_PRINT  MODE_XEQ_NORMAL,
                                       # Clear these:
                                       MODE_TEXT_STRING   MODE_XEQ_BREAK   MODE_XEQ_CONTINUE  MODE_XEQ_RETURN \
                                       INIT_DOTFILES      INIT_ORD         INIT_ROT13)
    initialize_prog_paths()

    # Initialize days per month
    split("31 31 28 29 31 31 30 30 31 31 30 30 31 31 31 31 30 30 31 31 30 30 31 31", monthdays)
    for (i = 0; i < 24; i++) {
        month = int(i/2) + 1
        leap  = i % 2
        __monthdays[month, leap] = monthdays[i+1]
    }

    __roman[__rv[1]=1000] =  "M"
    __roman[__rv[2]= 900] = "CM"; __roman[__rv[6]=90] = "XC"; __roman[__rv[10]=9] = "IX"
    __roman[__rv[3]= 500] =  "D"; __roman[__rv[7]=50] =  "L"; __roman[__rv[11]=5] =  "V"
    __roman[__rv[4]= 400] = "CD"; __roman[__rv[8]=40] = "XL"; __roman[__rv[12]=4] = "IV"
    __roman[__rv[5]= 100] =  "C"; __roman[__rv[9]=10] =  "X"; __roman[__rv[13]=1] =  "I"

    if (secure_level() < SEC_PARANOID) {
        # Set up some symbols that depend on external programs

        # Current date & time
        if ("date" in PROG) {
            # Capture m2 run start time.                 1  2  3  4  5  6  7  8  9
            get_date_cmd = build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z %s %a'", MODE_IO_CAPTURE)
            get_date_cmd | getline dateout
            close(get_date_cmd)
            split(dateout, d)

            sym_ll_fiat("__DATE__",         NOKEY, PTYPE_READONLY_INTEGER, d[1] d[2] d[3])
            sym_ll_fiat("__DOW__",          NOKEY, PTYPE_READONLY_SYMBOL,  d[9])
            sym_ll_fiat("__EPOCH__",        NOKEY, PTYPE_READONLY_INTEGER, d[8])
            sym_ll_fiat("__TIME__",         NOKEY, PTYPE_READONLY_SYMBOL,  d[4] d[5] d[6]) # not an INTEGER because I want leading 0 if before 12:00
            sym_ll_fiat("__TIMESTAMP__",    NOKEY, PTYPE_READONLY_SYMBOL,  d[1] "-" d[2] "-" d[3] \
                                                                    "T" d[4] ":" d[5] ":" d[6] d[7])
            sym_ll_fiat("__TZ__",           NOKEY, PTYPE_READONLY_SYMBOL,  d[7])
        }

        # Deferred symbols
        if ("id" in PROG) {
            sym_deferred_symbol("__GID__",      PTYPE_READONLY_INTEGER, "id", "-g")
            sym_deferred_symbol("__USER__",     PTYPE_READONLY_SYMBOL,  "id", "-un")
            if (! nam_ll_in_ns(M2_SYSNS, "__UID__", ROOT_LEVEL))
                sym_deferred_symbol("__UID__",  PTYPE_READONLY_INTEGER, "id", "-u")
        }
        if ("hostname" in PROG) {
            sym_deferred_symbol("__HOST__",     PTYPE_READONLY_SYMBOL,  "hostname", "-s")
            # OpenBSD's hostname(1) does not support the `-f' flag;
            # since it is already the default on FreeBSD, I just removed it.
            sym_deferred_symbol("__HOSTNAME__", PTYPE_READONLY_SYMBOL,  "hostname", "")
        }
        if ("uname" in PROG) {
            sym_deferred_symbol("__OSNAME__",   PTYPE_READONLY_SYMBOL,  "uname", "-s")
        }
        if ("sh" in PROG) {
            sym_deferred_symbol("__PID__", PTYPE_READONLY_INTEGER, "sh", "-c 'echo $PPID'")
        }
    } else {
        # Try to get some common identifiers through other means
        if ("HOST" in ENVIRON)
            sym_ll_fiat("__HOST__", NOKEY, PTYPE_READONLY_SYMBOL, ENVIRON["HOST"])
        else if ("HOSTNAME" in ENVIRON)
            sym_ll_fiat("__HOST__", NOKEY, PTYPE_READONLY_SYMBOL, ENVIRON["HOSTNAME"])
        if ("UID" in ENVIRON &&
            ! nam_ll_in_ns(M2_SYSNS, "__UID__", ROOT_LEVEL))
            sym_ll_fiat("__UID__", NOKEY,  PTYPE_READONLY_INTEGER, ENVIRON["UID"])
        if ("USER" in ENVIRON)
            sym_ll_fiat("__USER__", NOKEY, PTYPE_READONLY_SYMBOL, ENVIRON["USER"])
        else if ("LOGNAME" in ENVIRON)
            sym_ll_fiat("__USER__", NOKEY, PTYPE_READONLY_SYMBOL, ENVIRON["LOGNAME"])
    }

    nam_ll_write_ns(M2_SYSNS, "__FMT__",    ROOT_LEVEL, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)
    nam_ll_write_ns(M2_SYSNS, "__STRICT__", ROOT_LEVEL, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE FLAG_BOOLEAN)

    if ("COLUMNS" in ENVIRON)
      sym_ll_fiat("__COLUMNS__",    NOKEY, PTYPE_WRITABLE_INTEGER, ENVIRON["COLUMNS"])
    else if (secure_level() < SEC_PARANOID && ("tput" in PROG))
      sym_deferred_symbol("__COLUMNS__",   PTYPE_WRITABLE_INTEGER, "tput", "cols")
    else
      sym_ll_fiat("__COLUMNS__",    NOKEY, PTYPE_WRITABLE_INTEGER, 80)
    if ("PWD" in ENVIRON)
      sym_ll_fiat("__CWD__",        NOKEY, PTYPE_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["PWD"]))
    else if (secure_level() < SEC_PARANOID && ("pwd" in PROG))
      sym_deferred_symbol("__CWD__",       PTYPE_READONLY_SYMBOL,  "pwd", "")
    sym_ll_fiat("__DEBUGFILE__",    NOKEY, PTYPE_WRITABLE_SYMBOL,  STDERR)
    sym_ll_fiat("__DEPTH__",        NOKEY, PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__DIVNUM__",       NOKEY, PTYPE_READONLY_INTEGER, TERMINAL)
    sym_ll_fiat("__EXPR__",         NOKEY, PTYPE_READONLY_NUMERIC, 0.0)
    sym_ll_fiat("__FILE__",         NOKEY, PTYPE_READONLY_SYMBOL,  "")
    sym_ll_fiat("__FILE_UUID__",    NOKEY, PTYPE_READONLY_SYMBOL,  "")
    sym_ll_fiat("__FMT__",         "1", "",                     "1") # True
    sym_ll_fiat("__FMT__",         "0", "",                     "0") # False
    sym_ll_fiat("__FMT__",      "date", "",                     "%Y-%m-%d")
    sym_ll_fiat("__FMT__",     "epoch", "",                     "%s")
    sym_ll_fiat("__FMT__",    "number", "",                     CONVFMT)
    sym_ll_fiat("__FMT__",       "seq", "",                     "%d")
    sym_ll_fiat("__FMT__",      "time", "",                     "%H:%M:%S")
    sym_ll_fiat("__FMT__",        "tz", "",                     "%Z")
    sym_ll_fiat("__FMT__",       "utc", "",                     "%Y-%m-%dT%H:%M:%S%z") # ISO 8601
    nam_ll_write_ns(M2_SYSNS, "__FS__", ROOT_LEVEL, PTYPE_WRITABLE_SYMBOL) # NB - *not* in sync with real FS
    if ("HOME" in ENVIRON)
      sym_ll_fiat("__HOME__",       NOKEY, PTYPE_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["HOME"]))
    else if ("LOGDIR" in ENVIRON)
      sym_ll_fiat("__HOME__",       NOKEY, PTYPE_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["LOGDIR"]))
    sym_ll_fiat("__INCPATH__",      NOKEY, PTYPE_READONLY_SYMBOL,  "M2PATH" in ENVIRON ? ENVIRON["M2PATH"] : EMPTY)
    sym_ll_fiat("__INPUT__",        NOKEY, PTYPE_WRITABLE_SYMBOL,  EMPTY)
    sym_ll_fiat("__LENIENT__",      NOKEY, PTYPE_WRITABLE_INTEGER, 0)
    sym_ll_fiat("__LINE__",         NOKEY, PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__M2_UUID__",      NOKEY, PTYPE_READONLY_SYMBOL,  uuid())
    sym_ll_fiat("__M2_VERSION__",   NOKEY, PTYPE_READONLY_SYMBOL,  M2_VERSION)
    sym_ll_fiat("__NFILE__",        NOKEY, PTYPE_READONLY_INTEGER, 0); __rnf = 0
    sym_ll_fiat("__NLINE__",        NOKEY, PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__NSPATH__",       NOKEY, PTYPE_READONLY_SYMBOL,  EMPTY)
    sym_ll_fiat("__STRICT__",   "bool", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "def", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "env", "",                     TRUE)
    sym_ll_fiat("__STRICT__",   "file", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "key", "",                     TRUE)
    sym_ll_fiat("__SYNC__",         NOKEY, PTYPE_WRITABLE_INTEGER, SYNC_FILE)
    sym_ll_fiat("__SYSVAL__",       NOKEY, PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__VERBOSE__",      NOKEY, PTYPE_WRITABLE_INTEGER, FALSE) # Undocumented

    # IMMEDS
    # These commands are Immediate
    split("array break case continue define else endcase endcmd endif endlong" \
          " endlongdef endwhile esac fi for foreach if list local longdef" \
          " newcmd next of otherwise return set sm2ctl unless until wend while",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write_ns(M2_SYSNS, array[elem], ROOT_LEVEL, TYPE_COMMAND FLAG_SYSTEM FLAG_IMMEDIATE)

    # CMDS
    # Built-in commands
    # Also need to add entry in execute__command()  [search: DISPATCH]
    split("append cleardivert data debug decr default divert" \
          " divpop divpush dump dumpall dumpdef echo enddata eod error errprint" \
          " esyscmd eval exit filedata filedef filedefine ignore import include incr" \
          " initialize input literal m2ctl namespace nextfile" \
          " nsinclude paste readonly secho sequence serror sexit sfiledata" \
          " sfiledef sfiledefine shell simport sinclude snsinclude spaste split syscmd" \
          " tracemode traceoff traceon typeout undef undefine undivert warn wrap",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write_ns(M2_SYSNS, array[elem], ROOT_LEVEL, TYPE_COMMAND FLAG_SYSTEM)

    # FUNCS
    # They are similar to symbols but with optional parameter handling
    # Also need to add handler in dosubs()  [search: SYMFUNC]
    # Functions cannot be used as symbol or sequence names.
    split("basename boolval center chr comma date dirname divnl dow empty epoch" \
          " execpath expr format geodist gregdate hex hms hr ifdef ifelse ifndef" \
          " ifx index join lc left len ljust ltrim mid mjd mktemp ord rem right" \
          " rjust rot13 rtrim scenter scomma sexecpath sexpr sjoin" \
          " sljust space spaces sprintf srem srjust strftime substr tab tabs time" \
          " ns" \
          " trim tz uc utc uuid xbasename xdirname",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write_ns(M2_SYSNS, array[elem], ROOT_LEVEL, TYPE_FUNCTION FLAG_SYSTEM)

    # INTERNAL
    # Used for tracing internal functions - not reachable by user
    split("dosubs qualify", array, TOK_SPACE)
    for (elem in array)
        nam_ll_write_ns(M2_SYSNS, array[elem], ROOT_LEVEL, TYPE_INTERNAL FLAG_SYSTEM)

    # Set up terminal to receive output as stream 0 (default)
    div2blktab[0] = TERMINAL
    stk_push(__stream_stack, TERMINAL) # sets __DIVNUM__
    __block_cnt = -1                   # blk_new() increments first,
    __terminal = blk_new(BLK_TERMINAL) # so __terminal == block 0
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

    __m2_config_flags = flag_set_clear(__m2_config_flags, INIT_ORD)
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
    __m2_config_flags = flag_set_clear(__m2_config_flags, INIT_ROT13, EMPTY)
}


# It is important that __PROG__ remains a read-only symbol.
# Otherwise, some bad person could entice you to evaluate:
#       @define __PROG__[stat]  /bin/rm
#       @include my_precious_file
function initialize_prog_paths()
{
    sym_ll_fiat("__TMPDIR__", NOKEY,       PTYPE_WRITABLE_SYMBOL,  "/tmp/")
    nam_ll_write_ns(M2_SYSNS, "__PROG__", ROOT_LEVEL, TYPE_ARRAY FLAG_READONLY FLAG_SYSTEM)
    if (secure_level() >= SEC_PARANOID)
        return

    if ("basename" in PROG)
        sym_ll_fiat("__PROG__", "xbasename", PTYPE_READONLY_SYMBOL, PROG["basename"])
    if ("date" in PROG)
        sym_ll_fiat("__PROG__", "date",      PTYPE_READONLY_SYMBOL, PROG["date"])
    if ("dirname" in PROG)
        sym_ll_fiat("__PROG__", "xdirname",  PTYPE_READONLY_SYMBOL, PROG["dirname"])
    if ("hostname" in PROG)
        sym_ll_fiat("__PROG__", "hostname",  PTYPE_READONLY_SYMBOL, PROG["hostname"])
    if ("id" in PROG)
        sym_ll_fiat("__PROG__", "id",        PTYPE_READONLY_SYMBOL, PROG["id"])
    if ("pwd" in PROG)
        sym_ll_fiat("__PROG__", "pwd",       PTYPE_READONLY_SYMBOL, PROG["pwd"])
    if ("rm" in PROG)
        sym_ll_fiat("__PROG__", "rm",        PTYPE_READONLY_SYMBOL, PROG["rm"])
    if ("sh" in PROG)
        sym_ll_fiat("__PROG__", "sh",        PTYPE_READONLY_SYMBOL, PROG["sh"])
    if ("stat" in PROG)
        sym_ll_fiat("__PROG__", "stat",      PTYPE_READONLY_SYMBOL, PROG["stat"])
    if ("tput" in PROG)
        sym_ll_fiat("__PROG__", "tput",      PTYPE_READONLY_SYMBOL, PROG["tput"])
    if ("uname" in PROG)
        sym_ll_fiat("__PROG__", "uname",     PTYPE_READONLY_SYMBOL, PROG["uname"])
}


# Try to read init "dotfiles" files: $M2RC, $HOME/.m2rc, and/or ./.m2rc
# M2RC is intended to *override* $HOME (in case HOME is unavailable or
# otherwise unsuitable), so if the variable is specified and the file
# exists, then do that file; only otherwise do $HOME/.m2rc.  An init
# file from the current directory is always attempted in any case.
# No worries or errors if any of them don't exist.
function load_init_files(    old_debug)
{
    # Don't load the init files more than once
    if (flag_1true_p(__m2_config_flags, INIT_DOTFILES))
        return

    # If debugging is enabled, temporarily disable it while loading the
    # init files.  We presumably don't need it for files we don't want
    # to check.  Be careful to manipulate the symbol table directly!  We
    # don't want to trigger the special __DEBUG__ processing that is
    # baked into sym_ll_write_ns().
    old_debug = symtab[M2_SYSNS, "__DEBUG__", NOKEY, ROOT_LEVEL, "symval"]
    symtab[M2_SYSNS, "__DEBUG__", NOKEY, ROOT_LEVEL, "symval"] = FALSE

    if ("M2RC" in ENVIRON && path_exists_p(ENVIRON["M2RC"]))
        dofile(ENVIRON["M2RC"])
    else if (sys_in("__HOME__", NOKEY))
        dofile(sys_read("__HOME__", NOKEY)  ".m2rc")
    dofile("./.m2rc")

    # Don't count init files in total line/file tally - it's better to
    # keep them in sync with the files from the command line.
    sys_write("__NFILE__", 0)
    sys_write("__NLINE__", 0)

    # Restore debugging, if any, and we're done
    symtab[M2_SYSNS, "__DEBUG__", NOKEY, ROOT_LEVEL, "symval"] = old_debug
    __m2_config_flags = flag_set_clear(__m2_config_flags, INIT_DOTFILES, EMPTY)

    # FOR TESTING - start in Debug mode
    # enable_debugging()
    # dbg__all_lev_standard()

    run_hook("m2_begin")
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       P R O C E S S   C O M M A N D   L I N E   A R G U M E N T S
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       ARGC is known to be greater than one, so loop through all arguments.
#       Each arg is either a NAME=VALUE definition, or a file to parse.
#
#*****************************************************************************
function process_command_line_arguments(    nfile, arg, i, eq, name, val, file,
                                            oldip)
{
    # Delay loading $HOME/.m2rc as long as possible.  This allows us
    # to set symbols on the command line which will have taken effect
    # by the time the init file loads.
    nfile = 0
    for (i = 1; i < ARGC; i++) {
        # Show each arg as we process it
        arg = ARGV[i]
        dbg__print("args", 3, ("BEGIN: ARGV[" i "]:" arg))

        # Is it a command?
        if (first(arg) == TOK_AT) {
            dbg__print("args", 3, sprintf("BEGIN: Eval '%s'", arg))
            xeq_cmd__eval("eval", arg)

        # If it's a definition on the command line, define it
        } else if (arg ~ /^([^= ][^= ]*)=(.*)/) {
            eq   = index(arg, "=")
            name = substr(arg, 1, eq-1)
            val  = substr(arg, eq+1)

            # Some args like debug and trace are merely aliases for other,
            # harder-to-type symbol names.  They just get re-written.
            # Other args like init or U trigger actions which are executed
            # immediately, and then the loop continues with the next arg.
            if (name == "debug") {
                name = "__DEBUG__"
            } else if (name == "fs") {
                name = "__FS__"
            } else if (name == "I") {      # I=<path>
                # Include-path elements on command-line are prepended
                # to __INCPATH__ so they override M2PATH env variable values.
                if (!emptyp(val)) {
                    oldip = sys_read("__INCPATH__", NOKEY)
                    sys_write("__INCPATH__", val (!emptyp(oldip) ? TOK_COLON : "") oldip)
                }
                continue
            } else if (name == "init") {   # init=<VAL>
                # This may cause __m2_begin_hook to run either prematurely or not at all
                if (val > 0)
                    # Positive value loads init files immediately
                    # without needing to providing a command-line file.
                    load_init_files()
                else
                    # Do not load the init files.  Inhibit init file
                    # loading by pretending we already did it.
                    __m2_config_flags = flag_set_clear(__m2_config_flags, INIT_DOTFILES, EMPTY)
                continue
            } else if (name == "R") {      # R=<path>
                # Remove element on command-line from Include-path
                if (!emptyp(val))
                    rm_INCPATH(val)
                continue
            } else if (name == "secure") {
                name = "__SECURE__"
            } else if (name == "strict") {
                val = to_bool(val) # (val > 0) # convert int value to bool
                # Update strict settings
                sym_ll_write_ns(M2_SYSNS, "__STRICT__", "bool", ROOT_LEVEL, val)
                sym_ll_write_ns(M2_SYSNS, "__STRICT__",  "def", ROOT_LEVEL, val)
                sym_ll_write_ns(M2_SYSNS, "__STRICT__",  "env", ROOT_LEVEL, val)
                sym_ll_write_ns(M2_SYSNS, "__STRICT__", "file", ROOT_LEVEL, val)
                sym_ll_write_ns(M2_SYSNS, "__STRICT__",  "key", ROOT_LEVEL, val)
                continue
            } else if (name == "trace") {
                if (emptyp(val))
                    # trace= sets __TRACE__ to False
                    sys_write("__TRACE__", FALSE)
                else {
                    # trace=abcd sets __TRACE__ to True and _val is
                    # passed to @tracemode.  Don't forget "+" FLAGS
                    sys_write("__TRACE__", TRUE)
                    xeq_cmd__tracemode("tracemode", val)
                }
                continue
            } else if (name == "T") {      # T=<name>
                # traceon (and T=...) sets __TRACE__ to True
                xeq_cmd__traceon("traceon", val)
                continue
            } else if (name == "U") {      # U=<name>
                # Undefine name, like @undef
                xeq_cmd__undefine("undefine", val)
                continue
            } else if (name == "verbose") {
                name = "__VERBOSE__"
            }

            # If we reach here, we still have our NAME=VAL arg to process,
            # and we haven't broken off taking some arg-triggered action.
            # Remember, "NAME=" on command line defines with empty value.
            dbg__print("args", 3, "BEGIN: Setting '" name "' to '" val "'")
            if (emptyp(val))
                xeq_cmd__define("set", name)
            else
                xeq_cmd__define("define", name TOK_SPACE val)

        # If not NAME=VAL, try to load arg as a file.
        } else {
            nfile++
            file = search_file(arg)
            if (emptyp(file)) {
                warn("File '" arg "' not found", "ARGV", i)
                sys_write("__EXIT__", EX_NOINPUT)
                continue
            }
            load_init_files()
            if (! dofile(file)) {
                warn("Problem parsing file '" file "'", "ARGV", i)
                sys_write("__EXIT__", EX_M2_ERROR)
            }
        }
    }

    # If we get here with __rnf still zero, that means we used
    # up every ARGV defining symbols and didn't specify any files.
    # (Well that used to be true, but you can also get here by
    # specifying files that don't exist.)  So we check the number of
    # files we've processed vs the number we were requested to handle.
    #print_stderr("nfile=" nfile "  __rnf=" __rnf)
    if (__rnf == 0) {
        # Not specifying any input files, like the ARGC==1 situation,
        # means to read standard input, so that is what we must now do.
        if (nfile == 0) {
            load_init_files()
            sys_write("__EXIT__", dofile("-") ? EX_OK : EX_NOINPUT)
        } else {
            # User specified file(s) but not one of them existed.
            sys_write("__EXIT__", EX_NOINPUT)
        }
    }
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

    # In Awk, ARGC is never zero; no command line arguments is indicated
    # by ARGC being equal to 1.  If so, process standard input.
    if (ARGC == 1) {
        load_init_files()
        sys_write("__EXIT__", dofile("-") ? EX_OK : EX_NOINPUT)
    } else
        # Otherwise, there must be at least one command line argument,
        # so process them all.  Args might be file names to parse, or
        # user settings (symbols to define) of the form NAME=VALUE.
        process_command_line_arguments()

    # Under normal execution, all blocks should have been popped from
    # the parse stack, so check that.  There should only be the terminal
    # block (created in initialize) remaining but we can't remove it
    # because we might need it in end_program() to ship out diversions and
    # wraps.  I also can't move this check into end_program(), because
    # that routine might be called during execution with parsers still
    # present on the stack.
    if (stk_depth(__parse_stack) != 1) {
        print_stderr("Parse stack is not empty!")
        dump_parse_stack()
        abend()
    }

    end_program(MODE_STREAMS_SHIP_OUT)
}


function close_open_files(delete_blocks_p,
                          filename)
{
    for (filename in __active_files) {
        #print_stderr("Attempting close of " filename)
        if (filename != STDIN)
            close(filename)
        blktab[__active_files[filename], 0, "open"] = FALSE
        if (delete_blocks_p)
            blk_master_delete(__active_files[filename])
    }
}


# Prepare to exit.  Normally, diverted_streams_final_disposition is
# MODE_STREAMS_SHIP_OUT, so we usually undivert all pending streams.
# When diverted_streams_final_disposition is MODE_STREAMS_DISCARD, any
# diverted data is dropped.  Standard output is always flushed, and
# program exits with value from __EXIT__.
function end_program(diverted_streams_final_disposition,
                     i, timestamp, stream, exit_code)
{
    if (debugging_enabled_p())
        print_debugfile(sprintf("m2:%s %s%s", "END PROGRAM", "Cave closing soon",
                        VERBOSE() ? ".  All adventurers exit immediately through Main Office." : ""))

    run_hook("m2_end")

    exit_code = sys_read("__EXIT__", NOKEY)
    if (exit_code == EX_OK &&
        diverted_streams_final_disposition == MODE_STREAMS_SHIP_OUT) {

        # In the normal case of MODE_STREAMS_SHIP_OUT, ship out any remaining
        # diverted data.  See "STREAMS & DIVERSIONS" documentation in man page
        # to see how the user can prevent this, if desired.
        #
        # Regardless of whether the parse stack is empty or not, streams
        # which ship out when m2 ends must go to standard output.  So
        # always create a TERMINAL block to receive this data.  Since
        # the program is about to terminate anyway, we don't care about
        # managing the parse stack from here on out.
        stk_push(__stream_stack, TERMINAL)
        undivert_all()
    }

    # Regardless of exit status, execute any wrapped text/commands
    if (__wrap_cnt > 0)
        for (i = 1; i <= __wrap_cnt; i++)
            dostring(__wrap_text[i])

    run_hook("m2_exit")

    # for (stream in div2blktab)
    #     blk_master_delete(div2blktab[stream])

    # Close open files, attempt to reclaim block
    close_open_files(TRUE)

    # NOTE - dev stuff here
    # nam_purge(ROOT_LEVEL)
    # sym_purge(ROOT_LEVEL)

    # if (tracing_event_p(TRACE_BLOCKS))
    #     blk_nicer_dump_blktab()

    if (debugging_enabled_p())
        print_debugfile(sprintf("m2:%s %d",
                                (exit_code == EX_NOINPUT ? "NOFILE" \
                               : exit_code == EX_OK      ? "END" \
                               :                           "ERROR"),
                                exit_code))
    flush_stdout(SYNC_FORCE)
    exit exit_code
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
