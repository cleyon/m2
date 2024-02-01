#!/usr/bin/awk -f

BEGIN { version = "3.3.4" }

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
#       portable "standard" Awk and does not depend on Gawk or any other
#       files.  Even later Awk additions such as systime() are avoided.
#
#       The program can perform several functions, including:
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
#       4. Comments are removed from the output.  @comment commands
#          appear on a line of their own and are dropped from the
#          output.  @rem ...@ macros are embedded in the input text and
#          produce no output.  Use @ignore for a multi-line comment.
#
#       5. Manage multiple output data streams with diversions.
#
#       Control commands (@if, @define, etc) are distinguished by a "@"
#       as the first character at the beginning of a line.  They consume
#       the entire line.  The following table lists control commands to
#       evaluate, control, or define macros for subsequent processing:
#
#           @append NAME TEXT      Add TEXT to an already defined macro NAME
#           @comment [TEXT]        Comment; ignore line.  Also @@, @c, @#
#           @debug [TEXT]          If debugging, send TEXT to standard error
#           @decr NAME [N]         Subtract N (1) from an already defined NAME
#           @default NAME VAL      Like @define, but no-op if NAME already defined
#           @define NAME TEXT      Set NAME to TEXT
#           @divert [N]            Divert output to stream N (default 0 means stdout)
#           @dump(all) [FILE]      Output symbol names & definitions to FILE (stderr)
#           @error [TEXT]          Send TEXT to standard error; exit code 2
#           @exit [CODE]           Immediately stop parsing; exit CODE (default 0)
#           @flush                 Flush standard output
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
#           @longdef NAME          Set NAME to <...> (all lines until @endlongdef)
#             <...>                  Don't use other @ commands inside definition
#           @endlongdef              But simple @NAME@ references should be okay
#           @newcmd NAME           Create a user command NAME (lines until @endcmd)
#             <...>
#           @endcmd
#           @paste FILE            Insert FILE contents literally, no macros
#           @read NAME FILE        Read FILE contents to define NAME
#           @sequence ID ACT [N]   Create and manage sequences
#           @shell DELIM [PROG]    Evaluate input until DELIM, send raw data to PROG
#                                    Output from prog is captured in output stream
#           @typeout               Print remainder of input file literally, no macros
#           @undefine NAME         Remove definition of NAME
#           @undivert [N]          Inject stream N (def all) into current stream
#           @unless NAME           Include subsequent text if NAME == 0 (or undefined)
#           @warn [TEXT]           Send TEXT to standard error; continue
#                                    Also called @echo, @stderr
#
#       A definition may extend across multiple lines by ending each
#       line with a backslash, thus quoting the following newline.
#       (Alternatively, use @longdef.)  Short macros can be defined on
#       the command line by using the form "NAME=VAL", or "NAME=" to
#       define with empty value (NAME will be defined but false).
#
#       m2 does not scan tokens or replace unadorned text: macro
#       substitution must be explicitly requested by enclosing the macro
#       name in "@" characters.  Thus, any occurrence of @name@ in the
#       input is replaced in the output by the corresponding value.  On
#       the other hand, there is no need to `quote' any identifiers to
#       protect against inadvertent replacement.  Various substitutions
#       can occur multiple times in a single line.
#
#       Example:
#           @define Condition under
#           You are clearly @Condition@worked.
#               => You are clearly underworked.
#
#       Specifying more than one word between @ signs, as in
#           @xxxx AA BB CC@
#       is used as a crude form of function invocation.  Macros can
#       expand positional parameters whose actual values will be
#       supplied when the macro is called.  The definition should refer
#       to $1, $2, etc.  ${1} also works, so ${1}1 is distinguishable
#       from $11.  $0 refers to the name of the macro itself.  You may
#       supply more parameters than needed, but it is an error if a
#       definition refers to a parameter which is not supplied.
#
#       Example:
#           @define greet Hello, $1!  m2 sends you $0ings.
#           @greet world@
#               => Hello, world!  m2 sends you greetings.
#
#       m2 can incorporate the contents of files into its data stream.
#       @include scans and processes the file data for macros; @paste
#       will retrieve the contents with no modifications.  Attempting to
#       @include or @paste a non-existent file results in an error.
#       However, if the "silent" variants (@sinclude, @spaste) are used,
#       no message is printed.
#
#       To alleviate scanning ambiguities, any characters enclosed in
#       at-sign braces will be recursively scanned and expanded.  Thus
#           @data_list[@{my_key}]@
#       uses the value in "my_key" to look up data from "data_list".
#       The text between the braces is implicitly interpreted as if it
#       were surrounded by "@" characters, so @{SYMBOL} is correct.
#
#       The following definitions are recognized:
#
#           @basename SYM@         Base (file) name of SYM
#           @boolval SYM@          Output "1" if SYM is true, else "0"
#           @date@           [***] Current date (format as __FMT__[date])
#           @dirname SYM@          Directory name of SYM
#           @epoch@          [***] Number of seconds since the Epoch, UTC
#           @expr MATH@            Evaluate mathematical expression
#           @getenv VAR@       [*] Get environment variable
#           @lc SYM@               Lower case
#           @left SYM [N]@         Substring of SYM from 1 to Nth character
#           @len SYM@              Number of characters in SYM's value
#           @mid SYM BEG [LEN]@    Substring of SYM from BEG, LEN chars long
#           @rem COMMENT@          Embedded comment text is ignored
#           @right SYM [N]@        Substring of SYM from N to last character
#           @spaces [N]@           Output N space characters  (default 1)
#           @time@           [***] Current time (format as __FMT__[time])
#           @trim SYM@             Remove leading and trailing whitespace
#           @tz@             [***] Time zone name (format as __FMT__[tz])
#           @uc SYM@               Upper case
#           @uuid@                 Something that resembles a UUID:
#                                    C3525388-E400-43A7-BC95-9DF5FA3C4A52
#
#       Symbols can be suffixed with "[<key>]" to form simple arrays.
#
#       Symbols that start and end with "__" (like __FOO__) are called
#       "system" symbols.  Except for certain unprotected symbols, they
#       cannot be modified by the user.  The following are pre-defined;
#       example values, defaults, or types are shown:
#
#           __DATE__         [***] m2 run start date as YYYYMMDD (eg 19450716)
#           __DEBUG__         [**] Debugging enabled? (boolean, def FALSE)
#           __DEBUG__[<id>]   [**] Debugging levels for m2 systems (integer)
#           __DIVNUM__             Current stream number (0; 0-9 valid)
#           __EPOCH__        [***] Seconds since Epoch at m2 run start time
#           __EXPR__               Value from most recent @expr ...@ result
#           __FILE__               Current file name
#           __FILE_UUID__          UUID unique to this file
#           __FMT__[0]        [**] Text output when @boolval@ is false (0)
#           __FMT__[1]        [**] Text output when @boolval@ is true (1)
#           __FMT__[date]     [**] Date format for @date@ (%Y-%m-%d)
#           __FMT__[seq]      [**] Format for printing sequence values (%d)
#           __FMT__[time]     [**] Time format for @time@ (%H:%M:%S)
#           __FMT__[tz]       [**] Time format for @tz@   (%Z)
#           __GID__                Group id (effective gid)
#           __HOST__               Short host name (eg myhost)
#           __HOSTNAME__           FQDN host name (eg myhost.example.com)
#           __INPUT__         [**] The data read by @input
#           __LINE__               Current line number inside __FILE__
#           __M2_UUID__            UUID unique to this m2 run
#           __M2_VERSION__         m2 version
#           __NFILE__              Number of files processed so far (eg 2)
#           __NLINE__              Number of lines read so far from all files
#           __OSNAME__             Operating system name
#           __PID__                m2 process id
#           __STATUS__             Exit status of most recent @shell command
#           __STRICT__        [**] Strict mode? (boolean, def TRUE)
#           __TIME__         [***] m2 run start time as HHMMSS (eg 053000)
#           __TIMESTAMP__    [***] ISO 8601 timestamp (1945-07-16T05:30:00-0600)
#           __TMPDIR__        [**] Location for temporary files (def /tmp)
#           __TZ__           [***] Time zone numeric offset from UTC (-0400)
#           __UID__                User id (effective uid)
#           __USER__               User name
#
#       [*] @getenv VAR@ will be replaced by the value of the environment
#           variable VAR.  An error is thrown if VAR is not defined.  To
#           ignore error and continue with empty string, disable __STRICT__.
#
#       [**] denotes an "unprotected" system symbol.
#
#       [***] __DATE__, __EPOCH__, __TIME__, __TIMESTAMP__, and __TZ__
#             are fixed at program start and do not change.  @date@,
#             @epoch@, @time@, and @tz@ do change, so:
#                 @date@T@time@@__TZ__@
#             will generate an up-to-date timestamp.  Of course time
#             zones don't normally change; the point is that @__TZ__@
#             prints "-0800" while @tz@ prints "PST".
#
# STREAMS & DIVERSIONS
#       m2 attempts to follow m4 in its use of @divert and @undivert.
#       If argument is not an integer, no action is taken and no error
#       is thrown.
#
#       Divert:
#           @divert
#               - Same as @divert 0
#           @divert -1
#               - All subsequent output in this diversion is discarded.
#           @divert 0
#               - Resume normal output: all subsequent output is sent
#                 to standard output (aka stream # 0)
#           @divert N       # N ::= 1..9
#               - All subsequent output is sent to stream N
#           @divert N1 N2...
#               - Error!  Multiple arguments are not allowed.
#
#       Undivert:
#           @undivert
#               - Inject all diversions, in numerical order, into
#                 current stream.
#           @undivert -1
#               - No effect.
#           @undivert 0
#               - No effect.
#           @undivert N
#               - Inject only the numbered diversion into current stream.
#           @undivert N1 N2 ...
#               - Inject all specified diversions (in argument order,
#                 not numerical order), if legal, into current stream.
#
#       End-of-Data Processing:
#           There is an implicit "@divert 0" and "@undivert" performed
#           when m2 reaches the end of its input.  If you want to avoid
#           this and discard any diverted data that hasn't shipped out yet,
#           add the following to the end of your input data:
#               @divert -1
#               @undivert
#
#       Example:
#           @divert 1
#           World!
#           @divert
#           Hello,
#               => Hello,
#               => World!
#
# SEQUENCES
#       m2 supports named sequences which are integer values.  By
#       default, sequences begin at zero and increment by one as
#       appropriate.  These defaults can be changed, and the value
#       updated or restarted.  You create and manage sequences with the
#       @sequence command.  The following actions are valid:
#
#           ID create              Create a new sequence named ID
#           ID delete              Destroy sequence named ID
#           ID format PRINTFSTR    Format string used to print value (%d)
#           ID inc    N            Set increment to N (1)
#           ID init   N            Set initial value to N (1)
#           ID next                Increment value (no output)
#           ID prev                Decrement value (no output)
#           ID restart             Set current value to initial value
#           ID set    N            Set value directly to N
#
#       To use a sequence, surround the sequence ID with @ characters
#       just like a macro.  This injects the current value, formatted by
#       calling sprintf with the specified format.  To get the current
#       value printed in decimal wihthout any special formatting, say
#       "@ID currval@".
#
#       Sequence values can be modified in two ways:
#
#       1. The @sequence command actions next, prev, restart, and set will
#          change the value as specified without generating any output.
#
#       2. Used inline, ++ or -- (prefix or postfix) will automatically
#          modify the sequence while outputting the desired value.
#
#       Example:
#           @sequence counter create
#           @sequence counter format # %d.
#           @++counter@ First header
#           @++counter@ Second header
#               => # 1. First header
#               => # 2. Second header
#
# MATHEMATICAL EXPRESSIONS
#       The @expr ...@ function evaluates mathematical expressions and
#       inserts their results.  It is based on "calc3" from "The AWK
#       Programming Language" p. 146, with enhancements by Kenny
#       McCormack and Alan Linton.  @expr@ supports the standard
#       arithmetic operators  +  -  *  /  %  ^  (  )
#       Comparison operators  <  <=  ==  !=  >=  >  return 0 or 1,
#       as per Awk.  Logical negation (!) is allowed, but no other
#       boolean operators are permitted.  && and || are NOT supported!
#
#       @expr@ supports the following functions:
#
#           atan2(y,x)             Arctangent of y/x, -pi <= atan2 <= pi
#           cos(x)                 Cosine of x, in radians
#           deg(x)                 Convert radians to degrees
#           exp(x)                 Exponential (anti-logarithm) of x, e^x
#           int(x)                 Integer part of x
#           log(x)                 Natural logarithm of x, base e
#           log10(x)               Common logarithm of x, base 10
#           rad(x)                 Convert degrees to radians
#           rand()                 Random float, 0 <= rand < 1
#           randint(x)             Random integer, 1 <= randint <= x
#           sin(x)                 Sine of x, in radians
#           sqrt(x)                Square root of x
#           tan(x)                 Tangent of x, in radians
#
#       @expr@ will automatically use symbols' values in expressions.
#       Inside @expr ...@, there is no need to surround symbol names
#       with "@" characters to retrieve their values.  @expr@ also
#       recognizes the predefined constants "e", "pi", and "tau".
#
#       The most recent expression value is automatically stored in
#       __EXPR__.  @expr@ can also assign values to symbols with the
#       "=" assignment operator.  Assignment is itself an expression, so
#       @expr x=5@ assigns the value 5 to x and also outputs the result.
#       To assign a value to a variable without printing, use @define.
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
#           Division by zero
#               - @expr@ attempted to divide by zero.
#           Duplicate '@else' not allowed
#               - More than one @else found in a single @if block.
#           Empty symbol table
#               - A @dump command found no definitions to display.
#           Environment variable 'XXX' not defined
#               - Attempt to getenv an undefined environment variable
#                 while __STRICT__ is in effect.
#           Error reading 'FILE'
#               - Read error on file.
#           Expected number or '(' at 'XXX'
#               - @expr ...@ received unexpected input or bad syntax.
#           File 'XXX' does not exist
#               - Attempt to @include a non-existent file in strict mode.
#           Math expression error [hint]
#               - An error occurred during @expr ...@ evaluation.
#               - A math expression returned +/-Infinity or NaN.
#           Missing 'X' at 'XXX'
#               - @expr ...@ did not match syntax required for expression.
#           Name 'XXX' not available
#               - Despite being valid, the name cannot be used/found here.
#           Name 'XXX' not defined
#               - A symbol name without a value was passed to a function
#               - An undefined macro was referenced and __STRICT__ is true.
#               - Attempt to use an undefined sequence ("create" is allowed)
#           Name 'XXX' not valid
#               - A symbol name does not pass validity check.  In __STRICT__
#                 mode (the default), a symbol name may only contain letters,
#                 digits, #, -, or _ characters.
#               - Environment variable name does not pass validity check.
#           No corresponding 'XXX'
#               - @if: An @else or @endif was seen without a matching @if.
#               - @longdef: An @endlongdef was seen without a matching @longdef.
#               - @newcmd: An @endcmd was seen without a matching @newcmd
#               - Indicates a "finishing" command was seen without a starter.
#           Parameter N not supplied in 'XXX'
#               - A macro referred to a parameter (such as $1) for which
#                 no value was supplied.
#           Symbol 'XXX' already defined
#               - @initialize attempted to define a previously defined symbol.
#           Symbol 'XXX' protected
#               - Attempt to modify a protected symbol (__EXAMPLE__).
#                 (__STRICT__ is an exception and can be modified.)
#           Unexpected end of definition
#               - Input ended before macro definition was complete.
#           Unknown function 'FUNC'
#               - @expr ...@ found an unrecognized mathematical function.
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
#       foo has three arguments -- '"a', 'b"', 'c' -- not two.
#
#       Self-referential/recursive macros will hang the program.
#
#       Left-to-right order of evaluation is not necessarily guaranteed.
#           @++N@ - We are now on step @N@
#       may not produce exactly the output you expect.  This is
#       especially noticeable if @{...} is used in complex ways.
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
#           @define images[us-east-1]   my-east1-image-name
#           @define images[us-east-2]   my-east2-image-name
#           @define images[us-west-1]   my-west1-image-name
#           @define images[us-west-2]   my-west2-image-name
#           @define my_image @images[@{region}]@
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
#       M2RC            If exists, overrides $HOME/.m2rc
#       SHELL           Used as a possible default shell
#       TMPDIR          Used as a possible temporary directory
#
# AUTHOR
#       Jon L. Bentley, jlb@research.bell-labs.com
#
# EMBIGGENER
#       Chris Leyon, cleyon@gmail.com
#
# OTHER Ms
#       M   Admiral Sir Miles Messervy
#       M1  Jon Bentley's original macro processor, the progenitor of this
#           program.  See: "m1: A Mini Macro Processor", Computer Language,
#           June 1990, Volume 7, Number 6, pages 47-61.
#       M2  This program.
#       M3  Kernighan & Plauger's book "Software Tools", Addison-Wesley (1976),
#           describes a macro-processor language which inspired D. M. Ritchie
#           to write m3, a macro processor for the AP-3 minicomputer.
#           Originally, the Kernighan and Plauger macro-processor, and
#           then m3, formed the engine for the Rational FORTRAN
#           preprocessor, although it was later replaced with m4.
#       M4  From Unix V7, a macro processor "intended as a front end for Ratfor,
#           C, and other languages."  See: B. W. Kernighan and D. M. Ritchie,
#           The M4 Macro Processor, AT&T Bell Laboratories, Computing Science
#           Technical Report #59, July 1977.
#       M5  Prof. A. Dain Samples described and implemented M5.
#           See: User's Guide to the M5 Macro Language 2ed [in comp.compilers
#           newsgroup, 1992].  May also refer to a multitronic computer designed
#           and built by Dr Richard Daystrom, ~2268.  (Not entirely successful.)
#       M6  Andrew D. Hall - M6, "a general purpose macro processor used to port
#           the Fortran source code of the Altran computer algebra system."
#           See: A. D. Hall, M6 Reference Manual.  Computer Science Technical
#           Report #2, Bell Laboratories, 1972.
#           - http://man.cat-v.org/unix-6th/6/m6
#           - http://cm.bell-labs.com/cm/cs/cstr/2.pdf
#
# SEE ALSO
#       - http://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791
#       - https://docstore.mik.ua/orelly/unix3/sedawk/ch13_10.htm
#
#*****************************************************************************

BEGIN {
    EX_OK             =  0      # Exit codes
    EX_M2_ERROR       =  1
    EX_USER_REQUEST   =  2
    EX_USAGE          = 64
    EX_NOINPUT        = 66

    exit_code         = EX_OK
}



#*****************************************************************************
#
#       I/O functions
#
#*****************************************************************************

# file ":" line  ":" text
function format_message(text, file, line,    s)
{
    if (file == "")
        file = sym_fetch("__FILE__")
    if (file == "/dev/stdin" || file == "-")
        file = "<STDIN>"
    if (line == "")
        line = sym_fetch("__LINE__")

    # If file and line are provided with default values, why is the if()
    # guard still necessary?  Ah, because this function might get invoked
    # very early in m2 execution, before the symbol table is populated.
    # The defaults are therefore empty, resulting in superfluous ":"s.
    if (file) { s = s file ":" }
    if (line) { s = s line ":" }
    if (text) { s = s text     }
    return s
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


function warn(text, file, line)
{
    print_stderr(format_message(text, file, line))
}

function error(text, file, line)
{
    warn(text, file, line)
    exit_code = EX_M2_ERROR
    end_program(DISCARD_STREAMS)
}



#*****************************************************************************
#
#       Stream functions
#
#*****************************************************************************

# Send text to the destination stream __DIVNUM__
#   < 0         Discard
#   = 0         Standard output
#   > 0         Stream # N
function ship_out(text,    divnum)
{
    divnum = sym_fetch("__DIVNUM__")
    if (divnum == 0)
        printf("%s", text)
    else if (divnum > 0)
        streambuf[divnum] = streambuf[divnum] text
}


# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-parsed for macros, and buffer is cleared after
# injection into target stream.
function undivert(stream)
{
    dbg_print("divert", 1, "undivert(" stream ")")
    if (stream <= 0 || stream == sym_fetch("__DIVNUM__"))
        return
    if (! emptyp(streambuf[stream])) {
        ship_out(streambuf[stream])
        streambuf[stream] = ""
    }
}

function undivert_all(    stream)
{
    for (stream = 1; stream <= MAX_STREAM; stream++)
        undivert(stream)
}



#*****************************************************************************
#
#       String functions
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


#*****************************************************************************
#
#       Symbol table API
#
#*****************************************************************************

function sym_defined_p(sym,    s)
{
    s = sym_internal_form(sym)
    if (init_deferred && s in deferred_syms)
        initialize_deferred_symbols()
    return s in symtab
}

function sym2_defined_p(arr, key)
{
    if (init_deferred && sym2_printable_form(arr, key) in deferred_syms)
        initialize_deferred_symbols()
    return (arr, key) in symtab
}

function sym_definition_pp(sym,    sym_name, definition)
{
    sym_name = sym_printable_form(sym)
    definition = sym_fetch(sym)
    return (index(definition, "\n") == IDX_NOT_FOUND) \
        ? "@define " sym_name "\t" definition "\n" \
        : "@longdef " sym_name "\n" \
          definition           "\n" \
          "@endlongdef"        "\n"
}


# Caller is responsible for ensuring user is allowed to delete symbol
function sym_destroy(sym)
{
    dbg_print("m2", 5, ("sym_destroy(" sym ")"))
    # It is legal to delete an array key that does not exist
    delete symtab[sym_internal_form(sym)]
}

function sym_fetch(sym,    s)
{
    s = sym_internal_form(sym)
    if (init_deferred && s in deferred_syms)
        initialize_deferred_symbols()
    return symtab[s]
}

function sym2_fetch(arr, key)
{
    if (init_deferred && sym2_printable_form(arr, key) in deferred_syms)
        initialize_deferred_symbols()
    return symtab[arr, key]
}

function sym_increment(sym, incr)
{
    if (incr == "")
        incr = 1
    symtab[sym_internal_form(sym)] += incr
}

# Convert a symbol name into its "internal" form (for table lookup
# purposes) by removing and separating any array-referring brackets.
#       "arr[key]"  =>  "arr <SUBSEP> key"
# If there are no array-referring brackets, the symbol is returned
# unchanged, without a <SUBSEB>.
function sym_internal_form(sym,    lbracket, arr, key)
{
    if ((lbracket = index(sym, "[")) == IDX_NOT_FOUND)
        return sym
    if (sym !~ /^.+\[.+\]$/)
        error("Name '" sym "' not valid:" $0)
    arr = substr(sym, 1, lbracket-1)
    key = substr(sym, lbracket+1, length(sym)-lbracket-1)
    return build_subsep(arr, key)
}

# Convert a symbol name into a nice, user-friendly format, usually for
# printing (i.e., put the array-looking brackets back if needed).
#       "arr <SUBSEP> key"  =>  "arr[key]"
# If there is no <SUBSEP>, the symbol is returned unchanged.
function sym_printable_form(sym,    sep, arr, key)
{
    if ((sep = index(sym, SUBSEP)) == IDX_NOT_FOUND)
        return sym
    arr = substr(sym, 1, sep-1)
    key = substr(sym, sep+1)
    return sym2_printable_form(arr, key)
}

# Convert an array name and key into a nice, user-friendly format, usually for
# printing (i.e., put the array-looking brackets back if needed).
#       (arr, key)  =>  "arr[key]"
# Since we're calling with the 2-arg form, it is known there is
# no <SUBSEP> present, so the strings can be used raw safely.
function sym2_printable_form(arr, key)
{
    return arr "[" key "]"
}

# Protected symbols cannot be changed by the user.
function sym_protected_p(sym,    root)
{
    root = sym_root(sym)
    # Names known to be protected
    if (root in protected_syms)
        return TRUE
    # Whitelist of known safe symbols
    if (root in unprotected_syms)
        return FALSE
    return name_system_p(root)
}

function sym_root(sym,    s)
{
    s = sym_internal_form(sym)
    if (index(s, SUBSEP) == IDX_NOT_FOUND)
        return sym
    else
        return substr(s, 1, index(s, SUBSEP)-1)
}

function sym_store(sym, val)
{
    dbg_print("m2", 5, ("sym_store(" sym "," val ")"))
    # __DEBUG__ and __STRICT__ can only store boolean values
    if (sym == "__DEBUG__" || sym == "__STRICT__")
        val = !!val
    if (sym == "__DEBUG__" && sym_fetch(sym) == FALSE && val == TRUE)
        initialize_debugging()
    return symtab[sym_internal_form(sym)] = val
}

function sym2_store(arr, key, val)
{
    dbg_print("m2", 5, ("sym2_store(" arr "," key "," val ")"))
    return symtab[arr, key] = val
}

# System symbols start and end with double underscores
function sym_system_p(sym)
{
    return name_system_p(sym_root(sym))
}

function sym_true_p(sym)
{
    return (sym_defined_p(sym)      && \
            sym_fetch(sym) != FALSE && \
            sym_fetch(sym) != "")
}

# In strict mode, a symbol must match the following regexp:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
# In non-strict mode, any non-empty string is valid.
function sym_valid_p(sym,    result, lbracket, root, key)
{
    # These are the ways a symbol is not valid:
    result = FALSE

    do {
        # 1. Empty string is never a valid symbol name
        if (emptyp(sym))
             break

        # Fake/hack out any "array name" by removing brackets
        if ((lbracket = index(sym, "[")) != IDX_NOT_FOUND) {
            # 2. Doesn't look exactly like "xx[yy]"
            if (sym !~ /^.+\[.+\]$/)
                break
            root = substr(sym, 1, lbracket-1)
            key  = substr(sym, lbracket+1, length(sym)-lbracket-1)

            # 3. Empty parts are not valid
            if (emptyp(root) || emptyp(key))
                break
            sym = root
        }

        # 4. We're in strict mode and the name doesn't pass regexp check
        if (strictp() && ! name_strict_symbol_p(sym))
            break

        # We've passed all the tests
        result = TRUE
    } while (FALSE)

    return result
}

####    Assertions on symbols

# Throw an error if symbol is NOT defined
function assert_sym_defined(sym, hint,    s)
{
    if (sym_defined_p(sym))
        return TRUE
    s = sprintf("Name '%s' not defined%s%s",  sym,
                ((hint != "")   ? " [" hint "]" : ""),
                ((! emptyp($0)) ? ":" $0        : "") )
    error(s)
}

function assert_sym_okay_to_define(name)
{
    assert_sym_valid_name(name)
    assert_sym_unprotected(name)
    # You can redefine a symbol, but not a cmd, function, or sequence
    if (! name_available_in_all_p(name, TYPE_CMD TYPE_FUNCTION TYPE_SEQUENCE))
        error("Name '" name "' not available:" $0)
    return TRUE
}

# Throw an error if symbol IS protected
function assert_sym_unprotected(sym)
{
    if (! sym_protected_p(sym))
        return TRUE
    error("Symbol '" sym "' protected:" $0)
}

# Throw an error if the symbol name is NOT valid
function assert_sym_valid_name(sym)
{
    if (sym_valid_p(sym))
        return TRUE
    error("Name '" sym "' not valid:" $0)
}



#*****************************************************************************
#
#       Cmd API
#
#*****************************************************************************

function cmd_defined_p(id,    s)
{
    return (id, "defined") in cmdtab
}

function cmd_definition_pp(id)
{
    # XXX parameters
    return "@newcmd " id            "\n" \
           cmdtab[id, "definition"] "\n" \
           "@endcmd"                "\n"
}

function cmd_destroy(id)
{
    delete cmdtab[id, "defined"]
    delete cmdtab[id, "definition"]
    delete cmdtab[id, "nparam"]
}

function cmd_valid_p(id)
{
    return name_strict_symbol_p(id) && !name_system_p(id)
}



#*****************************************************************************
#
#       Sequence API
#
#*****************************************************************************

function seq_defined_p(id,    s)
{
    return (id, "defined") in seqtab
}


function seq_definition_pp(id,    buf)
{
    buf = "@sequence " id "\tcreate\n"
    if (seqtab[id, "value"] != SEQ_DEFAULT_INIT)
        buf = buf "@sequence " id "\tset " seqtab[id, "value"] "\n"
    if (seqtab[id, "init"] != SEQ_DEFAULT_INIT)
        buf = buf "@sequence " id "\tinit " seqtab[id, "init"] "\n"
    if (seqtab[id, "inc"] != SEQ_DEFAULT_INC)
        buf = buf "@sequence " id "\tinc " seqtab[id, "inc"] "\n"
    if (seqtab[id, "fmt"] != sym2_fetch("__FMT__", "seq"))
        buf = buf "@sequence " id "\tformat " seqtab[id, "fmt"] "\n"
    return buf
}


function seq_destroy(id)
{
    delete seqtab[id, "defined"]
    delete seqtab[id, "inc"]
    delete seqtab[id, "init"]
    delete seqtab[id, "fmt"]
    delete seqtab[id, "value"]
}


# Sequence names must always match strict symbol name syntax:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
function seq_valid_p(id)
{
    return name_strict_symbol_p(id) && !name_system_p(id)
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
    # name cannot be a cmd, function, an existing sequence (no
    # redefinitions), or a symbol.  Furthermore, it can't be a
    # system-type name: __SEQ__ is not allowed.
    if (! name_available_in_all_p(name, TYPE_ANY))
        error("Name '" id "' not available:" $0)
    return TRUE
}



#*****************************************************************************
#
#       Names API
#
#       TYPE_CMD:               cmdtab
#           cmdtab[NAME, "defined"] ::= TRUE | FALSE
#           cmdtab[NAME, "definition"] ::= <definition>
#
#       TYPE_FUNCTION:          functab
#           functab[NAME] ::= TRUE | FALSE
#
#       TYPE_SEQUENCE:          seqtab
#           seqtab[NAME, KEY] // various types for different KEYs
#
#       TYPE_SYMBOL:            symtab
#           symtab[NAME] = <definition>
#           Check "foo in symtab" for defined
#
#*****************************************************************************

# TRUE if name is available in all components (logical AND)
# FALSE if name is unavailable in at least one of the components, not sure which
function name_available_in_all_p(name, components,    avail)
{
    if (first(name) == "@")
        name = substr(name, 2)
    if (emptyp(name))
        return FALSE
    avail = TRUE
    if (components == TYPE_ANY || index(components, TYPE_CMD))
        avail = avail && ! ((name, "defined") in cmdtab)
    if (components == TYPE_ANY || index(components, TYPE_FUNCTION))
        avail = avail && ! (name in functab)
    if (components == TYPE_ANY || index(components, TYPE_SEQUENCE))
        avail = avail && ! seq_defined_p(name)
    if (components == TYPE_ANY || index(components, TYPE_SYMBOL))
        avail = avail && ! sym_defined_p(name)
    return avail
}


function name_system_p(name)
{
    return name ~ /^__.*__$/
}


function name_strict_symbol_p(name)
{
    return name ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
}



#*****************************************************************************
#
#       Utility functions
#
#*****************************************************************************
function integerp(pat)
{
    return pat ~ /^[-+]?[0-9]+$/
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


function assert_cmd_name_okay_to_define(name)
{
    if (! cmd_valid_p(name))
        error("Name '" name "' not valid:" $0)
    # fail if symbol or sequence or function
    if (! name_available_in_all_p(name, TYPE_FUNCTION TYPE_SEQUENCE TYPE_SYMBOL))
        error("Name '" name "' not available:" $0)
    return TRUE                 # not really necessary
}


function debugging_enabled_p()
{
    return sym_true_p("__DEBUG__")
    #return sym_defined_p("__DEBUG__") && sym_fetch("__DEBUG__") > 0
}

function dbg(key, lev)
{
    if (lev == "") lev = 1
    if (key == "") key = "m2"
    if (lev <= 0)  return TRUE
    return (debugging_enabled_p() && sym2_defined_p("__DEBUG__", key)) \
        ? sym2_fetch("__DEBUG__", key) >= lev \
        : FALSE
}

function dbg_set_level(key, lev)
{
    if (lev == "")
        lev = 1
    if (key == "")
        key = "m2"
    sym2_store("__DEBUG__", key, lev)
}

function dbg_print(key, lev, text)
{
    if (dbg(key, lev))
        print_stderr(text)
}

function currently_active_p()
{
    return active[ifdepth]
}


function strictp()
{
    return sym_true_p("__STRICT__")
}


function build_prog_cmdline(prog, arg, silent)
{
    assert_sym_defined(sym2_printable_form("__PROG__", prog), "build_prog_cmdline")
    return sprintf("%s %s%s", \
                   sym2_fetch("__PROG__", prog), \
                   arg, \
                   (silent ? " >/dev/null 2>/dev/null" : ""))
}


function exec_prog_cmdline(prog, arg,    sym)
{
    assert_sym_defined(sym2_printable_form("__PROG__", prog), "exec_prog_cmdline")
    return system(build_prog_cmdline(prog, arg, TRUE)) # always silent
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
        t = sym_fetch("__TMPDIR__")
    while (last(t) == "\n")
        t = chop(t)
    return t ((last(t) != "/") ? "/" : "")
}


function default_shell()
{
    if (sym_defined_p("M2_SHELL"))
        return sym_fetch("M2_SHELL")
    if ("SHELL" in ENVIRON)
        return ENVIRON["SHELL"]
    return sym2_fetch("__PROG__", "sh")
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
function hex_digits(n,    s)
{
    s = ""
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


# Quicksort - from "The AWK Programming Language" p. 161.
# Used in m2_dump() to sort the symbol table.
function qsort(A, left, right,    i, lastpos)
{
    if (left >= right)          # Do nothing if array contains
        return                  # less than two elements
    swap(A, left, left + int((right-left+1)*rand()))
    lastpos = left              # A[left] is now partition element
    for (i = left+1; i <= right; i++)
        if (_less_than(A[i], A[left]))
            swap(A, ++lastpos, i)
    swap(A, left, lastpos)
    qsort(A, left,   lastpos-1)
    qsort(A, lastpos+1, right)
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
    else if (toupper(s1) != toupper(s2)) return toupper(s1) < toupper(s2)
    else return s1 < s2
}


# Read multiple lines until delim is seen as first characters on a line.
# If delimiter is not found, return eof marker.  Intermediate lines are
# terminated with a newline character, but last line has it stripped
# away.  The lines read are NOT macro-expanded; if desired, the caller
# can invoke dosubs() on the returned buffer.  Special case if delim is "":
# read until end of file and return whatever is found, without error.
function read_lines_until(delim,    buf, delim_len)
{
    buf = ""
    delim_len = length(delim)
    while (TRUE) {
        if (readline() != READLINE_OK) {
            # eof or error, it's time to stop
            if (delim_len > 0)
                return EoF_marker
            else
                break
        }
        dbg_print("cmd", 3, "(read_lines_until) readline='" $0 "'")
        if (delim_len > 0 && !emptyp($0) && substr($0, 1, delim_len) == delim)
            break
        buf = buf $0 "\n"
    }
    return chop(buf)
}


#*****************************************************************************
#
#       Calc3
#
#*****************************************************************************

# calc3_eval is the main entry point.  All other _c3_* functions are
# for internal use and should not be called by the user.
function calc3_eval(s,    e)
{
    _S_expr = s
    gsub(/[ \t]+/, "", _S_expr)

    # Bare @expr@ returns most recent result
    if (emptyp(_S_expr))
        return sym_fetch("__EXPR__")

    _f = 1
    e = _c3_expr()
    if (_f <= length(_S_expr))
        error(sprintf("Math expression error at '%s':", substr(_S_expr, _f)) $0)
    else if (match(e, /^[-+]?(nan|inf)/))
        error(sprintf("Math expression error:'%s' returned \"%s\":", s, e) $0)
    else
        return e
}

# rel | rel relop rel
function _c3_expr(    var, e, op1, op2, m2)
{
    if (match(substr(_S_expr, _f), /^[A-Za-z#_][A-Za-z#_0-9]*=/)) {
        var = _c3_advance()
        sub(/=$/, "", var)
        return sym_store(var, _c3_expr())
    }

    e = _c3_rel()
    # Only one relational operator allowed: 1<2<3 is a syntax error
    if ((m2 = ((op2 = substr(_S_expr, _f, 2)) ~ /<=|==|!=|>=/))  ||
              ((op1 = substr(_S_expr, _f, 1)) ~ /<|>/)) {
        if (m2) {
            _f += 2             # Use +0 to force numeric comparison
            if (op2 == "<=") return e+0 <= _c3_rel()+0
            if (op2 == "==") return e+0 == _c3_rel()+0
            if (op2 == "!=") return e+0 != _c3_rel()+0
            if (op2 == ">=") return e+0 >= _c3_rel()+0
        } else {
            _f += 1
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
    while ((op = substr(_S_expr, _f, 1)) ~ /[+-]/) {
        _f++
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
    while ((op = substr(_S_expr, _f, 1)) ~ /[*\/%]/) {
        _f++
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
    if (substr(_S_expr, _f, 1) != "^") return e
    _f++
    return e ^ _c3_factor()
}

# [+-]?factor3 | !*factor2
function _c3_factor2(    e)
{
    e = substr(_S_expr, _f)
    if (e ~ /^[-+!]/) {      #unary operators [+-!]
        _f++
        if (e ~ /^\+/) return +_c3_factor3() # only one unary + allowed
        if (e ~ /^-/)  return -_c3_factor3() # only one unary - allowed
        if (e ~ /^!/)  return !(_c3_factor2() + 0) # unary ! may repeat
    }
    return _c3_factor3()
}

# number | varname | (expr) | function(...)
function _c3_factor3(    e, fun, e2)
{
    e = substr(_S_expr, _f)

    # number
    if (match(e, /^([0-9]+[.]?[0-9]*|[.][0-9]+)([Ee][+-]?[0-9]+)?/)) {
        return _c3_advance()
    }

    # function ()
    if (match(e, /^([A-Za-z#_][A-Za-z#_0-9]+)?\(\)/)) {
        fun = _c3_advance()
        if (fun ~ /^srand()/) return srand()
        if (fun ~ /^rand()/)  return rand()
        error(sprintf("Unknown function '%s'", fun))
    }

    # (expr) | function(expr) | function(expr,expr)
    if (match(e, /^([A-Za-z#_][A-Za-z#_0-9]+)?\(/)) {
        fun = _c3_advance()
        if (fun ~ /^(cos|deg|exp|int|log(10)?|rad|randint|sin|sqrt|srand|tan)?\(/) {
            e = _c3_expr()
            e = _c3_calculate_function(fun, e)
        } else if (fun ~ /^atan2\(/) {
            e = _c3_expr()
            if (substr(_S_expr, _f, 1) != ",") {
                error(sprintf("Missing ',' at '%s'", substr(_S_expr, _f)))
            }
            _f++
            e2 = _c3_expr()
            e = atan2(e, e2)
        } else
            error(sprintf("Unknown function '%s'", fun))

        if (substr(_S_expr, _f++, 1) != ")")
            error(sprintf("Missing ')' at '%s'", substr(_S_expr, _f)))
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
            return seqtab[e2, "value"]
    }

    # error
    error(sprintf("Expected number or '(' at '%s'", substr(_S_expr, _f)))
}

# Mathematical functions of one variable
function _c3_calculate_function(fun, e,    c)
{
    if (fun == "(")        return e
    if (fun == "cos(")     return cos(e)
    if (fun == "deg(")     return e * (360 / TAU)
    if (fun == "exp(")     return exp(e)
    if (fun == "int(")     return int(e)
    if (fun == "log(")     return log(e)
    if (fun == "log10(")   return log(e) / LOG10
    if (fun == "rad(")     return e * (TAU / 360)
    if (fun == "randint(") return randint(e) + 1
    if (fun == "sin(")     return sin(e)
    if (fun == "sqrt(")    return sqrt(e)
    if (fun == "srand(")   return srand(e)
    if (fun == "tan(")     { c = cos(e)
                             if (c == 0) error("Division by zero:" $0)
                             return sin(e) / c }
    error(sprintf("Unknown function '%s'", fun))
}

function _c3_advance(    tmp)
{
    tmp = substr(_S_expr, _f, RLENGTH)
    _f += RLENGTH
    return tmp
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

# @endcmd
function m2_endcmd()
{
    # @endcmd should never be encountered alone because m2_newcmd()
    # consumes any matching @endcmd.
    error("No corresponding '@newcmd':" $0)
}


# @default, @initialize NAME TEXT
function m2_default(    sym)
{
    if (! currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    assert_sym_okay_to_define(sym)

    if (sym_defined_p(sym)) {
        if ($1 == "@init" || $1 == "@initialize")
            error("Symbol '" sym "' already defined:" $0)
    } else
        dodef(FALSE)
}


# @append, @define      NAME TEXT
function m2_define(    append_flag)
{
    if (! currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    append_flag = ($1 == "@append")
    assert_sym_okay_to_define($2)

    dodef(append_flag)
}


# @divert               [N]
function m2_divert()
{
    if (! currently_active_p())
        return
    if (NF > 2)
        error("Bad parameters:" $0)
    $2 = (NF == 1) ? "0" : dosubs($2)
    if (! integerp($2))
        error(sprintf("Value '%s' must be numeric:", $2) $0)
    if ($2 > MAX_STREAM)
        error("Bad parameters:" $0)

    dbg_print("divert", 1, "divert(" $2 ")")
    sym_store("__DIVNUM__", int($2))
}


# @dump[all]            [FILE]
function m2_dump(    buf, cnt, definition, dumpfile, i, key, keys, fields, sym_name, all_flag)
{
    if (! currently_active_p())
        return
    if ((all_flag = $1 == "@dumpall") && init_deferred)
        initialize_deferred_symbols() # Show all system symbols

    if (NF > 1) {
        $1 = ""
        sub("^[ \t]*", "")
        dumpfile = rm_quotes(dosubs($0))
    }
    # Count and sort the keys from the symbol and sequence tables
    cnt = 0
    for (key in symtab) {
        if (all_flag || ! sym_system_p(key))
            keys[++cnt] = key
    }
    for (key in seqtab) {
        split(key, fields, SUBSEP)
        if (fields[2] == "defined")
            keys[++cnt] = fields[1]
    }
    for (key in cmdtab) {
        split(key, fields, SUBSEP)
        if (fields[2] == "defined")
            keys[++cnt] = fields[1]
    }
    qsort(keys, 1, cnt)

    # Format definitions
    buf = ""
    for (i = 1; i <= cnt; i++) {
        key = keys[i]
        if (sym_defined_p(key))
            buf = buf sym_definition_pp(key)
        else if (seq_defined_p(key))
            buf = buf seq_definition_pp(key)
        else if (cmd_defined_p(key))
            buf = buf cmd_definition_pp(key)
        else                    # Can't happen
            error("Name '" key "' not available:" $0)
    }
    buf = chop(buf)
    if (emptyp(buf)) {
        # I don't usually condone chatty programs, but it seems to me
        # that if the user asks for the symbol table and there's nothing
        # to print, she'd probably like to know.  Perhaps a config file
        # was not read properly...  Still, we only warn in strict mode.
        if (strictp())
            warn("Empty symbol table:" $0)
    } else if (dumpfile == "")  # No FILE arg provided to @dump command
        print_stderr(buf)
    else {
        print buf > dumpfile
        close(dumpfile)
    }
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


# @debug, @echo, @error, @stderr, @warn TEXT
# debug, error and warn format the message with file & line, etc.
# echo and stderr do no additional formatting.
#
# @debug only prints its message if debugging is enabled.  The user can
# control this since __DEBUG__ is an unprotected symbol.  @debug is
# purposefully not given access to the various dbg() keys and levels.
function m2_error(    m2_will_exit, do_format, do_print, message)
{
    if (! currently_active_p())
        return
    m2_will_exit = ($1 == "@error")
    do_format = ($1 == "@debug" || $1 == "@error" || $1 == "@warn")
    do_print  = ($1 != "@debug" || debugging_enabled_p())
    if (NF == 1) {
        message = format_message($1)
    } else {
        $1 = ""
        sub("^[ \t]*", "")
        message = dosubs($0)
        if (do_format)
            message = format_message(message)
    }
    if (do_print)
        print_stderr(message)
    if (m2_will_exit) {
        exit_code = EX_USER_REQUEST
        end_program(DISCARD_STREAMS)
    }
}


# @exit                 [CODE]
function m2_exit()
{
    if (! currently_active_p())
        return
    exit_code = (NF > 1 && integerp($2)) ? $2 : EX_OK
    end_program(SHIP_OUT_STREAMS)
}


# @flush
function m2_flush()
{
    if (! currently_active_p())
        return
    flush_stdout()
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
                assert_sym_valid_name(sym)
                cond = ! sym_true_p(sym)
            } else {
                assert_sym_valid_name($2)
                cond = sym_true_p($2)
            }
        } else if (NF == 3 && $2 == "!") {
            # @if ! FOO
            assert_sym_valid_name($3)
            cond = ! sym_true_p($3)
        } else if (NF == 4) {
            # @if FOO <op> BAR
            val2 = (sym_valid_p($2) && sym_defined_p($2)) ? sym_fetch($2) : $2
            op   = $3
            val4 = (sym_valid_p($2) && sym_defined_p($4)) ? sym_fetch($4) : $4

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
        assert_sym_valid_name($2)
        cond = ! sym_true_p($2)

    } else if ($1 == "if_defined" || $1 == "ifdef") {
        if (NF < 2) error("Bad parameters:" $0)
        assert_sym_valid_name($2)
        cond = sym_defined_p($2)

    } else if ($1 == "if_not_defined" || $1 == "ifndef") {
        if (NF < 2) error("Bad parameters:" $0)
        assert_sym_valid_name($2)
        cond = ! sym_defined_p($2)

    } else if ($1 == "if_env") {
        if (NF < 2) error("Bad parameters:" $0)
        assert_valid_env_var_name($2)
        cond = $2 in ENVIRON

    } else if ($1 == "if_not_env") {
        if (NF < 2) error("Bad parameters:" $0)
        assert_valid_env_var_name($2)
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
        assert_sym_valid_name($3)
        cond = sym2_defined_p($3, $2)

    } else if ($1 == "if_not_in") {
        if (NF < 3) error("Bad parameters:" $0)
        assert_sym_valid_name($3)
        cond = ! sym2_defined_p($3, $2)

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
    #        <...>
    #     Theodore Roosevelt
    # ignores <...> text up to, and including, the president's name.
    if (! currently_active_p())
        return
    if (NF != 2)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = sym_fetch("__LINE__")
    delim = $2
    buf = read_lines_until(delim)
    if (buf == EoF_marker)
        error(sprintf("Delimiter '%s' not found:%s" delim, save_line), "", save_lineno)
}


# @{s,}{include,paste}  FILE
function m2_include(    error_text, filename, read_literally, silent)
{
    if (! currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    read_literally = (substr($1, length($1) - 4) == "paste") # paste does not process macros
    silent         = (substr($1, 2, 1) == "s") # silent mutes file errors, even in strict mode
    $1 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))
    if (! dofile(filename, read_literally)) {
        if (silent) return
        error_text = "File '" filename "' does not exist:" $0
        if (strictp())
            error(error_text)
        else
            warn(error_text)
    }
}


# @decr, @incr          NAME [N]
function m2_incr(    sym, incr)
{
    if (! currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    assert_sym_okay_to_define(sym)
    assert_sym_defined(sym, "incr")
    if (NF >= 3 && ! integerp($3))
        error("Value '" $3 "' must be numeric:" $0)
    incr = (NF >= 3) ? $3 : 1
    sym_increment(sym, ($1 == "@incr") ? incr : -incr)
}


# @input                [NAME]
function m2_input(    getstat, input, sym)
{
    # Read a single line from /dev/tty.  No prompt is issued; if you
    # want one, use @echo.  Specify the symbol you want to receive the
    # data.  If no symbol is specified, __INPUT__ is used by default.
    if (! currently_active_p())
        return
    sym = (NF < 2) ? "__INPUT__" : $2
    assert_sym_okay_to_define(sym)
    getstat = getline input < "/dev/tty"
    if (getstat < 0) {
        warn("Error reading '/dev/tty' [input]:" $0)
        input = ""
    }
    sym_store(sym, input)
}


# @longdef              NAME
function m2_longdef(    buf, save_line, save_lineno, sym)
{
    if (! currently_active_p())
        return
    if (NF != 2)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = sym_fetch("__LINE__")
    sym = $2
    assert_sym_okay_to_define(sym)
    buf = read_lines_until("@endlong")
    if (buf == EoF_marker)
        error("Delimiter '@endlongdef' not found:" save_line, "", save_lineno)
    sym_store(sym, buf)
}


# @endlongdef
function m2_endlongdef()
{
    # @endlongdef should never be encountered alone because m2_longdef()
    # consumes any matching @endlongdef.
    error("No corresponding '@longdef':" $0)
}


# @newcmd               NAME
#
# Q. What is the difference between @define and @newcmd?
# A. @define (and @longdef) create a symbol whose value can be substituted
# in-line whenever you wish, by surrounding it with "@" characters, as in:
#
#     Hello @name@, I just got a great deal on this new @item@ !!!
#
# You can also invoke mini "functions", little in-line functions that may
# take parameters but generally produce or modify output in some way.
#
# Names declared with @newcmd are recognized and run in the procedure
# that processes the control commands (@if, @define, etc).  These things
# can only be on a line of their own and (mostly) do not produce output.
function m2_newcmd(    buf, save_line, save_lineno, name, nparam, i)
{
    if (! currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    name = $2
    assert_cmd_name_okay_to_define(name)
    save_line = $0
    save_lineno = sym_fetch("__LINE__")

    buf = read_lines_until("@endcmd")
    if (buf == EoF_marker)
        error("Delimiter '@endcmd' not found:" save_line, "", save_lineno)

    cmdtab[name, "defined"]    = TRUE
    cmdtab[name, "definition"] = buf
    cmdtab[name, "nparam"]     = nparam
}


# @read                 NAME FILE
function m2_read(    sym, filename, line, val, getstat)
{
    # This is not intended to be a full-blown file inputter but rather just
    # to read short snippets like a file path or username.  As usual, multi-
    # line values are accepted but the final trailing \n (if any) is stripped.
    if (! currently_active_p())
        return
    #dbg_print("read", 7, ("@read: $0='" $0 "'"))
    if (NF < 3)
        error("Bad parameters:" $0)
    sym  = $2
    assert_sym_okay_to_define(sym)

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
    sym_store(sym, chomp(val))
}


# @sequence             ID SUBCMD [ARG...]
function m2_sequence(    id, action, arg, saveline)
{
    if (! currently_active_p())
        return
    if (NF < 3)
        error("Bad parameters:" $0)
    id = $2
    assert_seq_valid_name(id)
    action = $3
    if (action != "create" && ! seq_defined_p(id))
        error("Name '" id "' not defined [sequence]:" $0)
    if (NF == 3) {
        if (action == "create") {
            assert_seq_okay_to_define(id)
            seqtab[id, "defined"] = TRUE
            seqtab[id, "inc"]     = SEQ_DEFAULT_INC
            seqtab[id, "init"]    = SEQ_DEFAULT_INIT
            seqtab[id, "fmt"]     = sym2_fetch("__FMT__", "seq")
            seqtab[id, "value"]   = SEQ_DEFAULT_INIT
        } else if (action == "delete") {
            seq_destroy(id)
        } else if (action == "next") { # Increment counter only, no output
            seqtab[id, "value"] += seqtab[id, "inc"]
        } else if (action == "prev") { # Decrement counter only, no output
            seqtab[id, "value"] -= seqtab[id, "inc"]
        } else if (action == "restart") { # Set current counter value to initial value
            seqtab[id, "value"] = seqtab[id, "init"]
        } else
            error("Bad parameters:" $0)
    } else {    # NF >= 4
        saveline = $0
        sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/, "") # a + this time because ARG is required
        arg = $0
        if (action == "format") {
            # format STRING :: Set format string for printf to STRING.
            # Arg should be the format string to use with printf.  It
            # must include exactly one %d for the sequence value, and no
            # other argument-consuming formatting characters.  You might
            # specify %x to print in hexadecimal instead.  The point is,
            # m2 can't police your format string and a bad value might
            # cause a crash if printf() fails.
            seqtab[id, "fmt"] = arg
        } else if (action == "inc") {
            # inc N :: Set increment value to N.
            if (! integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            if (arg+0 == 0)
                error(sprintf("Bad parameters in 'inc':%s", saveline))
            seqtab[id, "inc"] = int(arg)
        } else if (action == "init") {
            # init N :: Set initial  value to N.  If current
            # value == old init value (i.e., never been used), then set
            # the current value to the new init value also.  Otherwise
            # current value remains unchanged.
            if (! integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            if (seqtab[id, "value"] == seqtab[id, "init"])
                seqtab[id, "value"] = int(arg)
            seqtab[id, "init"] = int(arg)
        } else if (action == "set") {
            # set N :: Set counter value directly to N.
            if (! integerp(arg))
                error(sprintf("Value '%s' must be numeric:%s", arg, saveline))
            seqtab[id, "value"] = int(arg)
        } else
           error("Bad parameters:" saveline)
    }
}


# @shell                DELIM [PROG]
# Set symbol "M2_SHELL" to override.
function m2_shell(    delim, save_line, save_lineno, input_text, input_file,
                      output_text, output_file, sendto, path_fmt, getstat,
                      cmdline)
{
    # The sendto program defaults to a reasonable shell but you can
    # specify where you want to send your data.  Possibly useful choices
    # would be an alternative shell, an email message reader, or
    # /usr/bin/bc.  It must be a program that functions as a filter (in
    # the Unix sense, i.e., reading from standard input and writing to
    # standard output).  Standard error is not redirected, so any errors
    # will appear on the user's terminal.
    if (! currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = sym_fetch("__LINE__")
    delim = $2
    if (NF == 2) {              # @shell DELIM
        sendto = default_shell()
    } else {                    # @shell DELIM /usr/ucb/mail
        $1 = ""; $2 = ""
        sub("^[ \t]*", "")
        sendto = rm_quotes(dosubs($0))
    }

    input_text = read_lines_until(delim)
    if (input_text == EoF_marker)
        error("Delimiter '" delim "' not found:" save_line, "", save_lineno)

    path_fmt    = sprintf("%sm2-%d.shell-%%s", tmpdir(), sym_fetch("__PID__"))
    input_file  = sprintf(path_fmt, "in")
    output_file = sprintf(path_fmt, "out")
    print dosubs(input_text) > input_file
    close(input_file)

    # Don't tell me how fragile this is, we're whistling past the
    # graveyard here.  But it suffices to run /bin/sh, which is enough.
    cmdline = sprintf("%s < %s > %s", sendto, input_file, output_file)
    sym_store("__STATUS__", system(cmdline))
    while (TRUE) {
        getstat = getline line < output_file
        if (getstat < 0)        # Error
            warn("Error reading '" output_file "' [shell]")
        if (getstat <= 0)       # End of file
            break
        output_text = output_text line "\n" # Read a line
    }
    close(output_file)

    exec_prog_cmdline("rm", ("-f " input_file))
    exec_prog_cmdline("rm", ("-f " output_file))
    ship_out(output_text)
}


# @typeout
function m2_typeout(    buf)
{
    if (! currently_active_p())
        return
    buf = read_lines_until("")
    if (! emptyp(buf))
        ship_out(buf "\n")
}


# @undef[ine]           NAME
function m2_undefine(    name)
{
    if (! currently_active_p())
        return
    if (NF != 2)
        error("Bad parameters:" $0)
    name = $2
    if (seq_valid_p(name) && seq_defined_p(name))
        seq_destroy(name)
    else if (cmd_valid_p(name) && cmd_defined_p(name)) {
        cmd_destroy(name)
    } else {
        name = sym_root(name)
        assert_sym_valid_name(name)
        assert_sym_unprotected(name)
        # System symbols, even unprotected ones -- despite being subject
        # to user modification -- cannot be undefined.
        if (sym_system_p(name))
            error("Name '" name "' not available:" $0)
        sym_destroy(name)
    }
}


# @undivert             [N]
function m2_undivert(    stream, i)
{
    if (! currently_active_p())
        return
    if (NF == 1)
        undivert_all()
    else {
        i = 1
        while (++i <= NF) {
            stream = dosubs($i)
            if (! integerp(stream))
                error(sprintf("Value '%s' must be numeric:", stream) $0)
            if (stream > MAX_STREAM)
                error("Bad parameters:" $0)
            undivert(stream)
        }
    }
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
function dofile(filename, read_literally,    savebuffer, savefile, saveifdepth, saveline, saveuuid)
{
    if (filename == "-")
        filename = "/dev/stdin"
    if (! path_exists_p(filename))
        return FALSE
    dbg_print("m2", 1, ("(dofile) filename='" filename "'" \
                        (read_literally ? ", read_literally=TRUE" : "") \
                        ")"))
    if (filename in activefiles)
        error("Cannot recursively read '" filename "':" $0)

    # Save old file context
    savebuffer  = buffer
    savefile    = sym_fetch("__FILE__")
    saveifdepth = ifdepth
    saveline    = sym_fetch("__LINE__")
    saveuuid    = sym_fetch("__FILE_UUID__")

    # Set up new file context
    activefiles[filename] = TRUE
    buffer = ""
    sym_increment("__NFILE__", 1)
    sym_store("__FILE__", filename)
    sym_store("__LINE__", 0)
    sym_store("__FILE_UUID__", uuid())

    # Read the file and process each line
    while (readline() == READLINE_OK)
        process_line(read_literally)

    # Reached end of file
    flush_stdout()
    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != "-" && filename != "/dev/stdin")
        close(filename)
    delete activefiles[filename]

    # Restore previous file context
    if (ifdepth > saveifdepth)
        error("Delimiter '@endif' not found")
    buffer = savebuffer
    sym_store("__FILE__", savefile)
    sym_store("__LINE__", saveline)
    sym_store("__FILE_UUID__", saveuuid)

    return TRUE
}


# Put next input line into global string "buffer".  The readline()
# function manages the "pushback."  After expanding a macro, macro
# processors examine the newly created text for any additional macro
# names.  Only after all expanded text has been processed and sent to
# the output does the program get a fresh line of input.
# Return EoF_marker or "" (null string)
function readline(    getstat, i, status)
{
    status = READLINE_OK
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
        getstat = getline < sym_fetch("__FILE__")
        if (getstat < 0) {       # Error
            status = READLINE_ERROR
            warn("Error reading '" sym_fetch("__FILE__") "' [readline]")
        } else if (getstat == 0) # End of file
            status = READLINE_EOF
        else {                   # Read a line
            sym_increment("__LINE__", 1)
            sym_increment("__NLINE__", 1)
        }
    }
    # Hack: allow @Mname at start of line without a closing @.
    # This only applies if in non-strict mode.  Note, macro name must
    # start with a capital letter and must not be passed any parameters.
    if (! strictp() && ($0 ~ /^@[A-Z][A-Za-z#_0-9]*[ \t]*$/))
        sub(/[ \t]*$/, "@")
    return status
}


function process_line(read_literally,    name, sp, lbrace, cut, newstring, user_cmd)
{
    dbg_print("cmd", 1, "(process_line) Start; line " sym_fetch("__LINE__") ": $0='" $0 "'")

    # Short circuit if we're not processing macros, or no @ found
    if (read_literally ||
        (currently_active_p() && index($0, "@") == IDX_NOT_FOUND)) {
        ship_out($0 "\n")
        return
    }

    # Look for control commands.  These are hard-wired, and cannot be
    # overridden by @newcmd.  Note, they only match at beginning of line.
    if      (/^@(@|;|#)/)                 { } # Comments are ignored
    else if (/^@append([ \t]|$)/)         { m2_define() }
    else if (/^@c(omment)?([ \t]|$)/)     { } # Comments are ignored
    else if (/^@decr([ \t]|$)/)           { m2_incr() }
    else if (/^@default([ \t]|$)/)        { m2_default() }
    else if (/^@define([ \t]|$)/)         { m2_define() }
    else if (/^@debug([ \t]|$)/)          { m2_error() }
    else if (/^@divert([ \t]|$)/)         { m2_divert() }
    else if (/^@dump(all|def)?([ \t]|$)/) { m2_dump() }
    else if (/^@echo([ \t]|$)/)           { m2_error() }
    else if (/^@else([ \t]|$)/)           { m2_else() }
    else if (/^@endcmd([ \t]|$)/)         { m2_endcmd() }
    else if (/^@(endif|fi)([ \t]|$)/)     { m2_endif() }
    else if (/^@endlong(def)?([ \t]|$)/)  { m2_endlongdef() }
    else if (/^@err(or|print)([ \t]|$)/)  { m2_error() }
    else if (/^@(m2)?exit([ \t]|$)/)      { m2_exit() }
    else if (/^@flush([ \t]|$)/)          { m2_flush() }
    else if (/^@if(_not)?(_(defined|env|exists|in))?([ \t]|$)/)
                                          { m2_if() }
    else if (/^@ifn?def([ \t]|$)/)        { m2_if() }
    else if (/^@ignore([ \t]|$)/)         { m2_ignore() }
    else if (/^@s?include([ \t]|$)/)      { m2_include() }
    else if (/^@incr([ \t]|$)/)           { m2_incr() }
    else if (/^@init(ialize)?([ \t]|$)/)  { m2_default() }
    else if (/^@input([ \t]|$)/)          { m2_input() }
    else if (/^@longdef([ \t]|$)/)        { m2_longdef() }
    else if (/^@newcmd([ \t]|$)/)         { m2_newcmd() }
    else if (/^@s?paste([ \t]|$)/)        { m2_include() }
    else if (/^@read([ \t]|$)/)           { m2_read() }
    else if (/^@sequence([ \t]|$)/)       { m2_sequence() }
    else if (/^@shell([ \t]|$)/)          { m2_shell() }
    else if (/^@stderr([ \t]|$)/)         { m2_error() }
    else if (/^@typeout([ \t]|$)/)        { m2_typeout() }
    else if (/^@undef(ine)?([ \t]|$)/)    { m2_undefine() }
    else if (/^@undivert([ \t]|$)/)       { m2_undivert() }
    else if (/^@unless([ \t]|$)/)         { m2_if() }
    else if (/^@warn([ \t]|$)/)           { m2_error() }

    # Check for user commands
    else if (currently_active_p() &&
             first($1) == "@"     &&
             cmd_defined_p(substr($1, 2)))
        docommand()

    # Process @
    else {
        newstring = dosubs($0)
        if (newstring == $0 || index(newstring, "@") == IDX_NOT_FOUND) {
            if (currently_active_p())
                ship_out(newstring "\n")
        } else {
            buffer = newstring "\n" buffer
        }
    }
    dbg_print("cmd", 1, "(process_line) End")
}

# This is only called by process_line(), which guarantees that $0 is
# unchanged, and that $1 is "@<CMD>".  This is important because we have
# to get the command name from there (i.e., $1).  It's *not* passed in
# as a parameter as you might expect.  Also, process_line checks to make
# sure cmdtab[NAME] is defined; we trust that and just blindly grab the
# definition.  Arguments/parameters are WIP.
function docommand(    cmdname, narg, args, i, nparam, savebuffer, savefile, saveifdepth, saveline)
{
    dbg_print("cmd", 1, "(docommand) Start; line " sym_fetch("__LINE__") ": $0='" $0 "'")
    narg = NF - 1

    savebuffer  = buffer
    savefile    = sym_fetch("__FILE__")
    saveifdepth = ifdepth
    saveline    = sym_fetch("__LINE__")

    cmdname = substr($1, 2)
    buffer = cmdtab[cmdname, "definition"]
    sym_store("__FILE__", $1)
    sym_store("__LINE__", 0)

    while (buffer != "") {
        # Extract each line from buffer, one by one
        sym_increment("__LINE__", 1) # __LINE__ is local, but not __NLINE__
        if ((i = index(buffer, "\n")) == IDX_NOT_FOUND) {
            $0 = buffer
            buffer = ""
        } else {
            $0 = substr(buffer, 1, i-1)
            buffer = substr(buffer, i+1)
        }

        # Hack: allow @Mname at start of line without a closing @.
        # This only applies if in non-strict mode.  Note, macro name must
        # start with a capital letter and must not be passed any parameters.
        if (! strictp() && ($0 ~ /^@[A-Z][A-Za-z#_0-9]*[ \t]*$/))
            sub(/[ \t]*$/, "@")

        # String we want is in $0, go evaluate it
        dbg_print("cmd", 5, "(docommand) About to call process line with $0 = '" $0 "'")
        process_line()
    }

    # Restore to before command ran
    if (ifdepth > saveifdepth)
        error("Delimiter '@endif' not found")
    buffer = savebuffer
    sym_store("__FILE__", savefile)
    sym_store("__LINE__", saveline)
    dbg_print("cmd", 1, "(docommand) End")
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
function dosubs(s,    expand, i, j, l, m, nparam, p, param, r, fn, cmdline,
                      at_brace, x, y, inc_dec, pre_post, subcmd)
{
    l = ""                   # Left of current pos  - ready for output
    r = s                    # Right of current pos - as yet unexamined
    inc_dec = pre_post = 0   # track ++ or -- on sequences

    while (TRUE) {
        # Check entire string for recursive evaluation
        if (index(r, "@{") != IDX_NOT_FOUND)
            r = expand_braces(r)

        i = index(r, "@")
        if (i == IDX_NOT_FOUND)
            break

        dbg_print("dosubs", 7, (sprintf("(dosubs) Top of loop: l='%s', r='%s', expand='%s'", l, r, expand)))
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
        # - m :: Entire text between @'s.  Example: "mid foo 3".
        # - fn :: The name of the "function" to call.  The first element
        #         of m.  Example: "mid".
        # - nparam :: Number of parameters supplied to the function.
        #     @mid@         --> nparam == 0
        #     @mid foo@     --> nparam == 1
        #     @mid foo 3@   --> nparam == 2
        # In general, a function's parameter N is available in variable
        #   param[N+1].  Consider "mid foo 3".  nparam is 2.
        #   The fn is found in the first position, at param [0+1].
        #   The new prefix is at param[1+1] and new count is at param[2+1].
        #   This offset of one is referred to as `_fencepost' below.
        # Each function condition eventually executes
        #     r = <SOMETHING> r
        #   which injects <SOMETHING> just before the current value of
        #   r.  (r is defined above.)  r is what is to the right of the
        #   current position and contains as yet unexamined text that
        #   needs to be evaluated for possible macro processing.  This
        #   is the data we were going to evaluate anyway.  In other
        #   words, this injects the result of "invoking" fn.
        # Eventually this big while loop exits and we return "l r".

        nparam = split(m, param) - _fencepost
        fn = param[0 + _fencepost]
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

        # basename SYM: Base (i.e., file name) of path
        # dirname SYM: Directory name of path
        if (fn == "basename" || fn == "dirname") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            cmdline = build_prog_cmdline(fn, rm_quotes(sym_fetch(p)), FALSE)
            cmdline | getline expand
            close(cmdline)
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
            p = param[1 + _fencepost]
            # Always accept your current representation of true or false
            # to actually be true or false without further evaluation.
            if (p == sym2_fetch("__FMT__", TRUE) ||
                p == sym2_fetch("__FMT__", FALSE))
                r = p r
            else if (sym_valid_p(p)) {
                # It's a valid name -- now see if it's defined or not.
                # If not, check if we're in strict mode (error) or not.
                if (sym_defined_p(p))
                    r = sym2_fetch("__FMT__", sym_true_p(p)) r
                else if (strictp())
                    error("Name '" p "' not defined [boolval]:" $0)
                else
                    r = sym2_fetch("__FMT__", FALSE) r
            } else
                # It's not a symbol, so use its value interpreted as a boolean
                r = sym2_fetch("__FMT__", !!p) r

        # date  : Current date as YYYY-MM-DD
        # epoch : Number of seconds since Epoch
        # time  : Current time as HH:MM:SS
        # tz    : Current time zone name
        } else if (fn == "date" ||
                   fn == "epoch" ||
                   fn == "time" ||
                   fn == "tz") {
            y = sym2_fetch("__FMT__", fn)
            gsub(/"/, "\\\"", y)
            cmdline = build_prog_cmdline("date", "+\"" y "\"", FALSE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # expr ...: Evaluate mathematical epxression, store in __EXPR__
        } else if (fn == "expr") {
            sub(/^expr[ \t]*/, "", m) # clean up expression to evaluate
            x = calc3_eval(m)
            dbg_print("expr", 1, sprintf("expr{%s} = %s", m, x))
            sym_store("__EXPR__", x)
            r = x r

        # getenv : Get environment variable
        #   @getenv HOME@ => /home/user
        } else if (fn == "getenv") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_valid_env_var_name(p)
            if (p in ENVIRON)
                r = ENVIRON[p] r
            else if (strictp())
                error("Environment variable '" p "' not defined:" $0)

        # lc : Lower case
        # len : Length.        @len SYM@ => N
        # uc SYM: Upper case
        } else if (fn == "lc" ||
                   fn == "len" ||
                   fn == "uc") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_sym_valid_name(p)
            assert_sym_defined(p, fn)
            r = ((fn == "lc")  ? tolower(sym_fetch(p)) : \
                 (fn == "len") ?  length(sym_fetch(p)) : \
                 (fn == "uc")  ? toupper(sym_fetch(p)) : \
                 error("Name '" m "' not defined [can't happen]:" $0)) \
                r   # ^^^ This error() bit can't happen but I need something
                    # to the right of the :, and error() will abend.

        # left : Left (substring)
        #   @left ALPHABET 7@ => ABCDEFG
        } else if (fn == "left") {
            if (nparam < 1 || nparam > 2) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_sym_valid_name(p)
            assert_sym_defined(p, "left")
            x = 1
            if (nparam == 2) {
                x = param[2 + _fencepost]
                if (! integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(sym_fetch(p), 1, x) r

        # mid : Substring ...  SYMBOL, START[, LENGTH]
        #   @mid ALPHABET 15 5@ => OPQRS
        #   @mid FOO 3@
        #   @mid FOO 2 2@
        } else if (fn == "mid" || fn == "substr") {
            if (nparam < 2 || nparam > 3)
                error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_sym_valid_name(p)
            assert_sym_defined(p, "mid")
            x = param[2 + _fencepost]
            if (! integerp(x))
                error("Value '" x "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(sym_fetch(p), x) r
            } else if (nparam == 3) {
                y = param[3 + _fencepost]
                if (! integerp(y))
                    error("Value '" y "' must be numeric:" $0)
                r = substr(sym_fetch(p), x, y) r
            }

        # rem : Remark
        #   @rem STUFF@ is considered a comment and ignored
        } else if (fn == "rem") {
            ;

        # right : Right (substring)
        #   @right ALPHABET 20@ => TUVWXYZ
        } else if (fn == "right") {
            if (nparam < 1 || nparam > 2) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_sym_valid_name(p)
            assert_sym_defined(p, "left")
            x = length(sym_fetch(p))
            if (nparam == 2) {
                x = param[2 + _fencepost]
                if (! integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(sym_fetch(p), x) r

        # spaces [N]: N spaces
        } else if (fn == "spaces") {
            if (nparam > 1) error("Bad parameters in '" m "':" $0)
            x = 1
            if (nparam == 1) {
                x = param[1 + _fencepost]
                if (! integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            while (x-- > 0)
                expand = expand " "
            r = expand r

        # trim SYM: Remove leading and trailing whitespace
        } else if (fn == "trim") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + _fencepost]
            assert_sym_valid_name(p)
            assert_sym_defined(p, "trim")
            expand = sym_fetch(p)
            sub(/^[ \t]+/, "", expand)
            sub(/[ \t]+$/, "", expand)
            r = expand r

        # uuid : Something that resembles but is not a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (fn == "uuid") {
            r = uuid() r

        # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
        } else if (sym_valid_p(fn) && sym_defined_p(fn)) {
            expand = sym_fetch(fn)
            # Expand $N parameters (includes $0 for macro name)
            j = MAX_PARAM   # but don't go overboard with params
            # Count backwards to get around $10 problem.
            while (j-- >= 0) {
                if (index(expand, "${" j "}") != IDX_NOT_FOUND) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$\\{" j "\\}", param[j + _fencepost], expand)
                 }
                if (index(expand, "$" j) != IDX_NOT_FOUND) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$" j, param[j + _fencepost], expand)
                }
            }
            r = expand r

        # Check if it's a sequence
        } else if (seq_valid_p(fn) && seq_defined_p(fn)) {
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
                if (pre_post == 0)
                    # normal call : insert current value with formatting
                    r = sprintf(seqtab[fn, "fmt"], seqtab[fn, "value"]) r
                else {
                    # Handle prefix xor postfix increment/decrement
                    if (pre_post == -1)    # prefix
                        if (inc_dec == -1) # decrement
                            seqtab[fn, "value"] -= seqtab[fn, "inc"]
                        else
                            seqtab[fn, "value"] += seqtab[fn, "inc"]
                    # Get current value with desired formatting
                    r = sprintf(seqtab[fn, "fmt"], seqtab[fn, "value"]) r
                    if (pre_post == +1)    # postfix
                        if (inc_dec == -1)
                            seqtab[fn, "value"] -= seqtab[fn, "inc"]
                        else
                            seqtab[fn, "value"] += seqtab[fn, "inc"]
                }
            } else {
                if (pre_post != 0)
                    error("Bad parameters in '" m "':" $0)
                subcmd = param[1 + _fencepost]
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
                        r = seqtab[fn, "value"] r
                    } else if (subcmd == "nextval") {
                        # - nextval :: Increment and return new value of
                        # counter.  No prefix/suffix.
                        seqtab[fn, "value"] += seqtab[fn, "inc"]
                        r = seqtab[fn, "value"] r
                    } else
                        error("Bad parameters in '" m "':" $0)
                } else {
                    # These take one or more params.  Nothing here!
                    error("Bad parameters in '" m "':" $0)
                }
            }

        # Throw an error on undefined symbol (strict-only)
        } else if (strictp()) {
            error("Name '" m "' not defined [strict mode]:" $0)

        } else {
            l = l "@" m
            r = "@" r
        }
        i = index(r, "@")
    }

    dbg_print("dosubs", 3, sprintf("(dosubs) Out of loop, returning l r: l='%s', r='%s'", l, r))
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
            error("Bad @{...} expansion:" s)
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

        s = ltext dosubs("@" mtext "@") rtext
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
#     s         String to examine.
#     start     The position in s, not necessarily 1, of the "@{"
#               for which we need to find the closing brace.
#
# LOCAL VARIABLES
#     i         Counter of current offset into s from start.
#               Initially i=0.  As we scan right, i will be incremented.
#     c         The current character, at position i.
#                   c = substr(s, start+i, 1)
#     nc        The next character past c, at position i+1.
#                   nc = substr(s, start+i+1, 1)
#     cb        Position of inner "}" found via recursion.
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
    # Look at the character (c) immediately following "@{", and also the
    # next character (nc) after that.  One or both might be empty string.
    i  = 2
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
        if (readline() == READLINE_EOF)
            error("Unexpected end of definition:" name)
        # old bug: sub(/\\$/, "\n" $0, str)
        x = $0
        sub(/^[ \t]+/, "", x)
        str = chop(str) "\n" x
    }
    sym_store(name, append_flag ? sym_fetch(name) str : str)
}


# Try to read init files: $M2RC, $HOME/.m2rc, and/or ./.m2rc
# M2RC is intended to *override* $HOME, so if the variable is specified
# and the file exists, then do that file; only otherwise do $HOME/.m2rc.
# An init file from the current directory is always attempted in any
# case.  No worries or errors if any of them don't exist.
function load_init_files()
{
    # Don't load the init files more than once
    if (init_files_loaded == TRUE)
        return

    if ("M2RC" in ENVIRON && path_exists_p(ENVIRON["M2RC"]))
        dofile(ENVIRON["M2RC"], FALSE)
    else if ("HOME" in ENVIRON)
        dofile(ENVIRON["HOME"] "/.m2rc", FALSE)
    dofile("./.m2rc", FALSE)

    # Don't count init files in total line/file tally - it's better to
    # keep them in sync with the files from the command line.
    sym_store("__NFILE__", 0)
    sym_store("__NLINE__", 0)
    init_files_loaded = TRUE
}


# Change these paths as necessary for correct operation on your system.
# It is important that __PROG__ remain a protected symbol.  Otherwise,
# some bad person could entice you to evaluate:
#       @define __PROG__[stat]  /bin/rm
#       @include my_precious_file
function setup_prog_paths()
{
    sym2_store("__PROG__", "basename", "/usr/bin/basename")
    sym2_store("__PROG__", "date",     "/bin/date")
    sym2_store("__PROG__", "dirname",  "/usr/bin/dirname")
    sym2_store("__PROG__", "hostname", "/bin/hostname")
    sym2_store("__PROG__", "id",       "/usr/bin/id")
    sym2_store("__PROG__", "rm",       "/bin/rm")
    sym2_store("__PROG__", "sh",       "/bin/sh")
    sym2_store("__PROG__", "stat",     "/usr/bin/stat")
    sym2_store("__PROG__", "uname",    "/usr/bin/uname")
    sym_store("__TMPDIR__",            "/tmp")
}


# Nothing here is user-customizable
function initialize(    get_date_cmd, d, dateout, array, elem, i)
{
    DISCARD_STREAMS   = 0
    E                 = exp(1)
    FALSE             = 0
    IDX_NOT_FOUND     = 0
    LOG10             = log(10)
    MAX_PARAM         = 20
    MAX_STREAM        = 9
    PI                = atan2(0, -1)
    READLINE_ERROR    = -1
    READLINE_EOF      = 0
    READLINE_OK       = 1
    SEQ_DEFAULT_INC   = 1
    SEQ_DEFAULT_INIT  = 0
    SHIP_OUT_STREAMS  = 1
    TAU               = 2 * PI
    TRUE              = 1
    TYPE_ANY          = "*"
    TYPE_CMD          = "C"     # cmdtab
    TYPE_FUNCTION     = "F"     # functab
    TYPE_SEQUENCE     = "Q"     # seqtab
    TYPE_SYMBOL       = "S"     # symtab

    EoF_marker        = build_subsep("EoF1", "EoF2") # Unlikely to occur in normal text
    init_deferred     = TRUE    # Becomes FALSE in initialize_deferred_symbols()
    init_files_loaded = FALSE   # Becomes TRUE in load_init_files()
    ifdepth           = 0
    active[ifdepth]   = TRUE
    _fencepost        = 1
    buffer            = ""

    srand()                     # Seed random number generator
    setup_prog_paths()

    # Capture m2 run start time.                 1  2  3  4  5  6  7  8
    get_date_cmd = build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z %s'", FALSE)
    get_date_cmd | getline dateout
    split(dateout, d)
    close(get_date_cmd)

    sym_store("__DATE__",               d[1] d[2] d[3])
    sym_store("__DEBUG__",              FALSE)
    sym_store("__DIVNUM__",             0)
    sym_store("__EPOCH__",              d[8])
    sym_store("__EXPR__",               0)
    sym_store("__FILE__",               "")
    sym_store("__FILE_UUID__",          "")
    sym2_store("__FMT__", TRUE,         "1")
    sym2_store("__FMT__", FALSE,        "0")
    sym2_store("__FMT__", "date",       "%Y-%m-%d")
    sym2_store("__FMT__", "epoch",      "%s")
    sym2_store("__FMT__", "seq",        "%d")
    sym2_store("__FMT__", "time",       "%H:%M:%S")
    sym2_store("__FMT__", "tz",         "%Z")
    sym_store("__INPUT__",              "")
    sym_store("__LINE__",               0)
    sym_store("__M2_UUID__",            uuid())
    sym_store("__M2_VERSION__",         version)
    sym_store("__NFILE__",              0)
    sym_store("__NLINE__",              0)
    sym_store("__STRICT__",             TRUE)
    sym_store("__TIME__",               d[4] d[5] d[6])
    sym_store("__TIMESTAMP__",          d[1] "-" d[2] "-" d[3] "T" \
                                        d[4] ":" d[5] ":" d[6] d[7])
    sym_store("__TZ__",                 d[7])

    # These symbols' definitions are deferred until needed, because
    # initialization requires several relatively expensive subprocesses.
    split("__GID__ __HOST__ __HOSTNAME__ __OSNAME__ __PID__" \
          " __UID__ __USER__ unix",                          \
          array, " ")
    for (elem in array)
        deferred_syms[array[elem]] = TRUE

    # These non-system symbol names are protected and cannot be modified
    split("e pi tau unix", array, " ")
    for (elem in array)
        protected_syms[array[elem]] = TRUE

    # These symbols can be modified by the user
    split("__DEBUG__ __FMT__ __INPUT__ __STRICT__ __TMPDIR__", array, " ")
    for (elem in array)
        unprotected_syms[array[elem]] = TRUE

    # Functions cannot be used as symbol or sequence names.
    split("basename boolval date dirname epoch expr getenv lc left len" \
          " mid rem right spaces time trim tz uc uuid", array, " ")
    for (elem in array)
        functab[array[elem]] = TRUE

    # Zero stream buffers
    for (i = 1; i <= MAX_STREAM; i++)
        streambuf[i] = ""
}


# The code here requires invoking several subprocesses, a somewhat slow
# operation.  Since these features may not be used often, they are run
# only on-demand in order to speed up general usage.
function initialize_deferred_symbols(    gid, host, hostname, osname, pid, uid, user, elem, array)
{
    init_deferred = FALSE

    build_prog_cmdline("id", "-g", FALSE)              | getline gid
    build_prog_cmdline("hostname", "-s", FALSE)        | getline host
    build_prog_cmdline("hostname", "-f", FALSE)        | getline hostname
    build_prog_cmdline("uname", "-s", FALSE)           | getline osname
    build_prog_cmdline("sh", "-c 'echo $PPID'", FALSE) | getline pid
    build_prog_cmdline("id", "-u", FALSE)              | getline uid
    build_prog_cmdline("id", "-un", FALSE)             | getline user

    sym_store("__GID__",      gid)
    sym_store("__HOST__",     host)
    sym_store("__HOSTNAME__", hostname)
    sym_store("__OSNAME__",   osname)
    sym_store("__PID__",      pid)
    sym_store("__UID__",      uid)
    sym_store("__USER__",     user)

    split("Darwin FreeBSD Linux OpenBSD SunOS", array, " ")
    for (elem in array)
        if (osname == array[elem]) {
            sym_store("unix", TRUE)
            break
        }
}


# This function is called automagically (it's baked into sym_store())
# every time a non-zero value is stored into __DEBUG__.
function initialize_debugging()
{
    # dbg_set_level("cmd", 5)
    # dbg_set_level("dosubs", 7)
}


# The main program occurs in the BEGIN procedure below.
BEGIN {
    initialize()

    # No command line arguments: process standard input.
    if (ARGC == 1) {
        load_init_files()
        exit_code = dofile("-", FALSE) ? EX_OK : EX_NOINPUT

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
                val = substr(arg, eq+1)
                if (! sym_valid_p(name))
                    error("Name '" name "' not valid:" arg, "ARGV", i)
                if (sym_protected_p(name))
                    error("Symbol '" name "' protected:" arg, "ARGV", i)
                if (name == "strict")
                    name = "__STRICT__"
                else if (name == "debug") {
                    name = "__DEBUG__"
                }
                sym_store(name, val)

            # Otherwise load a file
            } else {
                load_init_files()
                if (! dofile(rm_quotes(arg), FALSE)) {
                    warn("File '" arg "' does not exist", "ARGV", i)
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
            exit_code = dofile("-", FALSE) ? EX_OK : EX_NOINPUT
        }

    # ARGC < 1, can't happen...
    } else {
        print_stderr("Usage: m2 [NAME=VAL ...] [file ...]")
        exit_code = EX_USAGE
    }

    end_program(SHIP_OUT_STREAMS)
}


# Prepare to exit.  Normally, flush_diverted_streams has a true value,
# viz. SHIP_OUT_STREAMS, so we usually undivert all pending streams.
# When flush_diverted_streams is false (DISCARD_STREAMS), any diverted
# data is dropped.  Standard output is always flushed, and program exits
# with value from global variable exit_code.
function end_program(flush_diverted_streams)
{
    # If requested (the normal case), ship out any remaining diverted
    # data.  See "STREAMS & DIVERSIONS" documentation above to see how
    # the user can prevent this if desired.
    if (flush_diverted_streams) {
        sym_store("__DIVNUM__", 0)
        undivert_all()
    }
    flush_stdout()
    exit exit_code
}
