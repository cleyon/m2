#!/usr/bin/awk -f
#!/usr/local/bin/mawk -f
#!/usr/local/bin/gawk -f
#
#*********************************************************** -*- mode: Awk -*-
#
#  File:        m2
#  Time-stamp:  <2025-10-24 12:21:35 cleyon>
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
#  Copyright (c) 2025 Christopher Leyon
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
    M2_VERSION = "5.0.0pre2"

    # Specify a shell for m2 to use for running utility program.  It
    # will be used for the safe_shell() function.  Requirements:
    #   - Accept a "-c" option to specify a command to execute
    #   - Honor the "<" # and ">" redirection operators
    #   - Support "command -v" to check if program would execute
    # Regardless of the program name (sh, bash, dash, ksh, etc), the
    # PROG array key MUST be "sh".
    _safe_shell = "/bin/sh"     # Customize me
    if (awk_stat(_safe_shell))
        PROG["sh"] = _safe_shell
    else
        print_stderr("m2:External program '" _safe_shell "' not found")

    # Customize these paths as needed for correct operation on your
    # system.  They are assumed to be safe to run even at secure level
    # SECURE (but not PARANOID).  If a program is not available, simply
    # remove the entry entirely.
    split("/usr/bin/basename" \
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
    for (_prog in _progs)
        if (awk_stat(_progs[_prog]))
            PROG[awk_basename(_progs[_prog])] = _progs[_prog]
        else
            print_stderr("m2:External program '" _progs[_prog] "' not found")

    # See the "SECURITY CONSIDERATIONS" section of the manual for more info:
    SEC_STANDARD     = 0 # Default secure level allows m2 to run normal
                         # programs for the user; this allows the @shell
                         # command to function and @undivert to a file.
    SEC_SECURE       = 1 # Secure level 1 prevents this, but does allow
                         # m2 to utilise the (presumably secure)
                         # utilities specified in the PROG array.
    SEC_PARANOID     = 2 # Secure level 2 prevents invoking any programs,
                         # and will terminate if any attempt is made.
                         # At level 2, m2 does not know the current time
                         # or date, host or user name, etc.
    __secure_level   = SEC_STANDARD

    # Largest legal diversion (stream) number.  Traditional m4 supports
    # nine diversions, but GNU m4 greatly increases that limit.  Despite
    # how bloated m2 may be, I don't have a need for more, but you might.
    MAX_STREAM = 9
}

# DO NOT CHANGE anything below this line

BEGIN {
    TRUE  = OKAY     =  1;              NULL   = "/dev/null"
    FALSE = EOF      =  0;              STDIN  = "/dev/stdin"
    ERROR = VOID     = -1;              STDOUT = "/dev/stdout"
    EMPTY            = "";              STDERR = "/dev/stderr"
    GLOBAL_NAMESPACE =  0;              TTY    = "/dev/tty"

    # Exit codes
    EX_OK            =  0;              __exit_code = EX_OK
    EX_M2_ERROR      =  1
    EX_USER_REQUEST  =  2
    EX_NOINPUT       = 66       # failure to process any files
    EX_SOFTWARE      = 70       # panic()
    EX_NOPERM        = 77       # security violation

    # Flags, Types, and Pseudo-Types
    FLAG_BOOLEAN   = "B"
    FLAG_DEFERRED  = "D"
    FLAG_IMMEDIATE = "!"
    FLAG_INTEGER   = "I"
    FLAG_KEY_NO    = "N"        # Key element (and brackets) must not be present
    FLAG_KEY_YES   = "K"        # Key element to index Array or List is required
    FLAG_NUMERIC   = "M"
    FLAG_READONLY  = "R"
    FLAG_SYSTEM    = "Y"
    FLAG_TRACING   = "T"
    FLAG_WRITABLE  = "W"

    TYPE_ARRAY       = "A";             __base_type[TYPE_ARRAY   ] = TYPE_ARRAY
    TYPE_COMMAND     = "C";             __base_type[TYPE_COMMAND ] = TYPE_COMMAND
    TYPE_FUNCTION    = "F";             __base_type[TYPE_FUNCTION] = TYPE_FUNCTION
    TYPE_INTERNAL    = "_";             __base_type[TYPE_INTERNAL] = TYPE_INTERNAL
    TYPE_LIST        = "L";             __base_type[TYPE_LIST    ] = TYPE_LIST
    TYPE_SEQUENCE    = "Q";             __base_type[TYPE_SEQUENCE] = TYPE_SEQUENCE
    TYPE_SYMBOL      = "S";             __base_type[TYPE_SYMBOL  ] = TYPE_SYMBOL
    TYPE_USER        = "U";             __base_type[TYPE_USER    ] = TYPE_USER
    #
    VALID_TYPES      = TYPE_ARRAY  TYPE_COMMAND   TYPE_FUNCTION  TYPE_INTERNAL \
                       TYPE_LIST   TYPE_SEQUENCE  TYPE_SYMBOL    TYPE_USER
    #
    PTYPE_ANY        = "*";             __base_type[PTYPE_ANY    ] = VALID_TYPES
    PTYPE_IDXABLE    = "i";             __base_type[PTYPE_IDXABLE] =              TYPE_ARRAY  TYPE_LIST
    PTYPE_NUMBER     = "n";             __base_type[PTYPE_NUMBER ] = TYPE_SYMBOL  TYPE_ARRAY  TYPE_LIST  FLAG_KEY_YES  TYPE_SEQUENCE
    PTYPE_SCALAR     = "s";             __base_type[PTYPE_SCALAR ] = TYPE_SYMBOL  TYPE_ARRAY  TYPE_LIST  FLAG_KEY_YES
    PTYPE_UNDEF      = "?";             __base_type[PTYPE_UNDEF  ] = EMPTY # Undef ::= type of a not-found namtab lookup
    #
    PTYPE_READONLY_SYMBOL  = TYPE_SYMBOL FLAG_SYSTEM FLAG_READONLY
    PTYPE_READONLY_INTEGER = TYPE_SYMBOL FLAG_SYSTEM FLAG_READONLY FLAG_INTEGER
    PTYPE_READONLY_NUMERIC = TYPE_SYMBOL FLAG_SYSTEM FLAG_READONLY FLAG_NUMERIC
    #
    PTYPE_WRITABLE_SYMBOL  = TYPE_SYMBOL FLAG_SYSTEM FLAG_WRITABLE
    PTYPE_WRITABLE_INTEGER = TYPE_SYMBOL FLAG_SYSTEM FLAG_WRITABLE FLAG_INTEGER
    PTYPE_WRITABLE_BOOLEAN = TYPE_SYMBOL FLAG_SYSTEM FLAG_WRITABLE FLAG_BOOLEAN

    # Set up critical symbols early
    namtab["__DEBUG__",      GLOBAL_NAMESPACE] = PTYPE_WRITABLE_BOOLEAN
    namtab["__SECURE__",     GLOBAL_NAMESPACE] = PTYPE_WRITABLE_INTEGER
    namtab["__TRACE__",      GLOBAL_NAMESPACE] = PTYPE_WRITABLE_BOOLEAN
    #
    symtab["__DEBUG__",  "", GLOBAL_NAMESPACE, "symval"] = FALSE
    symtab["__SECURE__", "", GLOBAL_NAMESPACE, "symval"] = __secure_level
    symtab["__TRACE__",  "", GLOBAL_NAMESPACE, "symval"] = FALSE
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


# Return N spaces (or other character)
function spaces(n,    c,
                s)
{
    if (c == EMPTY)
        c = TOK_SPACE
    while (n-- > 0)
        s = s c
    return s
}


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


function to_bool(x)
{
    return !! (0 + x)
}


function ppf__bool(x)
{
    return (x == FALSE || x == "") ? "False" : "True"
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


function split_subsep(s, item_arr,
                      nitem, i, retval)
{
    while (length(s) > 0) {
        nitem++
        if ((i = index(s, SUBSEP)) > 0) {
            item_arr[nitem] = substr(s, 1, i-1)
            s = substr(s, i+1)
        } else {
            item_arr[nitem] = s
            break
        }
    }
    return nitem
}


function ppf__sepstr(s,
                     i, retval)
{
    while (length(s) > 0) {
        if ((i = index(s, SUBSEP)) > 0) {
            retval = retval "ELEM: " substr(s, 1, i-1) TOK_NEWLINE
            retval = retval "SUBSEP" TOK_NEWLINE
            s = substr(s, i+1)
        } else {
            retval = retval "REST: " s TOK_NEWLINE
            break
        }
    }
    return chop(retval)
}


function extract_cmd_name(text,
                          name)
{
    if (!match(text, "^@[a-zA-Z0-9_]+"))
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
    return text ~ /^__.*__$/
}


# Environment variable names must match the following regexp:
#       /^[A-Za-z_][A-Za-z_0-9]*$/
function env_var_name_valid_p(var)
{
    return var ~ /^[A-Za-z_][A-Za-z_0-9]*$/
}


# Throw an error if the environment variable name is not valid
function assert_valid_env_var_name(var, caller)
{
    if (caller == EMPTY)
        panic("(assert_valid_env_var_name) Empty caller!")
    if (env_var_name_valid_p(var))
        return
    error(sprintf("%s: Name '%s' not valid",
                  caller, var))
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
        return 1                # <0 -> Non-existent or unreadable
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


# Construct a unique file path which does not currently exist.
# The path_template is expected to end in one or more "X" characters,
# which are replaced by random (hex) characters.  Unlike standard
# mktemp(1), this function does not actually create the file; it merely
# returns its path.  It makes no guarantees that such a file path can
# actually be created or used, so the caller must still take care.  This
# is less robust than the system version but hopefully still good enough.
function mktemp(path_template,
                leading_elements, file_path, tries)
{
    if (match(path_template, "X+$") == NOT_FOUND)
        error("(mktemp) Invalid template '" path_template "': missing X")
    # Leading elements are everything up to but not including trailing "X"s
    leading_elements = substr(path_template, 1, RSTART - 1)
    tries = 10
    while (tries-- > 0) {
        file_path = leading_elements  hex_digits(RLENGTH)
        if (path_exists_p(file_path))
            continue
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


function secure_level()
{
    return sym_ll_read("__SECURE__", "", GLOBAL_NAMESPACE)
}


function LINE()
{
    return sym_ll_read("__LINE__", "", GLOBAL_NAMESPACE) + 0
}


function FILE()
{
    return sym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
}


function strictp(ssys)
{
    if (ssys == EMPTY)
        panic("(strictp) ssys cannot be empty!")
    # Use low-level function here, not sym_true_p(), to prevent infinite loop
    return sym_ll_read("__STRICT__", ssys, GLOBAL_NAMESPACE) != FALSE
}


function build_prog_cmdline(prog, arg, mode)
{
    if (! sym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        panic(sprintf("build_prog_cmdline: __PROG__[%s] not defined", prog))
    return sprintf("%s %s%s", \
                   sym_ll_read("__PROG__", prog, GLOBAL_NAMESPACE),  \
                   arg, \
                   ((mode == MODE_IO_SILENT) ? sprintf(" >%s 2>%s", NULL, NULL) : EMPTY))
}


function exec_prog_cmdline(prog, arg,    sym)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation("(exec_prog_cmdline) Forbidden")

    if (! sym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        panic(sprintf("(exec_prog_cmdline) __PROG__[%s] not defined", prog))
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
        return sym_ll_read("__PROG__", "sh", GLOBAL_NAMESPACE)
    panic("(safe_shell) No shell program found")
}


# ATMODE is a property of the source.  If there is no source, we're probably
# in the process of undiverting some streams after the program ends.  Streams
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
        panic("(curr_dstblk) Parse stack is empty!")
    top_block = stk_top(__parse_stack)
    dbg__print_block("ship_out", 7, top_block, "(curr_dstblk) top_block [top of __parse_stack]")
    if (! ((top_block, 0, "dstblk") in blktab)) {
        panic("(curr_dstblk) Top block " top_block " does not have 'dstblk'")
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
    else
        panic("(ppf__mode) Unknown mode '" mode "'")
}


function raise_namespace()
{
    __namespace++
    dbg__print("namespace", 4, "(raise_namespace) namespace now " __namespace)
    return __namespace
}


function lower_namespace()
{
    if (__namespace == GLOBAL_NAMESPACE)
        panic("(lower_namespace) Cannot be called from global namespace")
    sym_purge(__namespace)
    nam_purge(__namespace)
    __namespace--
    dbg__print("namespace", 4, "(lower_namespace) namespace now " __namespace)
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
    if (stk_empty_p(__parse_stack)) {
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
                gsub(/\\}/, "}", mtext) # Fix quoted brace
        rtext = substr(s, cb+1)
        if (dbg__sys_level_p("braces", 7)) {
            print_debugfile("   expand_braces: ltext='" ltext "'")
            print_debugfile("   expand_braces: mtext='" mtext "'")
            print_debugfile("   expand_braces: rtext='" rtext "'")
        }

        while (length(mtext) >= 2 && first(mtext) == TOK_AT && last(mtext) == TOK_AT)
            mtext = substr(mtext, 2, length(mtext) - 2)

        macro_setup(macro, mtext)
        if (!emptyp(mtext)) {
            macro_expand(macro)
            if (!macro["okay"] && strictp("def"))
                error(sprintf("@%s@: Name '%s' not defined",
                              macro["urtext"], macro["fn"]))
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
    # Look at the character (c) immediately following token, and also the
    # next character (nc) after that.  One or both might be empty string.
    offset = toklen
    c  = substr(s, start+offset,   1)
    nc = substr(s, start+offset+1, 1)

    while (start+offset <= slen) {
        dbg__print("braces", 7, ("   find_closing_brace: offset=" offset ", c=" c ", nc=" nc))
        if (c == "") {          # end of string/error
            break
        } else if (c == TOK_RBRACE) {
            dbg__print("braces", 3, ("<< find_closing_brace: => " start+offset))
            return start+offset
        } else if (c == "\\" && nc == TOK_RBRACE) {
            # "\}" in expansion text will result in a single close brace
            # without ending the expansion text parser.  Skip over }
            # and do not return yet.  "\}" is fixed in calling routine.
            offset++; nc = substr(s, start+offset+1, 1)
        } else if (tok_opt == TOK_AT_BRACE && c == TOK_AT && nc == TOK_LBRACE) {
            # If the start token was "@{", then @{ in expansion text
            # will invoke a recursive scan.
            cb = find_closing_brace(s, start+offset, TOK_AT_BRACE)
            if (cb <= 0)
                return cb       # propagate failure/error

            # Since the return value is the absolute location of the "}"
            # in string s, update offset to be the value corresponding
            # to that location.  In fact, offset is exactly the distance
            # from that closing brace back to "start".
            offset = cb - start
            nc = substr(s, start+offset+1, 1)
            dbg__print("braces", 5, ("   find_closing_brace: (recursive '@{') cb=" cb \
                                     ".  Now, offset=" offset ", nc=" nc))
        } else if (c == TOK_LBRACE) {
            # In the general case, encountering an additional "{" means
            # we have to scan for *its* closing brace before we can
            # resume searching for the *current* closing brace.
            cb = find_closing_brace(s, start+offset, TOK_LBRACE)
            if (cb <= 0)
                return cb       # propagate failure/error
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
function format_message(text, file, line,    s)
{
    file = file ""
    if (file == EMPTY)
        file = FILE()
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
    if (flushlev <= sym_ll_read("__SYNC__", "", GLOBAL_NAMESPACE)) {
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
    __exit_code = EX_M2_ERROR
    end_program(MODE_STREAMS_DISCARD)
}


# abend() is more extreme than error().  It should not be possible to
# induce a panic merely by executing user code.  It is used when there
# is an internal error, a logical inconsistency, or a "can't happen"
# situation.  It prints its message and exits immediately with code 70.
function abend(tag, code)
{
    if (code == EMPTY)
        code = EX_SOFTWARE
    if (tag == EMPTY)
        tag = "ABEND"

    print_stderr(sprintf("m2:%s", tag))
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
function readline(    getstat, i)
{
    dbg__print("io", 6, "(readline) START")
    getstat = OKAY
    if (!emptyp(__buffer)) {
        dbg__print("io", 6, "(readline) __buffer not empty so using its contents")
        # Return the buffer even if somehow it doesn't end with a newline
        if ((i = index(__buffer, TOK_NEWLINE)) == NOT_FOUND) {
            $0 = __buffer
            __buffer = EMPTY
        } else {
            $0 = substr(__buffer, 1, i-1)
            __buffer = substr(__buffer, i+1)
        }

    } else if (stk_empty_p(__source_stack)) {
        panic("(readline) Source stack empty")

    } else if (blk_type(stk_top(__source_stack)) == SRC_STRING) {
        dbg__print("io", 6, "(readline) [STRING] RETURNING EOF")
        return EOF

    } else {
        dbg__print("io", 8, "(readline) source_stack count = " stk_depth(__source_stack))
        dbg__print_block("io", 7, stk_top(__source_stack), "(readline) About to call getline < FILE()...")
        getstat = getline < FILE()
        dbg__print("io", 7, "(readline) getstat=" getstat)
        if (getstat == OKAY) {
            sym_ll_incr("__LINE__", "", GLOBAL_NAMESPACE, 1)
            sym_ll_incr("__NLINE__", "", GLOBAL_NAMESPACE, 1)
        } else if (getstat == ERROR) {
            warn("(readline) getline=>Error reading file '" FILE() "'")
        } else if (getstat != EOF)
            panic("(readline) getline returned strange value: " getstat)
    }
    dbg__print("io", 3, sprintf("(readline) RETURNING %d, $0='%s'", getstat, $0))
    return getstat
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

    namtab["__DBG__", GLOBAL_NAMESPACE] = TYPE_ARRAY FLAG_SYSTEM
    split("args block bool braces case cmd del divert dosubs dump expr for " \
          "gate if io nam namespace parse read seq ship_out stk sym trace " \
          "while xeq",  _dbg_sys_array, TOK_SPACE)
    for (_dsys in _dbg_sys_array) {
        __dbg_sysnames[_dbg_sys_array[_dsys]] = TRUE
    }
}


# This function is called automagically (it's baked into sym_ll_write())
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
    dbg__set_level("dosubs",     7)
    dbg__set_level("dump",       5)
    dbg__set_level("expr",       3)
    dbg__set_level("for",        5)
    dbg__set_level("gate",       7)
    dbg__set_level("if",         5)
    dbg__set_level("io",         3)
    dbg__set_level("nam",        3)
    dbg__set_level("namespace",  5)
    dbg__set_level("parse",      7)
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
        sym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, 0)
}


# NB - This function writes directly to the symbol table.  It does not
# use sym_ll_write(), and does not trigger special __DEBUG__ handling.
function enable_debugging()
{
    symtab["__DEBUG__", "",  GLOBAL_NAMESPACE, "symval"] = TRUE
}


function debugging_enabled_p()
{
    return sym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE)+0 > 0
}


# Predicate: TRUE if debug system level >= provided level (lev).
# Example:
#     if (dbg__sys_level_p("sym", 3))
#         warn("Debugging sym at level 3 or higher")
# NB - do NOT call sym_defined_p() here, you will get infinite recursion
function dbg__sys_level_p(dsys, lev)
{
    if (lev == EMPTY)           lev = 1
    if (dsys == EMPTY)          panic("(dbg) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) panic("(dbg) Unknown dsys name '" dsys "' (lev=" lev "): " $0)
    if (lev < 0)                return TRUE
    if (!debugging_enabled_p()) return FALSE
    if (lev == 0)               return TRUE # Don't combine with .-2; this allows negative levels to print regardless of __DEBUG__
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    if (!sym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
        return FALSE
    return dbg__get_level(dsys) >= lev
}


# Return the debug level for a given dsys.  If debugging is not enabled,
# return its negative value (i.e., multiply by -1) to indicate this.
#
# Caller can easily call abs() to get the correct value.  Currently,
# dbg__sys_level_p() is the only caller of this, and negative values are always
# going to be less than any LEV.
function dbg__get_level(dsys)
{
    if (dsys == EMPTY) panic("(dbg__get_level) dsys cannot be empty")
    if (! (dsys in __dbg_sysnames)) panic("(dbg__get_level) Unknown dsys name '" dsys "'")
    if (!sym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
        return 0
    return (sym_ll_read("__DBG__", dsys, GLOBAL_NAMESPACE)+0) \
         * (debugging_enabled_p() ? 1 : -1)
}


# Set the level (lev) for the debug dsys
function dbg__set_level(dsys, lev)
{
    if (dsys == EMPTY)           panic("(dbg__set_level) dsys cannot be empty")
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
    sym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, lev+0)
}


function print_debugfile(text,
                         debugfile)
{
    debugfile = secure_level() == SEC_STANDARD \
        ? sym_ll_read("__DEBUGFILE__", "", GLOBAL_NAMESPACE) \
        : STDERR
    printf "%s\n", text > debugfile
}


function dbg__print(dsys, lev, text,
                   retval)
{
    if (dbg__sys_level_p(dsys, lev))
        print_debugfile(text)
}


function dbg__print_block(dsys, lev, blknum, description,
                          block_type, blk_label, text, body_block)
{
    if (! dbg__sys_level_p(dsys, lev))
        return
##    blknum = blknum+0
    # print_debugfile("(dbg__print_block) blknum = " blknum)
    if (! ((blknum, 0, "type") in blktab))
        panic("(dbg__print_block) No 'type' field for block " blknum)
    block_type = blk_type(blknum)
    # print_debugfile("(dbg__print_block) block_type = " block_type)
    blk_label = ppf__block_type(block_type)

    print_debugfile(sprintf("Block # %d, Type=%s: %s", blknum, blk_label, description))
    print_debugfile(ppf__BLK(blknum))
    if (((blknum, 0, "body_block") in blktab)) {
        body_block = blktab[blknum, 0, "body_block"]
        print_debugfile(sprintf("Block # %d, %s", body_block, blk_label, "body_ block from above"))
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
function tracingp(sym,
                  info)
{
    dbg__print("trace", 5, sprintf("(tracingp) START; sym='%s'", sym))

    if (nam__scan(sym, info) == ERROR)
        error("(tracingp) Scan error, '" sym "'")
    if (nam__lookup(info) == NAME_NOT_FOUND) {
        dbg__print("trace", 7, sprintf("(tracingp) nam__lookup() failed: " sym))
        return FALSE
    }
    return info__get(info, "tracing")
}


function trace_prefix(    prefix,
                          trace_mode)
{
    prefix = "m2trace:"
    trace_mode = sym_ll_read("__TRACEMODE__", "", GLOBAL_NAMESPACE)
    if (flag_1true_p(trace_mode, TRACE_SHOW_FILE_NAME))
        prefix = prefix FILE() ":"
    if (flag_1true_p(trace_mode, TRACE_SHOW_LINE_NUM))
        prefix = prefix LINE() ":"
    return prefix
}


function trace(event, sym, message,
               trace_mode)
{
    if (index(TRACE_VALID_EVENTS, event) == NOT_FOUND)
        panic("(trace) Unrecognized trace event '" event "'")
    if (double_underscores_p(sym) ||
        sym_ll_read("__TRACE__", "", GLOBAL_NAMESPACE) == FALSE)
        return

    trace_mode = sym_ll_read("__TRACEMODE__", "", GLOBAL_NAMESPACE)
    if (((event == TRACE_COMMAND) &&
         (flag_1true_p(trace_mode, TRACE_ALL) || (flag_1true_p(trace_mode, TRACE_COMMAND) && tracingp(sym)))) ||
        ((event == TRACE_EXPANSION) &&
         (flag_1true_p(trace_mode, TRACE_ALL) || (flag_1true_p(trace_mode, TRACE_EXPANSION) && tracingp(sym)))) ||
        ((event == TRACE_SYMBOL_READ_WRITE) &&
         (flag_1true_p(trace_mode, TRACE_ALL) || (flag_1true_p(trace_mode, TRACE_SYMBOL_READ_WRITE) && tracingp(sym)))) ||
        ((event == TRACE_INPUT_FILE_CHG || event == TRACE_PATH_SEARCH) &&
         (flag_1true_p(trace_mode, event))))

        print_debugfile(trace_prefix() " " message)
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
                    oplevel,     # Integer containing proposed namespace level
                                 # (might differ from info["level"], often called ilevel)
                    caller,      # caller tag shown in errors
                    assert_true_or_exit, # True if this function behaves like assert()
             retval)                     # assert() and exits if condition is not met;
{                                        # If False, meekly return boolean.
    if (caller == EMPTY)
        panic("(info__gate) Empty caller")
    if (info__get(info, "error"))
        # If it starts out being bad, we're not going to touch it and leave
        # the error message alone.  It's probably a scan error.
        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit, EMPTY)

    if (info__get(info, "valid") == FALSE)
        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                  sprintf("Name '%s' is not valid",
                                          info__get(info, "urtext")))

    if (optype == PTYPE_ANY || optype == PTYPE_UNDEF)
        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                  sprintf("Type '%s' is not allowed here",
                                          ppf__flag_type(optype)))

    retval = info["nparts"] == 1 ? info__gate_1part(opcode, optype, info, oplevel, caller, assert_true_or_exit) \
                                 : info__gate_2parts(opcode, optype, info, oplevel, caller, assert_true_or_exit)
    dbg__print("gate", 3, sprintf("(info__gate) (opcode=%s, optype=%s, text='%s', oplevel=%d, caller='%s' asrtTrue=%s) => %s",
                         __op_label[opcode], ppf__flag_type(optype), info__get(info, "urtext"),
                         oplevel, caller, ppf__bool(assert_true_or_exit), ppf__bool(retval)))
    return retval
}


function info__gate_1part(opcode, optype, info, oplevel, caller, assert_true_or_exit,
                          retval, itype, iname, icode, ilevel)
{
    iname = info__get(info, "name")
    dbg__print("gate", 3, sprintf("(info__gate_1part) opcode=%s, optype=%s, name='%s', oplevel=%d",
                         ppf__flag_type(optype), __op_label[opcode], iname, oplevel))
    if (optype == PTYPE_SCALAR)
        optype = TYPE_SYMBOL

    retval = FALSE
    icode  = info__get(info, "code")
    ilevel = info__get(info, "level")
    itype  = info__get(info, "type")

    do {
        #print_stderr("start 1part")
        #print_stderr("opcode=" opcode)
        if (opcode == OP_CREATE) {
            if (optype == TYPE_SEQUENCE) {
                if (ilevel != NAME_NOT_FOUND)
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' already defined as a %s",
                                                      iname, ppf__flag_type(itype)))
                # It's not found, so info[] won't be very helpful...
                if (double_underscores_p(iname))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected", iname))
                retval = TRUE; break

            } else if (optype == TYPE_SYMBOL || optype == TYPE_COMMAND ||
                       optype == TYPE_LIST   || optype == TYPE_ARRAY) {
                if (ilevel == NAME_NOT_FOUND) {
                    # It's a new, not-found symbol
                    if (double_underscores_p(iname))
                        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                                  sprintf("Name '%s' is protected", iname))
                    #print_stderr("should be true")
                    retval = TRUE; break
                } else {
                    # It was found
                    #print_stderr("Found sym " name " at ilevel=" ilevel ", oplevel=" oplevel)
                    # if (flag_1true_p(icode, FLAG_SYSTEM) ||
                    #     double_underscores_p(iname))
                    if (info__get(info, "protected"))
                        return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                                  sprintf("Name '%s' is protected", iname))
                    retval = TRUE; break
                }
            }

        } else if (opcode == OP_READ) {
            #print_stderr("1 part read, optype=" optype)
            # Name must always be found for a read to be successful
            if (ilevel == NAME_NOT_FOUND)
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' not defined", iname))

            # # SCALAR must be checked before IDXABLE because the latter
            # # is a subset of the former
            # # if (flag_alltrue_p(optype, PTYPE_SCALAR)) {
            # if (optype == PTYPE_SCALAR) {
            #     if (itype != TYPE_SYMBOL && itype != TYPE_ARRAY && itype != TYPE_LIST)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("A Name '%s' has type %s, not Scalar",
            #                                           iname, ppf__flag_type(itype)))
            #     retval = TRUE; break
            #
            # # } else if (flag_alltrue_p(optype, PTYPE_IDXABLE)) {
            # } else if (optype == PTYPE_IDXABLE) {
            #     if (itype != TYPE_ARRAY && itype != TYPE_LIST)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("B Name '%s' has type %s, not Array or List",
            #                                           iname, ppf__flag_type(itype)))
            #     retval = TRUE; break
            #
            # } else if (optype == TYPE_ARRAY) {
            #     if (itype != optype)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("C Name '%s' has type %s, not %s",
            #                                           iname, ppf__flag_type(itype), ppf__flag_type(optype)))
            #     retval = TRUE; break
            # }
            if (! info__satisfies_type(info, optype))
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' has type %s, not %s",
                                                  iname, ppf__flag_type(itype), ppf__flag_type(optype)))
            retval = TRUE; break

        } else if (opcode == OP_UPDATE) {
            #print_stderr("op_update, optype=" optype)
            if (ilevel == NAME_NOT_FOUND)
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' not defined", iname))

            if (optype == TYPE_SYMBOL || optype == TYPE_LIST || optype == TYPE_ARRAY || optype == PTYPE_NUMBER) {
                # if (itype != optype)
                if (! info__satisfies_type(info, optype))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' has type %s, not %s",
                                                      iname, ppf__flag_type(itype), ppf__flag_type(optype)))
                # So it *was found, on some level...  Can it be updated?
                # Good old dynamic scoping
                if (flag_1true_p(icode, FLAG_WRITABLE))
                    { retval = TRUE; break }
                if (flag_anytrue_p(icode, FLAG_READONLY FLAG_SYSTEM) ||
                    double_underscores_p(iname))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected", iname))
                #print_stderr("should be true")
                retval = TRUE; break
            }
        }
        panic(sprintf("(info__gate_1part) UNHANDLED (opcode=%s, optype=%s, name='%s', oplevel=%d, caller='%s' assert=%s) => %s",
                      __op_label[opcode], ppf__flag_type(optype), iname,
                      oplevel, caller, ppf__bool(assert_true_or_exit), ppf__bool(retval)))
    } while (FALSE)

    return retval
}


function info__gate_2parts(opcode, optype, info, oplevel, caller, assert_true_or_exit,
                           retval, itype, iname, ikey, icode, ilevel)
{
    iname = info__get(info, "name")
    ikey  = info__get(info, "key")
    dbg__print("gate", 3, sprintf("(info__gate_2parts) opcode=%s, optype=%s, name='%s', key='%s', oplevel=%d",
                         ppf__flag_type(optype), __op_label[opcode], iname, ikey, oplevel))
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
                                              ppf__flag_type(itype), iname))
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
            #                                   sprintf("Name '%s' is protected", iname))
            #     if (sym_ll_in(iname, ikey, oplevel))
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("Key '%s' already found in Array '%s' at level %d", ikey, iname, oplevel))
            #     # It's not found at this level, but maybe it's at a higher level
            #     # print_stderr("Want to create " iname "[" ikey "] at level " oplevel)
            #     # print_stderr("  info[code]=" icode "   info_level=" info__get(info, "level"))
            #     if (ilevel != oplevel)
            #         return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #                                   sprintf("Name '%s' is in a different namespace", iname))
            #     retval = TRUE; break
            # }
            if (info__satisfies_type(info, PTYPE_IDXABLE)) {
                if (info__get(info, "protected"))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is protected", iname))
                if (idx__key_exists_p(info, ikey))
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Key '%s' already found in %s '%s'",
                                                      ikey, ppf__flag_type(itype), iname))
                # It's not found at this level, but maybe it's at a higher level
                # print_stderr("Want to create " iname "[" ikey "] at level " oplevel)
                # print_stderr("  info[code]=" icode "   info_level=" info__get(info, "level"))
                if (ilevel != oplevel)
                    return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                              sprintf("Name '%s' is in a different namespace", iname))
                retval = TRUE; break
            }
        } else if (opcode == OP_UPDATE) {
            #print_stderr("op_update; optype=" optype)

            if (! info__satisfies_type(info, optype))
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' has type %s, not %s",
                                                  iname, ppf__flag_type(itype), ppf__flag_type(optype)))
            if (info__get(info, "protected"))
                return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
                                          sprintf("Name '%s' is protected", iname))

            # We actually don't handle 2part PTYPE_NUMBER quite yet...
            # if (optype == PTYPE_NUMBER) {
            #     #print_stderr("ptype_number")
            #     print_stderr("OP_UPDATE : PTYPE_NUMBER : name='" iname "'; code='" icode "'; now what?")
            #     # if (! info__satisfies_type(info, optype))
            #     #     # return info__gate_resolve(FALSE, caller, info, assert_true_or_exit,
            #     #     #                           sprintf("Name '%s' has type %s, not %s",
            #     #     #                                   iname, ppf__flag_type(itype), ppf__flag_type(optype)))
            #     #     print_stderr("Type NOT satisfied")
            #     # else
            #     #     print_stderr("Type IS satisfied")
            # } else if (optype == TYPE_ARRAY) {

            # if (optype == TYPE_ARRAY) {
            #     #print_stderr("type_array")
            #     if (! sym_ll_in(iname, ikey, oplevel))
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
                                                      ikey, ppf__flag_type(itype), iname))
                retval = TRUE; break
            }
        }

        panic(sprintf("(info__gate_2parts) UNHANDLED (opcode=%s, optype=%s, name='%s', key='%s', oplevel=%d, caller='%s' assert=%s) => %s",
                      __op_label[opcode], ppf__flag_type(optype), iname, ikey,
                      oplevel, caller, ppf__bool(assert_true_or_exit), ppf__bool(retval)))
    } while (FALSE)

    return retval
}


# function info__gate_text(opcode, optype, text, oplevel, caller, assertTrueOrExit,
#                          info)
# {
#     if (caller == EMPTY)
#         panic("(info__gate_text) Empty caller")
#     info__create_from_text(text, info)
#     return info__gate(opcode, optype, info, oplevel, caller, assertTrueOrExit)
# }


function info__satisfies_type(info, type_target,
                              itype, base_types, type_array, tentry)
{
    if (type_target == PTYPE_ANY)
        return TRUE
    itype = info__get(info, "type")
    base_types = __base_type[type_target]

    if (itype == PTYPE_UNDEF || type_target == PTYPE_UNDEF)
        panic("(info__satisfies) Cannot handle PTYPE_UNDEF")
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
        info["error"] = TRUE
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
    if (info["error"] == TRUE)
        return FALSE # error("(arrayp) " info["errtext"])
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


# function array_defined_p(arr)
# {
#     if (! arrayp(arr))
#         return FALSE
#     return TRUE
# }


# function assert_array_defined(arr, caller,
#                               level, info)
# {
#     if (caller == EMPTY)
#         panic("(assert_array_defined) Empty caller!")
#     if (! array_defined_p(arr))
#         error(sprintf("%s: Array '%s' not defined",
#                       caller, arr))
# }


# Check that arr is really an ARRAY and that it's writable
# function assert_array_okay_to_define(arr, caller,
#                                      nparts, level, info, code)
# {
#     if (caller == EMPTY)
#         panic("(assert_array_okay_to_define) Empty caller!")
#     # Check namtab
#     if ((nparts = nam__scan(arr, info)) == ERROR)
#         error("(assert_array_okay_to_define) Scan error, " __m2_msg)
#     if (nparts == 2)
#         error(sprintf("%s: Array '%s' cannot have subscripts", caller, arr))
#
#     # Now call nam__lookup(info).  Must be TYPE_ARRAY && !FLAG_SYSTEM
#     level = nam__lookup(info)
#     if (level == NAME_NOT_FOUND)
#         error(sprintf("%s: Name '%s' not found", caller, arr))
#     if (info["type"] != TYPE_ARRAY)
#         error(sprintf("%s: Name '%s' not an array", caller, arr))
#     code = info["code"]
#     if (flag_anytrue_p(code, FLAG_SYSTEM FLAG_READONLY))
#         error(sprintf("%s: Array '%s' not writable", caller, arr))
#
#     # Maybe more checks later as I think of them
# }


# Check that lis is really a List and that it's writable
# function assert_list_okay_to_define(lis, caller,
#                                     nparts, level, info, code)
# {
#     if (caller == EMPTY)
#         panic("(assert_list_okay_to_define) Empty caller!")
#     # Check namtab
#     if ((nparts = nam__scan(lis, info)) == ERROR)
#         error("(assert_list_okay_to_define) Scan error, " __m2_msg)
#     if (nparts == 2)
#         error(sprintf("%s: List '%s' cannot have subscripts", caller, lis))
#
#     # Now call nam__lookup(info).  Must be TYPE_LIST && !FLAG_SYSTEM
#     level = nam__lookup(info)
#     if (level == NAME_NOT_FOUND)
#         error(sprintf("%s: Name '%s' not found", caller, lis))
#     if (info["type"] != TYPE_LIST)
#         error(sprintf("%s: Name '%s' not a List", caller, lis))
#     code = info["code"]
#     if (flag_anytrue_p(code, FLAG_SYSTEM FLAG_READONLY))
#         error(sprintf("%s: List '%s' not writable", caller, lis))
#
#     # Maybe more checks later as I think of them
# }

# function arr__assert_okay_to_define(arr, caller,
#                                     level, info, type)
# {
#     if (caller == EMPTY)
#         panic("(arr__assert_okay_to_define) Empty caller!")
#     if ((level = info__create_from_text(arr, info)) == ERR_SCAN_INVALID_NAME)
#         error(sprintf("%s: %s", caller, info["errtext"]))
# }


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
                        type, name, key, level, val, code)
{
    if ((type = info__get(info, "type")) != TYPE_ARRAY)
        panic("(arr_fetch_info) Info not an Array")
    name = info__get(info, "name")
    key = info__get(info, "key")
    level = info__get(info, "level")
    if (! sym_ll_in(name, key, level))
        error("(arr_fetch_info) Not in symtab: NAME='" name "', KEY='" key "'")
    val = sym_ll_read(name, key, level)
    code = info__get(info, "code")
    dbg__print("sym", 2, sprintf("(arr_fetch_info) END sym='%s', level=%d => %s", name, level, ppf__bool(TRUE)))
    if (flag_1true_p(code, FLAG_INTEGER))
        return 0 + val
    else if (flag_1true_p(code, FLAG_NUMERIC))
        return 0.0 + val
    else if (flag_1true_p(code, FLAG_BOOLEAN))
        return sym_ll_read("__FMT__", to_bool(val)) # !! (0 + val))
    else
        return val
}

function lis_fetch_info(info, caller,
                        type, name, key, level, agg_block, count, val)
{
    if (caller == EMPTY)
        panic("(lis_fetch_info) Empty caller!")
    if ((type = info__get(info, "type")) != TYPE_LIST)
        panic("(lis_fetch_info) Info not a List")
    if (! integerp(key = info__get(info, "key")))
        error(sprintf("%s: Invalid List index '%s'", caller, key))
    if (! ((name = info__get(info, "name"), "", level = info__get(info, "level"), "agg_block") in symtab))
        panic(sprintf("(lis_fetch_info) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                      name, "", level))
    agg_block = symtab[name, "", level, "agg_block"]
    count = blktab[agg_block, 0, "count"]+0
    if (key < 1 || key > count)
        if (strictp("key"))
            error(sprintf("%s: Index '%s' out of bounds", caller, key))
        else
            return EMPTY

    # Make sure slot holds text, which it pretty much has to
    if (blk_ll_slot_type(agg_block, key) != OBJ_TEXT)
        panic(sprintf("(lis_fetch_info) Block # %d slot %d is not OBJ_TEXT", agg_block, key))
    val = blk_ll_slot_value(agg_block, key)
    return val
}


function lis_clear(lis, level, code,
                   agg_block, count, i)
{
    if (code == EMPTY)
        panic("(lis_clear) Missing code!")

    # Clear List
    if (! ((lis, "", level, "agg_block") in symtab))
        panic(sprintf("(lis_clear) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                      lis, "", level))
    agg_block = symtab[lis, "", level, "agg_block"]
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
                           itype, iname, ilevel)
{
    itype  = info__get(info, "type")
    iname  = info__get(info, "name")
    ilevel = info__get(info, "level")
    if (itype == TYPE_ARRAY)
        return sym_ll_in(iname, key, ilevel)
    else if (itype == TYPE_LIST)
        return lis__key_exists_p(iname, key, ilevel)
    else
        panic("(idx__key_exists_p) Cannot handle type " itype)
}


# function arr_clear(arr, level, code,
#                      k, x, del_list, agg_block, count, i)
# {
#     if (code == EMPTY)
#         panic("(arr_clear) Missing code!")
#     if (flag_1true_p(code, FLAG_BLKARRAY)) {
#         # # Clear block array
#         # if (! ((arr, "", level, "agg_block") in symtab))
#         #     panic(sprintf("(arr_clear) Could not find ['%s','%s',%d,'agg_block'] in symtab",
#         #                   arr, "", level))
#         # agg_block = symtab[arr, "", level, "agg_block"]
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
#             if (x[1] == arr && x[3]+0 == level)
#                 del_list[x[1], x[2], x[3], x[4]] = TRUE
#         }
#         for (k in del_list) {
#             split(k, x, SUBSEP)
#             dbg__print("sym", 3, sprintf("(arr_clear) Delete symtab['%s', '%s', %d, %s]",
#                                         x[1], x[2], x[3], x[4]))
#             delete symtab[x[1], x[2], x[3], x[4]]
#         }
#     }
# }


function lis__size(lis, level,
                   agg_block)
{
    # Size block array
    if (! ((lis, "", level, "agg_block") in symtab))
        panic(sprintf("(lis__size) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                      lis, "", level))
    agg_block = symtab[lis, "", level, "agg_block"]
    return blktab[agg_block, 0, "count"] + 0
}

function lis__key_exists_p(lis, key, level)
{
    key = 0 + key
    return key > 0 && key <= lis__size(lis, level)
}

function lis__assign(name, key, level, new_val,
                     agg_block, count)
{
    # print_stderr(sprintf("List: %s[%s] = %s",
    #                      name, key, new_val))
    if (! integerp(key))
        error(sprintf("(lis__assign) Invalid List index '%s'", key))
    if (key < 1)
        error(sprintf("(lis_assign) Index '%s' out of bounds", key))
    if (! ((name, "", level, "agg_block") in symtab))
        panic(sprintf("(lis__assign) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                      name, "", level))
    agg_block = symtab[name, "", level, "agg_block"]
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

function arr__size(arr, level,
                   k, x, count)
{
    count = 0
    for (k in symtab) {
        split(k, x, SUBSEP)
        if (x[1] == arr && x[3]+0 == level)
            count++
    }
    return count
}

function idx__size(arr, level, code,
                    agg_block, count, k, x)
{
    if (code == EMPTY)
        panic("(idx__size) Missing code!")
    count = 0
    if (flag_1true_p(code, TYPE_LIST)) {
        # # Size block array
        # if (! ((arr, "", level, "agg_block") in symtab))
        #     panic(sprintf("(idx__size) Could not find ['%s','%s',%d,'agg_block'] in symtab",
        #                   arr, "", level))
        # agg_block = symtab[arr, "", level, "agg_block"]
        # count = blktab[agg_block, 0, "count"]+0
        count = lis__size(arr, level)
    } else {
        # Size regular array
        # for (k in symtab) {
        #     split(k, x, SUBSEP)
        #     if (x[1] == arr && x[3]+0 == level)
        #         count++
        # }
        count = arr__size(arr, level)
    }
    dbg__print("sym", 7, sprintf("(idx__size) arr='%s', level=%d, RETURNING %d",
                                arr, level, count))
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
function blk_new(block_type,
                  new_blknum)
{
    if (block_type == EMPTY)
        panic("(blk_new) Missing type")
    new_blknum = ++__block_cnt
    blktab[new_blknum, 0, "depth"] = stk_depth(__parse_stack)
    blktab[new_blknum, 0, "type"] = block_type

    if (block_type == BLK_AGG)
        blktab[new_blknum, 0, "count"] = 0
    else if (block_type == BLK_CASE)
        blktab[new_blknum, 0, "terminator"] = "^@(endcase|esac)"
    else if (block_type == BLK_IF)
        blktab[new_blknum, 0, "terminator"] = "^@(endif|fi)"
    else if (block_type == SRC_FILE) {
        blktab[new_blknum, 0, "open"] = FALSE
        blktab[new_blknum, 0, "terminator"] = ""
        blktab[new_blknum, 0, "oob_terminator"] = "EOF"
    } else if (block_type == SRC_STRING) {
        blktab[new_blknum, 0, "terminator"] = ""
        blktab[new_blknum, 0, "oob_terminator"] = "EOS"
    } else if (block_type == BLK_FOR)
        # [0, "array_type"]     each    TYPE_ARRAY or TYPE_LIST
        # [0, "body_block"]     *
        # [0, "dstblk"]         *
        # [0, "level"]          each
        # [0, "loop_array_name] each
        # [0, "loop_end"]       iter
        # [0, "loop_incr"]      iter
        # [0, "loop_start"]     iter
        # [0, "loop_type"]      *       @for, @foreach, @sforeach
        # [0, "loop_var"]       *
        blktab[new_blknum, 0, "terminator"] = "^@next"
        # [0, "valid"]          *
    else if (block_type == BLK_LONGDEF)
        blktab[new_blknum, 0, "terminator"] = "^@endlong(def)?"
    else if (block_type == BLK_TERMINAL) {
        blktab[new_blknum, 0, "dstblk"] = TERMINAL
        blktab[new_blknum, 0, "terminator"] = ""
    } else if (block_type == BLK_USER) {
        # [0, "body_block"]
        # [0, "dstblk"]
        # [0, "name"]
        # [0, "nparam"]
        # [N, "param_name"]
        blktab[new_blknum, 0, "terminator"] = "^@endcmd"
        # [0, "valid"]
    } else if (block_type == BLK_WHILE)
        blktab[new_blknum, 0, "terminator"] = "^@(endwhile|wend)"
    else
        panic("(blk_new) Uncaught block_type '" block_type "'")

    dbg__print("ship_out", 2, sprintf("(blk_new) Block # %d; type=%s",
                                      new_blknum, ppf__block_type(block_type)))
    return new_blknum
}


function blk_type(blknum,
                  bt)
{
    if (! ((blknum, 0, "type") in blktab))
        panic("(blk_type) Block # " blknum " has no type!")
    bt = blktab[blknum, 0, "type"]
    if (! (bt in __blk_label))
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
                      blknum, ppf__block_type(blk_type(blknum))))

    if (slot_type != OBJ_CMD  && slot_type != OBJ_BLKNUM &&
        slot_type != OBJ_TEXT && slot_type != OBJ_USER)
        panic(sprintf("(blk_append) Argument has bad type %s; should be OBJ_{CMD,BLKNUM,TEXT,USER}", ppf__block_type(slot_type)))

    slot = ++blktab[blknum, 0, "count"]
    dbg__print("ship_out", 3,
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
            dbg__print("xeq", 5, "(blk_dump_blktab) type=" type)
            dbg__print_block("xeq", -1, blknum, "(blk_dump_blktab)")
        }
        seen[blknum]++
    }
    return "(blk_dump_blktab)"
}


function blk_dump_block_raw(blknum,
                            x, k, blk, type, slot_type_str)
{
    type = blk_type(blknum)
    dbg__print("xeq", 5, "(blk_dump_block_raw) type=" type)
    dbg__print_block("xeq", -1, blknum, "(blk_dump_block_raw)")

    for (k in blktab) {
        split(k, x, SUBSEP)
        blk = x[1] + 0
        if (blk == blknum) {
            dbg__print("xeq", 9, "(blk_dump_block_raw) k=" k)
            slot_type_str = ""
            if (x[3] == "slot_type")
                slot_type_str = " (" ppf__block_type(blktab[x[1], x[2], x[3]]) ")"
            print_debugfile("blknum=" x[1] ", slot=" x[2] ", tag=" x[3] \
                            " => '" blktab[x[1], x[2], x[3]] "'" slot_type_str)
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
        panic("(ppf__block_type) block_type is empty")
    dbg__print("xeq", 7, "(ppf__block_type) block_type = " block_type)
    if (! (block_type in __blk_label)) {
        panic("(ppf__block_type) Invalid block type '" block_type "'")
    }
    return __blk_label[block_type]
}


function ppf__block(blknum,
                    block_type, buf)
{
    block_type = blk_type(blknum)
    dbg__print("xeq", 3, sprintf("(ppf__block) START blknum=%d, type=%s",
                                blknum, ppf__block_type(block_type)))

    if      (block_type == BLK_AGG)       buf = ppf__agg(blknum)
    else if (block_type == BLK_CASE)      buf = ppf__case(blknum)
    else if (block_type == BLK_FOR)       buf = ppf__for(blknum)
    else if (block_type == BLK_IF)        buf = ppf__if(blknum)
    else if (block_type == BLK_LONGDEF)   buf = ppf__longdef(blknum)
    else if (block_type == BLK_TERMINAL)  buf = EMPTY
    else if (block_type == BLK_USER)      buf = ppf__user(blknum)
    else if (block_type == BLK_WHILE)     buf = ppf__while(blknum)
    else if (block_type == SRC_FILE)      buf = EMPTY
    else
        panic(sprintf("(ppf__block) Block # %d: type %s (%s) not handled",
                      blknum, block_type, ppf__block_type(block_type)))
    return buf
}


function ppf__BLK(blknum,
                  block_type, text)
{
    block_type = blk_type(blknum)
    dbg__print("xeq", 3, sprintf("(ppf__BLK) START blknum=%d, type=%s",
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
        panic(sprintf("(ppf__BLK) Can't handle type '%s' for block %d",
                      block_type, blknum))

    return text
}


function execute__block(blknum,
                        block_type, old_level)
{
    block_type = blk_type(blknum)
    dbg__print("xeq", 1, sprintf("(execute__block) START blknum=%d, type=%s",
                                blknum, ppf__block_type(block_type)))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg__print("xeq", 3, "(execute__block) NOP due to __xeq_ctl=" __xeq_ctl)
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
        panic(sprintf("(execute__block) Block # %d: type %s (%s) not handled",
                      blknum, block_type, ppf__block_type(block_type)))

    if (__namespace != old_level)
        panic(sprintf("(execute__block) blknum=%d, type=%s: %s; old_level=%d, __namespace=%d",
                      blknum, ppf__block_type(block_type), "Namespace level mismatch", old_level, __namespace))
    dbg__print("xeq", 1, "(execute__block) END")
}


function xeq__BLK_AGG(agg_block,
                      i, lim, slot_type, value, block_type, name)
{
    block_type = blk_type(agg_block)
    dbg__print("xeq", 3, sprintf("(xeq__BLK_AGG) START dstblk=%d, agg_block=%d, type=%s",
                                curr_dstblk(), agg_block, ppf__block_type(block_type)))

    dbg__print_block("xeq", 7, agg_block, "(xeq__BLK_AGG) agg_block")
    lim = blktab[agg_block, 0, "count"]
    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(agg_block, i)
        value = blk_ll_slot_value(agg_block, i)
        dbg__print("xeq", 3, sprintf("(xeq__BLK_AGG) LOOP; dstblk=%d, agg_block=%d, slot=%d, slot_type=%s, value='%s'",
                                    curr_dstblk(), agg_block, i, ppf__block_type(slot_type), value))

        dbg__print("xeq", 3, sprintf("(xeq__BLK_AGG) CALLING ship_out(%s, '%s')", slot_type, value))
        ship_out(slot_type, value)
        dbg__print("xeq", 3, "(xeq__BLK_AGG) RETURNED FROM ship_out()")
    }
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
    if ((level = nam__lookup(info)) == NAME_NOT_FOUND)
        error("(cmd_definition_ppf) nam__lookup failed")
    # See if it's a user command
    if (flag_1false_p(nam_ll_read(name, level), TYPE_USER))
        panic("(cmd_definition_ppf) " name " is no longer a user command")

    user_block = cmd_ll_read(name, level)
    return ppf__user(user_block)
}


# s is the encoded version of the invocation:
#       <name> SUBSEP <args> [ SUBSEP <arg-N> ... ]
function ppf__user_call(s,
                        nitem, citem, arg, retval)
{
    # print_stderr(ppf__sepstr(s))
    nitem = split_subsep(s, citem)
    if (nitem < 2 || nitem != 2+citem[2])
        panic(sprintf("(execute__user) split_subsep() returned strange value: %d\n>>%s<<",
                      nitem, ppf__sepstr(s)))

    retval = TOK_AT citem[1]
    for (arg = 3; arg <= nitem; arg++)
        retval = retval TOK_LBRACE citem[arg] TOK_RBRACE
    return retval
}


function ppf__user(user_block,
                   name, params, i)
{
    if ((blk_type(user_block) != BLK_USER) ||
        (blktab[user_block, 0, "valid"] != TRUE))
        panic("(ppf__user) Bad user_block config")

    name = blktab[user_block, 0, "name"]
    params = ""
    for (i = 1; i <= blktab[user_block, 0, "nparam"]; i++)
        params = params TOK_LBRACE blktab[user_block, i, "param_name"] TOK_RBRACE
    dbg__print("cmd", 5, "params='" params "'") # probably 7 or 8

    return "@newcmd " name params                           TOK_NEWLINE \
              ppf__agg(blktab[user_block, 0, "body_block"]) TOK_NEWLINE \
           "@endcmd"
}


function cmd_destroy(id)
{
    dbg__print("cmd", 2, "(cmd_destroy) BROKEN!")
    # delete namtab[id, GLOBAL_NAMESPACE]
    # delete cmdtab[id, "definition"]
    # delete cmdtab[id, "nparam"]
}


# function cmd_valid_p(text)
# {
#     return nam_valid_strict_regexp_p(text) &&
#            !double_underscores_p(text)
# }


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
    dbg__print("xeq", 3, sprintf("(execute__command) START name='%s', cmdline='%s'",
                                name, cmdline))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg__print("xeq", 3, "(execute__command) NOP due to __xeq_ctl=" __xeq_ctl)
        return
    }

    trace(TRACE_COMMAND, name, sprintf("[Execute] @%s %s", name, cmdline))
    old_level = __namespace

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
    else if (name ==  "dumpdef")        xeq_cmd__dumpdef(name, cmdline)
    else if (name ~   /dump(all)?/)     xeq_cmd__dump(name, cmdline)
    else if (name ~ /s?echo/)           xeq_cmd__error(name, cmdline)
    else if (name ~   /enddata|eod/)    error(sprintf("[@%s] Parse error; Not in a @data block", name))
    else if (name ~ /s?error/)          xeq_cmd__error(name, cmdline)
    else if (name ==  "errprint")       xeq_cmd__error(name, cmdline)
    else if (name ==  "esyscmd")        xeq_cmd__esyscmd(name, cmdline)
    else if (name ==  "eval")           xeq_cmd__eval(name, cmdline)
    else if (name ==  "exit")           xeq_cmd__exit(name, cmdline)
    else if (name ~ /s?filedata/)       xeq_cmd__filedata(name, cmdline)
    else if (name ~ /s?filedef(ine)?/)  xeq_cmd__filedefine(name, cmdline)
    else if (name ==  "ignore")         xeq_cmd__ignore(name, cmdline)
    else if (name ~ /s?include/)        xeq_cmd__include(name, cmdline)
    else if (name ==  "incr")           xeq_cmd__incr(name, cmdline)
    else if (name ==  "initialize")     xeq_cmd__define(name, cmdline)
    else if (name ==  "input")          xeq_cmd__input(name, cmdline)
    else if (name ==  "list")           xeq_cmd__list(name, cmdline)
    else if (name ==  "literal")        xeq_cmd__literal(name, cmdline)
    else if (name ==  "local")          xeq_cmd__local(name, cmdline)
    else if (name ==  "m2ctl")          xeq_cmd__m2ctl(name, cmdline)
    else if (name ==  "nextfile")       xeq_cmd__nextfile(name, cmdline)
    else if (name ==  "null")           xeq_cmd__null(name, cmdline)
    else if (name ~ /s?paste/)          xeq_cmd__include(name, cmdline)
    else if (name ==  "readonly")       xeq_cmd__readonly(name, cmdline)
    else if (name ==  "return")         xeq_cmd__return(name, cmdline)
    else if (name ==  "sequence")       xeq_cmd__sequence(name, cmdline)
    else if (name ==  "shell")          xeq_cmd__shell(name, cmdline)
    else if (name ==  "split")          xeq_cmd__split(name, cmdline)
    else if (name ==  "syscmd")         xeq_cmd__syscmd(name, cmdline)
    else if (name ==  "tracemode")      xeq_cmd__tracemode(name, cmdline)
    else if (name ==  "traceoff")       xeq_cmd__traceoff(name, cmdline)
    else if (name ==  "traceon")        xeq_cmd__traceon(name, cmdline)
    else if (name ==  "typeout")        xeq_cmd__typeout(name, cmdline)
    else if (name ~   "undef(ine)?")    xeq_cmd__undefine(name, cmdline)
    else if (name ==  "undivert")       xeq_cmd__undivert(name, cmdline)
    else if (name ==  "warn")           xeq_cmd__error(name, cmdline)
    else if (name ==  "wrap")           xeq_cmd__wrap(name, cmdline)
    else
        panic("(execute__command) Unrecognized command '" name "' in '" cmdline "'")

    if (__namespace != old_level)
        panic(sprintf("(execute__command) [@%s] Namespace level mismatch; old_level=%d, __namespace=%d",
                      name, old_level, __namespace))
}


# function assert_cmd_okay_to_define(name, caller)
# {
#     if (caller == EMPTY)
#         panic("(assert_cmd_okay_to_define) Empty caller!")
#     if (!cmd_valid_p(name))
#         error(sprintf("%s: Cmd '%s' not valid",
#                       caller, name))
#
#     # FIXME This is not quite sufficient (I think).  I probably need
#     # to do a full nam__scan() / nam__lookup() because I don't want
#     # to shadow a system symbol.  At least I need to be more careful
#     # than "it's not in the current namespace, looks good!!"
#     if (nam_ll_in(name, __namespace))
#         error("Cmd '" name "' not available:" $0)
# }
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
    print_debugfile("(dump_parse_stack) BEGIN")
    if (stk_depth(__parse_stack) == 0)
        print_debugfile("(dump_parse_stack) Parse stack is empty")
    else
        for (level = stk_depth(__parse_stack); level > 0; level--) {
            block = __parse_stack[level]
            block_type = blk_type(block)
            print_debugfile("(dump_pars_stack) Level " level ", block # " block ", type=" block_type )
            dbg__print_block("xeq", -1, block)
        }
    print_debugfile("(dump_parse_stack) END")
}


function prep_file(filename,
                   file_block, retval)
{
    dbg__print("parse", 7, "(prep_file) START filename='" filename "'")
    # create and return a SRC_FILE set up for the terminal
    file_block = blk_new(SRC_FILE)
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
    dbg__print("parse", 5, "(dofile) START filename='" filename "'")

    # Prepare to read filename; set up a SRC_FILE block to manage input
    # and a BLK_TERMINAL to receive output
    file_block = prep_file(filename)
    dbg__print("parse", 7, sprintf("(dofile) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)
    stk_push(__parse_stack, __terminal)

    dbg__print("parse", 5, "(dofile) CALLING parse__file()")
    retval = parse__file()
    dbg__print("parse", 5, "(dofile) RETURNED FROM parse__file()")

    # Clean up
    # (parse_file() pops the source stack)
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
function parse__file(    filename, file_block1, file_block2, pstat, d)
{
    if (stk_empty_p(__source_stack))
        panic("(parse__file) Source stack empty")
    file_block1 = stk_top(__source_stack)

    filename = blktab[file_block1, 0, "filename"]
    dbg__print("parse", 2, sprintf("(parse__file) filename='%s', dstblk=%d, mode=%s",
                                  filename, curr_dstblk(),
                                  ppf__mode(blktab[file_block1, 0, "atmode"])))
    if (!path_exists_p(filename)) {
        dbg__print("parse", 2, sprintf("(parse__file) END File '%s' does not exist => %s",
                                     filename, ppf__bool(FALSE)))
        stk_pop(__source_stack) # Remove SRC_FILE for non-existent file
        return FALSE
    }
    if (filename in __active_files)
        error("Cannot recursively read '" filename "':" $0)
    __active_files[filename] = TRUE
    sym_ll_incr("__NFILE__", "", GLOBAL_NAMESPACE, 1); __rnf++
    blktab[file_block1, 0, "open"]          = TRUE
    blktab[file_block1, 0, "old.buffer"]    = __buffer
    blktab[file_block1, 0, "old.file"]      = FILE()
    blktab[file_block1, 0, "old.line"]      = LINE()
    blktab[file_block1, 0, "old.file_uuid"] = sym_ll_read("__FILE_UUID__", "", GLOBAL_NAMESPACE)
    dbg__print_block("ship_out", 7, file_block1, "(parse__file) file_block1")

    # # Set up new file context
    __buffer = EMPTY
    sym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, filename)
    sym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, 0)
    sym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, uuid())

    # Read the file and process each line
    dbg__print("parse", 5, "(parse__file) CALLING parse()")
    pstat = parse()
    dbg__print("parse", 5, "(parse__file) RETURNED FROM parse() => " ppf__bool(pstat))

    # Reached end of file
    flush_stdout(SYNC_FILE)

    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != STDIN)
        close(filename)
    blktab[file_block1, 0, "open"] = FALSE
    delete __active_files[filename]

    file_block2 = stk_pop(__source_stack)
    if (file_block1 != file_block2)
        panic("(parse__file) File block mismatch")
    __buffer = blktab[file_block2, 0, "old.buffer"]
    sym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, blktab[file_block2, 0, "old.file"])
    sym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, blktab[file_block2, 0, "old.line"])
    sym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, blktab[file_block2, 0, "old.file_uuid"])

    dbg__print("parse", 2, sprintf("(parse__file) END '%s' => %s",
                                 filename, ppf__bool(pstat)))
    return pstat
}


# PARSE
function parse(    code, terminator, rstat, name, retval, new_block, fc,
                   info, level, parser, parser_type, parser_label, i, scnt, found,
                   new_cmd_name, clevel, call_details, src_block, l2, _)
{
    dbg__print("parse", 3, "(parse) START dstblk=" curr_dstblk() ", mode=" ppf__mode(curr_atmode()))

    # The "parser" is the topmost element of the __parse_stack
    # which we wish to access a few times
    if (stk_empty_p(__parse_stack))
        panic("Parse error, Empty parse stack")
    parser = stk_top(__parse_stack)
    parser_type = blk_type(parser)
    parser_label = ppf__block_type(parser_type)

    if (stk_empty_p(__source_stack))
        panic("Parse error, Empty source stack")
    src_block = stk_top(__source_stack)

    # terminator is a regular expression, and we call
    # match($1, terminator) to see if terminator is seen.
    terminator = blktab[parser, 0, "terminator"]
    retval = FALSE

    while (TRUE) {
        dbg__print("parse", 4, sprintf("(parse) [%s] TOP OF LOOP: ____ %s  LINE %d ________________________________",
                                     parser_label, FILE(), LINE()+1)) # LINE will be +1 after upcoming readline()

        rstat = readline()   # OKAY, EOF, ERROR
        dbg__print("parse", 4, "(parse) [" parser_label "] readline() returned " rstat)
        if (rstat == ERROR) {
            # Whatever just happened, the parse didn't finish properly
            dbg__print("parse", 5, "(parse) [" parser_label "] readline()=>ERROR")
            break          # out of entire parsing loop, to then return
        }
        if (rstat == EOF) {
            # End of file SRC_FILE is fine, just return a TRUE to say so.
            # EOF on any other block type means the parse didn't find
            # a terminator, so return FALSE.
            dbg__print("parse", 5, sprintf("(parse) [%s] readline() detected EOF on '%s'",
                                         parser_label, blktab[src_block, 0, "filename"]))
            if ((src_block, 0, "oob_terminator") in blktab &&
                blktab[src_block, 0, "oob_terminator"] == "EOF")
                retval = TRUE
            break          # out of entire parsing loop, to then return
        }
        dbg__print("parse", 5, "(parse) [" parser_label "] readline() okay; $0='" $0 "'")

        # Maybe short-circuit and ship line out now
        if (curr_atmode() == MODE_AT_LITERAL ||
            index($0, TOK_AT) == NOT_FOUND ||
            first($0) != TOK_AT) {
            dbg__print("parse", 3, sprintf("(parse) [%s, short circuit] CALLING ship_out(OBJ_TEXT, '%s')",
                                         parser_label, $0))
            ship_out(OBJ_TEXT, $0)
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

        # See if it's a command of some kind.  first == @ and last != @
        # catches @foo...@ at BOL not being a command.  Of course we
        # want first($1)==TOK_AT because we expect the at-sign in column
        # one for a command.  Adding AND last($1)!=TOK_AT catches when
        # we're looking at a line like @date@, which is invoking an
        # inline "sym-function" to be resolved by dosubs().  It has a @
        # in column one, but that's just a coincidence.
        # WART:  Loses on  @somecommand A B @symbol@
        if (first($1) == TOK_AT &&
            last($1)  != TOK_AT &&
            match($1, "^@[A-Za-z#_]")) {        # skip "@{"
            # Looks like it might be a command.
            # Winnow out the primary name.  Be sure to handle
            # "@myfn{aaa}{ccc ddd}".  (Naive old code name=$1 resulted
            # in $1 being "@myfn{aaa}{ccc" which wrecks havoc.)
            # However, we need to keep $1 intact in order for upcoming
            # match($1,terminator) checks to work.  This takes advantage
            # of the fact that all commands must have strict names.
            for (i = 2; substr($0, i, 1) ~ /[A-Za-z#_0-9]/; i++)
                ;
            name = substr($0, 2, i-2)
            dbg__print("parse", 7, "(parse) [" parser_label "] name now '" name "'")

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
                            error(sprintf("%s: Parse error, Missing parser; wanted FOR or WHILE but found %s",
                                          "@" name, parser_label))
                        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else if (name == "case") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__case(dstblk=" curr_dstblk() ")"))
                        new_block = parse__case()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__case() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "else") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__else(dstblk=" curr_dstblk() ")"))
                        _ = parse__else()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__else() : dstblk => " curr_dstblk()))

                    } else if (name == "endcase" || name == "esac") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endcase(dstblk=" curr_dstblk() ")"))
                        _ = parse__endcase()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endcase() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endcase matched terminator => TRUE")
                            return TRUE
                        }
                        error(sprintf("%s: Parse error, Missing terminator; wanted '%s' but found '@endcase'",
                                      "@" name, terminator))

                    } else if (name == "endcmd") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endcmd(dstblk=" curr_dstblk() ")"))
                        new_block = parse__endcmd()
                        dbg__print_block("parse", 7, new_block, sprintf("newcmd block returned from parse__endcmd"))
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endcmd() : dstblk => " curr_dstblk()))

                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endcmd matched terminator => TRUE")
                            if (dbg__sys_level_p("parse", 7)) {
                                print_debugfile("(parse) [" parser_label "] new_block=" new_block)
                                ppf__block(new_block)
                            }

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
                            #
                            # XXX There should be a gate here.  It should not
                            # be possible to shadow an existing name, unless
                            # you are re-defining a command.
                            if (! nam_ll_in(name, __namespace)) {
                                new_cmd_name = blktab[new_block, 0, "name"]
                                dbg__print("parse", 3, sprintf("(parse) [" parser_label "] Declaring new user command '%s' at level %d",
                                                               new_cmd_name, __namespace))
                                nam_ll_write(new_cmd_name, __namespace, TYPE_USER)
                            }
                            return TRUE
                        }
                        error(sprintf("%s: Parse error; Missing terminator; wanted '%s' but found '@endcmd'",
                                      "@" name, terminator))

                    } else if (name == "endif" || name == "fi") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endif(dstblk=" curr_dstblk() ")"))
                        _ = parse__endif()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endif() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endif matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endif but expecting '" terminator "'")

                    } else if (name == "endlong" || name == "endlongdef") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endlongdef(dstblk=" curr_dstblk() ")"))
                        _ = parse__endlongdef()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endlongdef() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endlongdef matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endlongdef but expecting '" terminator "'")

                    } else if (name == "endwhile" || name == "wend") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__endwhile(dstblk=" curr_dstblk() ")"))
                        _ = parse__endwhile()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__endwhile() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END; @endwhile matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @endwhile but expecting '" terminator "'")

                    } else if (name == "for" || name == "foreach") {
                        dbg__print("parse", 5, sprintf("(parse) [%s] curr_dstblk()=%d CALLING parse__for()",
                                                     parser_label, curr_dstblk()))
                        new_block = parse__for()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__for() : new_block is " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "if" || name == "unless") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__if(dstblk=" curr_dstblk() ")"))
                        new_block = parse__if()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__if() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "longdef") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__longdef(dstblk=" curr_dstblk() ")"))
                        new_block = parse__longdef()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__longdef() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "newcmd") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__newcmd(dstblk=" curr_dstblk() ")"))
                        new_block = parse__newcmd()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__newcmd() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else if (name == "next") {
                        dbg__print("parse", 5, sprintf("(parse) [%s] dstblk=%d; CALLING parse__next()",
                                                     parser_label, curr_dstblk()))
                        _ = parse__next()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__next() : dstblk => " curr_dstblk()))
                        if (match($1, terminator)) {
                            dbg__print("parse", 5, "(parse) [" parser_label "] END Matched terminator => TRUE")
                            return TRUE
                        }
                        error("(parse) [" parser_label "] Found @next but expecting '" terminator "'")

                    } else if (name == "of") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__of(dstblk=" curr_dstblk() ")"))
                        _ = parse__of()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__of() : dstblk => " curr_dstblk()))

                    } else if (name == "otherwise") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__otherwise(dstblk=" curr_dstblk() ")"))
                        _ = parse__otherwise()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__otherwise() : dstblk => " curr_dstblk()))

                    } else if (name == "return") {
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
                        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_CMD, '%s')", parser_label, $0))
                        ship_out(OBJ_CMD, $0)
                        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")

                    } else if (name == "while" || name == "until") {
                        dbg__print("parse", 5, ("(parse) [" parser_label "] CALLING parse__while(dstblk=" curr_dstblk() ")"))
                        new_block = parse__while()
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM parse__while() : new_block => " new_block))
                        dbg__print("parse", 5, sprintf("(parse) [" parser_label "] CALLING ship_out(OBJ_BLKNUM, %d)", new_block))
                        ship_out(OBJ_BLKNUM, new_block)
                        dbg__print("parse", 5, ("(parse) [" parser_label "] RETURNED FROM ship_out()"))

                    } else
                        panic("(parse) [" parser_label "] Found immediate command " name " but no handler")

                } else {
                    # It's a non-immediate built-in command -- ship it
                    # out as a command to be executed later.
                    dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_CMD, '%s')", parser_label, $0))
                    ship_out(OBJ_CMD, $0)
                    dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
                }
                continue
            } else {
                # Look up user command
                if (nam__scan(name, info) == ERROR)
                    error("Scan error; " __m2_msg)
                if ((level = nam__lookup(info)) != NAME_NOT_FOUND) {
                    # A value of NAME_NOT_FOUND would mean a valid name wasn't
                    # found, in which case name is definitely not a user
                    # command, so we do nothing for the moment in that
                    # case and let normal text ship out.  But since it's
                    # *not* NAME_NOT_FOUND, something *was* found at "level".  See
                    # if it's a user command and ship it out if so.
                    if (flag_1true_p((code = nam_ll_read(name, level)), TYPE_USER)) {
                        call_details = scan__usercmd_call()
                        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_USER, '%s')", parser_label, call_details))
                        ship_out(OBJ_USER, call_details)
                        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
                        continue
                    }
                }
            }
            # It's okay to reach here with no actions taken.  In this
            # case, just process the line as normal text.
        }
        # doesn't look like a command - ship it out as text
        dbg__print("parse", 3, sprintf("(parse) [%s] CALLING ship_out(OBJ_TEXT, '%s')", parser_label, $0))
        ship_out(OBJ_TEXT, $0)
        dbg__print("parse", 3, "(parse) [" parser_label "] RETURNED FROM ship_out()")
    } # continue loop again, reading next line
    dbg__print("parse", 5, "(parse) END => " ppf__bool(retval))
    return retval
}


# Unlike built-in commands, which must be complete on a single line, USER
# commands might span multiple physical lines.  This is because (unlike
# built-in commands), parameters are enclosed with braces, so one may write:
#       @mycmd{Title}{A very very very
#       very long title}
# Call readline() repeatedly until braces are closed properly.
#
# More details on why it is possible to call readline() and and not call
# it from dosubs().  This is because the only caller of
# scan__usercmd_call is parse() -- specifically, in parse's main loop
# where it is also executing readline().  An extra readline here in an
# auxiliary function to help finish a command doesn't hurt things.
#
# dosubs() *cannot* call readline() [to assist in scanning multi-line
# @ifelse@, perhaps] because readline's may be long over.  dosubs() is
# often called on a static string, for example.
#
# This function returns an encoded version of the user command call.
#     <name> SUBSEP <narg> [ SUBSEP <argN> ... ]
# When the call details are eventually decoded in execute__user(), the
# OBJ_USER value is passed to split_subsep() to access individual items.
function scan__usercmd_call(    s, name, obj, i, oldi, c, nc, narg, nlbr,
                                readstat, arg, inarg, thisi, retval, j,
                                brpos, cb)
{
    s = $0
    narg = 0
    dbg__print("parse", 5, "(scan__usercmd_call) s='" s "'")
    if (emptyp(s))
        panic("(scan__usercmd_call) s cannot be empty!")
    if (first(s) != TOK_AT)
        error(sprintf("(scan__usercmd_call) Doesn't start with @: s='%s'", s))
    if ((brpos = index(s, TOK_LBRACE)) == NOT_FOUND) {
        name = substr(s, 2)
        dbg__print("parse", 3, sprintf("(scan__usercmd_call) OUT: name='%s'", name))
        return name SUBSEP narg
    }

    # Read cmd name between @ and {
    name = substr(s, 2, brpos - 2)
    dbg__print("parse", 3, sprintf("(scan__usercmd_call) name='%s'", name))

    # Remove everything that came before.  We are now left with (hopefully)
    # a series of brace-enclosed arguments.
    s = substr(s, brpos)        # s == "{..."
    while (substr(s, 1, 1) == TOK_LBRACE) {
        cb = find_closing_brace(s, 1, TOK_LBRACE)
        if (cb == ERROR)
            error("(scan__usercmd_call) Could not find closing brace: " s)
        else if (cb == EOF) {
            # We ran out of characters looking for a "}".
            # Try reading some more lines to fill our need.
            readstat = readline()
            if (readstat <= 0)
                error(sprintf("(scan__usercmd_call) ERROR, missing '}'"))
            dbg__print("parse", 9, "just read = >" $0 "<")
            s = s TOK_NEWLINE $0
            dbg__print("parse", 7, sprintf("(scan__usercmd_call) After readline, s='%s'", s))
            continue
        } else {
            # Found a }
            dbg__print("parse", 5, ("   (scan__usercmd_call) in loop, cb=" cb))
            inarg = substr(s, 2, cb - 2)
            gsub(/\\}/, "}", inarg) # Fix quoted brace
            arg[++narg] = inarg
            s = substr(s, cb + 1)
        }
    }

    dbg__print("parse", 2, sprintf("(scan__usercmd_call) END 3: narg=%d, s='%s'", narg, s))
    retval = name SUBSEP narg SUBSEP
    for (j = 1; j <= narg; j++)
        retval = retval arg[j] SUBSEP
    return chop(retval)
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
#           TYPE_ARRAY          A : Array refs must use subscripts
#           TYPE_COMMAND        C : Built-in "@" command; Global namespace
#           TYPE_FUNCTION       F : Global namespace
#           TYPE_INTERNAL       _ : Awk function tracing, not reachable by user
#           TYPE_SEQUENCE       Q : Global namespace
#           TYPE_SYMBOL         S
#           TYPE_USER           U : User-defined command; dynamic namespace
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
    return index(char, VALID_TYPES) > 0
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
        flag = substr(clear_fs, x, 1)
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


function ppf__flag_type(code,
                        type)
{
    if (code == EMPTY)
        panic("(ppf__flag_type) code is empty")
    code = first(code)
    dbg__print("xeq", 7, "(ppf__flag_type) code = " code)
    if (! (code in __flag_label)) {
        panic("(ppf__flag_type) Invalid type '" code "'")
    }
    return __flag_label[code]
}


function ppf__flags(code,
                    l, s, desc, x)
{
    if ((l = length(code)) == 0)
        error("(ppf__flags) Did not specify code")
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
#       Info[] is an array with following entries created in nam__scan():
#             error       : TRUE if an error condition was encountered
#             errtext     : Text relating to any error condition.
#                           Errtext NEVER includes ``caller'' information:
#                           that bit is added on when m2 errors & exits.
#             has_bracket : TRUE if text matches CHARS[CHARS..]
#                           It is normal for plain "NAME" to be FALSE here.
#             key         : Key, part[2] of NAME[KEY]; may be empty.
#             key_valid   : TRUE if KEY is valid according to non-strict.
#                           This restricts it to most printable characters.
#             name        : Name, part[1] of NAME[KEY].
#             name_valid  : TRUE if NAME is valid according to current __STRICT__[name]
#             nparts      : 1 or 2 depending if text is NAME or NAME[KEY]
#             urtext      : original text string
#             valid       : TRUE if both name_valid && key_valid are TRUE
#
#       After a successful nam__lookup(), the following entries are added:
#             code        : String holding the type and any flags (from namtab)
#             idxable     : TRUE if type == TYPE_ARRAY or TYPE_LIST.
#                           Means this incantation can support NAME[KEY].
#                           Useful for PTYPE_IDXABLE and FLAG_KEY_YES.
#             level       : Namespace level number where this object was found.
#                           0 => GLOBAL_NAMESPACE; NAME_NOT_FOUND => symbol not found
#             tracing     : TRUE if this object/symbol is being traced
#             type        : Char encoding obj type, also in code; one of TYPE_*
#*****************************************************************************

#*****************************************************************************
#
# This code scans random string "text" into either NAME or NAME[KEY].
# Rudimentary error checking is done.
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
                   name, key, nparts, part, count, i)
{
    # dbg__print("nam", 5, sprintf("(nam__scan) START text='%s'", text))
    name = key = info["name"] = info["key"] = info["errtext"] = EMPTY
    info["urtext"] = text
    info["error"] = FALSE
    info["_protected"] = VOID

    # Simple test for CHARS or CHARS[CHARS]
    #   CHARS ::= [-"-Z^-z~]+
    # CHARS regexp excludes     ! [ \ ] { | }
    # Anchored at front and back, match CHARS,
    # optionally followed by bracket CHARS bracket
    #   /^ CHARS ( \[ CHARS \] )? $/
    if (text !~ /^["-Z^-z~]+(\[["-Z^-z~]+\])?$/) {
        #warn("(nam__scan) Name '" text "' not valid")
        dbg__print("nam", 2, sprintf("(nam__scan) '%s' => %d", text, ERROR))
        #__m2_msg = "Invalid name: '" text "'"
        info["error"] = TRUE
        info["errtext"] = "Error scanning '" text "'"
        return ERROR            # interpret as ERR_SCAN_INVALID_NAME
    }

    count = split(text, part, "(\\[|\\])")
    if (dbg__sys_level_p("nam", 7)) {
        print_debugfile("'split(" text ")' ==> " count " fields:")
        for (i = 1; i <= count; i++)
            print_debugfile(i " = '" part[i] "'")
    }
    if (count < 1 || count > 3) # assert count in [1,2,3]
        panic("(nam__scan) split() returned strange value: " count)
    if (count == 3 && !emptyp(part[3]))
        panic("(nam__scan) split() part[3] should be empty")
    if (count >= 2) {
        info["has_bracket"] = TRUE
        info["key"] = key   = part[2]
        if (key == EMPTY)
            panic("(nam__scan) key cannot be empty!")
        info["key_valid"] = nam_valid_with_strict_as(key, FALSE)
            # info["errtext"] = "Key '" key "' is not valid"
    }
    if (count >= 1) {
        info["name"] = name = part[1]
        if (name == EMPTY)
            panic("(nam__scan) name cannot be empty!")
        info["name_valid"] = nam_valid_with_strict_as(name, strictp("name"))
    }
    if (count == 1)
        info["has_bracket"] = FALSE


    # Since we passed the regexp in first if() statement, we can be
    # assured that text is either ^CHARS$ or ^CHARS\[CHARS\]$.
    info["nparts"] = nparts = (count == 1) ? 1 : 2
    if (nparts == 1) {
        if ((info["valid"] = info["name_valid"]) == FALSE)
            info["errtext"] = "Name '" name "' is not valid"
    } else {
        # nparts == 2
        if ((info["valid"] = (info["name_valid"] && info["key_valid"])) == FALSE)
            info["errtext"] = sprintf("%s%s%s",
                                      info["name_valid"] ? "" : "Name '" name "' is not valid",
                                      info["name_valid"] == FALSE && info["key_valid"] == FALSE ? "; " : "",
                                      info["key_valid"] ? "" : "Key '" key "' is not valid")
    }

    dbg__print("nam", 4, sprintf("(nam__scan) '%s' => %d", text, nparts))
    return nparts
}


#*****************************************************************************
# This will examine namtab from __namespace downto 0, seeing if name
# exists at that level.  If so, it populates info[] with the code string
# for the item from namtab, and also sets other values.  The return
# value is the namespace level number (0..N).
#
# If no matching name is found, return NAME_NOT_FOUND (-1).  It also sets
# info["error"] to True and reports that the name was not found.
# The caller may or may not consider this a real error, depending on
# whether he expected the name to be found or not.
# *****************************************************************************
function nam__lookup(info,
                     name, level, code, type)
{
    info["code"] = PTYPE_UNDEF
    info["level"] = NAME_NOT_FOUND

    if (info__get(info, "error") || info__get(info, "valid") == FALSE) {
        dbg__print("nam", 2, "(nam__lookup) END Invalid info => NAME_NOT_FOUND")
        info["error"] = TRUE
        #info["errtext"] = "Invalid info"
        return ERR_SCAN_INVALID_NAME
    }
    dbg__print("sym", 5, sprintf("(nam__lookup) name='%s' START", \
    (name = info["name"])))

    for (level = __namespace; level >= GLOBAL_NAMESPACE; level--)
        if (nam_ll_in(name, level)) {
            info["code"] = code = nam_ll_read(name, level)
            type = first(code)
            info["idxable"] = (type == TYPE_ARRAY || type == TYPE_LIST)
            info["tracing"] = flag_1true_p(code, FLAG_TRACING)
            info["level"] = level
            dbg__print("nam", 2, sprintf("(nam__lookup) END name '%s', level=%d, code=%s=%s Found in namtab => %s",
                                         name, level, code,
                                         nam_ppf_name_level(name, level),
                                         (level == 0 ? "GLOBAL_NAMESPACE" \
                                             : sprintf("Level %d", level))))
            if (info["has_bracket"] && !info["idxable"]) {
                info["error"] = TRUE
                info["errtext"] = sprintf("Cannot use brackets with %s '%s'", ppf__flag_type(type), name)
                return ERR_SCAN_INVALID_NAME
            }
            return level
        }
    dbg__print("nam", 2, sprintf("(nam__lookup) END Could not find name '%s' on any level in namtab => NAME_NOT_FOUND", name))
    # Set the text when the name isn't found, but not the error flag itself.
    info["errtext"] = "Name not found: '" name "'"
    return NAME_NOT_FOUND
}


function info__create_from_text(text, info,
                      nparts)
{
    nparts = nam__scan(text, info)
    if (nparts == ERROR)
        return ERR_SCAN_INVALID_NAME
    return nam__lookup(info)    # level (>= 0) or NAME_NOT_FOUND
}


# Remove any name at level "level" or greater
function nam_purge(level,
                    x, k, del_list)
{
    dbg__print("nam", 7, "(nam_purge) BEGIN")

    for (k in namtab) {
        split(k, x, SUBSEP)
        if (x[2]+0 >= level)
            del_list[x[1], x[2]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        dbg__print("nam", 3, sprintf("(nam_purge) Delete namtab['%s', %d]",
                                     x[1], x[2]))
        trace(TRACE_SYMBOL_READ_WRITE, x[1],
              sprintf("[Name Delete] \"%s\" (lev:%d)", x[1], x[2]))
        delete namtab[x[1], x[2]]
    }
    dbg__print("nam", 7, "(nam_purge) END")
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
            #print_debugfile(sprintf("code=%s, filter=%s, flag filter failed", code, filter_fs))
            continue
        }
        if (flag_1true_p(code, FLAG_SYSTEM) && !include_system) {
            #print_debugfile("system filter failed")
            continue
        }
        print_debugfile("(nam_dump_namtab) " nam_ppf_name_level(name, level))
    }
    print_debugfile("(nam_dump_namtab) End namtab")
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
    if (level == EMPTY)
        panic("(nam_ll_in) LEVEL missing")
    if (name != "__LINE__" && name != "__NLINE__" && name != "__DBG__")
        dbg__print("sym", 5, sprintf("(nam_ll_in) Looking for '%s' at level %d", name, level))
    return (name, level) in namtab
}


function nam_ll_write(name, level, code,
                       retval)
{
    if (level == EMPTY)
        panic("(nam_ll_write) LEVEL missing")
    # It's important to use low-level functions here, and not invoke
    # dbg__* functions in this procedure, otherwise nasty loops ensue.
    if (sym_ll_in("__DBG__", "nam", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "nam", GLOBAL_NAMESPACE) >= 5)
        print_debugfile(sprintf("(nam_ll_write) namtab[\"%s\", %d] = %s", name, level, code))

    trace(TRACE_SYMBOL_READ_WRITE, name,
          sprintf("[Name Write] \"%s\" (lev:%d) := Code '%s'",
                  name, level, code))
    return namtab[name, level] = code
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
    if (elem == "protected") {
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
function seqinfo_valid_p(seqinfo,
                         name)
{
    name = info__get(seqinfo, "name")
    return nam_valid_strict_regexp_p(name) &&
           !double_underscores_p(name)
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
function seqinfo_defined_p(seqinfo,
                           name, code)
{
    if (!seqinfo_valid_p(seqinfo))
        return FALSE
    name = info__get(seqinfo, "name")
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
# function seqinfo_ll_incr(seqinfo, incr,
#                          name)
# {
#     name = info__get(seqinfo, "name")
#     if (incr == EMPTY)
#         incr = seqtab[name, "incr"]
#     seqtab[name, "seqval"] += incr
# }


# function assert_seq_valid_name(name, caller)
# {
#     if (caller == EMPTY)
#         panic("(assert_seq_valid_name) Empty caller!")
#     if (! seq_valid_p(name))
#         error(sprintf("%s: Sequence name '%s' not valid",
#                       caller, name))
# }
# function assert_seqinfo_valid_name(info, caller,
#                                    name)
# {
#     if (caller == EMPTY)
#         panic("(assert_seqinfo_valid_name) Empty caller!")
#     name = info__get(info, "name")
#     if (! seq_valid_p(name))
#         error(sprintf("%s: Sequence name '%s' not valid",
#                       caller, name))
# }


# function assert_seq_okay_to_define(name, caller)
# {
#     if (caller == EMPTY)
#         panic("(assert_seq_okay_to_define) Empty caller!")
#     assert_seq_valid_name(name, caller)
#     if (nam_ll_in(name, GLOBAL_NAMESPACE))
#         error(sprintf("%s: Name '%s' not available", caller, name))
# }
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
              sprintf("[File] Input file now '%s'", blktab[new_elem, 0, "filename"]))
    if (dbg__sys_level_p("stk", 5)) {
        siz = stack[0]
        print_debugfile(sprintf("(stk_push) %s[%d] := %s",
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
        panic("(stk_top) Empty stack")
    return stack[stack[0]]
}


function stk_pop(stack,
                 old_top, new_top, siz)
{
    if (stk_empty_p(stack))
        panic("(stk_pop) Empty stack")
    siz = stack[0]
    old_top = stack[stack[0]--]
    if (!stk_empty_p(stack) && stack["name"] == "source_stack") {
        new_top = stack[stack[0]]
        trace(TRACE_INPUT_FILE_CHG, EMPTY,
              sprintf("[File] Input file now '%s'", blktab[new_top, 0, "filename"]))
    }
    if (dbg__sys_level_p("stk", 5)) {
        print_debugfile(sprintf("(stk_pop) %s[%d] -> %s",
                                stack["name"], siz, old_top))
    }
    return old_top
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
    dbg__print("divert", 2, sprintf("(undivert) START dstblk=%d, stream=%d",
                                   curr_dstblk(), stream))
    if (dstblk < 0) {
        dbg__print("divert", 3, "(undivert) END because dstblk <0")
        return
    }
    if (stream <= 0 || stream == DIVNUM()) {
        dbg__print("divert", 3, "(undivert) END because stream <= 0 or == DIVNUM")
        return
    }
    if (blk_type(stream) != BLK_AGG)
        panic(sprintf("(undivert) Block %d has type %s, not AGG",
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


# Print stream to a file
# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-scanned for macros, and buffer is cleared after
# injection into target stream.
function undivert_to_file(stream, file,
                          count, i)
{
    dbg__print("divert", 2, sprintf("(undivert_to_file) START; stream=%d, file='%s'", stream, file))
    if (blk_type(stream) != BLK_AGG)
        panic(sprintf("(undivert_to_file) Block %d has type %s, not AGG",
                      stream, ppf__block_type(blk_type(stream))))
    if ((count = blktab[stream, 0, "count"]) > 0) {
        ship_out_to_file(stream, file)
        cleardivert(stream)
    }
}


# Remove all slots from an AGG block and return its count to zero.
function cleardivert(stream,
                     count, i)
{
    dbg__print("divert", 2, sprintf("(cleardivert) START dstblk=%d, stream=%d",
                                   curr_dstblk(), stream))
    if (stream < 0) {
        dbg__print("divert", 3, "(cleardivert) END because stream <0")
        return
    }
    if (blk_type(stream) != BLK_AGG)
        panic(sprintf("(cleardivert) Block %d has type %s, not AGG",
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

# In strict [name] mode, a symbol must match the following regexp:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
# see function nam_valid_strict_regexp_p()
# In non-strict mode, any non-empty string is valid.  NOT TRUE
function sym_valid_p(sym,
                      nparts, info, retval)
{
    dbg__print("sym", 5, sprintf("(sym_valid_p) sym='%s' START", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR) {
        __msg_m2 = "Invalid name: '" sym "'"
        #error("(sym_valid_p) ERROR nam__scan('" sym "') failed")
        return FALSE
    }
    # nparts must be either 1 or 2
    retval = (nparts == 1) ?  info["name_valid"] \
                           : (info["name_valid"] && info["key_valid"])
    dbg__print("sym", 4, sprintf("(sym_valid_p) END sym='%s' => %s",
                                 sym, ppf__bool(retval)))
    return retval
}
function syminfo_valid_p(syminfo,
                         name, retval)
{
    name = info__get(syminfo, "name")
    dbg__print("sym", 5, sprintf("(syminfo_valid_p) sym='%s' START", name))

    retval = info__get(syminfo, "error") == FALSE &&
             info__get(syminfo, "valid") == TRUE

    # # If a key is given, it must also be valid
    # if (retval && info__get(syminfo, "nparts") == 2)
    #     retval = info__get(syminfo, "key_valid")

    # retval = (nparts == 1) ?  info["name_valid"] \
    #                        : (info["name_valid"] && info["key_valid"])
    dbg__print("sym", 4, sprintf("(syminfo_valid_p) END sym='%s' => %s",
                                 name, ppf__bool(retval)))
    return retval

}


# function sym_create(sym, code,
#                      nparts, name, key, info, level)
# {
#     dbg__print("sym", 4, sprintf("sym_create: START (sym=%s, code=%s)", sym, code))
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
#     #dbg__print("sym", 2, sprintf("...
#     # print_debugfile(sprintf("sym_create: namtab += [\"%s\",%d]=%s", name, level, code))
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
        panic("Cannot create deferred symbol when it already exists")

    nam_ll_write(name, level, code FLAG_DEFERRED)
    # It has no symbol value (yet), but we do store the two args in the
    # symbol table
    symtab[name, "", level, "deferred_prog"] = deferred_prog
    symtab[name, "", level, "deferred_arg"]  = deferred_arg
}


function sym_destroy(name, key, level)
{
    dbg__print("sym", 5, sprintf("(sym_destroy) START; name='%s', key='%s', level=%d",
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
    delete namtab[name, level]
    trace(TRACE_SYMBOL_READ_WRITE, name,
          sprintf("[Name Delete] \"%s\" (lev:%d)", name, level))
    delete symtab[name, key, level, "agg_block"]
    delete symtab[name, key, level, "deferred_arg"]
    delete symtab[name, key, level, "deferred_prog"]
    delete symtab[name, key, level, "symval"]
}


# DO NOT require CODE parameter.  Instead, look up NAME and
# find its code as normal.  NAME might not even be defined!
function nam_system_p(name)
{
    if (name == EMPTY)
        panic("nam_system_p: NAME missing")
    return nam_ll_in(name, GLOBAL_NAMESPACE) &&
           flag_1true_p(nam_ll_read(name, GLOBAL_NAMESPACE), FLAG_SYSTEM)
}


# Remove any symbol at level "level" or greater
function sym_purge(level,
                    x, k, del_list)
{
    dbg__print("sym", 7, "(sym_purge) BEGIN")
    for (k in symtab) {
        split(k, x, SUBSEP)
        if (x[3]+0 >= level)
            del_list[x[1], x[2], x[3], x[4]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        dbg__print("sym", 3, sprintf("(sym_purge) Delete symtab['%s', '%s', %d, %s]",
                                     x[1], x[2], x[3], x[4]))
        delete symtab[x[1], x[2], x[3], x[4]]
    }
    dbg__print("sym", 7, "(sym_purge) END")
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
    dbg__print("nam", 5, "(sym_define_all_deferred) BEGIN")
    if (secure_level() >= SEC_PARANOID)
        return

    for (k in namtab) {
        split(k, x, SUBSEP)
        sym = x[1]
        code = nam_ll_read(sym, GLOBAL_NAMESPACE)
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


function sym_destroy_all_deferred(    x, k, def_list, sym, code)
{
    dbg__print("nam", 5, "(sym_destroy_all_deferred) BEGIN")

    for (k in namtab) {
        split(k, x, SUBSEP)
        sym = x[1]
        code = nam_ll_read(sym, GLOBAL_NAMESPACE)
        if (flag_1true_p(code, FLAG_DEFERRED)) {
            dbg__print("nam", 7, "(sym_destroy_all_deferred) Want to destroy deferred " sym)
            def_list[sym] = TRUE
        }
    }

    for (sym in def_list) {
        dbg__print("nam", 5, "(sym_destroy_all_deferred) Destroying deferred " sym)
        sym_destroy(sym, "", GLOBAL_NAMESPACE)
    }
    dbg__print("nam", 5, "(sym_destroy_all_deferred) END")
}


function sym_defined_p(sym,
                       nparts, info, name, key, code, level, i,
                       agg_block, count)
{
    dbg__print("sym", 5, sprintf("(sym_defined_p) sym='%s' START", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR) {
        dbg__print("sym", 2, sprintf("(sym_defined_p) END nam__scan('%s') failed => %s", sym, ppf__bool(FALSE)))
        __m2_msg = "Scan error, " __m2_msg
        return FALSE
    }
    name = info["name"]
    key  = info["key"]

    # Now call nam__lookup(info)
    level = nam__lookup(info)
    if (level == NAME_NOT_FOUND) {
        dbg__print("sym", 2, sprintf("(sym_defined_p) END nam__lookup('%s') failed, maybe ok? => %s", sym, ppf__bool(FALSE)))
        return FALSE
    }

    # We've found some matching name on some level, but not sure if it's a Symbol or not.
    # This step is necessary to make sure it's actually a Symbol.
    for (i = nam_system_p(name) ? GLOBAL_NAMESPACE : __namespace; i >= GLOBAL_NAMESPACE; i--) {
        if (sym_info_defined_lev_p(info, i)) {
            dbg__print("sym", 2, sprintf("(sym_defined_p) END sym='%s', level=%d => %s", sym, i, ppf__bool(TRUE)))
            return TRUE
        }
    }

    # If it's not a normal symbol table entry, maybe a block-array
    if (flag_1true_p(info["code"], TYPE_LIST)) {
        if (emptyp(key)) {
            dbg__print("sym", 2, sprintf("(sym_defined_p) Block array bare name returns count"))
            return TRUE
        }

        if (!integerp(key)) {
            dbg__print("sym", 2, sprintf("(sym_defined_p) Block array indices must be integers"))
            return FALSE
        }
        if (! ((name, "", level, "agg_block") in symtab))
            panic(sprintf("(sym_defined_p) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                          name, "", level))

        agg_block = symtab[name, "", level, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, key) != OBJ_TEXT)
                panic(sprintf("(sym_defined_p) Block # %d slot %d is not OBJ_TEXT", agg_block, key))
            dbg__print("sym", 2, sprintf("(sym_defined_p) END sym='%s', level=%d => %s", sym, level, ppf__bool(TRUE)))
            return TRUE
        }
    }

    dbg__print("sym", 2, sprintf("(sym_defined_p) END No symbol named '%s' on any level => %s", sym, ppf__bool(FALSE)))
    return FALSE
}

function syminfo_defined_p(info,
                           itype, ilevel)
{
    if (! info__get(info, "name_valid"))
        return FALSE
    if ((ilevel = info__get(info, "level")) == NAME_NOT_FOUND)
        return FALSE
    itype = info__get(info, "type")
    if (itype == TYPE_SYMBOL)
        return sym_info_defined_lev_p(info, ilevel)
    else if (itype == TYPE_ARRAY || itype == TYPE_LIST)
        return idx__key_exists_p(info, info__get(info, "key"))
    else if (itype == TYPE_SEQUENCE)
        return seq_defined_p(info__get(info, "name"))
    else
        panic(sprintf("(syminfo_defined_p) Cannot handle '%s' type %s",
                      info__get(info, "name"), ppf__flag_type(itype)))
}


# Caller MUST have previously called nam__scan().
# It's the only way to get the `info' parameter value.
#
# The caller is responsible for inquiring about nam_system_p(name),
# and overriding level to zero if appropriate.  This code does
# not make any assumptions about name/levels.
function sym_info_defined_lev_p(info, level,
                                name, key)
{
    name = info["name"]
    key  = info["key"]
    dbg__print("sym", 5, sprintf("(sym_info_defined_lev_p) sym='%s' START", name))

    if ((name, key, 0+level, "symval") in symtab) {
        dbg__print("sym", 5, sprintf("(sym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Found in symtab => TRUE", name, key, level))
        return TRUE
    } else {
        dbg__print("sym", 5, sprintf("(sym_info_defined_lev_p) END [\"%s\",\"%s\",%d,\"symval\"] Not found => FALSE", name, key, level))
        return FALSE
    }
}


function sym_store(sym, new_val,
                    nparts, info, name, key, level, code, good, dbg5)
{
    # Fetch debug level first before it might possibly change
    dbg5 = dbg__sys_level_p("sym", 5)
    if (dbg5)
        print_debugfile(sprintf("(sym_store) START sym='%s'", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR)
        error("(sym_store) Scan error: " __m2_msg)
    name = info["name"]
    key  = info["key"]

    # Compute level
    # Now call nam__lookup(info)
    level = nam__lookup(info)
    # It's okay if nam__lookup returns NAME_NOT_FOUND because we might be
    # attempting to store a new, non-existing symbol.

    # At this point:
    #   level == NAME_NOT_FOUND             -> no matching name of any kind
    #   level == GLOBAL_NAMESPACE -> found in global
    #   0 < level < ns-1          -> find in other non-global frame
    #   level == __namespace      -> found in current namespace
    # Just because we found a namtab entry doesn't
    # mean it's okay to just muck about with symtab.

    good = FALSE
    do {
        if (level == NAME_NOT_FOUND) {   # name not found in nam
            # No namtab entry, no code : This means a normal
            # @define in the global namespace
            if (info["has_bracket"])
                error(sprintf("(sym_store) '%s' is not an Array; cannot use brackets here", name))
            # Do scalar store
            level = info["level"] = GLOBAL_NAMESPACE
            code  = info["code"]  = TYPE_SYMBOL
            nam_ll_write(name, level, code)
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        # At this point we know nam__lookup() found *something* because
        # level != NAME_NOT_FOUND
        code = info["code"]

        # Error if we found an array without key,
        # or a plain symbol with a subscript.
        if (flag_1true_p(code, TYPE_ARRAY) && !info["has_bracket"])
            error(sprintf("(sym_store) '%s' is an Array, so brackets are required", name))
        if (flag_1false_p(code, TYPE_ARRAY) && info["has_bracket"])
            error(sprintf("(sym_store) '%s' is not an Array; cannot use brackets here", name))

        if (flag_1true_p(code, TYPE_SYMBOL) &&
            !sym_ll_protected(name, code) &&
            !info["has_bracket"] &&
            flag_1false_p(code, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (flag_1true_p(code, TYPE_ARRAY) &&
            !sym_ll_protected(name, code) &&
            info["has_bracket"] &&
            flag_1false_p(code, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (dbg5) {
            print_debugfile(sprintf("(sym_store) LOOP BOTTOM: name='%s', key='%s', level=%d, code='%s', good=%s",
                                 name, key, level, code, ppf__bool(good)))
            nam_dump_namtab(TYPE_SYMBOL, FALSE)
            print_debugfile(dump__symtab(TYPE_SYMBOL, FALSE)) # print_debugfile() adds newline.  FALSE means omit system symbols
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
        dbg__print("sym", 2, sprintf("(sym_store) [\"%s\",\"%s\",%d,\"symval\"]=%s",
                                     name, key, level, new_val))
        sym_ll_write(name, key, level, new_val)
    } else {
        warn(sprintf("(sym_store) !good sym='%s'", sym))
    }
    if (dbg5)
        print_debugfile(sprintf("(sym_store) END;"))
}
function syminfo_store(info, new_val,
                       iname, ikey, ilevel, good, ihasbracket, itype, icode, dbg5,
                       idxable)
{
    dbg5 = dbg__sys_level_p("sym", 5)
    if (dbg5)
        print_debugfile(sprintf("(syminfo_store) START sym='%s'", iname))

    # This needs to be much more robust, like sym_store() above
    iname = info__get(info, "name")
    ikey  = info__get(info, "key")
    ilevel = info__get(info, "level")
    ihasbracket = info__get(info, "has_bracket")
    itype = info__get(info, "type")

    good = FALSE
    do {
        if (ilevel == NAME_NOT_FOUND) {   # name not found in nam
            # No namtab entry, no code : This means a normal
            # @define in the global namespace
            if (ihasbracket)
                error(sprintf("(syminfo_store) '%s' is not an array; cannot use brackets here", iname))
            # Do scalar store
            ilevel = info["level"] = GLOBAL_NAMESPACE
            itype = icode  = info["code"]  = TYPE_SYMBOL
            nam_ll_write(iname, ilevel, icode)
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        # At this point we know nam__lookup() found *something* because
        # ilevel != NAME_NOT_FOUND
        icode = info__get(info, "code")
        idxable = info__satisfies_type(info, PTYPE_IDXABLE)

        # Error if we found an array without key,
        # or a plain symbol with a subscript.
        if (idxable && !ihasbracket)
            error(sprintf("(syminfo_store) '%s' is an array, so brackets are required", iname))
        if (!idxable && ihasbracket)
            error(sprintf("(syminfo_store) '%s' is not an array; cannot use brackets here", iname))

        if (itype == TYPE_SYMBOL &&      #flag_1true_p(icode, TYPE_SYMBOL) &&
            !sym_ll_protected(iname, icode) &&
            ! ihasbracket &&
            flag_1false_p(icode, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (idxable && # itype == TYPE_ARRAY &&       # flag_1true_p(icode, TYPE_ARRAY) &&
            !sym_ll_protected(iname, icode) &&
            ihasbracket &&
            flag_1false_p(icode, FLAG_READONLY)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        if (dbg5) {
            print_debugfile(sprintf("(syminfo_store) LOOP BOTTOM: name='%s', key='%s', level=%d, code='%s', good=%s",
                                 iname, ikey, ilevel, icode, ppf__bool(good)))
            nam_dump_namtab(TYPE_SYMBOL, FALSE)
            print_debugfile(dump__symtab(TYPE_SYMBOL, FALSE)) # print_debugfile() adds newline.  FALSE means omit system symbols
        }
    } while (FALSE)

    # if nam_system_p(iname)          ilevel = 0
    # Error if name does not exist at that level
    # Error if symbol is an array but sym doesn't have array[key] syntax
    # Error if symbol is not an array but sym has array[key] syntax
    # Error if you don't have permission to write to the symbol
    #   == Error ("read-only") if (flag_true(FLAG_READONLY))
    # Error if new_val is not consistent with symbol type (haha)
    #   or else coerce it to something acceptable (boolean)
    # Special processing (CONVFMT, __DEBUG__)

    # Add entry:        symtab[iname, ikey, ilevel, "symval"] = new_val
    if (good) {
        dbg__print("sym", 2, sprintf("(syminfo_store) code=%s [\"%s\",\"%s\",%d,\"symval\"]=%s",
                                     ppf__flags(itype), iname, ikey, ilevel, new_val))
        if (! ((itype == TYPE_SYMBOL && ikey == EMPTY) ||
               ((itype == TYPE_ARRAY || itype == TYPE_LIST) && ikey != EMPTY))) {
            info__dump(info)
            panic("(syminfo_store) bad type/key combo")
        }

        if (itype == TYPE_LIST)
            lis__assign(iname, ikey, ilevel, new_val)
        else
            sym_ll_write(iname, ikey, ilevel, new_val) # store into symtab[]
    } else {
        warn(sprintf("(syminfo_store) !good sym='%s'", iname))
    }
    if (dbg5)
        print_debugfile(sprintf("(syminfo_store) END;"))
}


function sym_ll_read(name, key, level,
                     retval)
{
    if (level == EMPTY) level = GLOBAL_NAMESPACE
    # if key == EMPTY that's probaby just fine.
    # if name == EMPTY that's probably NOT fine.
    if (name == EMPTY)
        panic("(sym_ll_read) Name cannot be empty!")
    if (double_underscores_p(name))
        return symtab[name, key, level, "symval"]

    if (! sym_ll_in(name, key, level))
        panic(sprintf("(sym_ll_read) symtab['%s','%s',%d,'symval'] does not exist",
                      name, key, level))
    retval = symtab[name, key, level, "symval"]

    #print_stderr("ll_read: name='" name "'")
    if (! double_underscores_p(name))
        trace(TRACE_SYMBOL_READ_WRITE, name,
              sprintf("[Symbol Read] %s (lev:%d) == '%s'",
                      sprintf("\"%s%s\"", name, (key ? "[" key "]" : "")),
                      level, retval))
    return retval
}


function sym_ll_in(name, key, level)
{
    if (level == EMPTY)
        panic("sym_ll_in: LEVEL missing")
    return (name, key, level, "symval") in symtab
}


function sym_ll_write(name, key, level, val)
{
    if (level == EMPTY)
        panic("sym_ll_write: LEVEL missing")
    # Can't call normal dbg__*() functions here, mutually recursive
    if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 5 &&
        !nam_system_p(name))
        print_debugfile(sprintf("(sym_ll_write) symtab[\"%s\", \"%s\", %d, \"symval\"] = %s", name, key, level, val))

    # Run triggers for various special symbols
    if (name == "__DEBUG__" &&
        sym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE) == FALSE &&
        val != FALSE) {
        dbg__all_lev_standard()
    } else if (name == "__SECURE__") {
        val = max(secure_level(), val) # Don't allow __SECURE__ to decrease
        if (val >= SEC_PARANOID)
            sym_destroy_all_deferred()
    } else if (name == "__FMT__" &&
               key == "number" &&
               level == GLOBAL_NAMESPACE) {
        # Maintain equivalence:  __FMT__[number] === CONVFMT
        if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
            sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 7)
            print_debugfile(sprintf("(sym_ll_write) Setting CONVFMT to %s", val))
        CONVFMT = val
    }

    trace(TRACE_SYMBOL_READ_WRITE, name,
          sprintf("[Symbol Write] %s (lev:%d) := Val '%s'",
                  sprintf("\"%s%s\"", name, !emptyp(key) ? "[" key "]" : ""),
                  level, val))
    return symtab[name, key, level, "symval"] = val
}


function sym_ll_incr(name, key, level, incr)
{
    if (incr == EMPTY) incr = 1
    if (level == EMPTY)
        panic("(sym_ll_incr) LEVEL missing")
    if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 5 &&
        !nam_system_p(name))
        print_debugfile(sprintf("(sym_ll_incr) symtab[\"%s\", \"%s\", %d, \"symval\"] += %d",
                             name, key, level, incr))
    return symtab[name, key, level, "symval"] += incr
}

# NB - *Caller* is responsible for checking   integerp(idx) and
#               1 <= idx <= lis count
function lis__ll_incr(lis, idx, level, incr,
                      agg_block, count, val)
{
    if (incr == EMPTY) incr = 1
    if (level == EMPTY)
        panic("(lis__ll_incr) LEVEL missing")

    if (sym_ll_in("__DBG__", "sym", GLOBAL_NAMESPACE) &&
        sym_ll_read("__DBG__", "sym", GLOBAL_NAMESPACE) >= 5 &&
        !nam_system_p(lis))
        print_debugfile(sprintf("(lis__ll_incr) List %s[%s] (level %d) += %d",
                                lis, idx, level, incr))
    if (! ((lis, "", level, "agg_block") in symtab))
        panic(sprintf("(lis__ll_incr) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                      lis, "", level))

    agg_block = symtab[lis, "", level, "agg_block"]
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
                   nparts, info, name, key, icode, level, val, good,
                   agg_block, count, i)
{
    dbg__print("sym", 5, sprintf("(sym_fetch) START; sym='%s'", sym))

    # Scan sym => name, key
    if ((nparts = nam__scan(sym, info)) == ERROR)
        error("(sym_fetch) Scan error, '" sym "'")
    name = info["name"]
    key  = info["key"]

    # Now call nam__lookup(info)
    level = nam__lookup(info)
    if (level == NAME_NOT_FOUND)
        error("(sym_fetch) nam__lookup(info) failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # symtab because NAME[KEY] might not be defined.
    icode = info["code"]
    dbg__print("sym", 5, sprintf("(sym_fetch) nam__lookup ok; level=%d, code=%s", level, icode))

    # Sanity checks
    good = FALSE

    # 0. Sequences return their value
    if (info__get(info, "type") == TYPE_SEQUENCE) {
        val = seq_ll_read(name)
        dbg__print("sym", 2, sprintf("(sym_fetch) END sym='%s', level=%d RETURNING %d",
                                    sym, level, val))
        return val
    }

    # 1. Fetching @ARRNAME@ without key return # elements in ARRNAME.
    # 'idxable' means Array or List.
    if (info["idxable"] == TRUE && info["has_bracket"] == FALSE) {
        val = idx__size(name, level, icode)
        dbg__print("sym", 2, sprintf("(sym_fetch) END sym='%s', level=%d RETURNING %d",
                                    sym, level, val))
        return val
    }

    # 2. Error if symbol is not an Array or List but sym has array[key] syntax
    if (info["idxable"] == FALSE && info["has_bracket"] == TRUE)
        error("(sym_fetch) Name is not an Array or List but has Name[Key] syntax")

    # Now, idxable and hasbracket are either both TRUE or both FALSE.
    # (Earlier version referred to `is_array' but now with Lists we use
    # a more general term to encompass both types)
    do {
        # 3. Check code for TYPE_SYMBOL
        if (info["idxable"] == FALSE &&
            info["has_bracket"] == FALSE &&
            flag_1true_p(icode, TYPE_SYMBOL) &&
            emptyp(key)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }
        # 4. Check code for TYPE_ARRAY
        if (info["idxable"] == TRUE &&
            info["has_bracket"] == TRUE &&
            flag_anytrue_p(icode, __base_type[PTYPE_IDXABLE]) &&
            key != EMPTY) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        panic(sprintf("(sym_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
                      sym, name, key, level, icode))
        # print_debugfile(sprintf("(sym_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
        #                      sym, name, key, level, icode))
    } while (FALSE)

    if (flag_1true_p(icode, FLAG_DEFERRED))
        sym_deferred_define_now(sym)

    if (flag_1true_p(icode, TYPE_LIST)) {
        # Look up block
        if (!integerp(key))
            error(sprintf("(sym_fetch) Block array indices must be integers"))
        if (! ((name, "", level, "agg_block") in symtab))
            panic(sprintf("(sym_fetch) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                          name, "", level))

        agg_block = symtab[name, "", level, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, key) != OBJ_TEXT)
                panic(sprintf("(sym_fetch) Block # %d slot %d is not OBJ_TEXT", agg_block, key))
            val = blk_ll_slot_value(agg_block, key)
        } else
            error(sprintf("(sym_fetch) Out of bounds"))
    } else {
        # It's a normal symbol
        if (! sym_ll_in(name, key, level))
            error(sprintf("(sym_fetch) Not in symtab: name='%s', key='%s', level=%d",
                          name, key, level))
        val = sym_ll_read(name, key, level)
    }

    dbg__print("sym", 2, sprintf("(sym_fetch) END sym='%s', level=%d => %s", name, level, ppf__bool(TRUE)))
    if (flag_1true_p(icode, FLAG_INTEGER))
        return 0 + val
    else if (flag_1true_p(icode, FLAG_NUMERIC))
        return 0.0 + val
    else if (flag_1true_p(icode, FLAG_BOOLEAN))
        return sym_ll_read("__FMT__", to_bool(val)) # !! (0 + val))
    else
        return val
}
function syminfo_fetch(syminfo,
                       sym, nparts, info, name, key, icode, level, val, good,
                       is_array, agg_block, count, has_bracket)
{
    sym = info__get(syminfo, "name")
    dbg__print("sym", 5, sprintf("(syminfo_fetch) START; sym='%s'", sym))

    name = info__get(syminfo, "name")
    key  = info__get(syminfo, "key")
    level = info__get(syminfo, "level")
    if (level == NAME_NOT_FOUND)
        error("(syminfo_fetch) nam__lookup(info) failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # symtab because NAME[KEY] might not be defined.
    icode = info__get(syminfo, "code")
    dbg__print("sym", 5, sprintf("(syminfo_fetch) nam__lookup ok; level=%d, code=%s", level, icode))

    # Sanity checks
    good = FALSE

    # 0. Sequences return their value
    if (info__get(syminfo, "type") == TYPE_SEQUENCE) {
        val = seq_ll_read(name)
        dbg__print("sym", 2, sprintf("(sym_fetch) END sym='%s', level=%d RETURNING %d",
                                    sym, level, val))
        return val
    }

    # 1. Fetching @ARRNAME@ without key return # elements in ARRNAME.
    is_array = info__get(syminfo, "idxable")
    has_bracket = info__get(syminfo, "has_bracket")
    if (is_array == TRUE && has_bracket == FALSE) {
        val = idx__size(name, level, icode)
        dbg__print("sym", 2, sprintf("(syminfo_fetch) END sym='%s', level=%d RETURNING %d",
                                    sym, level, val))
        return val
    }

    # 2. Error if symbol is not an array but sym has array[key] syntax
    if (is_array == FALSE && has_bracket == TRUE)
        error("(syminfo_fetch) Symbol is not an array but sym has array[key] syntax")

    # Now, either both is_array and has_bracket are TRUE
    # or both are FALSE.
    do {
        # 3. Check code for TYPE_SYMBOL
        if (is_array == FALSE &&
            has_bracket == FALSE &&
            flag_1true_p(icode, TYPE_SYMBOL) &&
            emptyp(key)) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }
        # 4. Check code for TYPE_ARRAY
        if (is_array == TRUE &&
            has_bracket == TRUE &&
            flag_1true_p(icode, TYPE_ARRAY) &&
            key != EMPTY) {
            good = TRUE
            break # - - - - - - - - - - - - - - - - - - - - - - - - - -
        }

        panic(sprintf("(syminfo_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
                      sym, name, key, level, icode))
        # print_debugfile(sprintf("(syminfo_fetch) LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
        #                      sym, name, key, level, icode))
    } while (FALSE)

    if (flag_1true_p(icode, FLAG_DEFERRED)) {
        warn("(syminfo_fetch) about to define deferred symbol")
#        sym_deferred_define_now(sym)
    }

    if (flag_1true_p(icode, TYPE_LIST)) {
        # Look up block
        if (!integerp(key))
            error(sprintf("(syminfo_fetch) Block array indices must be integers"))
        if (! ((name, "", level, "agg_block") in symtab))
            panic(sprintf("(syminfo_fetch) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                          name, "", level))

        agg_block = symtab[name, "", level, "agg_block"]
        count = blktab[agg_block, 0, "count"]+0
        if (key >= 1 && key <= count) {
            # Make sure slot holds text, which it pretty much has to
            if (blk_ll_slot_type(agg_block, key) != OBJ_TEXT)
                panic(sprintf("(syminfo_fetch) Block # %d slot %d is not OBJ_TEXT", agg_block, key))
            val = blk_ll_slot_value(agg_block, key)
        } else
            error(sprintf("(syminfo_fetch) Out of bounds"))
    } else {
        # It's a normal symbol
        if (! sym_ll_in(name, key, level))
            error("(syminfo_fetch) Not in symtab: NAME='" name "', KEY='" key "'")
        val = sym_ll_read(name, key, level)
    }

    dbg__print("sym", 2, sprintf("(syminfo_fetch) END sym='%s', level=%d => %s", sym, level, ppf__bool(TRUE)))
    if (flag_1true_p(icode, FLAG_INTEGER))
        return 0 + val
    else if (flag_1true_p(icode, FLAG_NUMERIC))
        return 0.0 + val
    else if (flag_1true_p(icode, FLAG_BOOLEAN))
        return sym_ll_read("__FMT__", to_bool(val)) # !! (0 + val))
    else
        return val
}


function sym_value_or_literal(s)
{
    return (sym_valid_p(s) && sym_defined_p(s)) \
        ? sym_fetch(s) : s
}


# XXX Bare bones, no checking yet
function syminfo_increment(info, incr,
                           iname, ilevel, itype)
{
    # if (incr == EMPTY)
    #     incr = 1

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
    iname = info__get(info, "name")
    ilevel = info__get(info, "level")
    itype = info__get(info, "type")

    if (itype == TYPE_LIST)
        lis__ll_incr(iname, info__get(info, "key"), ilevel, incr)
    else if (itype == TYPE_ARRAY || itype == TYPE_SYMBOL)
        sym_ll_incr(iname, "", ilevel, incr)
    else if (itype == TYPE_SEQUENCE)
        seq_ll_incr(iname, incr)
    else
        panic("(syminfo_increment) Cannot handle type " ppf__flag_type(itype))
}


# function sym_protected_p(sym,
#                          nparts, info, name, key, code, level, retval)
# {
#     dbg__print("sym", 5, sprintf("(sym_protected_p) START sym='%s'", sym))
#
#     # Scan sym => name, key
#     if ((nparts = nam__scan(sym, info)) == ERROR)
#         error("(sym_protected_p) Scan error, '" sym "'")
#     name = info["name"]
#     key  = info["key"]
#
#     # Now call nam__lookup(info)
#     level = nam__lookup(info)
#     if (level == NAME_NOT_FOUND)
#         return double_underscores_p(name)
#
#     # Error if (! name in namtab)
#     if (!nam_ll_in(name, level))
#         error("not in namtab!?  name=" name ", level=" level)
#
#     # Error if name does not exist at that level
#     code = nam_ll_read(name, level)
#     retval = sym_ll_protected(name, code)
#     dbg__print("sym", 4, sprintf("(sym_protected_p) END; sym '%s' => %s", sym, ppf__bool(retval)))
#     return retval
# }
# function syminfo_protected_p(syminfo,
#                              name, type, code, retval)
# {
#     name = info__get(syminfo, "name")
#     type = info__get(syminfo, "type")
#     dbg__print("sym", 5, sprintf("(syminfo_protected_p) START sym='%s'", name))
#
#     if (type == PTYPE_UNDEF) {
#         #warn("(syminfo_protected_p) type is PTYPE_UNDEF")
#         retval = double_underscores_p(name)
#     } else if (type == TYPE_SYMBOL || type == TYPE_ARRAY || type == TYPE_SEQUENCE) {
#         code = info__get(syminfo, "code")
#         if (flag_1true_p(code, FLAG_READONLY))
#             retval = TRUE
#         else if (flag_1true_p(code, FLAG_WRITABLE))
#             retval = FALSE
#         else
#             retval = double_underscores_p(name)
#     } else
#         panic(sprintf("(syminfo_protected_p) Called on '%s' which has type %s",
#                       name, type))
#
#     # # Scan sym => name, key
#     # if ((nparts = nam__scan(sym, info)) == ERROR)
#     #     error("(syminfo_protected_p) Scan error, '" sym "'")
#     # name = info["name"]
#     # key  = info["key"]
#     #
#     # # Now call nam__lookup(info)
#     # level = nam__lookup(info)
#     # if (level == NAME_NOT_FOUND)
#     #     return double_underscores_p(name)
#     #
#     # # Error if (! name in namtab)
#     # if (!nam_ll_in(name, level))
#     #     error("not in namtab!?  name=" name ", level=" level)
#     #
#     # # Error if name does not exist at that level
#     # code = nam_ll_read(name, level)
#     # retval = sym_ll_protected(name, code)
#
#     dbg__print("sym", 4, sprintf("(syminfo_protected_p) END; sym '%s' => %s",
#                                  name, ppf__bool(retval)))
#     return retval
# }


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
        return "@null "    sym
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
        error(sprintf("%s: Symbol '%s' not defined",
                      caller, sym))
}
# function assert_syminfo_defined(syminfo, caller,
#                                 s)
# {
#     if (caller == EMPTY)
#         panic("(assert_syminfo_defined) Empty caller!")
#     if (! syminfo_defined_p(syminfo))
#         error(sprintf("%s: Symbol '%s' not defined",
#                       caller, info__get(syminfo, "name")))
# }

# function syminfo_okay_to_define_p(syminfo,
#                                   name, code, type)
# {
#     #print_stderr("Looking at '" syminfo["name"] (!emptyp(syminfo["key"]) ? "[" syminfo["key"] "]" : "") "'")
#     # I believe this flag trumps all other computations
#     code = info__get(syminfo, "code")
#     if (flag_1true_p(code, FLAG_WRITABLE))
#         return TRUE
#
#     name = info__get(syminfo, "name")
#     type = info__get(syminfo, "type")
#     if (type == TYPE_SYMBOL || type == TYPE_ARRAY || type == PTYPE_UNDEF || type == TYPE_SEQUENCE)
#         return info__get(syminfo, "valid") &&
#                !double_underscores_p(name) &&
#                flag_allfalse_p(code, FLAG_READONLY FLAG_SYSTEM)
#     else {
#         panic("(syminfo_okay_to_define_p) Cannot handle type '" type "'")
#         return FALSE
#     }
#     # if (nam_ll_in(name, __namespace) &&
#     #     flag_alltrue_p((code = nam_ll_read(name, __namespace)), TYPE_SYMBOL) &&
#     #     flag_allfalse_p(code, FLAG_READONLY))
#     #     return TRUE
#     # if (nam_ll_in(name, __namespace)) return FALSE
#     #
#     # if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
#     #     flag_alltrue_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL) &&
#     #     flag_allfalse_p(code, FLAG_READONLY))
#     #     return TRUE
#     # if (nam_ll_in(name, GLOBAL_NAMESPACE)) return FALSE
#
#     # # Can't shadow a system symbol
#     # if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
#     #     flag_alltrue_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL FLAG_SYSTEM))
#     #     return FALSE
#
#     # if (double_underscores_p(name))
#     #     return FALSE
#
#     # # You can redefine a symbol, but not a command, function, or sequence
#     # # if (!name_available_in_all_p(name, TYPE_USER TYPE_FUNCTION TYPE_SEQUENCE))
#     # #     error("Name '" name "' not available:" $0)
#     # return TRUE
# }

# function assert_sym_okay_to_define(name,
#                                    code)
# {
#     assert_sym_valid_name(name)
#     assert_sym_unprotected(name)
#
#     if (nam_ll_in(name, __namespace) &&
#         flag_alltrue_p((code = nam_ll_read(name, __namespace)), TYPE_SYMBOL) &&
#         flag_allfalse_p(code, FLAG_READONLY))
#         return TRUE
#     if (nam_ll_in(name, __namespace)) return FALSE
#
#     if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
#         flag_alltrue_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL) &&
#         flag_allfalse_p(code, FLAG_READONLY))
#         return TRUE
#     if (nam_ll_in(name, GLOBAL_NAMESPACE)) return FALSE
#
#     # Can't shadow a system symbol
#     if (nam_ll_in(name, GLOBAL_NAMESPACE) &&
#         flag_alltrue_p((code = nam_ll_read(name, GLOBAL_NAMESPACE)), TYPE_SYMBOL FLAG_SYSTEM))
#         return FALSE
#
#     if (double_underscores_p(name))
#         return FALSE
#
#     # You can redefine a symbol, but not a command, function, or sequence
#     # if (!name_available_in_all_p(name, TYPE_USER TYPE_FUNCTION TYPE_SEQUENCE))
#     #     error("Name '" name "' not available:" $0)
#     return TRUE
# }
# function assert_syminfo_okay_to_define(syminfo, caller,
#                                        name, code, type)
# {
#     if (caller == EMPTY)
#         panic("(assert_syminfo_okay_to_define) Empty caller!")
#
#     assert_syminfo_valid_name(syminfo, caller)
#     assert_syminfo_unprotected(syminfo, caller)
#
#     if (! syminfo_okay_to_define_p(syminfo))
#         error(sprintf("%s: Symbol '%s' cannot be defined here",
#                       caller, info__get(syminfo, "name")))
# }


# Throw an error if symbol IS protected
# function assert_sym_unprotected(sym)
# {
#     if (sym_protected_p(sym))
#         error("Symbol '" sym "' protected:" $0)
# }
# function assert_syminfo_unprotected(syminfo, caller)
# {
#     if (caller == EMPTY)
#         panic("(assert_syminfo_unprotected) Empty caller!")
#     if (syminfo_protected_p(syminfo))
#         error(sprintf("%s: Symbol '%s' protected",
#                       caller, info__get(syminfo, "name")))
# }


# Throw an error if the symbol name is NOT valid
function assert_sym_valid_name(sym, caller)
{
    if (caller == EMPTY)
        panic("(assert_sym_valid_name) Empty caller!")
    if (! sym_valid_p(sym))
        error("Symbol '" sym "' not valid:" $0)
}
# function assert_syminfo_valid_name(syminfo, caller)
# {
#     if (caller == EMPTY)
#         panic("(assert_syminfo_valid_name) Empty caller!")
#     if (! syminfo_valid_p(syminfo))
#         error(sprintf("%s: Name '%s' not valid",
#                       caller, info__get(syminfo, "name")))
# }
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
    dbg__print("xeq", 1, sprintf("(execute__text) START; text='%s'", text))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg__print("xeq", 3, "(execute__text) NOP due to __xeq_ctl=" __xeq_ctl)
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
        dbg__print("ship_out", 1, sprintf("(execute__text) END Appending text to stream %d", stream))
        blk_append(stream, OBJ_TEXT, text)
        return
    }

    if (__print_mode == MODE_TEXT_PRINT) {
        printf("%s\n", text)
        flush_stdout(SYNC_LINE)
    } else if (__print_mode == MODE_TEXT_STRING)
        __textbuf = sprintf("%s%s\n", __textbuf, text)
    else
        panic("(execute__text) Bad __print_mode " __print_mode)
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
    return str ~ /^(canrun|defined|env|exists)\(/
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
            print_debugfile(sprintf("(bool__tokenize_string) __btoken[%d]='%s'", i, __btoken[i]))
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
        #print("(bool__scan_factor) CANRUN name='" name "'")
        if (emptyp(name)) return ERROR
        if (secure_level() >= SEC_PARANOID)
            security_violation("canrun(): Forbidden")
        # Check via "sh -c 'command -v ARG'"
        rc = system(sprintf("%s -c 'command -v %s' >%s 2>%s",
                            safe_shell(), name, NULL, NULL))
        r = (rc == 0)
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

    } else if (__btoken[__bf] == TOK_ENV_P) {
        name = __btoken[++__bf]
        if (emptyp(name)) return ERROR
        assert_valid_env_var_name(name, "env()_B")
        r = name in ENVIRON
        dbg__print("bool", 5, "(bool__scan_factor) ENV; name='" name "', RETURNING " ppf__bool(r))
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
                        me, name, info)
{
    # print_stderr(sprintf("(xeq_cmd__array) cmd='%s', cmdline='%s', $0='%s'",
    #                      cmd, cmdline, $0))
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    name = $1
    info__create_from_text(name, info)
    info__gate(OP_CREATE, TYPE_ARRAY, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)
    # if (nam_ll_in(name, __namespace))
    #     error(sprintf("%s: Array '%s' already defined",
    #                   me, name))
    nam_ll_write(name, __namespace, TYPE_ARRAY)
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
    if (__xeq_ctl != XEQ_NORMAL)
        panic("(xeq_cmd__break) __xeq_ctl is not normal")

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
    dbg__print("case", 3, sprintf("(parse__case) START dstblk=%d, $0='%s'", curr_dstblk(), $0))

    raise_namespace()

    # Create a new block for case_block
    case_block = blk_new(BLK_CASE)
    dbg__print("case", 5, "(parse__case) New block # " case_block " type " ppf__block_type(blk_type(case_block)))
    preamble_block = blk_new(BLK_AGG)
    dbg__print("case", 5, "(parse__case) New block # " case_block " type " ppf__block_type(blk_type(preamble_block)))

    $1 = ""
    blktab[case_block, 0, "casevar"]        = $2
    blktab[case_block, 0, "preamble_block"] = preamble_block
    blktab[case_block, 0, "seen_otherwise"] = FALSE
    blktab[case_block, 0, "dstblk"]         = preamble_block
    blktab[case_block, 0, "valid"]          = FALSE
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
                                 curr_dstblk(), ppf__mode(curr_atmode()), $0))
    if (check__parse_stack(BLK_CASE) != ERR_OKAY)
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
    dbg__print("case", 3, sprintf("(parse__otherwise) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_CASE) != ERR_OKAY)
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
    dbg__print("case", 3, sprintf("(parse__endcase) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_CASE) != ERR_OKAY)
        error("[@endcase] Parse error; " __m2_msg)

    case_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endcase) popped parse_stack => " case_block)
    blktab[case_block, 0, "valid"] = TRUE
    lower_namespace()
    return case_block
}


function xeq__BLK_CASE(case_block,
                       block_type, casevar, caseval, preamble_block)
{
    block_type = blk_type(case_block)
    dbg__print("case", 3, sprintf("(xeq__BLK_CASE) START dstblk=%d, case_block=%d, type=%s",
                                 curr_dstblk(), case_block, ppf__block_type(block_type)))

    dbg__print_block("case", 7, case_block, "(xeq__BLK_CASE) case_block")
    if ((blk_type(case_block) != BLK_CASE) ||  \
        (blktab[case_block, 0, "valid"] != TRUE))
        panic("(xeq__BLK_CASE) Bad case_block config")

    # Check if the case variable value matches any @of values
    casevar = blktab[case_block, 0, "casevar"]
    dbg__print("case", 5, sprintf("(xeq__BLK_CASE) casevar '%s'", casevar))
    assert_sym_defined(casevar, "@case")
    caseval = sym_fetch(casevar)
    dbg__print("case", 5, sprintf("(xeq__BLK_CASE) caseval '%s'", caseval))

    if ((case_block, caseval, "of_block") in blktab) {
        # See if there's a preamble which is non-empty.  Preambles get
        # their own namespace.
        preamble_block = blktab[case_block, 0, "preamble_block"]
        if (blktab[preamble_block, 0, "count"]+0 > 0) {
            dbg__print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                         blktab[case_block, 0, "preamble_block"]))
            raise_namespace()
            execute__block(blktab[case_block, 0, "preamble_block"])
            lower_namespace()
            dbg__print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        }

        # The @of branch gets a new namespace
        raise_namespace()
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                     blktab[case_block, caseval, "of_block"]))
        execute__block(blktab[case_block, caseval, "of_block"])
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        lower_namespace()
    } else if (blktab[case_block, 0, "seen_otherwise"] == TRUE) {
        # NB - @otherwise branches DO NOT execute the preamble (if any)
        raise_namespace()
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) CALLING execute__block(%d)",
                                     blktab[case_block, 0, "otherwise_block"]))
        execute__block(blktab[case_block, 0, "otherwise_block"])
        dbg__print("case", 5, sprintf("(xeq__BLK_CASE) RETURNED FROM execute__block()"))
        lower_namespace()
    }

    dbg__print("case", 3, sprintf("(xeq__BLK_CASE) END"))
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
            if (stream > MAX_STREAM)
                error(sprintf("%s: Bad parameters: %s", me, $0))
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
    if (__xeq_ctl != XEQ_NORMAL)
        panic("(xeq_cmd__continue) __xeq_ctl is not normal")

    __xeq_ctl = XEQ_CONTINUE
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
                       lis, info, key, level, code)
{
    me = "@" cmd
    dbg__print("parse", 5, sprintf("(xeq_cmd__data) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

    $0 = cmdline
    if (NF == 0)
        error(me ": Bad parameters")

    lis = $1
    # assert_list_okay_to_define(lis, me)
    save_line = $0
    save_lineno = LINE()

    # # Check ARR.  assert_array_okay_to_define() passed, so this won't fail
    # nam__scan(lis, info)
    # level = nam__lookup(info)
    level = info__create_from_text(lis, info)
    info__gate(OP_UPDATE, TYPE_LIST, info, __namespace, me, TRUE)
    code = info["code"]
    dbg__print("xeq", 5, sprintf("(xeq_cmd__data) code=%s", code))
    lis_clear(lis, level, code)

    # create a new Agg block
    agg_block = blk_new(BLK_AGG)
    key = ""
    dbg__print("parse", 5, sprintf("(xeq_cmd__data) symtab['%s','%s',%d,'agg_block'] = %d",
                                 lis, key, level, agg_block))
    symtab[lis, key, level, "agg_block"] = agg_block
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
function xeq_cmd__define(cmd, cmdline,
                         me, name, append_flag, nop_if_defined, error_if_defined,
                         info, info2, level, ok_update, ok_create, agg_block)
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
    # assert_syminfo_okay_to_define(info, me)
    # if (syminfo_defined_p(info)) {
    #     if (nop_if_defined)
    #         return
    #     if (error_if_defined)
    #         error("Symbol '" name "' already defined:" $0)
    # }

#SO FRESH:
    info__create_from_text(name, info)
    ok_update = info__gate(OP_UPDATE, PTYPE_SCALAR, info, __namespace, me, FALSE)
    if (ok_update) {
        dbg__print("gate", 5, "(@DEFINE) Symbol '" name "' update OK...")
    } else {
        dbg__print("gate", 7, "(xeq_cmd__define) gate(update) failed: " info__get(info, "errtext"))

        info__create_from_text(name, info2)
        ok_create = info__gate(OP_CREATE, PTYPE_SCALAR, info2, __namespace, me, FALSE)
        if (ok_create) {
            dbg__print("gate", 5, "(@DEFINE) Symbol '" name "' create OK...")
        } else {
            dbg__print("gate", 7, "(xeq_cmd__define) gate(create) failed: " info__get(info2, "errtext"))
            if (info__get(info2, "error"))
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
        agg_block = symtab[name, "", level, "agg_block"]
        blk_append(agg_block, OBJ_TEXT, $0)
    } else {
        if ($0 == EMPTY)
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
    if (new_stream > MAX_STREAM)
        error(me ": Bad parameters:" $0)

    sym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, int(new_stream))
    dbg__print("divert", 2, sprintf("(xeq_cmd__divert) END; __DIVNUM__ now %d", new_stream))
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
        what_type = PTYPE_ANY
        buf = nam_dump_namtab(what_type, all_flag)
    } else if (what ~ /bl(oc)?ks?/) {
        what_type = PTYPE_ANY    # There is no "block" type
        buf = blk_dump_blktab()
    } else if (what ~ /[0-9]+/) {
        what_type = PTYPE_ANY    # There is no "block" type
        dbg__print("sym", 9, "Dump of block # " what)
        if (! ((what, 0, "type") in blktab))
            panic("(xeq_cmd__dump) No 'type' field for block " what)
        block_type = blk_type(what)
        blk_label = ppf__block_type(block_type)
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
    dbg__print("dump", 7, sprintf("_less_than: s1='%s', s='%s'", s1, s2))
    fs1 = first(s1)
    fs2 = first(s2)

    if      (fs1 == "" && fs2 == "") panic("(_less_than) fs1 and fs2 are empty!")
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
                      keys, cnt, i, blk, count)
{
    dbg__print("sym", 4, "(dump__symtab) BEGIN")
    if (first(type) != TYPE_SYMBOL)
        panic("(dump__symtab) Bad type " ppf__flags(first(type)))
    sym_define_all_deferred()

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (k in symtab) {
        split(k, x, SUBSEP)
        dbg__print("sym", 8, sprintf("(dump__symbtab) ['%s','%s',%d,%s]",
                                    x[1], x[2], x[3], x[4]))
        # print "name  =", x[1]
        # print "key   =", x[2]
        # print "level =", x[3]
        # print "elem  =", x[4]

        code = nam_ll_read(x[1], x[3]) # name, level
        dbg__print("sym", 7, sprintf("(dump__symtab) name='%s', key='%s', code=%s",
                                    x[1], x[2], code))
        if (!include_sys && flag_1true_p(code, FLAG_SYSTEM))
            continue

        if (x[4] == "agg_block") {
            if (flag_1false_p(code, TYPE_LIST))
                panic("(dump__symtab) Found type 'agg_block' but not a List")
            # It's a block array so insert all the keys.
            blk = symtab[x[1], x[2], x[3], x[4]]
            count = blktab[blk, 0, "count"]
            #print_stderr("blk=" blk ", count=" count)
            if (count > 0)
                for (i = 1; i <= count; i++) {
                    #print_stderr("Adding keys[" cnt+1 "] = " x[1] "[" i "]")
                    keys[++cnt] = x[1] "[" i "]"
                }
            continue
        } else if (x[4] != "symval")
            panic(sprintf("(dump__symtab) Unexpected elem type: ['%s','%s',%d,%s]",
                          x[1], x[2], x[3], x[4]))

        # It's a regular symbol so process it
        if ((flag_1true_p(code, TYPE_SYMBOL) && x[2] == EMPTY) ||
            (flag_anytrue_p(code, TYPE_ARRAY TYPE_LIST)  && x[2] != EMPTY))
            keys[++cnt] = x[1] (x[2] != EMPTY ? "[" x[2] "]" : "")
        else
            panic(sprintf("(dump__symtab) Strange combo: ('%s','%s') code=%s",
                          x[1], x[2], code))
    }

    qsort(keys, 1, cnt)

    # Construct output lines in buf
    buf = EMPTY
    for (i = 1; i <= cnt; i++)
        buf = buf sym_definition_ppf(keys[i]) TOK_NEWLINE
    dbg__print("sym", 4, "(dump__symtab) END")
    return chomp(buf)
}


function dump__seqtab(type, include_sys,
                      x, k, keys, cnt, code, buf, i)
{
    dbg__print("seq", 4, "(dump__seqtab) BEGIN")
    if (first(type) != TYPE_SEQUENCE)
        panic("(dump__seqtab) Bad type " ppf__flags(first(type)))

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (k in seqtab) {
        split(k, x, SUBSEP)
        # print "name  =", x[1]
        # print "elem  =", x[2]
        if (x[2] != "seqval") continue
        code = nam_ll_read(x[1], GLOBAL_NAMESPACE) # name, level
        dbg__print("seq", 7, sprintf("(dump__seqtab) name='%s', code=%s",
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
    dbg__print("seq", 4, "(dump__seqtab) END")
    return chomp(buf)
}


function dump__cmdtab(type, include_sys,
                      x, k, keys, cnt, code, buf, i)
{
    dbg__print("cmd", 4, "(dump__cmdtab) BEGIN")
    if (first(type) != TYPE_USER)
        panic("(dump__cmdtab) Bad type " ppf__flags(first(type)))

    # Build keys[] array, whose values are printable symbol names that
    # pass restrictive checks.
    cnt = 0
    for (k in cmdtab) {
        split(k, x, SUBSEP)
        # print_debugfile("x[1]=" x[1])
        # print_debugfile("x[2]=" x[2])
        # print_debugfile("x[3]=" x[3])
        # print_debugfile("value => " cmdtab[x[1], x[2], x[3]])

        if (x[3] != "user_block") continue
        code = nam_ll_read(x[1], x[2]) # name, level
        dbg__print("cmd", 5, sprintf("(dump__cmdtab) name='%s', code=%s",
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
    dbg__print("cmd", 4, "(dump__cmdtab) END")
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
        buf = dump__symtab(TYPE_SYMBOL, FALSE) # normal symbols only
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
        __exit_code = EX_USER_REQUEST
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
                          rc, shell_cmdline, output_file, getstat, line, output_text, me)
{
    me = "@" cmd
    dbg__print("cmd", 3, sprintf("(xeq_cmd__esyscmd) START; cmdline='%s'", cmdline))
    if (secure_level() >= SEC_SECURE)
        security_violation(me ": Forbidden")

    output_file = mktemp(tmpdir() "m2-esyscmd.out.XXXXXX")
    shell_cmdline = sprintf("%s -c '%s' <%s >%s",
                            safe_shell(), cmdline, NULL, output_file)
    flush_stdout(SYNC_FORCE)
    rc = system(shell_cmdline)
    sym_ll_write("__SYSVAL__", "", GLOBAL_NAMESPACE, rc)

    while (TRUE) {
        getstat = getline line < output_file
        if (getstat == ERROR)
            warn(me ": Error reading file '" output_file "'")
        if (getstat != OKAY)
            break
        output_text = output_text line TOK_NEWLINE # Read a line
    }
    close(output_file)
    if ("rm" in PROG)
        exec_prog_cmdline("rm", ("-f " output_file))
    else if (debugging_enabled_p())
        warn(me ": PROG[rm] not defined; '" output_file "' not deleted")

    output_text = chomp(output_text)
    dbg__print("cmd", 5, sprintf("(xeq_cmd__esyscmd) output_text='%s'", output_text))
    if (!emptyp(output_text))
        ship_out(OBJ_TEXT, output_text)
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
    $1 = ""
    sub("^[ \t]*", "")
    dbg__print("parse", 5, "(xeq_cmd__eval) '" $0 "'")
    dostring($0)
}


function dostring(str,
                  string_block, term2, retval, p)
{
    dbg__print("parse", 5, "(dostring) START str='" str "'")

    # Set up a SRC_STRING parser for str, and the __terminal
    string_block = blk_new(SRC_STRING)
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


function parse__string(    str, string_block1, string_block2, pstat, d)
{
    if (stk_empty_p(__source_stack))
        panic("(parse__string) Source stack empty")
    string_block1 = stk_top(__source_stack)
    str = blktab[string_block1, 0, "str"]

    dbg__print("parse", 2, sprintf("(parse__string) str='%s', dstblk=%d, mode=%s",
                                   str, curr_dstblk(),
                                   ppf__mode(blktab[string_block1, 0, "atmode"])))

    blktab[string_block1, 0, "old.buffer"] = __buffer
    dbg__print_block("ship_out", 7, string_block1, "(parse__string) string_block1")

    # Set up new file context
    __buffer = str

    # Read the file and process each line
    dbg__print("parse", 5, "(parse__string) CALLING parse()")
    pstat = parse()
    dbg__print("parse", 5, "(parse__string) RETURNED FROM parse() => " ppf__bool(pstat))

    string_block2 = stk_pop(__source_stack)
    if (string_block1 != string_block2)
        panic("(parse__string) String block mismatch")
    __buffer = blktab[string_block2, 0, "old.buffer"]

    dbg__print("parse", 2, sprintf("(parse__string) END '%s' => %s",
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
function xeq_cmd__exit(cmd, cmdline)
{
    __exit_code = (!emptyp(cmdline) && integerp(cmdline)) ? cmdline+0 : EX_OK

    # For full portability, exit values should be between 0 and 126, inclusive.
    # Negative values, and values of 127 or greater, may not produce
    # consistent results across different operating systems.
    if (__exit_code < 0 || __exit_code > 126)
        __exit_code = 1
    end_program(__exit_code == EX_OK ? MODE_STREAMS_SHIP_OUT \
                                     : MODE_STREAMS_DISCARD)
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =



#*****************************************************************************
#
#       @  F I L E D A T A
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @{s,}filedata        LIS FILE
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
                           me)
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
    # assert_list_okay_to_define(lis, me)

    # Check LIS.  assert_list_okay_to_define() passed, so this won't fail
    # nam__scan(lis, info)
    # level = nam__lookup(info)
    level = info__create_from_text(lis, info)
    info__gate(OP_UPDATE, TYPE_LIST, info, __namespace, me, TRUE)
    code = info__get(info, "code")
    dbg__print("xeq", 5, sprintf("(xeq_cmd__filedata) code=%s", code))
    lis_clear(lis, level, code)

    # create a new Agg block
    agg_block = blk_new(BLK_AGG)
    key = ""
    dbg__print("parse", 5, sprintf("(xeq_cmd__filedata) symtab['%s','%s',%d,'agg_block'] = %d",
                                 lis, key, level, agg_block))
    symtab[lis, key, level, "agg_block"] = agg_block
    blktab[agg_block, 0, "dstblk"] = agg_block

    # create a new literal file parser
    stk_push(__parse_stack, agg_block)
    file_block = prep_file(filename)
    blktab[file_block, 0, "atmode"] = MODE_AT_LITERAL
    # Push file block manually because prep_file doesn't do that
    dbg__print("parse", 7, sprintf("(xeq_cmd__filedata) Pushing file block %d (%s) onto source_stack", file_block, filename))
    stk_push(__source_stack, file_block)

    dbg__print("parse", 5, "(xeq_cmd__filedata) CALLING parse__file()")
    rc = parse__file()
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
# @{s,}filedefine         NAME FILE
function xeq_cmd__filedefine(cmd, cmdline,
                             name, filename, line, val, getstat, silent, info,
                             me)
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
    info__gate(OP_CREATE, PTYPE_SCALAR, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)
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
    sym_store(name, chomp(val))
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
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))
    cmd = $1
    if (NF < 3)
        error(sprintf("%s: Bad parameters:", cmd, $0))

    raise_namespace()

    # Create two new blocks: "for_block" for loop control (for_block),
    # and "body_block" for the loop code definition.
    for_block = blk_new(BLK_FOR)
    dbg__print("for", 5, "(parse__for) for_block # " for_block " type " ppf__block_type(blk_type(for_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("for", 5, "(parse__for) body_block # " body_block " type " ppf__block_type(blk_type(body_block)))

    blktab[for_block, 0, "body_block"] = body_block
    blktab[for_block, 0, "dstblk"] = body_block
    blktab[for_block, 0, "valid"] = FALSE
    blktab[for_block, 0, "loop_var"] = $2

    if (cmd == "@for") {
        dbg__print("for", 9, "(parse__for) Found FOR: " $0)
        blktab[for_block, 0, "loop_type"] = cmd
        blktab[for_block, 0, "loop_start"] = $3 + 0
        blktab[for_block, 0, "loop_end"] = $4 + 0
        blktab[for_block, 0, "loop_incr"] = incr = NF >= 5 ? ($5 + 0) : 1
        if (incr == 0)
            error(cmd ": Increment value cannot be zero!")

    } else if (cmd == "@foreach") {
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
        blktab[for_block, 0, "array_type"] = info__get(info, "type") # (flag_1true_p(info["code"], FLAG_BLKARRAY)) ? "block" : "normal"
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
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))
    if (check__parse_stack(BLK_FOR) != ERR_OKAY)
        error("[@next] Parse error; " __m2_msg)
    for_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__next) popped parse_stack => " for_block)

    if (blktab[for_block, 0, "loop_var"] != $2)
        error(sprintf("%s: Variable mismatch; '%s' specified, but '%s' was expected",
                      $1, $2, blktab[for_block, 0, "loop_var"]))
    blktab[for_block, 0, "valid"] = TRUE

    lower_namespace()

    dbg__print("for", 3, sprintf("(parse__next) END => %d", for_block))
    return for_block
}


function xeq__BLK_FOR(for_block,
                      block_type)
{
    block_type = blk_type(for_block)
    dbg__print("for", 3, sprintf("(xeq__BLK_FOR) START dstblk=%d, for_block=%d, type=%s",
                                curr_dstblk(), for_block, ppf__block_type(block_type)))
    dbg__print_block("for", 7, for_block, "(xeq__BLK_FOR) for_block")
    if ((block_type != BLK_FOR) || \
        (blktab[for_block, 0, "valid"] != TRUE))
        panic("(xeq__BLK_FOR) Bad for_block config")

    if (blktab[for_block, 0, "loop_type"] == "@for" )
        execute__for(for_block)
    else
        execute__foreach(for_block)
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

    dbg__print_block("for", 7, for_block, "(execute__for) for_block")
    dbg__print_block("for", 7, body_block, "(execute__for) body_block")
    dbg__print("for", 4, sprintf("(execute__for) loopvar='%s', start=%d, end=%d, incr=%d",
                                 loopvar, start, end, incr))

    if (start > end && incr > 0)
        error("(execute__for) Start cannot be greater than End")
    if (start < end && incr < 0)
        error("(execute__for) Start cannot be less than End")

    # Run the loop
    while (!done) {
        new_level = raise_namespace()
        nam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY)
        sym_ll_write(loopvar, "", new_level, counter)
        dbg__print("for", 5, sprintf("(execute__for) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg__print("for", 5, sprintf("(execute__for) RETURNED FROM execute__block()"))
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
                                loopvar, arrname, level, keys, x, k, body_block, new_level)
{
    loopvar = blktab[for_block, 0, "loop_var"]
    arrname = blktab[for_block, 0, "loop_array_name"]
    level = blktab[for_block, 0, "level"]
    body_block = blktab[for_block, 0, "body_block"]
    dbg__print("for", 4, sprintf("(execute__foreach_array) loopvar='%s', arrname='%s', level=%d, body_block=%d",
                                loopvar, arrname, level, body_block))
    # Find the keys
    for (k in symtab) {
        split(k, x, SUBSEP)
        dbg__print("for", 7, sprintf("symtab[%s,%s,%d,%s]", x[1], x[2], x[3], x[4]))
        if (x[1] == arrname && x[3] == level && x[4] == "symval")
            keys[x[2]] = 1
    }

    # Run the loop
    for (k in keys) {
        new_level = raise_namespace()
        nam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_READONLY)
        sym_ll_write(loopvar, "", new_level, k)
        dbg__print("for", 5, sprintf("(execute__foreach_array) CALLING execute__block(%d)", body_block))
        execute__block(body_block)
        dbg__print("for", 5, sprintf("(execute__foreach_array) RETURNED FROM execute__block()"))
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
    dbg__print("for", 2, "(execute__foreach_array) END")
}

function execute__foreach_list(for_block,
                               arrname, level, loopvar, start, count, done,
                               counter, body_block, new_level, agg_block)
{
    loopvar = blktab[for_block, 0, "loop_var"]
    arrname = blktab[for_block, 0, "loop_array_name"]
    level = blktab[for_block, 0, "level"]
    body_block = blktab[for_block, 0, "body_block"]
    dbg__print("for", 4, sprintf("(execute__foreach_list) loopvar='%s', arrname='%s', level=%d, body_block=%d",
                                loopvar, arrname, level, body_block))

    counter = 1
    agg_block = symtab[arrname, "", level, "agg_block"]
    count = blktab[agg_block, 0, "count"]

    if (count > 0 ) {
        # Run the loop
        while (!done) {
            new_level = raise_namespace()
            nam_ll_write(loopvar, new_level, TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY)
            sym_ll_write(loopvar, "", new_level, counter)
            dbg__print("for", 5, sprintf("(execute__for) CALLING execute__block(%d)", body_block))
            execute__block(body_block)
            dbg__print("for", 5, sprintf("(execute__for) RETURNED FROM execute__block()"))
            lower_namespace()
            done = (counter += 1) > count

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
    }

    dbg__print("for", 2, "(execute__foreach_list) END")
}


function ppf__for(for_block,
                  buf, ltype)
{
    ltype = blktab[for_block, 0, "loop_type"]
    buf = ltype TOK_SPACE \
          blktab[for_block, 0, "loop_var"] TOK_SPACE
    if (ltype == "@for")
        buf = buf blktab[for_block, 0, "loop_start"] TOK_SPACE \
                  blktab[for_block, 0, "loop_end"]   TOK_SPACE \
                  blktab[for_block, 0, "loop_incr"]
    else                        # foreach
        buf = buf blktab[for_block, 0, "loop_array_name"]
    buf = buf TOK_NEWLINE
    buf = buf ppf__block(blktab[for_block, 0, "body_block"]) TOK_NEWLINE
    buf = buf "@next "  blktab[for_block, 0, "loop_var"]
    return buf
}


function ppf__BLK_FOR(blknum)
{
    return sprintf("  valid   : %s\n" \
                   "  type    : %s\n"       \
                   "  loopvar : %s\n"       \
                   "  start   : %d\n"       \
                   "  end     : %d\n"       \
                   "  incr    : %d\n"       \
                   "  body    : %d",
                   ppf__bool(blktab[blknum, 0, "valid"]),
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

    raise_namespace()

    # Create two new blocks: one for if_block, other for true branch
    if_block = blk_new(BLK_IF)
    dbg__print("if", 5, "(parse__if) New block # " if_block " type " ppf__block_type(blk_type(if_block)))
    true_block = blk_new(BLK_AGG)
    dbg__print("if", 5, "(parse__if) New block # " true_block " type " ppf__block_type(blk_type(true_block)))

    blktab[if_block, 0, "condition"]   = $0
    blktab[if_block, 0, "init_negate"] = (name == "@unless")
    blktab[if_block, 0, "seen_else"]   = FALSE
    blktab[if_block, 0, "true_block"]  = true_block
    blktab[if_block, 0, "dstblk"]      = true_block
    blktab[if_block, 0, "valid"]       = FALSE
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
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_IF) != ERR_OKAY)
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
    dbg__print("if", 3, sprintf("(parse__endif) START dstblk=%d, mode=%s",
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_IF) != ERR_OKAY)
        error("[@endif] Parse error; " __m2_msg)

    if_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endif) popped parse_stack => " if_block)
    blktab[if_block, 0, "valid"] = TRUE
    lower_namespace()
    return if_block
}


function xeq__BLK_IF(if_block,
                     block_type, condition, condval, negate)
{
    block_type = blk_type(if_block)
    dbg__print("if", 3, sprintf("(xeq__BLK_IF) START dstblk=%d, if_block=%d, type=%s",
                               curr_dstblk(), if_block, ppf__block_type(block_type)))

    dbg__print_block("if", 7, if_block, "(xeq__BLK_IF) if_block")
    if ((block_type != BLK_IF) || \
        (blktab[if_block, 0, "valid"] != TRUE))
        panic("(xeq__BLK_IF) Bad if_block config")

    # Evaluate condition, determine if TRUE/FALSE and also
    # which block to follow.  For now, always take TRUE path
    condition = blktab[if_block, 0, "condition"]
    negate = blktab[if_block, 0, "init_negate"]
    condval = evaluate_boolean(condition, negate)
    dbg__print("if", 2, sprintf("(xeq__BLK_IF) evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
    if (condval == ERROR)
        error("@if: Error evaluating condition '" condition "'")

    raise_namespace()
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
    lower_namespace()

    dbg__print("if", 3, sprintf("(xeq__BLK_IF) END"))
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

        retval = sym_ll_in(arr, key, info["level"])

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

        if (sym_valid_p(lhs) && sym_deferred_p(lhs))
            sym_deferred_define_now(lhs)
        if (sym_valid_p(lhs) && sym_defined_p(lhs))
            lval = sym_fetch(lhs)
        else if (seq_defined_p(lhs))
            lval = seq_ll_read(lhs)
        else
            lval = lhs

        if (sym_valid_p(rhs) && sym_deferred_p(rhs))
            sym_deferred_define_now(rhs)
        if (sym_valid_p(rhs) && sym_defined_p(rhs))
            rval = sym_fetch(rhs)
        else if (seq_defined_p(rhs))
            rval = seq_ll_read(rhs)
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
function xeq_cmd__ignore(cmd, cmdline,
                         readstat, save_line, save_lineno)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__ignore) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

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
# @{s,}{include,paste}  FILE
function xeq_cmd__include(cmd, cmdline,
                          error_text, filename, silent, file_block, rc,
                          me)
{
    me = "@" cmd
    rc = FALSE
    dbg__print("parse", 5, sprintf("(xeq_cmd__include) cmd='%s', cmdline='%s'",
                                   cmd, cmdline))
    if (cmdline == EMPTY)
        error(me ": Bad parameters")
    # S variants mute file errors, even in strict mode
    silent = (first(cmd) == "s")

    # error_text is set aggressively, but only is seen if rc is FALSE
    do {
        error_text = me ": File '" cmdline "' not found"
        filename = search_file(cmdline)
        if (emptyp(filename))
            break
        file_block = prep_file(filename)
        blktab[file_block, 0, "atmode"] = substr(cmd, length(cmd)-4) == "paste" \
                                          ? MODE_AT_LITERAL : MODE_AT_PROCESS
        # prep_file doesn't push the SRC_FILE onto the __source_stack,
        # so we have to do that ourselves due to customization
        dbg__print("parse", 7, sprintf("(xeq_cmd__include) Pushing file block %d (%s) onto source_stack", file_block, filename))
        stk_push(__source_stack, file_block)

        error_text = me ": File '" filename "' not found"
        dbg__print("parse", 5, "(xeq_cmd__include) CALLING parse__file()")
        rc = parse__file()
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
    if (first(f) == "/")
        # If path is absolute, do not invoke path search mechanism
        return pe ? f : EMPTY
    icount = split(__inc_path, paths, TOK_COLON)
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
                       sym, info, me)
{
    me = "@" cmd
    $0 = cmdline
    if (NF == 0)
        error(me ": Bad parameters")
    name = $1
    info__create_from_text(name, info)
    info__gate(OP_UPDATE, PTYPE_NUMBER, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)
    # assert_sym_defined(name, me)
    # assert_syminfo_defined(info, me)
    # if (!sym_defined_p(name) && !seq_defined_p(name))
    #     error(sprintf("%s: Name '%s' not defined",
    #                   me, name))

    if (NF >= 2 && ! integerp($2))
        error(sprintf("%s: Value '%s' must be numeric",
                      me, $2))
    incr = (NF >= 2) ? $2 : 1
    incr = (cmd == "incr") ? incr : -incr
    if (syminfo_defined_p(info))
        syminfo_increment(info, incr)
    else if (seqinfo_defined_p(info))
        seq_ll_incr(info__get(info, "name"), incr)
    else
        error(sprintf("%s: Name '%s' not defined",
                      me, name))
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
                        me)
{
    me = "@" cmd
    $0 = cmdline
    name = (NF == 0) ? "__INPUT__" : $1
    info__create_from_text(name, info)
    info__gate(OP_CREATE, PTYPE_SCALAR, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)

    input = EMPTY
    getstat = getline input < TTY
    if (getstat == ERROR)
        warn(me ": Error reading file '" TTY "' [input]:" $0)
    sym_store(name, input)
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
                       name, info, agg_block, me)
{
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error("Bad parameters:" $0)
    name = $1
    info__create_from_text(name, info)
    info__gate(OP_CREATE, TYPE_LIST, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)
    # if (nam_ll_in(name, __namespace))
    #     error(sprintf("%s: List '%s' already defined",
    #                   m3, name))
    nam_ll_write(name, __namespace, TYPE_LIST)
    agg_block = blk_new(BLK_AGG)
    dbg__print("parse", 5, sprintf("(xeq_cmd__data) symtab['%s','',%d,'agg_block'] = %d",
                                 name, __namespace, agg_block))
    symtab[name, "", __namespace, "agg_block"] = agg_block
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
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

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

    dbg__print("parse", 5, sprintf("(xeq_cmd__literal) CALLING ship_out(%s, '%s')", OBJ_BLKNUM, lit_block))
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
# @local FOO adds to namtab (as a scalar) in the current namespace, does not define it
function xeq_cmd__local(cmd, cmdline,
                        name, info, me)
{
    me = "@" cmd
    $0 = cmdline
    if (NF < 1)
        error(me ": Bad parameters:" $0)
    if (__namespace == GLOBAL_NAMESPACE)
        error(me ": Not usable in global namespace")
    name = $1
    # check for valid name
    if (!nam_valid_with_strict_as(name, strictp("name")))
        error(sprintf("%s: Invalid name '%s'", me, name))
    info__create_from_text(name, info)
    info__gate(OP_CREATE, TYPE_SYMBOL, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)
    if (flag_1true_p(info__get(info, "code"), FLAG_SYSTEM))
        error(sprintf("%s: Name '%s' is protected",
                      me, name))
    if (nam_ll_in(name, __namespace))
        error(sprintf("%s: Name '%s' already defined as a %s",
                      me, name, ppf__flag_type(info__get(info, "type"))))
    nam_ll_write(name, __namespace, TYPE_SYMBOL)
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
                            info, me)
{
    me = "@longdef1"            # ?
    dbg__print("sym", 5, "(parse__longdef) START dstblk=" curr_dstblk() ", mode=" ppf__mode(curr_atmode()) "; $0='" $0 "'")

    # Create two new blocks: one for the "longdef" block, other for definition body
    sym_block = blk_new(BLK_LONGDEF)
    dbg__print("sym", 5, "(parse__longdef) New block # " sym_block " type " ppf__block_type(blk_type(sym_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("sym", 5, "(parse__longdef) New block # " body_block " type " ppf__block_type(blk_type(body_block)))

    $1 = ""
    name = $2
    info__create_from_text(name, info)
    info__gate(OP_CREATE, PTYPE_SCALAR, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, "@longdef")
    blktab[sym_block, 0, "name"] = name
    blktab[sym_block, 0, "body_block"] = body_block
    blktab[sym_block, 0, "dstblk"] = body_block
    blktab[sym_block, 0, "valid"] = FALSE
    dbg__print_block("sym", 7, sym_block, "(parse__longdef) sym_block")
    stk_push(__parse_stack, sym_block) # Push it on to the parse_stack

    dbg__print("sym", 5, "(parse__longdef) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcmd
    dbg__print("sym", 5, "(parse__longdef) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error("[@longdef] Parse error")

    dbg__print("sym", 5, "(parse__longdef) END => " sym_block)
    return sym_block
}


function parse__endlongdef(    sym_block)
{
    dbg__print("sym", 3, sprintf("(parse__endlongdef) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_LONGDEF) != ERR_OKAY)
        error("[@endlongdef] Parse error; " __m2_msg)
    sym_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endlongdef) popped parse_stack => " sym_block)
    blktab[sym_block, 0, "valid"] = TRUE
    dbg__print("sym", 3, sprintf("(parse__endlongdef) END => %d", sym_block))
    return sym_block
}


function xeq__BLK_LONGDEF(longdef_block,
                          block_type, name, info, body_block, opm,
                          me)
{
    me = "@longdef2"            # ?
    block_type = blk_type(longdef_block)
    dbg__print("sym", 3, sprintf("(xeq__BLK_LONGDEF) START dstblk=%d, longdef_block=%d, type=%s",
                                 curr_dstblk(), longdef_block, ppf__block_type(block_type)))
    dbg__print_block("sym", 7, longdef_block, "(xeq__BLK_LONGDEF) longdef_block")
    if ((block_type != BLK_LONGDEF) ||
        (blktab[longdef_block, 0, "valid"] != TRUE))
        panic("(xeq__BLK_LONGDEF) Bad longdef_block config")

    name = blktab[longdef_block, 0, "name"]
    info__create_from_text(name, info)
    info__gate(OP_CREATE, PTYPE_SCALAR, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, "@longdef")

    body_block = blktab[longdef_block, 0, "body_block"]
    dbg__print_block("sym", 3, body_block, "(xeq__BLK_LONGDEF) body_block")
    sym_store(name, blk_to_string(body_block))
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
#       Undocumented - Reserved for internal use
#
#       @m2ctl booltest                 Scan boolean expr from user
#       @m2ctl dbg_max                  All 9s
#       @m2ctl dbg_namespace            Debug namespaces
#       @m2ctl dbg_params               Debug function parameters
#       @m2ctl dbg_reset                Reset all dbg levels to standard
#       @m2ctl dbg_ship_out
#       @m2ctl dbg_user                 Debug @newcmd, user_blocks
#       @m2ctl dbg_zero                 Clear debugging
#       @m2ctl dump_block BLOCK         Raw dump block #
#       @m2ctl dump_namtab              Dump of name table (non-system)
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
            #print("just read '" input "'")
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
            sym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, 9)

    } else if ($1 == "dbg_namespace") {
        enable_debugging()
        # Debug namespaces
        dbg__all_lev_zero()
        dbg__set_level("for",       5)
        dbg__set_level("namespace", 5)
        dbg__set_level("cmd",       5)
        dbg__set_level("nam",       3)
        dbg__set_level("sym",       5)

    } else if ($1 == "dbg_params") {
        enable_debugging()
        # Debug function params: help scan @foo a b c@ and @foo{a}{b}{c}@
        dbg__all_lev_zero()
        dbg__set_level("dosubs",    7)
        # dbg__set_level("namespace", 5)
        # dbg__set_level("cmd",       5)
        # dbg__set_level("nam",       3)
        dbg__set_level("sym",       5)

    } else if ($1 == "dbg_reset") {
        dbg__all_lev_standard()

    } else if ($1 == "dbg_ship_out") {
        enable_debugging()
        dbg__all_lev_zero()
        dbg__set_level("dosubs",    7)
        dbg__set_level("parse",   9)
        dbg__set_level("io",   5)
        dbg__set_level("ship_out",   9)
        dbg__set_level("stk", 5)

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
        nam_dump_namtab(PTYPE_ANY, FALSE)

    } else if ($1 == "dump_parse_stack") {
        dump_parse_stack()

    } else if ($1 == "incpath") {
        print_stderr("__inc_path = " __inc_path)

    } else if ($1 == "set_dbg") { # Set __DBG__[dsys] level directly
        dsys = $2                 # Note, does not affect __DEBUG__
        lev = $3
        print_stderr(sprintf("Setting __DBG__[%s] to %d", dsys, lev))
        dbg__set_level(dsys, lev)

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
function parse__newcmd(    name, user_block, body_block, pstat, nparam, p, pname,
                           me, info)
{
    me = "@newcmd"
    nparam = 0
    dbg__print("cmd", 5, "(parse__newcmd) START dstblk=" curr_dstblk() ", mode=" ppf__mode(curr_atmode()) "; $0='" $0 "'")

    raise_namespace()

    # Create two new blocks: one for the "new command" block, other for command body
    user_block = blk_new(BLK_USER)
    dbg__print("cmd", 5, "(parse__newcmd) New block # " user_block " type " ppf__block_type(blk_type(user_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("cmd", 5, "(parse__newcmd) New block # " body_block " type " ppf__block_type(blk_type(body_block)))

    $1 = ""
    name = $2
    while (match(name, "{[^}]*}")) {
        p = ++nparam
        pname = substr(name, RSTART+1, RLENGTH-2)
        dbg__print("cmd", 5, sprintf("(parse__newcmd) Parameter %d : %s",
                                     p, pname))
        blktab[user_block, p, "param_name"] = pname
        name = substr(name, 1, RSTART-1) substr(name, RSTART+RLENGTH)
    }
    #assert_cmd_okay_to_define(name, "@newcmd")
    info__create_from_text(name, info)
    info__gate(OP_CREATE, TYPE_COMMAND, info, __namespace, me, TRUE)

    blktab[user_block, 0, "name"] = name
    blktab[user_block, 0, "body_block"] = body_block
    blktab[user_block, 0, "dstblk"] = body_block
    blktab[user_block, 0, "valid"] = FALSE
    blktab[user_block, 0, "nparam"] = nparam
    dbg__print_block("cmd", 7, user_block, "(parse__newcmd) user_block")
    stk_push(__parse_stack, user_block) # Push it on to the parse_stack

    dbg__print("cmd", 5, "(parse__newcmd) CALLING parse()")
    pstat = parse() # parse() should return after it encounters @endcmd
    dbg__print("cmd", 5, "(parse__newcmd) RETURNED FROM parse() => " ppf__bool(pstat))
    if (!pstat)
        error(me ": Parse error")

    dbg__print("cmd", 5, "(parse__newcmd) END; user_block => " user_block)
    return user_block
}


function parse__endcmd(                     newcmd_block)
{
    dbg__print("cmd", 3, sprintf("(parse__endcmd) START dstblk=%d, mode=%s",
                                 curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_USER) != ERR_OKAY)
        error("[@endcmd] Parse error; " __m2_msg)
    newcmd_block = stk_pop(__parse_stack)
    dbg__print("parse", 7, "(parse__endcmd) popped parse_stack => " newcmd_block)
    blktab[newcmd_block, 0, "valid"] = TRUE
    lower_namespace()

    dbg__print("cmd", 3, sprintf("(parse__endcmd) END => %d", newcmd_block))
    dbg__print_block("parse", 7, newcmd_block, sprintf("newcmd block:"))
    return newcmd_block
}


function xeq__BLK_USER(newcmd_block,
                       block_type, name)
{
    block_type = blk_type(newcmd_block)
    dbg__print("cmd", 1, sprintf("(xeq__BLK_USER) START dstblk=%d, newcmd_block=%d, type=%s",
                                 curr_dstblk(), newcmd_block, ppf__block_type(block_type)))
    dbg__print_block("cmd", 7, newcmd_block, "(xeq__BLK_USER) newcmd_block")
    if ((block_type != BLK_USER) ||
        (blktab[newcmd_block, 0, "valid"] != TRUE))
        panic("(xeq__BLK_USER) Bad newcmd_block config")

    # Instantiate command, but do not run.  "@newcmd FOO" is just declaring FOO.
    # @FOO{...} actually ships it out (and is done under ship_out/xeq_user).
    name = blktab[newcmd_block, 0, "name"]
    dbg__print("cmd", 3, sprintf("(xeq__BLK_USER) name='%s', level=%d: TYPE_USER, value=%d",
                                 name, __namespace, newcmd_block))
    nam_ll_write(name, __namespace, TYPE_USER)
    cmd_ll_write(name, __namespace, newcmd_block)

    dbg__print("cmd", 1, "(xeq__BLK_USER) END")
}


function execute__user(user_invocation,
                       level, info, code,
                       old_level, user_block,
                       nitem, citem, name,
                       args, arg, narg, argval)
{
    dbg__print("xeq", 3, sprintf("(execute__user) START"))
    if (__xeq_ctl != XEQ_NORMAL) {
        dbg__print("xeq", 3, "(execute__user) NOP due to __xeq_ctl=" __xeq_ctl)
        return
    }

    # print_stderr(ppf__sepstr(user_invocation))
    nitem = split_subsep(user_invocation, citem)
    if (nitem < 2 || nitem != 2+citem[2])
        panic(sprintf("(execute__user) split_subsep() returned strange value: %d\n>>%s<<",
                      nitem, ppf__sepstr(user_invocation)))
    name = citem[1]

    # See if it's a user command
    if (nam__scan(name, info) == ERROR)
        error("(execute__user) Scan error, " __m2_msg)
    if ((level = nam__lookup(info)) == NAME_NOT_FOUND)
        error("(execute__user) nam__lookup failed")
    if (flag_1false_p((code = nam_ll_read(name, level)), TYPE_USER))
        panic("(execute__user) " name " seems to no longer be a command")

    user_block = cmd_ll_read(name, level)
    dbg__print_block("xeq", 7, user_block, "(execute__user) user_block")
    dbg__print_block("xeq", 7, blktab[user_block, 0, "body_block"], "(execute__user) body_block")

    old_level = __namespace
    execute__user_body(user_block, citem)
    if (__namespace != old_level)
        panic(sprintf("(execute__user) [@%s] user_block=%d: Namespace level mismatch; old_level=%d, __namespace=%d",
                      name, user_block, old_level, __namespace))
}


function execute__user_body(user_block, args,
                            block_type, new_level, i, p, body_block)
{
    block_type = blk_type(user_block)
    dbg__print("cmd", 3, sprintf("(execute__user_body) START dstblk=%d, user_block=%d, type=%s",
                                 curr_dstblk(), user_block, ppf__block_type(block_type)))
    dbg__print_block("cmd", 7, user_block, "(execute__user_body) user_block")
    if ((block_type != BLK_USER) ||
        (blktab[user_block, 0, "valid"] != TRUE))
        panic("(execute__user_body) Bad user_block config")
    body_block = blktab[user_block, 0, "body_block"]
    dbg__print_block("cmd", 7, body_block, "(execute__user_body) body_block")

    # Always raise namespace level (even if nparam == 0) because
    # user code might run @local.
    new_level = raise_namespace()

    # Evaluate arguments before any parameter instantiations.  It is
    # critical to do this first (and not all together in a loop as
    # before), because invoking nam_ll_write() before sym_ll_write()
    # will LOSE if a parameter has the same name as a global variable
    # due to namtab[] mismatch.
    for (i = 1; i <= blktab[user_block, 0, "nparam"]; i++)
        # +2 to skip past first two entries (cmdname, nargs)
        args[i + 2] = dosubs(args[i + 2])

    # Instantiate parameters
    for (i = 1; i <= blktab[user_block, 0, "nparam"]; i++) {
        p = blktab[user_block, i, "param_name"]
        nam_ll_write(p, new_level, TYPE_SYMBOL)
        sym_ll_write(p, "", new_level, args[i + 2])
        dbg__print("cmd", 6, sprintf("(execute__user_body) Setting param %s to '%s'", p, args[i]))
    }

    dbg__print("cmd", 5, sprintf("(execute__user_body) CALLING execute__block(%d)", body_block))
    execute__block(body_block)
    dbg__print("cmd", 5, sprintf("(execute__user_body) RETURNED FROM execute__block()"))
    lower_namespace()

    # If we've been asked to return, well now we have
    if (__xeq_ctl == XEQ_RETURN)
        __xeq_ctl = XEQ_NORMAL
    # If things are still not normal, that's a problem
    if (__xeq_ctl != XEQ_NORMAL)
        panic("(xeq_cmd__return) __xeq_ctl is not normal")

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
    return sprintf("  name       : %s\n" \
                   "  valid      : %s\n" \
                   "  body_block : %d\n" \
                   "  nparam     : %d\n" \
                   "%s",
                   blktab[blknum, 0, "name"],
                   ppf__bool(blktab[blknum, 0, "valid"]),
                   blktab[blknum, 0, "body_block"],
                   nparam,
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
function xeq_cmd__nextfile(cmd, cmdline,
                           readstat, save_line, save_lineno)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__nextfile) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))
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
#       @  N U L L
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#*****************************************************************************
# @null         NAME
function xeq_cmd__null(cmd, cmdline,
                       name, info, me)
{
    me = "@" cmd
    $0 = cmdline
    dbg__print("xeq", 2, sprintf("(xeq_cmd__null) START cmdline='%s'",
                                  cmdline))
    if (NF == 0)
        error("Bad parameters:" $0)

    name = $1
    info__create_from_text(name, info)
    info__gate(OP_CREATE, PTYPE_SCALAR, info, __namespace, me, TRUE)
    # assert_syminfo_okay_to_define(info, me)
    # XXX No checking, dangerous!
    sym_store(name, "")
    dbg__print("xeq", 2, "(xeq_cmd__null) END")
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
                           me)
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
    # assert_syminfo_okay_to_define(info, me)
    # assert_syminfo_defined(info, me)
    # assert_syminfo_unprotected(info, me)
    # code = info__get(info, "code")
    # if (flag_allfalse_p(code, TYPE_ARRAY TYPE_SYMBOL))
    #     error("@readonly: Name must be symbol or array")
    # if (flag_1true_p(code, FLAG_SYSTEM))
    #     error("@readonly: Name protected")
#NEW:
    info__create_from_text(name, info)
    #info__gate(OP_UPDATE, TYPE_ARRAY TYPE_LIST TYPE_SYMBOL, info, __namespace, me, TRUE)
    info__gate(OP_UPDATE, PTYPE_SCALAR, info, __namespace, me, TRUE)
    ilevel = info__get(info, "level")
    if (ilevel == NAME_NOT_FOUND)
        panic("(xeq_cmd__readonly) gate(OP_UPDATE) passed but level was name_not_found")
    icode = info__get(info, "code")
    nam_ll_write(name, ilevel, flag_set_clear(icode, FLAG_READONLY))
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
function xeq_cmd__return(cmd, cmdline,
                        level, block, block_type)
{
    # Logical check
    if (__xeq_ctl != XEQ_NORMAL)
        panic("(xeq_cmd__return) __xeq_ctl is not normal")

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
function xeq_cmd__sequence(cmd, cmdline,
                           id, level, info, action, arg, saveline,
                           me)
{
    me = "@" cmd
    $0 = cmdline
    dbg__print("seq", 2, sprintf("(xeq_cmd__sequence) START dstblk=%d, cmd=%s, cmdline='%s'",
                                curr_dstblk(), cmd, cmdline))
    if (NF == 0)
        error("Bad parameters: Missing sequence name:" $0)
    id = $1
    level = info__create_from_text(id, info)
    #assert_seqinfo_valid_name(info, me)

    if (NF == 1)
        $2 = "create"
    action = $2
    if (action != "create" && !seqinfo_defined_p(info))
        error("Name '" id "' not defined [sequence]:" $0)
    if (NF == 2) {
        if (action == "create") {
            # assert_seq_okay_to_define(id, "@" cmd)
            info__gate(OP_CREATE, TYPE_SEQUENCE, info, GLOBAL_NAMESPACE, me, TRUE)
            #
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
            seqtab[id, "fmt"] = arg
        } else if (action == "setincr") {
            # setincr N :: Set increment value to N.
            if (!integerp(arg))
                error(sprintf("@sequence setincr: Value '%s' must be numeric", arg))
            if (arg+0 == 0)
                error(sprintf("@sequence setincr: Bad parameters: %s", saveline))
            seqtab[id, "incr"] = int(arg)
        } else if (action == "setinit") {
            # setinit N :: Set initial  value to N.  If current
            # value == old init value (i.e., never been used), then set
            # the current value to the new init value also.  Otherwise
            # current value remains unchanged.
            if (!integerp(arg))
                error(sprintf("@sequence setinit: Value '%s' must be numeric", arg))
            if (seq_ll_read(id) == seqtab[id, "init"])
                seq_ll_write(id, int(arg))
            seqtab[id, "init"] = int(arg)
        } else if (action == "setval") {
            # setval N :: Set counter value directly to N.
            if (!integerp(arg))
                error(sprintf("@sequence setval: Value '%s' must be numeric", arg))
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
function xeq_cmd__shell(cmd, cmdline,
                        delim, save_line, save_lineno, shell_text_in, input_file,
                        output_text, output_file, sendto, getstat,
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

    input_file  = mktemp(tmpdir() "m2-shell.in.XXXXXX")
    output_file = mktemp(tmpdir() "m2-shell.out.XXXXXX")
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
            warn(me ": Error reading file '" output_file "'")
        if (getstat != OKAY)
            break
        output_text = output_text line TOK_NEWLINE # Read a line
    }
    close(output_file)
    if ("rm" in PROG) {
        exec_prog_cmdline("rm", ("-f " input_file))
        exec_prog_cmdline("rm", ("-f " output_file))
    } else if (debugging_enabled_p()) {
        warn(me ": PROG[rm] not defined; '"  input_file "' not deleted")
        warn(me ": PROG[rm] not defined; '" output_file "' not deleted")
    }
    output_text = chomp(output_text)
    dbg__print("cmd", 5, sprintf("(xeq_cmd__shell) output_text='%s'", output_text))
    if (!emptyp(output_text))
        ship_out(OBJ_TEXT, output_text)
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
                        wantfs, tmpfs, me)
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
#    print_stderr("ABOUT TO ASSERT")
    # assert_list_okay_to_define(lis, me)
    # Since assert_array_okay_to_define() passed,
    # these calls won't fail either...
    # nam__scan(lis, info)
    # level = nam__lookup(info)
    level = info__create_from_text(lis, info)
    info__gate(OP_UPDATE, TYPE_LIST, info, __namespace, me, TRUE)

    code = info["code"]
    dbg__print("xeq", 5, sprintf("(xeq_cmd__split) code=%s", code))
    lis_clear(lis, level, code)

    # Create a new Agg block
    agg_block = blk_new(BLK_AGG)
    dbg__print("parse", 5, sprintf("(xeq_cmd__split) symtab['%s','%s',%d,'agg_block'] = %d",
                                 lis, "", level, agg_block))
    symtab[lis, "", level, "agg_block"] = agg_block
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
    sym_ll_write("__SYSVAL__", "", GLOBAL_NAMESPACE, rc)
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
        sym_ll_write("__TRACEMODE__", "", GLOBAL_NAMESPACE, TRACE_DEFAULT_SET)
        return
    }

    letters = $1
    if (letters !~ /^[-+aeiflmpstTV][-+aeiflmpstTV]*$/)
        error("@tracemode: Bad parameters")

    add_rem = TRUE              # add_rem == TRUE  -> Adding flags
                                # add_rem == FALSE -> Removing flags
    if (first(letters) != "+" && first(letters) != "-")
        # Not a + or -, so override old flags
        sym_ll_write("__TRACEMODE__", "", GLOBAL_NAMESPACE, EMPTY)
    for (i = 1; i <= length(letters); i++) {
        flag = substr(letters, i, 1)
        if (flag == "+")
            add_rem = TRUE
        else if (flag == "-")
            add_rem = FALSE
        else {
            if (flag == TRACE_SET_ON)
                sym_ll_write("__TRACE__", "", GLOBAL_NAMESPACE, add_rem)
            else if (flag == TRACE_WILDCARD_ALL_FLAGS) {
                if (add_rem)
                    sym_ll_write("__TRACE__", "", GLOBAL_NAMESPACE, add_rem)
                sym_ll_write("__TRACEMODE__", "", GLOBAL_NAMESPACE, add_rem ? TRACE_ALL_SET : EMPTY)
            } else
                sym_ll_write("__TRACEMODE__", "", GLOBAL_NAMESPACE,
                             flag_set_clear(sym_ll_read("__TRACEMODE__", "", GLOBAL_NAMESPACE),
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
                           i, info, sym, level, code)
{
    dbg__print("trace", 3, sprintf("(xeq_cmd__traceoff) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0) {
        # Clear "t" trace flag
        sym_ll_write("__TRACEMODE__", "", GLOBAL_NAMESPACE,
                     flag_set_clear(sym_ll_read("__TRACEMODE__", "", GLOBAL_NAMESPACE),
                                    EMPTY, TRACE_ALL))
        # Set __TRACE__ to False
        sym_ll_write("__TRACE__", "", GLOBAL_NAMESPACE, FALSE)
    } else {
        # Clear FLAG_TRACING for every symbol mentioned
        i = 0
        while (++i <= NF) {
            sym = $i
            if (nam__scan(sym, info) == ERROR)
                error("(xeq_cmd__traceoff) Scan error; " __m2_msg)
            if ((level = nam__lookup(info)) == NAME_NOT_FOUND)
                error("(xeq_cmd__traceoff) nam__lookup(info) failed")
            code = nam_ll_read(sym, level)
            nam_ll_write(sym, level, flag_set_clear(code, EMPTY, FLAG_TRACING))
        }
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
                          i, info, sym, level, code)
{
    dbg__print("trace", 3, sprintf("(xeq_cmd__traceon) START; cmdline='%s'", cmdline))
    $0 = cmdline
    if (NF == 0) {
        # Set "t" trace flag
        sym_ll_write("__TRACEMODE__", "", GLOBAL_NAMESPACE,
                     flag_set_clear(sym_ll_read("__TRACEMODE__", "", GLOBAL_NAMESPACE),
                                    TRACE_ALL))
    } else {
        # Set FLAG_TRACING for every symbol mentioned
        i = 0
        while (++i <= NF) {
            sym = $i
            if (nam__scan(sym, info) == ERROR)
                error("(xeq_cmd__traceon) Scan error; " __m2_msg)
            if ((level = nam__lookup(info)) == NAME_NOT_FOUND)
                error("(xeq_cmd__traceon) nam__lookup(info) failed")
            code = nam_ll_read(sym, level)
            nam_ll_write(sym, level, flag_set_clear(code, FLAG_TRACING))
        }
    }
    sym_ll_write("__TRACE__", "", GLOBAL_NAMESPACE, TRUE)
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
                           x, k, del_list,
                           me)
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
    if ((nparts = nam__scan(name, info)) == ERROR)
        error("[@undefine] Scan error, " __m2_msg)
    if ((level = nam__lookup(info)) == NAME_NOT_FOUND) {
        error("(xeq_cmd__undefine) '" name "' not found")
    }

    if ((type = info__get(info, "type")) == TYPE_SYMBOL) {
        name = info__get(info, "name")
        # assert_syminfo_unprotected(info, "@" cmd)
        # System symbols, even unprotected ones -- despite being subject
        # to user modification -- cannot be undefined.
        # if (nam_system_p(name))
        #     error("Name '" name "' not available:" $0)
        if (info__get(info, "protected"))
            error(me ": Name '" name "' is protected")

        dbg__print("sym", 3, ("About to sym_destroy('" name "')"))
        sym_destroy(name, info["key"], info["level"])

    } else if (type == TYPE_ARRAY) {
        for (k in symtab) {
            split(k, x, SUBSEP)
            if (x[1] == name && x[3]+0 == info["level"])
                del_list[x[1], x[2], x[3], x[4]] = TRUE
        }
        for (k in del_list) {
            split(k, x, SUBSEP)
            dbg__print("sym", 3, sprintf("(xeq_cmd__undefine) Delete symtab['%s', '%s', %d, %s]",
                                         x[1], x[2], x[3], x[4]))
            delete symtab[x[1], x[2], x[3], x[4]]
        }

    } else if (type == TYPE_SEQUENCE)
        seq_destroy(name)
    else if (type == TYPE_USER)
        cmd_destroy(name)
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
        # @undivert N1 N2... : process one or more streams
        i = 0
        while (++i <= NF) {
            stream = dosubs($i)
            if (!integerp(stream) || stream <= 0)
                # @undivert -1 or 0 => no effect
                continue
            if (stream > MAX_STREAM)
                error("Bad parameters:" $0)
            dbg__print("divert", 5, sprintf("(xeq_cmd__undivert) CALLING undivert(%d)", stream))
            undivert(stream)
        }
    } else if (cmdline ~ "^[0-9]+[ \t]+.*[^0-9]") {
        # @undivert N FILE : process one stream, output to FILE
        if (secure_level() >= SEC_SECURE)
            security_violation("@undivert: Output file forbidden")
        stream = $1
        if (stream > MAX_STREAM)
            error("Bad parameters:" $0)
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

    raise_namespace()

    # Create two new blocks: one for while_block, other for true branch
    while_block = blk_new(BLK_WHILE)
    dbg__print("while", 5, "(parse__while) New block # " while_block " type " ppf__block_type(blk_type(while_block)))
    body_block = blk_new(BLK_AGG)
    dbg__print("while", 5, "(parse__while) New block # " body_block " type " ppf__block_type(blk_type(body_block)))

    blktab[while_block, 0, "condition"] = $0
    blktab[while_block, 0, "init_negate"] = (name == "@until")
    blktab[while_block, 0, "body_block"] = body_block
    blktab[while_block, 0, "dstblk"] = body_block
    blktab[while_block, 0, "valid"]      = FALSE
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
                               curr_dstblk(), ppf__mode(curr_atmode())))
    if (check__parse_stack(BLK_WHILE) != ERR_OKAY)
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
    dbg__print("while", 3, sprintf("(xeq__BLK_WHILE) START dstblk=%d, while_block=%d, type=%s",
                               curr_dstblk(), while_block, ppf__block_type(block_type)))

    dbg__print_block("while", 7, while_block, "(xeq__BLK_WHILE) while_block")
    if ((block_type != BLK_WHILE) || \
        (blktab[while_block, 0, "valid"] != TRUE))
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
        raise_namespace()
        dbg__print("while", 5, sprintf("(xeq__BLK_WHILE) CALLING execute__block(%d)",
                                       body_block))
        execute__block(body_block)
        dbg__print("while", 5, sprintf("(xeq__BLK_WHILE) RETURNED FROM execute__block()"))
        lower_namespace()

        condval = evaluate_boolean(condition, negate)
        dbg__print("while", 3, sprintf("(xeq__BLK_WHILE) Repeat evaluate_boolean('%s') => %s", condition, ppf__bool(condval)))
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
function xeq_cmd__wrap(cmd, cmdline,
                       rstat)
{
    dbg__print("parse", 5, sprintf("(xeq_cmd__wrap) START dstblk=%d, mode=%s, $0='%s'",
                                curr_dstblk(), ppf__mode(curr_atmode()), $0))

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
                                     dstblk, __blk_label[obj_type], obj))
    if (dstblk < 0) {
        dbg__print("ship_out", 3, "(ship_out) END, because dstblk <0")
        return
    }
    if (dstblk > MAX_STREAM) {
        dbg__print("ship_out", 5, sprintf("(ship_out) END Appending obj '%s' to block %d", obj, dstblk))
        blk_append(dstblk, obj_type, obj)
        return
    }
    if (dstblk != TERMINAL)
        panic(sprintf("(ship_out) dstblk is %d, not zero!", dstblk))

    # dstblk is zero, so obj must be executed (or text printed)
    if (obj_type == OBJ_BLKNUM) {
        dbg__print("ship_out", 5, sprintf("(ship_out) CALLING execute__block(%d)", obj))
        execute__block(obj)
        dbg__print("ship_out", 5, sprintf("(ship_out) RETURNED FROM execute__block"))

    } else if (obj_type == OBJ_CMD) {
        name = extract_cmd_name(obj)
        sub(/^[ \t]*[^ \t]+[ \t]*/, "", obj)
        # Unlike every other command, @wrap ships out its line literally here.
        # Function end_program(), which handles wrapped text, calls dosubs().
        if (name != "wrap") {
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
                      block, ppf__block_type(blk_type(block))))

    lim = blktab[block, 0, "count"]
    for (i = 1; i <= lim; i++) {
        slot_type = blk_ll_slot_type(block, i)
        if (slot_type != OBJ_TEXT)
            panic(sprintf("(ship_out_to_file) Block %d slot %d has type %s, not TEXT",
                          block, i, ppf__block_type(slot_type)))

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
function _c3_expr(    var, e, op1, op2, m2,
                      info)
{
    if (match(substr(_c3__Sexpr, _c3__f), /^[A-Za-z#_][A-Za-z#_0-9]*=[^=]/)) {
        var = _c3_advance()
        sub(/=.*$/, "", var)
        info__create_from_text(var, info)
        # assert_syminfo_okay_to_define(info, "@expr")
        info__gate(OP_UPDATE, TYPE_SYMBOL, info, __namespace, "@expr", TRUE)
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
        error(sprintf("Unknown function '%s':%s",
                      (last(fun) == "(") ? chop(fun) : fun, $0))
    }

    # (expr) | function(expr) | function(expr,expr)
    if (match(e, /^([A-Za-z#_][A-Za-z#_0-9]+)?\(/)) {
        fun = _c3_advance()
        # These are for numeric functions only, not strings/symbols
        if (fun ~ /^(abs|acos|asin|ceil|cos|deg|exp|floor|int|lg|ln|log(10)?|rad|randint|round|sign|sin|sqrt|srand|tan)?\(/) {
            e = _c3_expr()
            e = _c3_calculate_function(fun, e)
        } else if (fun ~ /^defined\(/) {
            e2 = substr(e, 9, length(e)-9)
            dbg__print("expr", 7, sprintf("defined(): e2='%s'", e2))
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
        } else if (seqinfo_valid_p(info, e2) && seqinfo_defined_p(info, e2)) {
            e = seq_ll_read(e2)
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
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return atan2(sqrt(1 - e^2), e) }
    if (fun == "asin(")    { if (e < -1 || e > 1)
                                 error(sprintf("%s%d): Math expression error", fun, e))
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
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return log(e) / LOG2 }
    if (fun == "log(" || fun == "ln(")
                           { if (e <= 0)
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return log(e) }
    if (fun == "log10(")   { if (e <= 0)
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return log(e) / LOG10 }
    if (fun == "rad(")     { return e * (TAU / 360) }
    if (fun == "randint(") { if (e < 1)
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return randint2(1,int(e)) }
    if (fun == "round(")   { return round(e) }
    if (fun == "sign(")    { return (e > 0) - (e < 0) } # cf _The Elements of Programming Style, 2ed_, Kernighan & Plauger, 1974, pp. 1-2
    if (fun == "sin(")     { return sin(e) }
    if (fun == "sqrt(")    { if (e < 0)
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return sqrt(e) }
    if (fun == "srand(")   { return srand(e) }
    if (fun == "tan(")     { c = cos(e)
                             if (c == 0)
                                 error(sprintf("%s%d): Math expression error", fun, e))
                             return sin(e) / c }
    error(sprintf("@expr: Unknown function '%s'",
                  (last(fun) == "(") ? chop(fun) : fun))
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
    error(sprintf("@expr: Unknown function '%s'",
                  (last(fun) == "(") ? chop(fun) : fun))
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
#               while R contains an "@" sign do
#                   let R = A @ B; set L = L A and R = B
#                   if R contains no "@" then
#                       L = L "@"
#                       break
#                   let R = A @ B; set M = A and R = B
#                   if M is in SymTab then
#                       R = SymTab[M] R
#                   else
#                       L = L "@" M
#                       R = "@" R
#               return L R
#
#       Note use of macro_*() functions, described below.
#
#*****************************************************************************
function dosubs(s,
                expand, i, j, L, M, nparam, p, pval, param, R, fn,
                x, inc_dec, pre_post, subcmd, br, lfn, incr, wrkm,
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
        dbg__print("dosubs", 7, (sprintf("(dosubs) Top of loop: L='%s', R='%s'", L, R)))
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

        macro_setup(macro, M)
        macro_expand(macro)
        if (macro["okay"] == TRUE) {
            # Kluge for @srem ...@ to remove preceding whitespace
            if (macro["fn"] == "srem")
                sub(/[ \t]+$/, "", L)
            trace(TRACE_EXPANSION, macro["fn"], sprintf("[Expand] @%s@ => '%s'",
                                                        macro["urtext"], macro["expansion"]))
            R = macro["expansion"] R
        } else {
            # If undefined symbol, throw an error (if __STRICT__[def] is
            # True, the default) or pass through the urtext (M) unchanged.
            if (strictp("def"))
                error(sprintf("@%s@: Name '%s' not defined",
                              macro["urtext"], macro["fn"]))
            L = L TOK_AT M
            R =   TOK_AT R
        }
        i = index(R, TOK_AT)
    }

    dbg__print("dosubs", 3, sprintf("(dosubs) END; Out of loop => '%s'", L R))
    return L R
}


# macro["expansion"] = macro expansion text
# macro["fn"]        = function name, 1st param
# macro["okay"]      = TRUE/FALSE
# macro["urtext"]    = original M text
#
# macro_expand() does the real work of transforming specific macro-invoking
# text from its original call to its expanded form.  It expects its argument
# to be something it can work on.  In contrast, dosubs() is much more
# laissez-faire -- it is given some text to scan, from somewhere, but if
# the @ signs don't quite work out, no worries.
function macro_setup(macro, urtext)
{
    macro["okay"] = FALSE
    macro["urtext"] = urtext
    macro["fn"] = macro["expansion"] = EMPTY
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
                      x, inc_dec, pre_post, subcmd, br, lfn, incr, wrkm,
                      fninfo, level)
{
    M = macro["urtext"]
    nparam = split(M, param)
    fn = param[1]
    macro["fn"] = fn

    # Check for @foo{...} -- isolate fn to scan @foo{a}{b}{c}...@ better
    if ((br = index(fn, TOK_LBRACE)) > 0) {
        fn = substr(fn, 1, br-1)
        dbg__print("dosubs", 6, sprintf("(macro_expand) fn='%s'", fn))

        # Re-create nparam and param[] according to braces,
        # not split() on whitespace
        split("", param)       # Start by deleting all entries
        param[nparam = 0] = fn # 1st element is function name
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
            print_debugfile("(macro_expand) nparam=" nparam)
            for (x in param)
                print_debugfile(sprintf("(macro_expand) param[%d] = '%s'", x, param[x]))
            print_debugfile("(macro_expand) End param[]")
        }
    } else {
        dbg__print("dosubs", 5, "(macro_expand) No brace; fn='" fn "'")
        nparam--
        dbg__print("dosubs", 7, "(macro_expand) nparam=" nparam)
        for (j = 1; j <= nparam; j++)
            param[j] = param[j+1]
        delete param[nparam + 1]
        param[0] = fn
        if (dbg__sys_level_p("dosubs", 7)) {
            for (x in param)
                print_debugfile(sprintf("(macro_expand) param[%d] = '%s'", x, param[x]))
            print_debugfile("(macro_expand) End param[]")
        }
    }
    lfn = length(fn)

    dbg__print("dosubs", 6, sprintf("(macro_expand) fn=%s, nparam=%d; M='%s", fn, nparam, M))

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
    #print_stderr("(macro_expand) fninfo[" info__get(fninfo, "name") "] => " info__get(fninfo, "type"))

    if (nam_ll_in(fn, GLOBAL_NAMESPACE) &&
        flag_1true_p((nam_ll_read(fn, GLOBAL_NAMESPACE)), TYPE_FUNCTION)) {
        # Quick check to make sure fninfo is okay
        if (info__get(fninfo, "type") != TYPE_FUNCTION)
            panic("(macro_expand) not TYPE_FUNCTION?")
        if (fn == "basename")
            macro_set_expansion(macro, xeq_fn__basename(fn, M, nparam, param))
        else if (fn == "boolval")
            macro_set_expansion(macro, xeq_fn__boolval(fn, M, nparam, param))
        else if (fn == "chr")
            macro_set_expansion(macro, xeq_fn__chr(fn, M, nparam, param))
        else if (fn == "date"     || fn == "epoch" ||
                 fn == "strftime" || fn == "time"  ||
                 fn == "tz"       || fn == "utc")
            macro_set_expansion(macro, xeq_fn__date(fn, M, nparam, param))
        else if (fn == "dirname")
            macro_set_expansion(macro, xeq_fn__dirname(fn, M, nparam, param))
        else if (fn == "divlines")
            macro_set_expansion(macro, xeq_fn__divlines(fn, M, nparam, param))
        else if (fn == "dow")
            macro_set_expansion(macro, xeq_fn__dow(fn, M, nparam, param))
        else if (fn == "executable" || fn == "sexecutable")
            macro_set_expansion(macro, xeq_fn__executable(fn, M, nparam, param))
        else if (fn == "expr" || fn == "sexpr")
            macro_set_expansion(macro, xeq_fn__expr(fn, M, nparam, param))
        else if (fn == "format")
            macro_set_expansion(macro, xeq_fn__format(fn, M, nparam, param))
        else if (fn == "getenv" || fn == "sgetenv")
            macro_set_expansion(macro, xeq_fn__getenv(fn, M, nparam, param))
        else if (fn == "gregdate")
            macro_set_expansion(macro, xeq_fn__gregdate(fn, M, nparam, param))
        else if (fn == "ifdef" || fn == "ifndef")
            macro_set_expansion(macro, xeq_fn__ifdef(fn, M, nparam, param))
        else if (fn == "ifelse")
            macro_set_expansion(macro, xeq_fn__ifelse(fn, M, nparam, param))
        else if (fn == "ifx")
            macro_set_expansion(macro, xeq_fn__ifx(fn, M, nparam, param))
        else if (fn == "index")
            macro_set_expansion(macro, xeq_fn__index(fn, M, nparam, param))
        else if (fn == "join" || fn == "sjoin")
            macro_set_expansion(macro, xeq_fn__join(fn, M, nparam, param))
        else if (fn == "left")
            macro_set_expansion(macro, xeq_fn__left(fn, M, nparam, param))
        else if (fn == "ljust"  || fn == "rjust"  || fn == "center" || \
                 fn == "sljust" || fn == "srjust" || fn == "scenter")
            macro_set_expansion(macro, xeq_fn__lrc(fn, M, nparam, param))
        else if (fn == "mid" || fn == "substr")
            macro_set_expansion(macro, xeq_fn__mid(fn, M, nparam, param))
        else if (fn == "mjd")
            macro_set_expansion(macro, xeq_fn__mjd(fn, M, nparam, param))
        else if (fn == "ord")
            macro_set_expansion(macro, xeq_fn__ord(fn, M, nparam, param))
        else if (fn == "rem" || fn == "srem")
            macro_set_expansion(macro, EMPTY)
        else if (fn == "right")
            macro_set_expansion(macro, xeq_fn__right(fn, M, nparam, param))
        else if (fn == "rot13")
            macro_set_expansion(macro, xeq_fn__rot13(fn, M, nparam, param))
        else if (fn == "space" || fn == "spaces" ||
                 fn == "tab"   || fn == "tabs")
            macro_set_expansion(macro, xeq_fn__spaces(fn, M, nparam, param))
        else if (fn == "lc" || fn == "len" || fn == "uc")
            macro_set_expansion(macro, xeq_fn__str_fn(fn, M, nparam, param))
        else if (fn == "trim" || fn == "ltrim" || fn == "rtrim")
            macro_set_expansion(macro, xeq_fn__trim(fn, M, nparam, param))
        else if (fn == "uuid")
            macro_set_expansion(macro, uuid())
        else if (fn == "xbasename" || fn == "xdirname")
            macro_set_expansion(macro, xeq_fn__xname(fn, M, nparam, param))
        else
            panic("(macro_expand) Function '" fn "' not handled")

    # Check if it's an array
    } else if (sym_valid_p(fn) && arrayp(fn)) {
        macro_set_expansion(macro, sym_fetch(fn))

    # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
    } else if (sym_valid_p(fn) && (sym_defined_p(fn) || sym_deferred_p(fn))) {
        macro_set_expansion(macro, substitute_params(sym_fetch(fn), nparam, param))

    # Check if it's a sequence
    } else if (seq_valid_p(fn) && seq_defined_p(fn)) {
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
            incr = seqtab[fn, "incr"]
            # Handle prefix increment/decrement
            if (pre_post == -1)
                seq_ll_incr(fn, incr * inc_dec)
            # Insert current value with desired formatting
            macro_set_expansion(macro, sprintf(seqtab[fn, "fmt"], seq_ll_read(fn)))
            # Handle postfix increment/decrement
            if (pre_post == +1)
                seq_ll_incr(fn, incr * inc_dec)
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
                    macro_set_expansion(macro, seq_ll_read(fn))
                } else if (subcmd == "nextval") {
                    # - nextval :: Increment and return new value of
                    # counter.  No prefix/suffix.
                    seq_ll_incr(fn, seqtab[fn, "incr"])
                    macro_set_expansion(macro, seq_ll_read(fn))
                } else
                    error("Bad parameters in '" M "':" $0)
            } else {
                # These take one or more params.  Nothing here!
                error("Bad parameters in '" M "':" $0)
            }
        }

    # Check fninfo for ARRAY[] or LIST[]
    } else if ( \
        info__get(fninfo, "valid") == TRUE &&
        (info__get(fninfo, "type") == TYPE_ARRAY || info__get(fninfo, "type") == TYPE_LIST) &&
        info__get(fninfo, "nparts") == 2 &&
        length(info__get(fninfo, "key")) > 0 &&
        info__get(fninfo, "level") != NAME_NOT_FOUND) {

        macro_set_expansion(macro, array_deref_info(fninfo, "@" M "@"))

    # Check fninfo for ARRAY or LIST
    } else if ( \
        info__get(fninfo, "valid") == TRUE &&
        (info__get(fninfo, "type") == TYPE_ARRAY || info__get(fninfo, "type") == TYPE_LIST) &&
        info__get(fninfo, "nparts") == 1 &&
        length(info__get(fninfo, "key")) == 0 &&
        info__get(fninfo, "level") != NAME_NOT_FOUND) {

        macro_set_expansion(macro, idx__size(info__get(fninfo, "name"), level, info__get(fninfo, "code")))
    }
}


# Use this macro[] array to control macro expansion results due to the
# need to track two return values: whether the expansion went "okay" and
# what the "expansion" text actually is.
function macro_setup(macro, urtext)
{
    macro["okay"] = FALSE
    macro["urtext"] = urtext
    macro["fn"] = macro["expansion"] = EMPTY
}


function macro_set_expansion(macro, expanded_text)
{
    macro["okay"] = TRUE
    macro["expansion"] = expanded_text
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
                         p, result)
{
    if (nparam == 0)
        # In an effort to spread a bit more entropy in the universe,
        # if you don't give an argument to boolval then you get
        # True 50% of the time and False the other 50%.
        result = sym_ll_read("__FMT__", rand() < 0.50)
    else {
        p = param[1]
        # Always accept your current representation of True or False
        # to actually be true or false without further evaluation.
        if (p == sym_ll_read("__FMT__", TRUE) ||
            p == sym_ll_read("__FMT__", FALSE))
            result = p
        else if (sym_valid_p(p)) {
            # It's a valid name -- now see if it's defined or not.
            # If not, check if we're in strict mode (error) or not.
            if (sym_defined_p(p))
                result = sym_ll_read("__FMT__", sym_true_p(p))
            else if (strictp("bool"))
                error("Name '" p "' not defined (__STRICT__[bool] is True):" $0)
            else
                result = sym_ll_read("__FMT__", FALSE)
        } else
            # It's not a symbol, so use its value interpreted as a boolean
            result = sym_ll_read("__FMT__", to_bool(p))  # !!p)
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
                      y, cmdline, result)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation(sprintf("@%s@: Forbidden", fn))
    if (! ("date" in PROG))
        error(sprintf("%s: PROG[date] not defined, cannot tell time", "@" M "@"))
    if (fn == "strftime" && nparam == 0)
        error("Bad parameters in '" M "':" $0)
    y = fn == "strftime" ? substr(M, length(fn)+2) \
        : sym_ll_read("__FMT__", fn)
    gsub(/"/, "\\\"", y)
    cmdline = build_prog_cmdline("date", "+\"" y "\"", MODE_IO_CAPTURE)
    if (fn == "utc")
        cmdline = "TZ=UTC " cmdline
    cmdline | getline result
    close(cmdline)
    return result
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
#       divlines : Number of lines in a stream, or zero if empty
#
#*****************************************************************************
# @divlines STREAM@
function xeq_fn__divlines(fn, M, nparam, param,
                          stream)
{
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    stream = param[1]
    if (! integerp(stream))
        error("Parameter must be integer: '" M "':" $0)
    if (stream <= TERMINAL) return 0
    if (stream > MAX_STREAM)
        error(sprintf("@%s@: Bad parameters", fn))
    return blktab[stream, 0, "count"]
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
#       @  E X E C U T A B L E  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       executable : Use sh command -v to return path to executable
#
#*****************************************************************************
# @executable PROG@
function xeq_fn__executable(fn, M, nparam, param,
                            p, silent, cmdline, result)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation(sprintf("@%s@: Forbidden", fn))
    # S variant won't warn about not being found
    silent = first(fn) == "s"
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]

    cmdline = build_prog_cmdline("sh", sprintf("-c 'command -v %s' 2>%s", p, NULL))
    cmdline | getline result
    close(cmdline)
    if (result == EMPTY && !silent)
        warn(sprintf("@%s %s@: Command not found", fn, p))
    return result
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
    sub(/^s?expr[ \t]*/, "", M) # clean up expression to evaluate
    result = calc3_eval(M)
    dbg__print("expr", 3, sprintf("(xeq_fn__expr) expr{%s} = %s", M, result))
    sym_ll_write("__EXPR__", "", GLOBAL_NAMESPACE, result+0)
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
# @format FMT SYM...@
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
#       @  G E T E N V  @
#
#       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
#       getenv: Get environment variable
#       sgetenv
#         @getenv HOME@ => /home/user
#
#       "silent" getenv returns empty string for non-existent variable,
#       regardless of strict setting.
#
#*****************************************************************************
# @getenv ENV@
function xeq_fn__getenv(fn, M, nparam, param,
                        p, silent)
{
    silent = first(fn) == "s"
    if (nparam != 1)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_valid_env_var_name(p, "@" M "@")
    if (p in ENVIRON)
        return ENVIRON[p]
    if (strictp("env") && !silent)
        error("Environment variable '" p "' not defined (__STRICT__[env] is True):" $0)
    return ""
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
    M = substr(M, 7)    # strip away "ifelse"
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
# @{s,}join LIS [FS]
function xeq_fn__join(fn, M, nparam, param,
                      info, nparts, level, s, lis, fs, fslen, silent,
                      code, size, k, x, keys, i, agg_block, me)
{
    me = "@" M "@"
    # S variant appends a final separator as a terminator
    silent = first(fn) == "s"
    if (nparam == 0)
        error(sprintf("%s: Bad parameters", me))
    lis = param[1]

    level = info__create_from_text(lis, info)
    info__gate(OP_READ, PTYPE_IDXABLE, info, level, me, TRUE)

    # # TODO Need real checks here!
    # assert_sym_valid_name(lis, me)
    # assert_list_defined(lis, me)

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
    size = idx__size(lis, level, code)

    s = ""
    if (size > 0) {
        # Build return string
        if (info__get(info, "type") == TYPE_LIST) {
            # It's a block array - Get its agg_block
            if (! ((lis, "", level, "agg_block") in symtab))
                panic(sprintf("(xeq_fn__join) Could not find ['%s','%s',%d,'agg_block'] in symtab",
                              lis, "", level))
            agg_block = symtab[lis, "", level, "agg_block"]
            # Inject the values
            for (i = 1; i <= size; i++) {
                # Make sure slot holds text, which it pretty much has to
                if (blk_ll_slot_type(agg_block, i) != OBJ_TEXT)
                    panic(sprintf("(xeq_fn__join) Block # %d slot %d is not OBJ_TEXT", agg_block, i))
                s = s  blk_ll_slot_value(agg_block, i)  fs
            }
        } else {
            # It's a normal array - Find the keys
            for (k in symtab) {
                split(k, x, SUBSEP)
                if (x[1] == lis && x[3] == level && x[4] == "symval") {
                    #print x[2]
                    keys[x[2]] = 1
                }
            }
            # Inject the values
            for (k in keys) {
                # print_stderr("JOIN: arr[" k "] = " sym_ll_read(lis, k, level))
                s = s sym_ll_read(lis, k, level) fs
            }
        }

        # Remove trailing field separator if need be
        if (!silent)
            s = substr(s, 1, length(s)-fslen)
    }
    return s
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
                     p, x, y, result)
{
    if (nparam < 2 || nparam > 3)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    x = param[2]
    if (!integerp(x))
        error("Value '" x "' must be numeric:" $0)
    if (nparam == 2) {
        result = substr(sym_fetch(p), x)
    } else if (nparam == 3) {
        y = param[3]
        if (!integerp(y))
            error("Value '" y "' must be numeric:" $0)
        result = substr(sym_fetch(p), x, y)
    }
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
    if (! __ord_initialized)
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
# @rot13 SYM@
function xeq_fn__rot13(fn, M, nparam, param,
                       p, i, c, result)
{
    if (! __rot13_initialized)
        initialize_rot13()
    if (nparam == 0)
        error("Bad parameters in '" M "':" $0)
    p = param[1]
    p = (sym_valid_p(p) && sym_defined_p(p)) \
        ? sym_fetch(p) : substr(M, length(fn)+2)
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
    if (substr(fn, 1, 3) == "tab")
        c = TOK_TAB
    else if (substr(fn, 1, 5) == "space")
        c = TOK_SPACE
    else
        c = "?"
    return spaces(n, c)
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
                       p, cmdline, expand)
{
    if (secure_level() >= SEC_PARANOID)
        security_violation(sprintf("@%s@: Forbidden", fn))
    if (nparam != 1)
        error("(" fn ") Bad parameters in '" M "':" $0)
    p = param[1]
    assert_sym_valid_name(p, "@" M "@")
    assert_sym_defined(p, "@" M "@")
    cmdline = build_prog_cmdline(fn, rm_quotes(sym_fetch(p)), MODE_IO_CAPTURE)
    cmdline | getline expand
    close(cmdline)

    return expand
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
    TERMINAL                    = 0     # Block zero means standard output

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

    # CRUD
    OP_CREATE                   =    1; __op_label[OP_CREATE]    = "CREATE"
    OP_READ                     =    2; __op_label[OP_READ]      = "READ"
    OP_UPDATE                   =    3; __op_label[OP_UPDATE]    = "UPDATE"
    OP_DELETE                   =    4; __op_label[OP_DELETE]    = "DELETE"

    # Errors
    ERR_OKAY                    =    0
    ERR_PARSE_STACK             = -100
    ERR_PARSE_MISMATCH          = -101
    ERR_PARSE_DEPTH             = -102
    ERR_SCAN_INVALID_NAME       = -103
    NAME_NOT_FOUND              = -104 # nam__{lookup,find} no result - not considered an error

    # Various modes
    MODE_AT_LITERAL             = "L" # atmode - scan literally
    MODE_AT_PROCESS             = "P" # atmode - scan with "@" macro processing
    MODE_IO_CAPTURE             = "C" # build command for getline
    MODE_IO_SILENT              = "X" # discard all command output
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
    TOK_AT_BRACE                = "@{"
    TOK_CANRUN_P                = "?R"; __predicate_token["canrun"]  = TOK_CANRUN_P
    TOK_COLON                   = ":"
    TOK_DEFINED_P               = "?D"; __predicate_token["defined"] = TOK_DEFINED_P
    TOK_ENV_P                   = "?E"; __predicate_token["env"]     = TOK_ENV_P
    TOK_EXISTS_P                = "?X"; __predicate_token["exists"]  = TOK_EXISTS_P
    TOK_LBRACE                  = "{"
    TOK_LPAREN                  = "("
    TOK_NEWLINE                 = "\n"
    TOK_NOT                     = "!"
    TOK_OR                      = "||"
    TOK_RBRACE                  = "}"
    TOK_RPAREN                  = ")"
    TOK_TAB                     = "\t"

    # For __TRACEMODE__
    TRACE_ARGUMENTS             = "a" # show actual arguments in each call
   #TRACE_MULTI_LINE            = "c" # show multiple trace lines for each call
    TRACE_EXPANSION             = "e" # show macro expansion
    TRACE_INPUT_FILE_CHG        = "i" # trace when input file changes
    TRACE_SHOW_FILE_NAME        = "f" # show file name
    TRACE_SHOW_LINE_NUM         = "l" # show line number
    TRACE_COMMAND               = "m" # trace when a command is executed
    TRACE_PATH_SEARCH           = "p" # trace when search path search succeeds
    TRACE_SYMBOL_READ_WRITE     = "s" # trace symbol low-level read & write
    TRACE_ALL                   = "t" # trace internal macros too
    TRACE_SET_ON                = "T" # Set __TRACE__ to true
   #TRACE_SHOW_CALL_ID          = "x" # show unique call id (may not be used)
    TRACE_WILDCARD_ALL_FLAGS    = "V" # shorthand for all of above options
    #
    TRACE_DEFAULT_SET           = TRACE_ARGUMENTS       TRACE_EXPANSION
    TRACE_VALID_EVENTS          = TRACE_COMMAND         TRACE_EXPANSION         \
                                  TRACE_INPUT_FILE_CHG  TRACE_PATH_SEARCH       \
                                  TRACE_SYMBOL_READ_WRITE
    TRACE_ALL_SET               = TRACE_ARGUMENTS       TRACE_EXPANSION         \
                                  TRACE_INPUT_FILE_CHG  TRACE_SHOW_FILE_NAME    \
                                  TRACE_SHOW_LINE_NUM   TRACE_COMMAND           \
                                  TRACE_PATH_SEARCH     TRACE_SYMBOL_READ_WRITE \
                                  TRACE_SET_ON          TRACE_ALL

    # Execution control states for loops
    XEQ_NORMAL                  = 0
    XEQ_BREAK                   = 1
    XEQ_CONTINUE                = 2
    XEQ_RETURN                  = 3

    # Global variables
    __block_cnt                 = 0
    __buffer                    = EMPTY
    __init_files_loaded         = FALSE # becomes True in load_init_files()
    __namespace                 = GLOBAL_NAMESPACE
    __ord_initialized           = FALSE # becomes True in initialize_ord()
    __print_mode                = MODE_TEXT_PRINT
    __rot13_initialized         = FALSE # becomes True in initialize_rot13()
    __parse_stack[0]            = 0;    __parse_stack["name"]  = "parse_stack"
    __source_stack[0]           = 0;    __source_stack["name"] = "source_stack"
    __wrap_cnt                  = 0
    __xeq_ctl                   = XEQ_NORMAL

    srand()                     # Seed random number generator
    initialize_prog_paths()
    __inc_path = "M2PATH" in ENVIRON ? ENVIRON["M2PATH"] : ""

    # Initialize days per month
    split("31 31 28 29 31 31 30 30 31 31 30 30 31 31 31 31 30 30 31 31 30 30 31 31", monthdays)
    for (i = 0; i < 24; i++) {
        month = int(i/2) + 1
        leap  = i % 2
        __monthdays[month, leap] = monthdays[i+1]
    }

    if (secure_level() < SEC_PARANOID) {
        # Set up some symbols that depend on external programs

        # Current date & time
        if ("date" in PROG) {
            # Capture m2 run start time.                 1  2  3  4  5  6  7  8  9
            get_date_cmd = build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z %s %a'", MODE_IO_CAPTURE)
            get_date_cmd | getline dateout
            close(get_date_cmd)
            split(dateout, d)

            sym_ll_fiat("__DATE__",         "", PTYPE_READONLY_INTEGER, d[1] d[2] d[3])
            sym_ll_fiat("__DOW__",          "", PTYPE_READONLY_SYMBOL,  d[9])
            sym_ll_fiat("__EPOCH__",        "", PTYPE_READONLY_INTEGER, d[8])
            sym_ll_fiat("__TIME__",         "", PTYPE_READONLY_SYMBOL,  d[4] d[5] d[6]) # not an INTEGER because I want leading 0 if before 12:00
            sym_ll_fiat("__TIMESTAMP__",    "", PTYPE_READONLY_SYMBOL,  d[1] "-" d[2] "-" d[3] \
                                                                    "T" d[4] ":" d[5] ":" d[6] d[7])
            sym_ll_fiat("__TZ__",           "", PTYPE_READONLY_SYMBOL,  d[7])
        }

        # Deferred symbols
        if ("id" in PROG) {
            sym_deferred_symbol("__GID__",      PTYPE_READONLY_INTEGER, "id", "-g")
            sym_deferred_symbol("__UID__",      PTYPE_READONLY_INTEGER, "id", "-u")
            sym_deferred_symbol("__USER__",     PTYPE_READONLY_SYMBOL,  "id", "-un")
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
            sym_deferred_symbol("__PID__",      PTYPE_READONLY_INTEGER, "sh", "-c 'echo $PPID'")
        }
    }

    nam_ll_write("__FMT__",    GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)
    nam_ll_write("__STRICT__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_SYSTEM FLAG_WRITABLE)

    if ("COLUMNS" in ENVIRON)
      sym_ll_fiat("__COLUMNS__",    "", PTYPE_WRITABLE_INTEGER, ENVIRON["COLUMNS"])
    else if (secure_level() < SEC_PARANOID && ("tput" in PROG))
      sym_deferred_symbol("__COLUMNS__",PTYPE_WRITABLE_INTEGER, "tput", "cols")
    else
      sym_ll_fiat("__COLUMNS__",    "", PTYPE_WRITABLE_INTEGER, 80)
    if ("PWD" in ENVIRON)
      sym_ll_fiat("__CWD__",        "", PTYPE_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["PWD"]))
    else if (secure_level() < SEC_PARANOID && ("pwd" in PROG))
      sym_deferred_symbol("__CWD__",    PTYPE_READONLY_SYMBOL,  "pwd", "")
    sym_ll_fiat("__DIVNUM__",       "", PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__DEBUGFILE__",    "", PTYPE_WRITABLE_SYMBOL,  STDERR)
    sym_ll_fiat("__EXPR__",         "", PTYPE_READONLY_NUMERIC, 0.0)
    sym_ll_fiat("__FILE__",         "", PTYPE_READONLY_SYMBOL,  "")
    sym_ll_fiat("__FILE_UUID__",    "", PTYPE_READONLY_SYMBOL,  "")
    sym_ll_fiat("__FMT__",         "1", "",                     "1") # True
    sym_ll_fiat("__FMT__",         "0", "",                     "0") # False
    sym_ll_fiat("__FMT__",      "date", "",                     "%Y-%m-%d")
    sym_ll_fiat("__FMT__",     "epoch", "",                     "%s")
    sym_ll_fiat("__FMT__",    "number", "",                     CONVFMT)
    sym_ll_fiat("__FMT__",       "seq", "",                     "%d")
    sym_ll_fiat("__FMT__",      "time", "",                     "%H:%M:%S")
    sym_ll_fiat("__FMT__",        "tz", "",                     "%Z")
    sym_ll_fiat("__FMT__",       "utc", "",                     "%Y-%m-%dT%H:%M:%S%z") # ISO 8601
    nam_ll_write("__FS__", GLOBAL_NAMESPACE, PTYPE_WRITABLE_SYMBOL) # NB - *not* in sync with real FS
    if ("HOME" in ENVIRON)
      sym_ll_fiat("__HOME__",       "", PTYPE_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["HOME"]))
    else if ("LOGDIR" in ENVIRON)
      sym_ll_fiat("__HOME__",       "", PTYPE_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["LOGDIR"]))
    sym_ll_fiat("__INPUT__",        "", PTYPE_WRITABLE_SYMBOL,  EMPTY)
    sym_ll_fiat("__LINE__",         "", PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__M2_UUID__",      "", PTYPE_READONLY_SYMBOL,  uuid())
    sym_ll_fiat("__M2_VERSION__",   "", PTYPE_READONLY_SYMBOL,  M2_VERSION)
    sym_ll_fiat("__NFILE__",        "", PTYPE_READONLY_INTEGER, 0); __rnf = 0
    sym_ll_fiat("__NLINE__",        "", PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__MAX_STREAM__",   "", PTYPE_READONLY_INTEGER, MAX_STREAM)
    sym_ll_fiat("__STRICT__",   "bool", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "def", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "env", "",                     TRUE)
    sym_ll_fiat("__STRICT__",   "file", "",                     TRUE)
    sym_ll_fiat("__STRICT__",    "key", "",                     TRUE)
    sym_ll_fiat("__STRICT__",   "name", "",                     TRUE)
    sym_ll_fiat("__SYNC__",         "", PTYPE_WRITABLE_INTEGER, SYNC_FILE)
    sym_ll_fiat("__SYSVAL__",       "", PTYPE_READONLY_INTEGER, 0)
    sym_ll_fiat("__TRACEMODE__",    "", PTYPE_READONLY_SYMBOL,  TRACE_DEFAULT_SET)

    # IMMEDS
    # These commands are Immediate
    split("break case continue else endcase endcmd endif endlong" \
          " endlongdef endwhile esac fi for foreach if longdef" \
          " newcmd next of otherwise return unless until wend while",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_COMMAND FLAG_SYSTEM FLAG_IMMEDIATE)

    # CMDS
    # Built-in commands
    # Also need to add entry in execute__command()  [search: DISPATCH]
    split("append array cleardivert data debug decr default define divert" \
          " dump dumpall dumpdef echo enddata eod error errprint esyscmd" \
          " eval exit filedata filedef filedefine ignore include incr initialize" \
          " input list literal local m2ctl nextfile null paste readonly secho" \
          " sequence serror sfiledata sfiledef sfiledefine shell sinclude spaste split" \
          " syscmd tracemode traceoff traceon typeout undef undefine" \
          " undivert warn wrap",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_COMMAND FLAG_SYSTEM)

    # FUNCS
    # They are similar to symbols but with optional parameter handling
    # Also need to add handler in dosubs()  [search: SYMFUNC]
    # Functions cannot be used as symbol or sequence names.
    split("basename boolval center chr date dirname divlines dow epoch" \
          " executable expr format getenv gregdate ifdef ifelse ifndef" \
          " ifx index join lc left len ljust ltrim mid mjd ord rem right" \
          " rjust rot13 rtrim scenter sexecutable sexpr sgetenv sjoin" \
          " sljust space spaces srem srjust strftime substr tab tabs time" \
          " trim tz uc utc uuid xbasename xdirname",
          array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_FUNCTION FLAG_SYSTEM)

    # INTERNAL
    # Used for tracing internal functions - not reachable by user
    split("dosubs", array, TOK_SPACE)
    for (elem in array)
        nam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_INTERNAL FLAG_SYSTEM)

    __flag_label[PTYPE_ANY]      = "Any"
    __flag_label[ TYPE_ARRAY]    = "Array"
    __flag_label[ TYPE_COMMAND]  = "Command"
    __flag_label[ TYPE_FUNCTION] = "Function"
    __flag_label[PTYPE_IDXABLE]  = "Indexable"
    __flag_label[ TYPE_INTERNAL] = "Intern"
    __flag_label[ TYPE_LIST]     = "List"
    __flag_label[PTYPE_NUMBER]   = "Number"
    __flag_label[PTYPE_SCALAR]   = "Scalar"
    __flag_label[ TYPE_SEQUENCE] = "Sequence"
    __flag_label[ TYPE_SYMBOL]   = "Symbol"
    __flag_label[PTYPE_UNDEF]    = "Undef"
    __flag_label[ TYPE_USER]     = "User"

    __flag_label[FLAG_BOOLEAN]   = "Boolean"
    __flag_label[FLAG_DEFERRED]  = "Deferred"
    __flag_label[FLAG_IMMEDIATE] = "Immediate"
    __flag_label[FLAG_INTEGER]   = "Integer"
    __flag_label[FLAG_KEY_NO]    = "Key-No"
    __flag_label[FLAG_KEY_YES]   = "Key-Yes"
    __flag_label[FLAG_NUMERIC]   = "Numeric"
    __flag_label[FLAG_READONLY]  = "Read-only"
    __flag_label[FLAG_SYSTEM]    = "System"
    __flag_label[FLAG_TRACING]   = "Tracing"
    __flag_label[FLAG_WRITABLE]  = "Writable"

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
    sym_ll_fiat("__TMPDIR__", "",       PTYPE_WRITABLE_SYMBOL,  "/tmp/")
    nam_ll_write("__PROG__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_READONLY FLAG_SYSTEM)
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
    else if (sym_ll_in("__HOME__", "", GLOBAL_NAMESPACE))
        dofile(sym_ll_read("__HOME__", "", GLOBAL_NAMESPACE) \
               ".m2rc")
    dofile("./.m2rc")

    # Don't count init files in total line/file tally - it's better to
    # keep them in sync with the files from the command line.
    sym_ll_write("__NFILE__", "", GLOBAL_NAMESPACE, 0)
    sym_ll_write("__NLINE__", "", GLOBAL_NAMESPACE, 0)

    # Restore debugging, if any, and we're done
    symtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = old_debug
    __init_files_loaded = TRUE

    # FOR TESTING - start in Debug mode
    # enable_debugging()
    # dbg__all_lev_standard()
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

    # Else, process all command line arguments.  These might be file
    # names to process, or user settings of the form NAME=VALUE.  ARGC
    # is never zero, so if it's not 1 (no command line args, checked
    # above), there must be parameters.
    } else {
        # Delay loading $HOME/.m2rc as long as possible.  This allows us
        # to set symbols on the command line which will have taken effect
        # by the time the init file loads.
        _nfile = 0
        for (_i = 1; _i < ARGC; _i++) {
            # Show each arg as we process it
            _arg = ARGV[_i]
            dbg__print("args", 3, ("BEGIN: ARGV[" _i "]:" _arg))

            # If it's a definition on the command line, define it
            if (_arg ~ /^([^= ][^= ]*)=(.*)/) {
                _eq   = index(_arg, "=")
                _name = substr(_arg, 1, _eq-1)
                _val  = substr(_arg, _eq+1)

                # Some args like debug and trace are merely aliases for other,
                # harder-to-type symbol names.  They just get re-written.
                # Other args like init or U trigger actions which are executed
                # immediately, and then the loop continues with the next arg.
                if (_name == "debug") {
                    _name = "__DEBUG__"
                } else if (_name == "fs") {
                    _name = "__FS__"
                } else if (_name == "I") {      # I=<path>
                    # Include-path elements on command-line are prepended
                    # to M2PATH so they override env variable values.
                    if (!emptyp(_val))
                        __inc_path = _val (emptyp(__inc_path) ? "" : ":" __inc_path)
                    continue
                } else if (_name == "init") {   # init=<VAL>
                    if (_val > 0)
                        # Positive value loads init files immediately
                        # without needing to providing a command-line file.
                        load_init_files()
                    else
                        # Do not load the init files.  Inhibit init file
                        # loading by pretending we already did it.
                        __init_files_loaded = TRUE
                    continue
                } else if (_name == "secure") {
                    _name = "__SECURE__"
                } else if (_name == "strict") {
                    _val = to_bool(_val) # (_val > 0) # convert int value to bool
                    # Update strict settings
                    sym_ll_write("__STRICT__", "bool", GLOBAL_NAMESPACE, _val)
                    sym_ll_write("__STRICT__",  "def", GLOBAL_NAMESPACE, _val)
                    sym_ll_write("__STRICT__",  "env", GLOBAL_NAMESPACE, _val)
                    sym_ll_write("__STRICT__", "file", GLOBAL_NAMESPACE, _val)
                    sym_ll_write("__STRICT__",  "key", GLOBAL_NAMESPACE, _val)
                    sym_ll_write("__STRICT__", "name", GLOBAL_NAMESPACE, _val)
                    continue
                } else if (_name == "trace") {
                    _name = "__TRACE__"
                } else if (_name == "U") {      # U=<name>
                    # Undefine name, like @undef
                    xeq_cmd__undefine("undefine", _val)
                    continue
                }
                # If we reach here, we still have our NAME=VAL arg to process,
                # and we haven't broken off taking some arg-triggered action.
                # Remember, "NAME=" on command line defines with empty value.
                if (emptyp(_val)) {
                    dbg__print("args", 3, "BEGIN: Setting '" _name "' to @null")
                    xeq_cmd__null("null", _name)
                } else {
                    dbg__print("args", 3, "BEGIN: Setting '" _name "' to '" _val "'")
                    xeq_cmd__define("define", _name TOK_SPACE _val)
                }

            # If not NAME=VAL, try to load arg as a file.
            } else {
                _nfile++
                _loadfile = search_file(_arg)
                if (emptyp(_loadfile)) {
                    warn("File '" _arg "' not found", "ARGV", _i)
                    __exit_code = EX_NOINPUT
                    continue
                }
                load_init_files()
                if (! dofile(_loadfile)) {
                    warn("Problem parsing file '" _loadfile "'", "ARGV", _i)
                    __exit_code = EX_M2_ERROR
                }
            }
        }

        # If we get here with __rnf still zero, that means we used
        # up every ARGV defining symbols and didn't specify any files.
        # (Well that used to be true, but if you can also get here by
        # specifying files that don't exist.)  So we check the number of
        # files we've processed vs the number we were requested to handle.
        #print_stderr("_nfile=" _nfile "  __rnf=" __rnf)
        if (__rnf == 0) {
            # Not specifying any input files, like the ARGC==1 situation,
            # means to read standard input, so that is what we must now do.
            if (_nfile == 0) {
                load_init_files()
                __exit_code = dofile("-") ? EX_OK : EX_NOINPUT
            } else {
                # User specified file(s) but not one of them existed.
                __exit_code = EX_NOINPUT
            }
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
        print_stderr("(main) Parse stack is not empty!")
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
                     i, timestamp)
{
    if (__exit_code == EX_OK &&
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
    }

    # Regardless of exit status, execute any wrapped text/commands
    if (__wrap_cnt > 0)
        for (i = 1; i <= __wrap_cnt; i++)
            dostring(__wrap_text[i])

    if (debugging_enabled_p())
        print_debugfile(sprintf("m2:%s",
                                __exit_code == EX_NOINPUT ? "NOFILE" : __exit_code == EX_OK ? "END" : "ERROR"))
    flush_stdout(SYNC_FORCE)
    exit __exit_code
}
# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
