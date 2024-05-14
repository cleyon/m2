#!/usr/local/bin/gawk -f
#!/usr/bin/awk -f

BEGIN { __version = "3.4.93_nsym" }

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
#           @array ARR             Declare ARR as an array
#           @case NAME             Evaluate value of NAME, comparing it with
#             @of TEXT               each successive @of TEXT.  If none match,
#             @otherwise             use text from @otherwise block if present.
#           @endcase               End @case structure.  Also @esac
#           @comment [TEXT]        Comment; ignore line.  Also @@, @c, @;, and @#
#           @debug [TEXT]          If debugging, send TEXT to standard error
#           @decr NAME [N]         Subtract N (1) from an already defined NAME
#           @default NAME VAL      Like @define, but no-op if NAME already defined
#           @define NAME TEXT      Set NAME to TEXT
#           @divert [N]            Divert output to stream N (default 0 means stdout)
#           @dump(all) [FILE]      Output symbol names & definitions to FILE (stderr)
#           @error [TEXT]          Send TEXT to standard error; exit code 2
#           @exit [CODE]       [S] Immediately stop parsing; exit CODE (default 0)
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
#           @include FILE      [S] Read and process contents of FILE
#           @incr NAME [N]         Add N (1) to an already defined NAME
#           @initialize NAME VAL   Like @define, but abort if NAME already defined
#           @input [NAME]          Read a single line from keyboard and define NAME
#           @local NAME            Declare NAME as a symbol local to the current frame
#           @longdef NAME          Set NAME to <...> (all lines until @endlongdef)
#             <...>                  Don't use other @ commands inside definition
#           @endlongdef              But simple @NAME@ references should be okay
#           @newcmd NAME           Create a user command NAME (lines until @endcmd)
#             <...>
#           @endcmd
#           @nextfile              Ignore remainder of file, continue processing
#           @paste FILE        [S] Insert FILE contents literally, no macros
#           @read NAME FILE    [S] Read FILE contents to define NAME
#           @readarray F FILE  [S] Read each line from FILE into array F[]
#           @readonly NAME         Make NAME unchangeable -- cannot be undone
#           @sequence ID ACT [N]   Create and manage sequences
#           @shell DELIM [PROG]    Evaluate input until DELIM, send raw data to PROG
#             <...>                  Prog output is captured; exit status in __SHELL__
#           @typeout               Print remainder of input file literally, no macros
#           @undefine NAME         Remove definition of NAME
#           @undivert [N]          Inject stream N (def all) into current stream
#           @unless NAME           Include subsequent text if NAME == 0 (or undefined)
#           @warn [TEXT]           Send TEXT to standard error; continue
#                                    Also called @echo, @stderr
#
#       [S] When the command is prefixed with "s" (@sinclude), denotes a
#           `silent' variant which prints fewer error messages .
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
#       input is replaced in the output by the corresponding value.
#
#       Example:
#           @define Condition under
#           You are clearly @Condition@worked.
#               => You are clearly underworked.
#
#       No white space is allowed between "@" and the name, so a lone
#       at-sign does not trigger m2 in any way.  Thus, a line like
#           100 dollars @ 5% annual interest
#       is completely benign.  Also, there is no need to `quote'
#       identifiers to protect against inadvertent/unwanted replacement.
#       Substitutions can occur multiple times in a single line.
#
#       Specifying more than one word between @ signs, as in
#           @xxxx AAA BBB CCC@
#       is used as a crude form of function invocation.  Macros can
#       expand positional parameters whose actual values will be
#       supplied when the macro is called.  The definition should refer
#       to $1, $2, etc.  ${1} also works, so ${1}1 is distinguishable
#       from $11.  $0 refers to the name of the macro itself.  You may
#       supply more parameters than needed, but it is an error if a
#       definition refers to a parameter which is not supplied.
#       WARNING: Parameters are parsed by splitting on white space.
#       This means that in:
#           @foo "a b" c
#       foo is given three arguments, not two: '"a', 'b"', and 'c'
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
#       The following definitions are recognized:
#
#           @basename SYM@         Base (file) name of SYM
#           @boolval [SYM]@        Output "1" if SYM is true, else "0"
#           @chr SYM@              Output character with ASCII code SYM
#           @date@             [1] Current date (format as __FMT__[date])
#           @dirname SYM@          Directory name of SYM
#           @epoch@            [1] Number of seconds since the Epoch, UTC
#           @expr MATH@        [S] Evaluate mathematical expression
#           @getenv VAR@       [2] Get environment variable
#           @lc SYM@               Lower case
#           @left SYM [N]@         Substring of SYM from 1 to Nth character
#           @len SYM@              Number of characters in SYM's value
#           @ltrim SYM@            Remove leading whitespace
#           @mid SYM BEG [LEN]@    Substring of SYM from BEG, LEN chars long
#           @rem COMMENT@      [S] Embedded comment text is ignored
#           @right SYM [N]@        Substring of SYM from N to last character
#           @rtrim SYM@            Remove trailing whitespace
#           @spaces [N]@           Output N space characters  (default 1)
#           @strftime FMT@         Current date/time in user-specified format
#           @time@             [1] Current time (format as __FMT__[time])
#           @trim SYM@             Remove both leading and trailing whitespace
#           @tz@               [1] Time zone name (format as __FMT__[tz])
#           @uc SYM@               Upper case
#           @uuid@                 Something that resembles a UUID:
#                                    C3525388-E400-43A7-BC95-9DF5FA3C4A52
#
#       Symbols can be suffixed with "[<key>]" to form simple arrays.
#
#       Symbols that start and end with "__" (like __FOO__) are called
#       "system" symbols.  Except for certain writable symbols, they
#       cannot be modified by the user.  The following are pre-defined;
#       example values, defaults, or types are shown:
#
#           __CWD__                Current working directory, trailing slash
#           __DATE__           [1] m2 run start date as YYYYMMDD (eg 19450716)
#           __DBG__[<id>]          Levels for internal debugging systems (integer)
#           __DEBUG__          [3] Debugging enabled? (boolean, def FALSE)
#           __DIVNUM__             Current stream number (0; 0-9 valid)
#           __EPOCH__          [1] Seconds since Epoch at m2 run start time
#           __EXPR__               Value from most recent @expr ...@ result
#           __FILE__               Current file name
#           __FILE_UUID__          UUID unique to this file
#           __FMT__[0]         [3] Text output when @boolval@ is false (0)
#           __FMT__[1]         [3] Text output when @boolval@ is true (1)
#           __FMT__[date]      [3] Date format for @date@ (%Y-%m-%d)
#           __FMT__[number]    [3] Format for printing numbers (sync w/CONVFMT)
#           __FMT__[seq]       [3] Format for printing sequence values (%d)
#           __FMT__[time]      [3] Time format for @time@ (%H:%M:%S)
#           __FMT__[tz]        [3] Time format for @tz@ (%Z)
#           __GID__                Group id (effective gid)
#           __HOME__               User's home directory, with trailing /
#           __HOST__               Short host name (eg myhost)
#           __HOSTNAME__           FQDN host name (eg myhost.example.com)
#           __INPUT__          [3] The data read by @input
#           __LINE__               Current line number inside __FILE__
#           __M2_UUID__            UUID unique to this m2 run
#           __M2_VERSION__         m2 version
#           __NFILE__              Number of files processed so far (eg 2)
#           __NLINE__              Number of lines read so far from all files
#           __OSNAME__             Operating system name
#           __PID__                m2 process id
#           __SHELL__              Exit status of most recent @shell command
#           __STRICT__         [3] Strict mode? (boolean, def TRUE)
#           __TIME__           [1] m2 run start time as HHMMSS (eg 053000)
#           __TIMESTAMP__      [1] ISO 8601 timestamp (1945-07-16T05:30:00-0600)
#           __TMPDIR__         [3] Location for temporary files (def /tmp/)
#           __TZ__             [1] Time zone numeric offset from UTC (-0400)
#           __UID__                User id (effective uid)
#           __USER__               User name
#
#       [1] __DATE__, __EPOCH__, __TIME__, __TIMESTAMP__, and __TZ__ are
#           fixed at program start and do not change.  @date@, @epoch@,
#           @time@, and @tz@ do change, so you could define timestamp as:
#               @define timestamp @date@T@time@@__TZ__@
#           to generate up-to-date timestamps.  Of course, time zones
#           don't normally change; the point is that @__TZ__@ prints
#           "-0800" while @tz@ prints "PST".
#
#       [2] @getenv VAR@ will be replaced by the value of the environment
#           variable VAR.  An error is thrown if VAR is not defined.  To
#           ignore error and continue with empty string, disable __STRICT__.
#
#       [3] Denotes a user-modifiable system symbol.
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
#           There is an implicit @divert 0 and @undivert performed
#           when m2 reaches the end of its input.  If you want to avoid
#           this and discard any diverted data that hasn't shipped out yet,
#           add the following to the end of your input data:
#               @divert -1
#               @undivert
#
#       Example:
#           @divert 1
#           world!
#           @divert
#           Hello,
#               => Hello,
#               => world!
#
# SEQUENCES
#       m2 supports named sequences which are integer values.  By
#       default, sequences begin at zero and increment by one as
#       appropriate.  These defaults can be changed, and the value
#       updated or restarted.  You create and manage sequences with the
#       @sequence <ID> <ACTION> [<ARG>] command.  Valid actions are:
#
#           ID [create]            Create a new sequence named ID
#           ID delete              Destroy sequence named ID
#           ID format STR          Format string used to print value (%d)
#           ID incr N              Set increment to N (1)
#           ID init N              Set initial value to N (0)
#           ID next                Increment value (no output)
#           ID prev                Decrement value (no output)
#           ID restart             Set current value to initial value
#           ID set N               Set value directly to N
#
#       To use a sequence, surround the sequence ID with @ characters
#       just like a macro.  This injects the current value, formatted by
#       calling sprintf with the specified format.  The form @++ID is
#       used to generate an increasing sequence of values printed in a
#       user-customizable format.  To get the current value printed in
#       decimal without modification or formatting, say @ID currval@.
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
#       inserts their results.  @expr@ supports the standard
#       arithmetic operators:               (  )  +  -  *  /  %  ^
#       and the comparison operators:       <  <=  ==  !=  >=  >
#       and return 0 or 1 as per Awk.  Logical negation is available with !.
#       NO OTHER boolean operators are supported.  Nota Bene,
#       && and || are NOT SUPPORTED!
#
#       @expr@ supports the following functions:
#
#           abs(x)                 Absolute value of x, |x|
#           acos(x)                Arc-cosine of x (-1 <= x <= 1)
#           asin(x)                Arc-sine of x (-1 <= x <= 1)
#           atan2(y,x)             Arctangent of y/x, -pi <= atan2 <= pi
#           ceil(x)                Ceiling of x, smallest integer >= x
#           cos(x)                 Cosine of x, in radians
#           defined(sym)           1 if sym is defined, else 0
#           deg(x)                 Convert radians to degrees
#           exp(x)                 Exponential (anti-logarithm) of x, e^x
#           floor(x)               Floor of x, largest integer <= x
#           hypot(x,y)             Hypotenuse of a right-angled triangle
#           int(x)                 Integer part of x
#           log(x)                 Natural logarithm of x, base e
#           log10(x)               Common logarithm of x, base 10
#           max(a,b)               The larger of a and b
#           min(a,b)               The smaller of a and b
#           pow(x,y)               Raise x to the y power, x^y
#           rad(x)                 Convert degrees to radians
#           rand()                 Random float, 0 <= rand < 1
#           randint(x)             Random integer, 1 <= randint <= x
#           round(x)               Normal rounding to nearest integer
#           sign(x)                Signum of x [-1, 0, or +1]
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
#           m2:<__FILE__>:<__LINE__>:<Error text>:<Offending input line>
#
#       All error texts and their meanings are as follows:
#
#           Bad parameters [in 'XXX']
#               - A command did not receive the expected/number of parameters.
#           Bad @{...} expansion
#               - Error expanding @{...}, often caused by a missing "}"
#           Cannot recursively read 'XXX'
#               - Attempt to @include the same file multiple times.
#               - Attempt to nest @case commands.
#           Comparison operator 'XXX' invalid
#               - An @if expression with an invalid comparison operator.
#               - Invalid conditions while sorting symbol table.
#           Delimiter 'XXX' not found
#               - A multi-line read (@ignore, @longdef, @shell) did not find
#                 its terminating delimiter line.
#               - An @if or @case block was not properly terminated with @endif
#                 or @endcase, usually due to premature end of input.
#               - Indicates a "starting" command did not find its finish.
#           Division by zero
#               - @expr@ attempted to divide by zero.
#           Duplicate 'XXX' not allowed
#               - More than one @else found in a single @if block.
#               - More than one @otherwise found in a single @case block.
#           Empty symbol table
#               - A @dump command found no definitions to display.
#           Environment variable 'XXX' not defined
#               - Attempt to getenv an undefined environment variable
#                 while __STRICT__ is in effect.
#           Error reading file 'FILE'
#               - Read error on file.
#           Expected number or '(' at 'XXX'
#               - @expr ...@ received unexpected input or bad syntax.
#           File 'XXX' does not exist
#               - Attempt to @include a non-existent file in strict mode.
#           Math expression error [hint]
#               - An error occurred during @expr ...@ evaluation.
#               - A math expression returned +/-Infinity or NaN.
#           Missing 'X' at 'XXX'
#               - @expr ...@ did not match syntax required for expression
#                 (missing a , or ( character in function calls).
#           Name 'XXX' not available
#               - Despite being valid, the name cannot be used/found here.
#               - Attempt to access an unknown debugging key.
#           Name 'XXX' not defined
#               - A symbol name without a value was passed to a function.
#               - An undefined macro was referenced and __STRICT__ is true.
#               - Attempt to use an undefined sequence ("create" is allowed).
#           Name 'XXX' not valid
#               - A symbol name does not pass validity check.  In __STRICT__
#                 mode (the default), a symbol name may only contain letters,
#                 digits, #, -, or _ characters.
#               - Environment variable name does not pass validity check.
#           No corresponding 'XXX'
#               - @if: An @else or @endif was seen without a matching @if.
#               - @longdef: An @endlongdef was seen without a matching @longdef.
#               - @newcmd: An @endcmd was seen without a matching @newcmd.
#               - @case: Normal text was found before an @of branch defined.
#               - Indicates a "finishing" command was seen without a starter.
#           Parameter N not supplied in 'XXX'
#               - A macro referred to a parameter (such as $1) for which
#                 no value was supplied.
#           Symbol 'XXX' already defined
#               - @initialize attempted to define a previously defined symbol.
#           Symbol 'XXX' read-only
#               - Attempt to modify a protected (read-only) symbol (__FOO__).
#                 (__STRICT__ is an exception and can be modified.)
#           Unexpected end of definition
#               - Input ended before macro definition was complete.
#           Unknown function 'FUNC'
#               - @expr ...@ found an unrecognized mathematical function.
#           Value 'XXX' must be numeric
#               - Something expected to be a number was not.
#
# FLAGS
#       A flag is a single character boolean-valued piece of information
#       about a "name", an entry in nnamtab.  The flag is True if the
#       character is present in the flags string and False if it is absent.
#       The following flag characters are recognized:
#
#       Type is mutually exclusive; exactly one must be present:
#           TYPE_ARRAY          1 : Array refs must use subscripts
#           TYPE_BUILTIN        2 : Global namespace (hard-wired @ commands)
#           TYPE_COMMAND        3 : Global namespace (user-defined commands)
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
#           FLAG_DELAYED        D : Delayed means value will be defined leter
#           FLAG_SYSTEM         Y : Internal variable, level 0, usually
#                                   (but not always) read-only.  Also,
#                                   system symbols cannot be shadowed.
#       When TYPE_ARRAY is set:
#           no flags            User can add/delete/whatever to array & elements
#           FLAG_SYSTEM         User cannot add or delete elements.  Existing
#                               elements may be updated.  As usual, level=0 and
#                               name cannot be shadowed.
#           FLAG_READONLY       User cannot change, add, or delete any element.
#           FLAG_WRITABLE       User can add, delete, change elements
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
#       Self-referential/recursive macros will hang the program.
#
#       m2 is not UTF-8 safe.
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
#           @array valid_regions
#           @define valid_regions[us-east-1]
#           @define valid_regions[us-east-2]
#           @define valid_regions[us-west-1]
#           @define valid_regions[us-west-2]
#           @if_not_in @region@ valid_regions
#           @error Region '@region@' is not valid: choose us-{east,west}-{1,2}
#           @endif
#           @#              Configure image name according to region
#           @array images
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
#       M5  Prof. A. Dain Samples described and implemented M5.  See: User's
#           Guide to the M5 Macro Language 2ed [Usenet comp.compilers, 1992].
#              "M5 is a powerful, easy to use, general purpose macro language.
#               M5's syntax allows concise, formatted, and easy to read
#               specifications of macros while still giving the user control
#               over the appearance of the resulting text.  M5 macros can have
#               named parameters, can have an unbounded number of parameters,
#               and can manipulate parameters as a single unit. [...]"
#           William A. Ward, Jr., School  of  Computer  and  Information
#           Sciences, University of South Alabama, Mobile, Alabama, also
#           wrote a macro processor translator (in Awk!) named m5 dated
#           July 23, 1999.
#              "m5, unlike many macro processors, does not directly
#              interpret its input.  Instead it uses a two-pass approach
#              in which the first pass translates the input to an awk
#              program, and the second pass executes the awk program to
#              produce the final output.  Macros are defined using awk
#              assignment statements and their values substituted using
#              the substitution prefix character ($ by default)."
#           May also refer to a multitronic computer designed and built by
#           Dr Richard Daystrom, ca. 2268.  (Not entirely successful.)
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
    TRUE = OKAY      =  1
    FALSE = EOF      =  0
    ERROR            = -1
    EMPTY            = ""
    GLOBAL_NAMESPACE =  0

    # Exit codes
    EX_OK            =  0;              __exit_code = EX_OK
    EX_M2_ERROR      =  1
    EX_USER_REQUEST  =  2
    EX_USAGE         = 64
    EX_NOINPUT       = 66

    # Flags
    TYPE_ANY         = "*";             FLAG_BOOLEAN     = "B"
    TYPE_ARRAY       = "1";             FLAG_DELAYED     = "D"
    TYPE_BUILTIN     = "2";             FLAG_INTEGER     = "I"
    TYPE_COMMAND     = "3";             FLAG_NUMERIC     = "N"
    TYPE_FUNCTION    = "4";             FLAG_READONLY    = "R"
    TYPE_SEQUENCE    = "5";             FLAG_WRITABLE    = "W"
    TYPE_SYMBOL      = "6";             FLAG_SYSTEM      = "Y"

    FLAGS_READONLY_INTEGER = TYPE_SYMBOL FLAG_INTEGER FLAG_READONLY FLAG_SYSTEM
    FLAGS_READONLY_NUMERIC = TYPE_SYMBOL FLAG_NUMERIC FLAG_READONLY FLAG_SYSTEM
    FLAGS_READONLY_SYMBOL  = TYPE_SYMBOL              FLAG_READONLY FLAG_SYSTEM
    FLAGS_WRITABLE_SYMBOL  = TYPE_SYMBOL              FLAG_WRITABLE FLAG_SYSTEM
    FLAGS_WRITABLE_BOOLEAN = TYPE_SYMBOL FLAG_BOOLEAN FLAG_WRITABLE FLAG_SYSTEM

    # Early initialize debug configuration.  This makes `gawk --lint' happy.
    nnamtab["__DEBUG__",     GLOBAL_NAMESPACE] = FLAGS_WRITABLE_BOOLEAN
    nsymtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = FALSE

    nnamtab["__DBG__", GLOBAL_NAMESPACE] = TYPE_ARRAY FLAG_WRITABLE FLAG_SYSTEM
    split("braces case divert dosubs dump expr io m2 read symbol" \
          " ncmd nnam nseq nsym namespace" \
          " for",\
          _dbg_sys_array, " ")
    for (_dsys in _dbg_sys_array) {
        __dbg_sysnames[_dbg_sys_array[_dsys]] = TRUE
    }
}



#*****************************************************************************
#
#       I/O functions
#
#*****************************************************************************

#  "m2:"  FILE  ":"  LINE  ":"  TEXT
function format_message(text, file, line,    s)
{
    if (file == EMPTY)
        file = nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
    if (file == "/dev/stdin" || file == "-")
        file = "<STDIN>"
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


# One of these is bound to work, right?
function flush_stdout()
{
    fflush("/dev/stdout")
    # Reputed to be more portable:
    #    system("")
    # Also, fflush("") will flush ALL files and pipes.
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
    end_program(DISCARD_STREAMS)
}



#*****************************************************************************
#
#       Debugging functions
#
#       dsys : Debug system name : key to __DBG__ hash
#
#*****************************************************************************
function debugp()
{
    return nsym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE)
}

# Predicate: TRUE if debug system level >= provided level (lev).
# Example:
#     if (dbg("nsym", 3))
#         warn("Debugging nsym at level 3 or higher")
# NB - do NOT call nsym_defined_p() here, you will get infinite recursion
function dbg(dsys, lev)
{
    if (lev == EMPTY)           lev = 1
    if (dsys == EMPTY)          error("Dsys is empty")
    if (! (dsys in __dbg_sysnames)) error("Name '" dsys "' not available")
    if (!debugp())              return FALSE
    if (lev <= 0)               return TRUE
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
# going to be  less than any LEV.
function dbg_get_level(dsys)
{
    if (dsys == EMPTY)          dsys = "m2"
    if (! (dsys in __dbg_sysnames)) error("Name '" dsys "' not available")
    # return (nsym_fetch(sprintf("%s[%s]", "__DBG__", dsys))+0) \
    if (!nsym_ll_in("__DBG__", dsys, GLOBAL_NAMESPACE))
        return 0
    return (nsym_ll_read("__DBG__", dsys, GLOBAL_NAMESPACE)+0) \
         * (debugp() ? 1 : -1)
}

# Set the level (lev) for the debug dsys
function dbg_set_level(dsys, lev)
{
    if (dsys == EMPTY)           dsys = "m2"
    if (! (dsys in __dbg_sysnames)) error("Name '" dsys "' not available")
    if (lev == EMPTY)           lev = 1
    if (lev < 0)                lev = 0
    if (lev > MAX_DBG_LEVEL)    lev = MAX_DBG_LEVEL
    nsym_ll_write("__DBG__", dsys, GLOBAL_NAMESPACE, lev+0)
}

function dbg_print(dsys, lev, text,
                   retval)
{
    retval = dbg(dsys, lev)
    #if (dbg(dsys, lev))
    if (dsys == "cmd" || dsys == "nnam" || dsys == "nsym")
        return
    if (retval) {
        #print_stderr(sprintf("dbg_print(%s,%d)=>%d : %s", dsys, lev, retval, text))
        print_stderr(text)
    } else {
        #print_stderr(sprintf("dbg_print(%s,%d)=>%d", dsys, lev, retval))
    }
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
    divnum = nsym_ll_read("__DIVNUM__", "", GLOBAL_NAMESPACE)
    if (divnum == 0)
        printf("%s", text)
    else if (divnum > 0)
        __streambuf[divnum] = __streambuf[divnum] text
}


# Inject (i.e., ship out to current stream) the contents of a different
# stream.  Negative streams and current diversion are silently ignored.
# Buffer text is not re-parsed for macros, and buffer is cleared after
# injection into target stream.
function undivert(stream)
{
    dbg_print("divert", 1, "undivert(" stream ")")
    if (stream <= 0 || stream == nsym_ll_read("__DIVNUM__", "", GLOBAL_NAMESPACE))
        return
    if (!emptyp(__streambuf[stream])) {
        ship_out(__streambuf[stream])
        __streambuf[stream] = EMPTY
    }
}

function undivert_all(    stream)
{
    for (stream = 1; stream <= MAX_STREAM; stream++)
        if (!emptyp(__streambuf[stream]))
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
    return substr(s, 1, length(s) - 1)
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



#*****************************************************************************
#
#       Flags API
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
                        l, f_arr)
{
    # If multi_fs is empty, we treat that as False.
    if ((l = split(multi_fs, f_arr, "")) == 0)
        return FALSE
    # Loop through all the flag characters in multi_fs.
    # If any of them are false, the whole thing is false.
    # If you reach the end, it's true.
    while (l > 0)
        if (flag_1false_p(code, f_arr[l--]))
            return FALSE
    return TRUE
}


# TRUE iff any flag in multi_fs are True (set in code).
function flag_anytrue_p(code, multi_fs,
                        l, f_arr)
{
    # If multi_fs is empty, we treat that as False.
    if ((l = split(multi_fs, f_arr, "")) == 0)
        return FALSE
    # True if any flag is True, else False
    while (l > 0)
        if (flag_1true_p(code, f_arr[l--]))
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
                        l, sf_arr, cf_arr, flag, _idx)
{
    # First, clear flags listed in clear_fs
    for (l = split(clear_fs, cf_arr, ""); l > 0; l--) {
        flag = cf_arr[l]
        if (flag_1true_p(code, flag)) {
            _idx = index(code, flag)
            code = substr(code, 1, _idx-1) \
                   substr(code, _idx+1)
        }
    }

    # Now set the ones in set_fs
    for (l = split(set_fs, sf_arr, ""); l > 0; l--) {
        flag = sf_arr[l]
        if (flag_1false_p(code, flag))
            code = code flag
    }

    return code
}



#*****************************************************************************
#
#       NEW Symbol API
#
#*****************************************************************************

# In strict mode, a symbol must match the following regexp:
#       /^[A-Za-z#_][A-Za-z#_0-9]*$/
# see function nnam_valid_strict_regexp_p()
# In non-strict mode, any non-empty string is valid.
function nsym_valid_p(sym,
                      nparts, info)
{
    dbg_print("nsym", 4, sprintf("nsym_valid_p: START (sym=%s)", sym))
    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("ERROR because nnam_parse failed")
    }
    # nparts must be either 1 or 2
    return nparts == 1 ? info["namevalid"] \
                       : (info["namevalid"] && info["keyvalid"])
}

function nsym_create(sym, code,
                     nparts, name, key, info, level)
{
    dbg_print("nsym", 4, sprintf("nsym_create: START (sym=%s, code=%s)", sym, code))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("ERROR because nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # I believe this code can never create system symbols, therefore
    # there's no need to look it up.  This is because m2 internally
    # wouldn't call this function (it would be done more directly in
    # code, with the level specified directly), and the user certainly
    # can't do it.
    #level = nsym_system_p(name) ? GLOBAL_NAMESPACE : __namespace
    level = __namespace

    # Error if name exists at that level
    if (nsym_info_defined_lev_p(info, level))
        error("nsym_create name already exists at that level")

    # Error if first(code) != valid TYPE
    if (!flag_1true_p(code, TYPE_SYMBOL))
        error("nsym_create asked to create a non-symbol")

    # Add entry:        nnamtab[name,level] = code
    # Create an entry in the name table
    #dbg_print("nsym", 2, sprintf("...
    # print_stderr(sprintf("nsym_create: nnamtab += [\"%s\",%d]=%s", name, level, code))
    if (! nnam_ll_in(name, level)) {
        nnam_ll_write(name, level, code)
    }
    # What if things aren't compatible?

    # MORE
}


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

# Delayed symbols cannot have keys, so don't even pass anything
function nsym_delayed_symbol(name, code, delayed_prog, delayed_arg,
                             level)
{
    level = GLOBAL_NAMESPACE

    # Create an entry in the name table
    if (nnam_ll_in(name, level))
        error("Cannot create delayed symbol when it already exists")

    nnam_ll_write(name, level, code FLAG_DELAYED)
    # It has no symbol value (yet), but we do store the two args in the
    # symbol table
    nsymtab[name, "", level, "delayed_prog"] = delayed_prog
    nsymtab[name, "", level, "delayed_arg"]  = delayed_arg
}

function nsym_destroy(sym, level,
                      name, key)
{
    # Parse sym => name, key
    # if nsym_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if nsym_system_p(name)
    # A ::= Cond: name is array T/F
    # B ::= Cond: sym has name[key] syntax T/F
    # if A & B          delete nsymtab[name, key, level, "symval"]
    # if A & !B         delete every nsymtab entry for key; delete nnamtab entry
    # if !A & B         syntax error: NAME is not an array and cannot be deindexed
    # if !A & !B        (normal symbol) delete nsymtab[name, "", level, "symval"];
    #                                   delete nnamtab[name]
}

# DO NOT require CODE parameter.  Instead, look up NAME and
# find its code as normally.  NAME might not even be defined!
function nsym_system_p(name)
{
    if (name == "")
        error("nsym_system_p: NAME missing")
    return nnam_ll_in(name, GLOBAL_NAMESPACE) &&
           flag_alltrue_p(nnam_ll_read(name, GLOBAL_NAMESPACE), TYPE_SYMBOL FLAG_SYSTEM)
}

function nsym_dump_nsymtab(flagset,    \
                           x, k, code)
{
    print("Begin nsymtab:")
    for (k in nsymtab) {
        split(k, x, SUBSEP)
        # print "name  =", x[1]
        # print "key   =", x[2]
        # print "level =", x[3]
        # print "elem  =", x[4]
        print sprintf("[\"%s\",\"%s\",%s,\"%s\"] = '%s'",
                      x[1], x[2], x[3], x[4],
                      nsymtab[x[1], x[2], x[3], x[4]])
        # print "----------------"
    }
    print("End nsymtab")
}

# Remove any symbol at level "level" or greater
function nsym_purge(level,
                    x, k, del_list)
{
    for (k in nsymtab) {
        split(k, x, SUBSEP)
        if (x[3]+0 >= level)
            del_list[x[1], x[2], x[3], x[4]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        delete nsymtab[x[1], x[2], x[3], x[4]]
    }
}

# Delayed symbols have an entry in nnamtab of TYPE_SYMBOL
# and FLAG_DELAYED.  Only system symbols in global namespace
# are delayed, so we don't need to be super careful
function nsym_delayed_p(sym,
                        code, level)
{
    level = GLOBAL_NAMESPACE
    if (!nnam_ll_in(sym, level))
        return FALSE
    code = nnam_ll_read(sym, level)
    if (flag_anyfalse_p(code, TYPE_SYMBOL FLAG_DELAYED))
        return FALSE
    return ((sym, "", level, "delayed_prog") in nsymtab &&
            (sym, "", level, "delayed_arg")  in nsymtab &&
          !((sym, "", level, "symval")       in nsymtab))
}

# User should have checked to make sure, so let's do it
function nsym_delayed_define_now(sym,
                                 code, delayed_prog, delayed_arg, output)
{
    code = nnam_ll_read(sym, GLOBAL_NAMESPACE)
    delayed_prog = nsymtab[sym, "", GLOBAL_NAMESPACE, "delayed_prog"]
    delayed_arg  = nsymtab[sym, "", GLOBAL_NAMESPACE, "delayed_arg"]

    # Build the command to generate the output value, then store it in the symbol table
    build_prog_cmdline(delayed_prog, delayed_arg, FALSE) | getline output
    # Kluge to add trailing slash to pwd(1) output
    if (sym == "__CWD__")
        output = with_trailing_slash(output)
    nsym_ll_write(sym, "", GLOBAL_NAMESPACE, output)

    # Get rid of any trace of FLAG_DELAYED
    nnam_ll_write(sym, GLOBAL_NAMESPACE, flag_set_clear(code, EMPTY, FLAG_DELAYED))
    delete nsymtab[sym, "", GLOBAL_NAMESPACE, "delayed_prog"]
    delete nsymtab[sym, "", GLOBAL_NAMESPACE, "delayed_arg"]
}

function nsym_defined_p(sym,
                        nparts, info, name, key, code, level)
{
    dbg_print("nsym", 4, sprintf("nsym_defined_p: START (sym=%s)", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR)
        return FALSE
    name = info["name"]
    key  = info["key"]

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    # if (level == ERROR)
    #     warn("nsym_defined_p: nnam_lookup failed, maybe that's okay")

    # for (level = nsym_system_p(name) ? GLOBAL_NAMESPACE : __namespace; \
    #      level >= 0; level--) {
    #     if (nsym_info_defined_lev_p(info, level)) {
    #         print_stderr("Returning TRUE!")
    #         return TRUE
    #     }
    # }
    if (!nsym_system_p(name))
        if (nsym_info_defined_lev_p(info, __namespace)) {
            dbg_print("nsym", 2, sprintf("nsym_defined_p: END (sym=%s) level=%d => %d", sym, __namespace, TRUE))
            return TRUE
        }
    if (nsym_info_defined_lev_p(info, GLOBAL_NAMESPACE)) {
        dbg_print("nsym", 2, sprintf("nsym_defined_p: END (sym=%s) level=%d => %d", sym, GLOBAL_NAMESPACE, TRUE))
        return TRUE
    }

    dbg_print("nsym", 2, sprintf("nsym_defined_p: END (sym=%s) => %d", sym, FALSE))
    return FALSE
}


# Caller MUST have previously called nnam_parse().
# It's the only way to get the `info' paramater value.
#
# The caller is responsible for inquiring about nsym_system_p(name),
# and overriding level to zero if appropriate.  This code does
# not make any assumptions about name/levels.
function nsym_info_defined_lev_p(info, level,
                                 name, key, code,
                                 x, k)
{
    name = info["name"]
    key  = info["key"]
    # code = info["code"]

    if (key == EMPTY) {
        if ((name, "", 0 + level, "symval") in nsymtab) {
            dbg_print("nsym", 5, sprintf("nsym_info_defined_lev_p TRUE for [\"%s\",\"%s\",%d,\"symval\"] FOUND in hash table", name, key, level))
            return TRUE
        }
        #print_stderr(sprintf("nsym_info_defined_lev_p FALSE for [\"%s\",\"%s\",%d,\"symval\"] bc NOT in hash table", name, key, level))
        return FALSE
    } else {
        # non-empty key means we have to sequential search through table
        for (k in nsymtab) {
            split(k, x, SUBSEP)
            if (x[1]   != name  ||
                x[2]   != key   ||
                x[3]+0 != level ||
                x[4]   != "symval")
                continue;
            # Everything matches
            #print_stderr(sprintf("nsym_info_defined_lev_p TRUE for [\"%s\",\"%s\",%d,\"symval\"] FOUND in hash table", name, key, level))
            return TRUE
        }
        #print_stderr(sprintf("nsym_info_defined_lev_p FALSE for [\"%s\",\"%s\",%d,\"symval\"] bc NOT in hash table", name, key, level))
        return FALSE
    }
}

function nsym_store(sym, new_val,
                    nparts, info, name, key, level, code, good)
{
    dbg_print("nsym", 6, sprintf("nsym_store: START (sym=%s)", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("nsym_store: nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # Compute level
    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    # It's okay if nnam_lookup "fails" (level == ERROR) because
    # we might be attempting to store a new, non-existing symbol.

    # At this point:
    #   level == ERROR       -> no matching name of any kind
    #   level == GLOBAL_NAMESPACE -> found in global
    #   0 < level < ns-1     -> find in other non-global frame
    #   level == __namespace -> found in current namespace
    # Just because we found a nnamtab entry doesn't
    # mean it's okay to just muck about with nsymtab.

    good = FALSE
    do {
        if (level == ERROR) {   # name not found in nnam
            # No nnamtab entry, no code : This means a normal
            # @define in the global namespace
            if (info["hasbracket"])
                error(sprintf("nsym_store: %s is not an array; cannot use brackets here", name))
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
            error(sprintf("nsym_store: %s is an array, so brackets are required", name))
        if (flag_1false_p(code, TYPE_ARRAY) && info["hasbracket"])
            error(sprintf("nsym_store: %s is not an array; cannot use brackets here", name))

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
        #nsym_dump_nsymtab()
        print_stderr(sprintf("nsym_store: LOOP BOTTOM: name='%s', key='%s', level=%d, code='%s'",
                             name, key, level, code))
    } while (FALSE)

    # if nsym_system_p(name)          level = 0
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
        dbg_print("nsym", 1, sprintf("nsym_store: [\"%s\",\"%s\",%d,\"symval\"]=%s",
                                     name, key, level, new_val))
        nsym_ll_write(name, key, level, new_val)
    } else {
        warn(sprintf("nsym_store: !good sym='%s'", sym))
    }
    dbg_print("nsym", 6, sprintf("nsym_store: END;"))
}

function nsym_ll_read(name, key, level)
{
    if (level == "") level = GLOBAL_NAMESPACE
    # if key == "" that's probaby just fine.
    # if name == "" that's probably NOT fine.
    return nsymtab[name, key, level, "symval"] # returns value
}

function nsym_ll_in(name, key, level)
{
    if (level == "") error("nsym_ll_in: LEVEL missing")
    return (name, key, level, "symval") in nsymtab
}

function nsym_ll_write(name, key, level, val)
{
    if (level == "") error("nsym_ll_write: LEVEL missing")
    if (nsym_ll_in("__DBG__", "nsym", GLOBAL_NAMESPACE) &&
        nsym_ll_read("__DBG__", "nsym", GLOBAL_NAMESPACE) >= 5)
        print_stderr(sprintf("nsym_ll_write: nsymtab[\"%s\", \"%s\", %d, \"symval\"] = %s", name, key, level, val))

    # Trigger debugging setup
    if (name == "__DEBUG__" && nsym_ll_read("__DEBUG__", "", GLOBAL_NAMESPACE) == FALSE &&
        val != FALSE)
        initialize_debugging()
    # Maintain equivalence:  __FMT__[number] === CONVFMT
    if (name == "__FMT__" && key == "number" && level == GLOBAL_NAMESPACE) {
        if (nsym_ll_in("__DBG__", "nsym", GLOBAL_NAMESPACE) &&
            nsym_ll_read("__DBG__", "nsym", GLOBAL_NAMESPACE) >= 6)
            print_stderr(sprintf("nsym_ll_write: Setting CONVFMT to %s", val))
        CONVFMT = val
    }

    return nsymtab[name, key, level, "symval"] = val
}

function nsym_fetch(sym,
                    nparts, info, name, key, code, level, val, good)
{
    dbg_print("nsym", 6, sprintf("nsym_fetch: START (sym=%s)", sym))

    # Parse sym => name, key
    if ((nparts = nnam_parse(sym, info)) == ERROR) {
        error("nsym_fetch: nnam_parse failed")
    }
    name = info["name"]
    key  = info["key"]

    # Now call nnam_lookup(info)
    level = nnam_lookup(info)
    if (level == ERROR)
        error("nsym_fetch: nnam_lookup failed")

    # Now we know it's a symbol, level & code.  Still need to look in
    # nsymtab because NAME[KEY] might not be defined.
    code = info["code"]
    dbg_print("nsym", 5, sprintf("nsym_fetch: nnam_lookup ok; level=%d, code=%s", level, code))

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

        print_stderr(sprintf("nsym_fetch: LOOP BOTTOM: sym='%s', name='%s', key='%s', level=%d, code='%s'",
                             sym, name, key, level, code))

    } while (FALSE)

    if (flag_1true_p(code, FLAG_DELAYED))
        nsym_delayed_define_now(sym)

    if (! nsym_ll_in(name, key, level))
        error("nsym_fetch: not in nsymtab: NAME='" name "', KEY='" key "'")

    val = nsym_ll_read(name, key, level)
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
    # if nsym_system_p(name)          level = 0
    # Error if name does not exist at that level
    # Error if incr is not numeric
    # Error if symbol is an array but sym doesn't have array[key] syntax
    # Error if symbol is not an array but sym has array[key] syntax
    # Error if you don't have permission to write to the symbol
    #   == Error ("read-only") if (flag_true(FLAG_READONLY))
    # Error if value is not consistent with symbol type (haha)
    #   or else coerce it to something acceptable (boolean)

    # Add entry:        nsymtab[name, key, level, "symval"] += incr
    nsymtab[sym, "", GLOBAL_NAMESPACE, "symval"] += incr
}

function nsym_protected_p(sym,
                          nparts, info, name, key, code, level, retval)
{
    dbg_print("nsym", 4, sprintf("nsym_protected_p: START (sym=%s)", sym))

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
    dbg_print("nsym", 4, sprintf("nsym_protected_p: END => %d", retval))
    return retval
    #return nsym_ll_protected(name, code)
}
function nsym_ll_protected(name, code)
{
    if (flag_1true_p(code, FLAG_READONLY)) return TRUE
    if (flag_1true_p(code, FLAG_WRITABLE)) return FALSE
    if (double_underscores_p(name)) return TRUE
    return FALSE
}


#*****************************************************************************
#
#       Symbol table API
#
#*****************************************************************************

function sym_definition_pp(sym,    sym_name, definition)
{
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

# function sym_increment(sym, incr)
# {
#     if (incr == EMPTY)
#         incr = 1
#     symtab[sym_internal_form(sym)] += incr
# }

# Protected symbols cannot be changed by the user.
# function sym_protected_p(sym,    root)
# {
#     root = sym # sym_root(sym)
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
#     # __DEBUG__ and __STRICT__ can only store boolean values
#     if (sym == "__DEBUG__" || sym == "__STRICT__")
#         val = !! (val+0)
#     return symtab[sym_internal_form(sym)] = val
# }

function nsym_true_p(sym,
                     val)
{
    return (nsym_defined_p(sym) &&
            ((val = nsym_fetch(sym)) != FALSE &&
              val                    != ""))
}



#*****************************************************************************
#
#       A S S E R T I O N S   O N   S Y M B O L S
#
#*****************************************************************************

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
    # if (!name_available_in_all_p(name, TYPE_COMMAND TYPE_FUNCTION TYPE_SEQUENCE))
    #     error("Name '" name "' not available:" $0)
    return TRUE
}

# Throw an error if symbol IS protected
function assert_nsym_unprotected(sym)
{
    if (!nsym_protected_p(sym))
        return TRUE
    error("Symbol '" sym "' protected:" $0)
}

# Throw an error if the symbol name is NOT valid
function assert_nsym_valid_name(sym)
{
    if (nsym_valid_p(sym))
        return TRUE
    error("Name '" sym "' not valid:" $0)
}
#*****************************************************************************
#
#       Cmd API
#
#*****************************************************************************

function ncmd_defined_p(name, code)
{
    if (!ncmd_valid_p(name))
        return FALSE
    if (! nnam_ll_in(name, GLOBAL_NAMESPACE))
        return FALSE
    code = nnam_ll_read(name, GLOBAL_NAMESPACE)
    return flag_1true_p(code, TYPE_COMMAND)
}

function ncmd_definition_pp(name)
{
    # XXX parameters
    return "@newcmd " name    "\n" \
           ncmd_ll_read(name) "\n" \
           "@endcmd"          "\n"
}

function ncmd_destroy(id)
{
    delete nnamtab[id, GLOBAL_NAMESPACE]
    delete ncmdtab[id, "definition"]
    delete ncmdtab[id, "nparam"]
}

function ncmd_valid_p(text)
{
    return nnam_valid_strict_regexp_p(text) &&
           !double_underscores_p(text)
}

function ncmd_ll_read(name)
{
    return ncmdtab[name, "definition"]
}
function ncmd_ll_write(name, new_defn)
{
    return ncmdtab[name, "definition"] = new_defn
}



#*****************************************************************************
#
#       Sequence API
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

function nsym_dump_nseqtab(flagset,    \
                           x, k, code)
{
    print("Begin nseqtab:")
    for (k in nseqtab) {
        split(k, x, SUBSEP)
        print sprintf("[\"%s\",\"%s\"] = '%s'",
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
    if (incr == "")
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
#*****************************************************************************
#
#       Names API
#
#       TYPE_SYMBOL:            symtab
#           symtab[NAME] = <definition>
#           Check "foo in symtab" for defined
#
#*****************************************************************************

# Warning - Do not use this in the general case if you want to know if a
# string is "system" or not.  This code only checks for underscores in
# its argument, but there do exist system symbols which do not match
# this naming pattern.
function double_underscores_p(text)
{
    return text ~ /^__.*__$/
}



#############################################################################
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
#       namevalid  : TRUE if NAME is valid according to current __STRICT__
#       nparts     : 1 or 2 depending if text is NAME or NAME[KEY]
#      #text       : original text string
#############################################################################
function nnam_parse(text, info,
                    name, key, nparts, part, count, i)
{
    dbg_print("nnam", 6, sprintf("nnam_parse START (text=%s)", text))
    #info["text"] = text

    # Simple test for CHARS or CHARS[CHARS]
    #   CHARS ::= [-!-Z^-z~]+
    # Match CHARS optionally followed by bracket CHARS bracket
    #   /^ CHARS ( \[ CHARS \] )? $/
    #if (text !~ /^[^[\]]+(\[[^[\]]+\])?$/) {   # too broad: matches non-printing characters
    # We carefully construct CHARS with about regexp
    # to exclude ! [ \ ] { | }
    if (text !~ /^["-Z^-z~]+(\[["-Z^-z~]+\])?$/) {
        warn("Name '" text "' not valid [nnam_parse]")
        dbg_print("nnam", 2, sprintf("nnam_parse(%s) => %d", text, ERROR))
        return ERROR
    }

    count = split(text, part, "(\\[|\\])")
    if (dbg("nnam", 8)) {
        print("'" text "' ==> " count " fields:")
        for (i = 1 ; i <= count; i++)
            print(i " = '" part[i] "'")
    }
    info["name"] = name = part[1]
    info["key"]   = key = part[2]

    # Since we passed the regexp in first if() statement, we can be
    # assured that text is either ^CHARS$ or ^CHARS\[CHARS\]$.  Thus, a
    # simple index() for an open bracket should suffice here.
    info["hasbracket"] = index(text, "[") > 0
    info["keyvalid"]   = nnam_valid_with_strict_as(key, FALSE)
    info["namevalid"]  = nnam_valid_with_strict_as(name)
    info["nparts"]     = nparts = (count == 1) ? 1 : 2
    dbg_print("nnam", 2, sprintf("nnam_parse(%s) => %d", text, nparts))
    return nparts
}

# Remove any name at level "level" or greater
function nnam_purge(level,
                    x, k, del_list)
{
    for (k in nnamtab) {
        split(k, x, SUBSEP)
        if (x[2]+0 >= level)
            del_list[x[1], x[2]] = TRUE
    }

    for (k in del_list) {
        split(k, x, SUBSEP)
        delete nnamtab[x[1], x[2]]
    }
}

function nnam_dump_nnamtab(filter_fs,
                           x, k, code, s, desc, name, level, f_arr, l,
                           include_system)
{
    include_system = flag_1true_p(filter_fs, FLAG_SYSTEM)
    filter_fs = flag_set_clear(filter_fs, EMPTY, FLAG_SYSTEM)
    print(sprintf("Begin nnamtab (%s%s):", filter_fs,
                  include_system ? "+Y" : ""))

    for (k in nnamtab) {
        split(k, x, SUBSEP)
        name  = x[1]
        level = x[2] + 0

        code = nnam_ll_read(name, level)
        if (! flag_alltrue_p(code, filter_fs))
            continue;
        if (flag_1true_p(code, FLAG_SYSTEM) && !include_system)
            continue;
        s = name
        if (level > GLOBAL_NAMESPACE)
            s = s "{" level "}"
        s = s "\t" __flag_label[first(code)]
        code = substr(code, 2)
        desc = "X"
        if (length(code) > 0) {
            desc = ""
            l = split(code, f_arr, "")
            while (l > 0)
                desc = desc __flag_label[f_arr[l--]] ","
        }
        s = s " <" chop(desc) ">"
        print s
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
    if (emptyp(text))           return FALSE
    if (emptyp(tmp_strict))     tmp_strict = strictp()
    if (tmp_strict)
        # In strict mode, only letters, #, and _ (and then digits)
        return nnam_valid_strict_regexp_p(text) # text ~ /^[A-Za-z#_][A-Za-z#_0-9]*$/
    else
        # In non-strict mode, printable characters except ! [ \ ] { | }
        return text ~ /^["-Z^-z~]+$/
}

function nnam_ll_read(name, level)
{
    if (level == "") level = GLOBAL_NAMESPACE
    return nnamtab[name, level] # returns code
}

function nnam_ll_in(name, level)
{
    if (level == "") error("nnam_ll_in: LEVEL missing")
    return (name, level) in nnamtab
}

function nnam_ll_write(name, level, code,
                       retval)
{
    if (level == "") error("nnam_ll_write: LEVEL missing")
    if (nsym_ll_in("__DBG__", "nnam", GLOBAL_NAMESPACE) &&
        nsym_ll_read("__DBG__", "nnam", GLOBAL_NAMESPACE) >= 5)
        print_stderr(sprintf("nnam_ll_write: nnamtab[\"%s\", %d] = %s", name, level, code))
    return nnamtab[name, level] = code
}

#############################################################################
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
#############################################################################
function nnam_lookup(info,
                     name, level, code)
{
    name = info["name"]

    for (level = __namespace; level >= 0; level--)
        if (nnam_ll_in(name, level)) {
            info["code"] = code = nnam_ll_read(name, level)
            info["isarray"] = flag_1true_p(code, TYPE_ARRAY)
            info["level"]   = level
            info["type"]    = first(code)
            return level;
        }
    return ERROR
}

#*****************************************************************************
#
#       Utility functions
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

function integerp(pat)
{
    return pat ~ /^[-+]?[0-9]+$/
}

function with_trailing_slash(s)
{
    return s ((last(s) != "/") ? "/" : EMPTY)
}


# Arnold Robbins, arnold@gnu.org, Public Domain
# 16 January, 1992
# 20 July, 1992, revised
function _ord_init(    low, high, i, t)
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
        _ord_[t] = i
    }
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


function assert_ncmd_okay_to_define(name)
{
    if (!ncmd_valid_p(name))
        error("Name '" name "' not valid:" $0)
    if (nnam_ll_in(name, GLOBAL_NAMESPACE))
        error("Name '" name "' not available:" $0)
    return TRUE
}


function currently_active_p()
{
    return __active[__if_depth]
}


function strictp()
{
    # Use low-level function here, not nsym_true_p(), to prevent infinite loop
    return nsym_ll_read("__STRICT__", "", GLOBAL_NAMESPACE)
}


function build_prog_cmdline(prog, arg, silent)
{
    if (! nsym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        error(sprintf("build_prog_cmdline: __PROG__[%s] not defined", prog))
    return sprintf("%s %s%s", \
                   nsym_ll_read("__PROG__", prog, GLOBAL_NAMESPACE),  \
                   arg, \
                   (silent ? " >/dev/null 2>/dev/null" : EMPTY))
}


function exec_prog_cmdline(prog, arg,    sym)
{
    if (! nsym_ll_in("__PROG__", prog, GLOBAL_NAMESPACE))
        # This should be same as assert_[n]sym_defined()
        error("exec_prog_cmdline: NOT DEFINED")
    return system(build_prog_cmdline(prog, arg, TRUE)) # always silent
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


function path_exists_p(path)
{
    return exec_prog_cmdline("stat", path) == EX_OK
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
         return int(x) - 1   # -2.5 --> -3
      else
         return int(x)       # -2.3 --> -2
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


# Quicksort - from "The AWK Programming Language" p. 161.
# Used in builtin_dump() to sort the symbol table.
function qsort(A, left, right,    i, lastpos)
{
    if (left >= right)          # Do nothing if array contains
        return                  #   less than two elements
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
        d1 = int(s1);  d2 = int(s2)
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


# Read multiple lines until delim is seen as first characters on a line.
# If delimiter is not found, return eof marker.  Intermediate lines are
# terminated with a newline character, but last line has it stripped
# away.  The lines read are NOT macro-expanded; if desired, the caller
# can invoke dosubs() on the returned buffer.  Special case if delim is "":
# read until end of file and return whatever is found, without error.
function read_lines_until(delim,    buf, delim_len)
{
    buf = EMPTY
    delim_len = length(delim)
    while (TRUE) {
        if (readline() != OKAY) {
            # eof or error, it's time to stop
            if (delim_len > 0)
                return EOD_INDICATOR
            else
                break
        }
        dbg_print("io", 3, "(read_lines_until) readline='" $0 "'")
        if (delim_len > 0 && !emptyp($0) && substr($0, 1, delim_len) == delim)
            break
        buf = buf $0 "\n"
    }
    return chop(buf)
}

function save_context(ctx)
{
    ctx["buffer"]  = __buffer
    ctx["file"]    = nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE)
    ctx["ifdepth"] = __if_depth
    ctx["line"]    = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    ctx["uuid"]    = nsym_ll_read("__FILE_UUID__", "", GLOBAL_NAMESPACE)
}

function process_buffer(    i)
{
    while (!emptyp(__buffer)) {
        # Extract each line from __buffer, one by one
        nsym_increment("__LINE__", 1) # __LINE__ is local, but not __NLINE__
        if ((i = index(__buffer, "\n")) == IDX_NOT_FOUND) {
            $0 = __buffer
            __buffer = EMPTY
        } else {
            $0 = substr(__buffer, 1, i-1)
            __buffer = substr(__buffer, i+1)
        }

        # String we want is in $0, go evaluate it
        #dbg_print("m2", 5, "(docommand) About to call process line with $0 = '" $0 "'")
        process_line()
    }
}

function restore_context(ctx)
{
    if (__if_depth > ctx["ifdepth"])
        error("Delimiter '@endif' not found")
    __buffer = ctx["buffer"]
    nsym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, ctx["file"])
    nsym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, ctx["line"])
    nsym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, ctx["uuid"])
}



#*****************************************************************************
#
#       C A L C  3
#
#       Based on `calc3' from "The AWK Programming Language" p. 146
#       with enhancements by Kenny McCormack and Alan Linton.
#
#       calc3_eval is the main entry point.  All other _c3_* functions
#       are for internal use and should not be called by the user.
#
#*****************************************************************************

function calc3_eval(s,    e)
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
function _c3_calculate_function(fun, e,    c)
{
    if (fun == "(")        return e
    if (fun == "abs(")     return e < 0 ? -e : e
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
function _c3_calculate_function2(fun, e, e2)
{
    if (fun == "atan2(")   return atan2(e, e2)
    if (fun == "hypot(")   return sqrt(e^2 + e2^2) # Beware overflow
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
#*****************************************************************************
#
#       The builtin_*() functions that follow can only be executed by
#       process_line().  That routine has already matched text at the
#       beginning of line in $0 to invoke a `control command' such as
#       @define, @if, etc.  Therefore, NF cannot be zero.
#
#       - NF==1 means @xxx called with zero arguments.
#       - NF==2 means @xxx called with 1 argument.
#       - NF==3 means @xxx called with 2 arguments.
#
#*****************************************************************************

# @array                ARR
function builtin_array(    arr)
{
    if (!currently_active_p())
        return
    if (NF < 1)
        error("Bad parameters:" $0)
    arr = $2
    # assert_nsym_okay_to_define(sym)
    # assert_nsym_defined(sym, "incr")
    if (nnam_ll_in(arr, __namespace))
        error("@array already defined")
    nnam_ll_write(arr, __namespace, TYPE_ARRAY)
}


# @case                 NAME | TEXT
# @of ....
# @otherwise
# @endcase, @esac
function builtin_case(    save_line, save_lineno, target, branch, next_branch,
                     max_branch, text, OTHERWISE, i, sym)
{
    if (!currently_active_p())
        return
    OTHERWISE = 0
    save_line = $0
    save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    sym = $2
    assert_nsym_defined(sym, "case")
    target = nsym_fetch(sym)
    __casenum++
    casetab[__casenum, OTHERWISE, "label"] = EMPTY
    casetab[__casenum, OTHERWISE, "line"] = 0
    casetab[__casenum, OTHERWISE, "definition"] = EMPTY
    max_branch = branch = ERROR;  next_branch = 1

    while (TRUE) {
        if (readline() != OKAY)
            # Whatever happened, the @case didn't finish properly
            error("Delimiter '@endcase' not found:" save_line, "", save_lineno)
        dbg_print("case", 5, "(builtin_case) readline='" $0 "'")
        if ($1 == "@endcase" || $1 == "@esac")
            break               # proceed with branch evaluation
        else if ($1 == "@case")
            error("Cannot recursively read '@case'") # maybe someday
        else if ($1 == "@of") {
            sub(/^@of[ \t]+/, "")
            text = $0
            # Start a new branch
            branch = next_branch++
            max_branch = max(branch, max_branch)
            dbg_print("case", 3, sprintf("(builtin_case) Found @of '%s' branch %d at line %d",
                                         text, branch, nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)))
            # Check if label is duplicate
            if (branch > 1)
                for (i = 1; i < branch; i++)
                    if (casetab[__casenum, i, "label"] == text)
                        error("Duplicate '@of' not allowed:@of " $0)
            # Store it
            casetab[__casenum, branch, "label"] = text
            casetab[__casenum, branch, "line"] = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
            casetab[__casenum, branch, "definition"] = EMPTY
        } else if ($1 == "@otherwise") {
            dbg_print("case", 3, "(builtin_case) Found @otherwise at line " \
                      nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE))
            # Check if otherwise already seen (there can be only one!)
            if (casetab[__casenum, OTHERWISE, "label"] == "otherwise")
                error("Duplicate '@otherwise' not allowed:" $0)
            # Start a new branch at zero and remember it's been seen.
            branch = OTHERWISE
            max_branch = max(branch, max_branch)
            casetab[__casenum, branch, "label"] = "otherwise"
            casetab[__casenum, branch, "line"] = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
        } else {
            if (branch == ERROR)
                error("No corresponding '@of':" $0)
            # Append line to current buffer
            dbg_print("case", 5, sprintf("(builtin_case) Appending to '%s' branch %d",
                                         casetab[__casenum, branch, "label"], branch))
            casetab[__casenum, branch, "definition"] = \
            casetab[__casenum, branch, "definition"] $0 "\n"
        }
    }

    # Entire @case structure read okay -- now figure out what block to
    # execute, using any "otherwise" block as a catch-all to act as a
    # default case.  This is accomplished by setting its label to be the
    # target we seek.
    casetab[__casenum, OTHERWISE, "label"] = target
    i = FALSE                   # remember if we've hit a match or not
    branch = max_branch
    while (branch >= 0) {
        dbg_print("case", 4, sprintf("casetab[%d,%d,label]='%s' =?= target='%s'",
                                     __casenum, branch,
                                     casetab[__casenum, branch, "label"], target))
        if (i == FALSE)         # not found (yet)
            if (casetab[__casenum, branch, "label"] == target) {
                i = TRUE
                if (! emptyp(casetab[__casenum, branch, "definition"]))
                    docasebranch(__casenum, branch, casetab[__casenum, branch, "line"])
            }
        # Clean up the case table entries for this branch
        delete casetab[__casenum, branch, "label"]
        delete casetab[__casenum, branch, "line"]
        delete casetab[__casenum, branch, "definition"]
        branch--
    }
}


# @default, @initialize NAME TEXT
function builtin_default(    sym)
{
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    assert_nsym_okay_to_define(sym)

    if (nsym_defined_p(sym)) {
        if ($1 == "@init" || $1 == "@initialize")
            error("Symbol '" sym "' already defined:" $0)
    } else
        dodef(FALSE)
}


# @append, @define      NAME TEXT
function builtin_define(    append_flag)
{
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    append_flag = ($1 == "@append")
    assert_nsym_okay_to_define($2)

    dodef(append_flag)
}


# @divert               [N]
function builtin_divert()
{
    if (!currently_active_p())
        return
    if (NF > 2)
        error("Bad parameters:" $0)
    $2 = (NF == 1) ? "0" : dosubs($2)
    if (!integerp($2))
        error(sprintf("Value '%s' must be numeric:", $2) $0)
    if ($2 > MAX_STREAM)
        error("Bad parameters:" $0)

    dbg_print("divert", 1, "divert(" $2 ")")
    nsym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, int($2))
}


# @dump[all]            [FILE]
# Output format:
#       @<command>  SPACE  <name>  TAB  <stuff includes spaces...>
function builtin_dump(    buf, cnt, definition, dumpfile, i, key, keys, sym_name, all_flag)
{
    return                      # OLD TABLES - BROKEN
    if (!currently_active_p())
        return
    all_flag = $1 == "@dumpall"

    if (NF > 1) {
        $1 = ""
        sub("^[ \t]*", "")
        dumpfile = rm_quotes(dosubs($0))
    }
    # Count and sort the keys from the symbol and sequence tables
    cnt = 0
    # for (key in symtab) {
    #     if (all_flag || ! nsym_system_p(key))
    #         keys[++cnt] = key
    # }
    # for (key in seqtab) {
    #     split(key, fields, SUBSEP)
    #     if (fields[2] == "defined")
    #         keys[++cnt] = fields[1]
    # }
    # for (key in cmdtab) {
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
            buf = buf sym_definition_pp(key)
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
        # was not read properly...  Still, we only warn in strict mode.
        if (strictp())
            warn("Empty symbol table:" $0)
    } else if (dumpfile == EMPTY)  # No FILE arg provided to @dump command
        print_stderr(buf)
    else {
        print buf > dumpfile
        close(dumpfile)
    }
}


# @else
function builtin_else()
{
    if (__if_depth == 0)
        error("No corresponding '@if':" $0)
    if (__seen_else[__if_depth])
        error("Duplicate '@else' not allowed:" $0)
    __seen_else[__if_depth] = TRUE
    __active[__if_depth] = __active[__if_depth - 1] ? !currently_active_p() : FALSE
}


# @debug, @echo, @error, @stderr, @warn TEXT
# debug, error and warn format the message with file & line, etc.
# echo and stderr do no additional formatting.
#
# @debug only prints its message if debugging is enabled.  The user can
# control this since __DEBUG__ is an unprotected symbol.  @debug is
# purposefully not given access to the various dbg() keys and levels.
function builtin_error(    m2_will_exit, do_format, do_print, message)
{
    if (!currently_active_p())
        return
    m2_will_exit = ($1 == "@error")
    do_format = ($1 == "@debug" || $1 == "@error" || $1 == "@warn")
    do_print  = ($1 != "@debug" || debugp())
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
        __exit_code = EX_USER_REQUEST
        end_program(DISCARD_STREAMS)
    }
}


# @exit                 [CODE]
function builtin_exit(    silent)
{
    if (!currently_active_p())
        return
    silent = (substr($1, 2, 1) == "s") # silent discards any pending streams
    __exit_code = (NF > 1 && integerp($2)) ? $2 : EX_OK
    end_program(silent ? DISCARD_STREAMS : SHIP_OUT_STREAMS)
}


# @if[_not][_{defined|env|exists|in}], @if[n]def, @unless
function builtin_if(    sym, cond, op, val2, val4)
{
    sub(/^@/, "")          # Remove leading @, otherwise dosubs($0) loses
    $0 = dosubs($0)

    if ($1 == "if") {
        if (NF == 2) {
            # @if [!]FOO
            if (first($2) == "!") {
                sym = substr($2, 2)
                assert_nsym_valid_name(sym)
                cond = !nsym_true_p(sym)
            } else {
                assert_nsym_valid_name($2)
                cond = nsym_true_p($2)
            }
        } else if (NF == 3 && $2 == "!") {
            # @if ! FOO
            assert_nsym_valid_name($3)
            cond = !nsym_true_p($3)
        } else if (NF == 4) {
            # @if FOO <op> BAR
            val2 = (nsym_valid_p($2) && nsym_defined_p($2)) ? nsym_fetch($2) : $2
            op   = $3
            val4 = (nsym_valid_p($2) && nsym_defined_p($4)) ? nsym_fetch($4) : $4

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
        assert_nsym_valid_name($2)
        cond = !nsym_true_p($2)

    } else if ($1 == "if_defined" || $1 == "ifdef") {
        if (NF < 2) error("Bad parameters:" $0)
        assert_nsym_valid_name($2)
        cond = nsym_defined_p($2)

    } else if ($1 == "if_not_defined" || $1 == "ifndef") {
        if (NF < 2) error("Bad parameters:" $0)
        assert_nsym_valid_name($2)
        cond = !nsym_defined_p($2)

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
        cond = !path_exists_p(rm_quotes($2))

    # @if(_not)_in KEY ARR
    # Test if symbol ARR[KEY] is defined.  Key comes first, because in Awk,
    # one writes "key IN array" for the predicate.  This is just prefix...
    } else if ($1 == "if_in") {   # @if_in us-east-1 VALID_REGIONS
        # @if_in KEY ARR
        if (NF < 3) error("Bad parameters:" $0)
        assert_nsym_valid_name($3)
        cond = nsym_defined_p(sprintf("%s[%s]", $3, $2))

    } else if ($1 == "if_not_in") {
        if (NF < 3) error("Bad parameters:" $0)
        assert_nsym_valid_name($3)
        #print_stderr(sprintf("if_not_in: %s[%s]", $3, $2))
        cond = !nsym_defined_p(sprintf("%s[%s]", $3, $2))

    } else
        # Should not happen
        error("builtin_if(): '" $1 "' not matched:" $0)

    __active[++__if_depth] = currently_active_p() ? cond : FALSE
    __seen_else[__if_depth] = FALSE
}


# @nextfile, @ignore    DELIM
function builtin_ignore(    buf, delim, save_line, save_lineno)
{
    # Ignore input until line starts with $2.  This means
    #     @ignore The
    #        <...>
    #     Theodore Roosevelt
    # ignores <...> text up to, and including, the president's name.

    if (!currently_active_p())
        return
    if (($1 == "@ignore" && NF != 2) || ($1 == "@nextfile" && NF != 1))
        error("Bad parameters:" $0)
    if ($1 == "@nextfile")
        read_lines_until("")
    else {
        save_line = $0
        save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
        delim = $2
        buf = read_lines_until(delim)
        if (buf == EOD_INDICATOR)
            error(sprintf("Delimiter '%s' not found:%s" delim, save_line), "", save_lineno)
    }
}


# @{s,}{include,paste}  FILE
function builtin_include(    error_text, filename, read_literally, silent)
{
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    read_literally = (substr($1, length($1) - 4) == "paste") # paste does not process macros
    silent         = (substr($1, 2, 1) == "s") # silent mutes file errors, even in strict mode
    $1 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))
    if (!dofile(filename, read_literally)) {
        if (silent) return
        error_text = "File '" filename "' does not exist:" $0
        if (strictp())
            error(error_text)
        else
            warn(error_text)
    }
}


# @decr, @incr          NAME [N]
function builtin_incr(    sym, incr)
{
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    sym = $2
    assert_nsym_okay_to_define(sym)
    assert_nsym_defined(sym, "incr")
    if (NF >= 3 && ! integerp($3))
        error("Value '" $3 "' must be numeric:" $0)
    incr = (NF >= 3) ? $3 : 1
    nsym_increment(sym, ($1 == "@incr") ? incr : -incr)
}


# @input                [NAME]
function builtin_input(    getstat, input, sym)
{
    # Read a single line from /dev/tty.  No prompt is issued; if you
    # want one, use @echo.  Specify the symbol you want to receive the
    # data.  If no symbol is specified, __INPUT__ is used by default.
    if (!currently_active_p())
        return
    sym = (NF < 2) ? "__INPUT__" : $2
    assert_nsym_okay_to_define(sym)
    getstat = getline input < "/dev/tty"
    if (getstat == ERROR) {
        warn("Error reading file '/dev/tty' [input]:" $0)
        input = EMPTY
    }
    nsym_store(sym, input)
}


# @local                NAME
# @local FOO adds to nnamtab (as a scalar) in the current namespace, does not define it
function builtin_local(    name)
{
    if (!currently_active_p())
        return
    if (NF != 2)
        error("Bad parameters:" $0)
    if (__namespace == GLOBAL_NAMESPACE)
        error("Cannot use @local in global namespace")
    name = $2

    # check for valid name
    if (!nnam_valid_with_strict_as(name))
        error("@local: Invalid name")
    if (nnam_ll_in(name, __namespace))
        error("@local: Name already exists in current namespace")

    nsym_create(name, TYPE_SYMBOL)
}


# @longdef              NAME
function builtin_longdef(    buf, save_line, save_lineno, sym)
{
    if (!currently_active_p())
        return
    if (NF != 2)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    sym = $2
    assert_nsym_okay_to_define(sym)
    buf = read_lines_until("@endlong")
    if (buf == EOD_INDICATOR)
        error("Delimiter '@endlongdef' not found:" save_line, "", save_lineno)
    nsym_store(sym, buf)
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
function builtin_newcmd(    buf, save_line, save_lineno, name, nparam)
{
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    name = $2
    assert_ncmd_okay_to_define(name)
    save_line = $0
    save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)

    buf = read_lines_until("@endcmd")
    if (buf == EOD_INDICATOR)
        error("Delimiter '@endcmd' not found:" save_line, "", save_lineno)

    nnam_ll_write(name, GLOBAL_NAMESPACE, TYPE_COMMAND)
    ncmd_ll_write(name, buf)
    ncmdtab[name, "nparam"] = nparam
}


# @{s,}read             NAME FILE
function builtin_read(    sym, filename, line, val, getstat, silent)
{
    # This is not intended to be a full-blown file inputter but rather just
    # to read short snippets like a file path or username.  As usual, multi-
    # line values are accepted but the final trailing \n (if any) is stripped.
    if (!currently_active_p())
        return
    #dbg_print("read", 7, ("@read: $0='" $0 "'"))
    if (NF < 3)
        error("Bad parameters:" $0)
    silent = (substr($1, 2, 1) == "s") # silent mutes file errors, even in strict mode
    sym  = $2
    assert_nsym_okay_to_define(sym)

    $1 = $2 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))

    val = EMPTY
    while (TRUE) {
        getstat = getline line < filename
        if (getstat == ERROR && !silent)
            warn("Error reading file '" filename "' [read]")
        if (getstat == EOF)
            break
        val = val line "\n"     # Read a line
    }
    close(filename)
    nsym_store(sym, chomp(val))
}


# @{s,}readarray        ARR FILE
function builtin_readarray(    arr, filename, line, getstat, line_cnt, silent, level)
{
    if (!currently_active_p())
        return
    #dbg_print("read", 7, ("@readarray: $0='" $0 "'"))
    if (NF < 3)
        error("Bad parameters:" $0)
    silent = (substr($1, 2, 1) == "s") # silent mutes file errors, even in strict mode
    arr = $2
    # Check that arr is really an ARRAY and that it's writable
    # What if it already has values?  Should they be erased?  I'm inclined to think so
    assert_nsym_okay_to_define(arr)

    $1 = $2 = ""
    sub("^[ \t]*", "")
    filename = rm_quotes(dosubs($0))
    line_cnt = 0
    level = __namespace         # FIXME

    while (TRUE) {
        getstat = getline line < filename
        if (getstat == ERROR && !silent)
            warn("Error reading file '" filename "' [read]")
        if (getstat == EOF)
            break
        nsym_ll_write(arr, ++line_cnt, level, line)
    }
    close(filename)
    nsym_ll_write(arr, 0, level, line_cnt)
}


# @readonly             NAME
#   @readonly VAR.  makes existing variable read-only.  No way to undo
#   @readonly ARR also works, freezes array preventing adding new elements.
#   @readonly cannot be performed on SYSTEM symbols or arrays
function builtin_readonly(    name, code, silent)
{
    if (!currently_active_p())
        return
    if (NF < 1)
        error("Bad parameters:" $0)
    name = $2
    if (!nnam_ll_in(name, __namespace))
        error("@readonly: name not defined in current namespace")
    code = nnam_ll_read(name, __namespace)
    if (flag_allfalse_p(code, TYPE_ARRAY TYPE_SYMBOL))
        error("@readonly: name must be symbol or array")
    if (flag_1true_p(code, FLAG_SYSTEM))
        error("@readonly: name protected")
    nnam_ll_write(name, __namespace, flag_set_clear(code, FLAG_READONLY))
}


# @sequence             ID SUBCMD [ARG...]
function builtin_sequence(    id, action, arg, saveline)
{
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    id = $2
    assert_nseq_valid_name(id)
    if (NF == 2)
        $3 = "create"
    action = $3
    if (action != "create" && !nseq_defined_p(id))
        error("Name '" id "' not defined [sequence]:" $0)
    if (NF == 3) {
        if (action == "create") {
            assert_nseq_okay_to_define(id)
            nnam_ll_write(id, GLOBAL_NAMESPACE, TYPE_SEQUENCE FLAG_INTEGER)
            nseqtab[id, "incr"]    = SEQ_DEFAULT_INCR
            nseqtab[id, "init"]    = SEQ_DEFAULT_INIT
            nseqtab[id, "fmt"]     = nsym_ll_read("__FMT__", "seq", GLOBAL_NAMESPACE)
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


# @shell                DELIM [PROG]
# Set symbol "M2_SHELL" to override.
function builtin_shell(    delim, save_line, save_lineno, input_text, input_file,
                      output_text, output_file, sendto, path_fmt, getstat,
                      cmdline, line)
{
    # The sendto program defaults to a reasonable shell but you can
    # specify where you want to send your data.  Possibly useful choices
    # would be an alternative shell, an email message reader, or
    # /usr/bin/bc.  It must be a program that functions as a filter (in
    # the Unix sense, i.e., reading from standard input and writing to
    # standard output).  Standard error is not redirected, so any errors
    # will appear on the user's terminal.
    if (!currently_active_p())
        return
    if (NF < 2)
        error("Bad parameters:" $0)
    save_line = $0
    save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    delim = $2
    if (NF == 2) {              # @shell DELIM
        sendto = default_shell()
    } else {                    # @shell DELIM /usr/ucb/mail
        $1 = ""; $2 = ""
        sub("^[ \t]*", "")
        sendto = rm_quotes(dosubs($0))
    }

    input_text = read_lines_until(delim)
    if (input_text == EOD_INDICATOR)
        error("Delimiter '" delim "' not found:" save_line, "", save_lineno)

    path_fmt    = sprintf("%sm2-%d.shell-%%s", tmpdir(), nsym_fetch("__PID__"))
    input_file  = sprintf(path_fmt, "in")
    output_file = sprintf(path_fmt, "out")
    print dosubs(input_text) > input_file
    close(input_file)

    # Don't tell me how fragile this is, we're whistling past the
    # graveyard here.  But it suffices to run /bin/sh, which is enough.
    cmdline = sprintf("%s < %s > %s", sendto, input_file, output_file)
    nsym_ll_write("__SHELL__", "", GLOBAL_NAMESPACE, system(cmdline))
    while (TRUE) {
        getstat = getline line < output_file
        if (getstat == ERROR)
            warn("Error reading file '" output_file "' [shell]")
        if (getstat == EOF)
            break
        output_text = output_text line "\n" # Read a line
    }
    close(output_file)

    exec_prog_cmdline("rm", ("-f " input_file))
    exec_prog_cmdline("rm", ("-f " output_file))
    ship_out(output_text)
}


# @typeout
function builtin_typeout(    buf)
{
    if (!currently_active_p())
        return
    buf = read_lines_until("")
    if (!emptyp(buf))
        ship_out(buf "\n")
}


# @undef[ine]           NAME
function builtin_undefine(    name, root)
{
    if (!currently_active_p())
        return
    if (NF != 2)
        error("Bad parameters:" $0)
    name = $2
    if (nseq_valid_p(name) && nseq_defined_p(name))
        nseq_destroy(name)
    else if (ncmd_valid_p(name) && ncmd_defined_p(name)) {
        ncmd_destroy(name)
    } else {
        root = name             # sym_root(name)
        assert_nsym_valid_name(root)
        assert_nsym_unprotected(root)
        # System symbols, even unprotected ones -- despite being subject
        # to user modification -- cannot be undefined.
        if (nsym_system_p(root))
            error("Name '" root "' not available:" $0)
        dbg_print("symbol", 3, ("About to sym_destroy('" name "')"))
        nsym_destroy(name)
    }
}


# @undivert             [N]
function builtin_undivert(    stream, i)
{
    if (!currently_active_p())
        return
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
# The high-level processing happens in the dofile() function, which
# reads one line at a time, and decides what to do with each line.  The
# __active_files array keeps track of open files.  The symbol __FILE__
# stores the current file to read data from.  When an "@include"
# directive is seen, dofile() is called recursively on the new file.
# Interestingly, the included filename is first processed for macros.
# Read this function carefully--there are some nice tricks here.
#
# Caller is responsible for removing potential quotes from filename.
function dofile(filename, read_literally,
                savebuffer, savefile, saveifdepth, saveline, saveuuid, ctx)
{
    if (filename == "-")
        filename = "/dev/stdin"
    if (!path_exists_p(filename))
        return FALSE
    dbg_print("m2", 1, ("(dofile) filename='" filename "'" \
                        (read_literally ? ", read_literally=TRUE" : EMPTY)))
    if (filename in __active_files)
        error("Cannot recursively read '" filename "':" $0)
    save_context(ctx)

    # Set up new file context
    __active_files[filename] = TRUE
    __buffer = EMPTY
    nsym_increment("__NFILE__", 1)
    nsym_ll_write("__FILE__",      "", GLOBAL_NAMESPACE, filename)
    nsym_ll_write("__LINE__",      "", GLOBAL_NAMESPACE, 0)
    nsym_ll_write("__FILE_UUID__", "", GLOBAL_NAMESPACE, uuid())

    # Read the file and process each line
    while (readline() == OKAY)
        process_line(read_literally)

    # Reached end of file
    flush_stdout()
    # Avoid I/O errors (on BSD at least) on attempt to close stdin
    if (filename != "-" && filename != "/dev/stdin")
        close(filename)
    delete __active_files[filename]
    restore_context(ctx)
    return TRUE
}


# Put next input line into global string "__buffer".  The readline()
# function manages the "pushback."  After expanding a macro, macro
# processors examine the newly created text for any additional macro
# names.  Only after all expanded text has been processed and sent to
# the output does the program get a fresh line of input.
# Return OKAY, ERROR, or EOF.
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
            warn("Error reading file '" nsym_ll_read("__FILE__", "", GLOBAL_NAMESPACE) "' [readline]")
        } else if (getstat != EOF) {
            nsym_increment("__LINE__", 1)
            nsym_increment("__NLINE__", 1)
        }
    }
    return getstat
}
function process_line(read_literally,    sp, lbrace, cut, newstring, user_cmd)
{
    dbg_print("io", 1, "(process_line) Start; line " nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE) ": $0='" $0 "'")

    # Short circuit if we're not processing macros, or no @ found
    if (read_literally ||
        (currently_active_p() && index($0, "@") == IDX_NOT_FOUND)) {
        ship_out($0 "\n")
        return
    }

    # Look for control commands.  These are hard-wired, and cannot be
    # overridden by @newcmd.  Note, they only match at beginning of line.
    if      (/^@(@|;|#)/)                 { } # Comments are ignored
    else if (/^@append([ \t]|$)/)         { builtin_define() }
    else if (/^@array([ \t]|$)/)          { builtin_array() }
    else if (/^@case([ \t]|$)/)           { builtin_case() }
    else if (/^@c(omment)?([ \t]|$)/)     { } # Comments are ignored
    else if (/^@decr([ \t]|$)/)           { builtin_incr() }
    else if (/^@default([ \t]|$)/)        { builtin_default() }
    else if (/^@define([ \t]|$)/)         { builtin_define() }
    else if (/^@debug([ \t]|$)/)          { builtin_error() }
    else if (/^@divert([ \t]|$)/)         { builtin_divert() }
    else if (/^@dump(all|def)?([ \t]|$)/) { builtin_dump() }
    else if (/^@echo([ \t]|$)/)           { builtin_error() }
    else if (/^@else([ \t]|$)/)           { builtin_else() }
    else if (/^@(endcase|esac)([ \t]|$)/) {
             error("No corresponding '@case':" $0) }
    else if (/^@endcmd([ \t]|$)/)         {
             error("No corresponding '@newcmd':" $0) }
    else if (/^@(endif|fi)([ \t]|$)/)     {
             if (__if_depth-- == 0)
                 error("No corresponding '@if':" $0) }
    else if (/^@endlong(def)?([ \t]|$)/)  {
             error("No corresponding '@longdef':" $0) }
    else if (/^@err(or|print)([ \t]|$)/)  { builtin_error() }
    else if (/^@s?(m2)?exit([ \t]|$)/)    { builtin_exit() }
    else if (/^@if(_not)?(_(defined|env|exists|in))?([ \t]|$)/)
                                          { builtin_if() }
    else if (/^@ifn?def([ \t]|$)/)        { builtin_if() }
    else if (/^@ignore([ \t]|$)/)         { builtin_ignore() }
    else if (/^@s?include([ \t]|$)/)      { builtin_include() }
    else if (/^@incr([ \t]|$)/)           { builtin_incr() }
    else if (/^@init(ialize)?([ \t]|$)/)  { builtin_default() }
    else if (/^@input([ \t]|$)/)          { builtin_input() }
    else if (/^@local([ \t]|$)/)          { builtin_local() }
    else if (/^@longdef([ \t]|$)/)        { builtin_longdef() }
    else if (/^@newcmd([ \t]|$)/)         { builtin_newcmd() }
    else if (/^@nextfile([ \t]|$)/)       { builtin_ignore() }
    else if (/^@of([ \t]|$)/)             {
             error("No corresponding '@case':" $0) }
    else if (/^@otherwise([ \t]|$)/)      {
             error("No corresponding '@case':" $0) }
    else if (/^@s?paste([ \t]|$)/)        { builtin_include() }
    else if (/^@s?read([ \t]|$)/)         { builtin_read() }
    else if (/^@s?readarray([ \t]|$)/)    { builtin_readarray() }
    else if (/^@s?readonly([ \t]|$)/)     { builtin_readonly() }
    else if (/^@sequence([ \t]|$)/)       { builtin_sequence() }
    else if (/^@shell([ \t]|$)/)          { builtin_shell() }
    else if (/^@stderr([ \t]|$)/)         { builtin_error() }
    else if (/^@typeout([ \t]|$)/)        { builtin_typeout() }
    else if (/^@undef(ine)?([ \t]|$)/)    { builtin_undefine() }
    else if (/^@undivert([ \t]|$)/)       { builtin_undivert() }
    else if (/^@unless([ \t]|$)/)         { builtin_if() }
    else if (/^@warn([ \t]|$)/)           { builtin_error() }

    # These are only for development
    else if (/^@dump_nnamtab$/)           { nnam_dump_nnamtab(TYPE_ANY) }
    else if (/^@dump_nseqtab$/)           { nnam_dump_nnamtab(TYPE_SEQUENCE)
                                            nsym_dump_nseqtab() }
    else if (/^@dump_nsymtab$/)           { nnam_dump_nnamtab(TYPE_ARRAY)
                                            nnam_dump_nnamtab(TYPE_SYMBOL)
                                            nsym_dump_nsymtab() }
    else if (/^@for([ \t]|$)/)            { builtin_for() }
    else if (/^@next([ \t]|$)/)           { builtin_next() }
    else if (/^@raise_namespace/)         { raise_namespace() }
    else if (/^@lower_namespace/)         { lower_namespace() }
    else if (/^@qq([ \t]|$)/)             { do_qq() }
    else if (/^@test([ \t]|$)/)           { run_latest_tests() }

    # Check for user commands
    else if (currently_active_p() &&
             first($1) == "@"     &&
             ncmd_defined_p(substr($1, 2)))
        docommand()

    # Process @
    else {
        newstring = dosubs($0)
        if (newstring == $0 || index(newstring, "@") == IDX_NOT_FOUND) {
            if (currently_active_p())
                ship_out(newstring "\n")
        } else {
            __buffer = newstring "\n" __buffer
        }
    }
    dbg_print("io", 1, "(process_line) End")
}



# This is only called by process_line(), which guarantees that $0 is
# unchanged, and that $1 is "@<CMD>".  This is important because we have
# to get the command name from there (i.e., $1).  It's *not* passed in
# as a parameter as you might expect.  Also, process_line checks to make
# sure the command name is defined; we trust that and just blindly grab
# the definition.  Arguments/parameters are WIP.
function docommand(    cmdname, ctx, narg)
{
    dbg_print("ncmd", 1, "(docommand) Start; line " nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE) ": $0='" $0 "'")
    narg = NF - 1
    save_context(ctx)

    cmdname = substr($1, 2)
    __buffer = ncmd_ll_read(cmdname)
    nsym_ll_write("__FILE__", "", GLOBAL_NAMESPACE, $1)
    nsym_ll_write("__LINE__", "", GLOBAL_NAMESPACE, 0)

    raise_namespace()
    process_buffer()
    lower_namespace()

    restore_context(ctx)
    dbg_print("ncmd", 1, "(docommand) End")
    return TRUE
}


function docasebranch(casenum, branch, brline,
                      ctx)
{
    save_context(ctx)

    __buffer = casetab[casenum, branch, "definition"]
    nsym_ll_write("__LINE__", "", GLOBAL_NAMESPACE, brline)

    process_buffer()

    restore_context(ctx)
    dbg_print("case", 1, "(docasebranch) End")
    return TRUE
}

function doforloop(fornum,
                   ctx, counter, done)
{
    save_context(ctx)
    nsym_ll_write("__LINE__", "", GLOBAL_NAMESPACE, 0)
    counter = 1

    raise_namespace()
    nnam_ll_write("I", __namespace, TYPE_SYMBOL FLAG_READONLY)
    nsym_ll_write("I", "", __namespace, counter)
    done = nsym_fetch("I") > 5
    while (!done) {
        __buffer = fortab[fornum, "definition"]
        process_buffer()
        # Must use ll function because loop index is read0-only,
        # and nsym_increment() is "user mode".
        nsym_ll_write("I", "", __namespace, ++counter)
        done = nsym_fetch("I") > 5
    }
    lower_namespace()

    restore_context(ctx)
    dbg_print("for", 1, "(doforloop) End")
    return TRUE
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
                      at_brace, x, y, inc_dec, pre_post, subcmd, silent)
{
    l = ""                   # Left of current pos  - ready for output
    r = s                    # Right of current pos - as yet unexamined
    inc_dec = pre_post = 0   # track ++ or -- on sequences

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
        #     @mid@         --> nparam == 0
        #     @mid foo@     --> nparam == 1
        #     @mid foo 3@   --> nparam == 2
        # In general, a function's parameter N is available in variable
        #   param[N+1].  Consider "mid foo 3".  nparam is 2.
        #   The fn is found in the first position, at param [0+1].
        #   The new prefix is at param[1+1] and new count is at param[2+1].
        #   This offset of one is referred to as `__off_by' below.
        # Each function condition eventually executes
        #     r = <SOMETHING> r
        #   which injects <SOMETHING> just before the current value of
        #   r.  (r is defined above.)  r is what is to the right of the
        #   current position and contains as yet unexamined text that
        #   needs to be evaluated for possible macro processing.  This
        #   is the data we were going to evaluate anyway.  In other
        #   words, this injects the result of "invoking" fn.
        # Eventually this big while loop exits and we return "l r".

        nparam = split(m, param) - __off_by
        fn = param[0 + __off_by]
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
        if (fn == "basename") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + __off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            # basename in Awk, assuming Unix style path separator.
            # return filename portion of path
            expand = rm_quotes(nsym_fetch(p))
            sub(/^.*\//, "", expand)
            # This is the original, expensive version that uses /usr/bin/basename
            # Retained for historical interest, or if above code doesn't work for you
            # cmdline = build_prog_cmdline(fn, rm_quotes(nsym_fetch(p)), FALSE)
            # cmdline | getline expand
            # close(cmdline)
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
                p = param[1 + __off_by]
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
                    else if (strictp())
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
            p = param[1 + __off_by]
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
            if (fn == "strftime" && nparam == 0)
                error("Bad parameters in '" m "':" $0)
            y = fn == "strftime" ? substr(m, length(fn)+2) \
                : nsym_ll_read("__FMT__", fn)
            gsub(/"/, "\\\"", y)
            cmdline = build_prog_cmdline("date", "+\"" y "\"", FALSE)
            cmdline | getline expand
            close(cmdline)
            r = expand r

        # dirname SYM: Directory name of path
        } else if (fn == "dirname") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + __off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            # dirname in Awk, assuming Unix style path separator.
            # return directory portion of path
            y = rm_quotes(nsym_fetch(p))
            expand = (sub(/\/[^\/]*$/, "", y)) ? y : "."
            # This is the original, expensive version that uses /usr/bin/basename
            # Retained for historical interest, or if above code doesn't work for you
            # cmdline = build_prog_cmdline(fn, rm_quotes(nsym_fetch(p)), FALSE)
            # cmdline | getline expand
            # close(cmdline)
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
        #   @getenv HOME@ => /home/user
        } else if (fn == "getenv") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + __off_by]
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
            p = param[1 + __off_by]
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
            p = param[1 + __off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            x = 1
            if (nparam == 2) {
                x = param[2 + __off_by]
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
            p = param[1 + __off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            x = param[2 + __off_by]
            if (!integerp(x))
                error("Value '" x "' must be numeric:" $0)
            if (nparam == 2) {
                r = substr(nsym_fetch(p), x) r
            } else if (nparam == 3) {
                y = param[3 + __off_by]
                if (!integerp(y))
                    error("Value '" y "' must be numeric:" $0)
                r = substr(nsym_fetch(p), x, y) r
            }

        # ord SYM : Output character with ASCII code SYM
        #   @define B *Nothing of interest*
        #   @ord A@ => 65
        #   @ord B@ => 42
        } else if (fn == "ord") {
            if (nparam != 1) error("Bad parameters in '" m "':" $0)
            p = param[1 + __off_by]
            if (nsym_valid_p(p) && nsym_defined_p(p))
                p = nsym_fetch(p)
            r = _ord_[first(p)] r

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
            p = param[1 + __off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            x = length(nsym_fetch(p))
            if (nparam == 2) {
                x = param[2 + __off_by]
                if (!integerp(x))
                    error("Value '" x "' must be numeric:" $0)
            }
            r = substr(nsym_fetch(p), x) r

        # spaces [N]: N spaces
        } else if (fn == "spaces") {
            if (nparam > 1) error("Bad parameters in '" m "':" $0)
            x = 1
            if (nparam == 1) {
                x = param[1 + __off_by]
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
            p = param[1 + __off_by]
            assert_nsym_valid_name(p)
            assert_nsym_defined(p, fn)
            expand = nsym_fetch(p)
            if (fn == "trim" || fn == "ltrim")
                sub(/^[ \t]+/, "", expand)
            if (fn == "trim" || fn == "rtrim")
                sub(/[ \t]+$/, "", expand)
            r = expand r

        # uuid : Something that resembles but is not a UUID
        #   @uuid@ => C3525388-E400-43A7-BC95-9DF5FA3C4A52
        } else if (fn == "uuid") {
            r = uuid() r

        # <SOMETHING ELSE> : Call a user-defined macro, handles arguments
        } else if (nsym_valid_p(fn) && (nsym_defined_p(fn) || nsym_delayed_p(fn))) {
            expand = nsym_fetch(fn)
            # Expand $N parameters (includes $0 for macro name)
            j = MAX_PARAM   # but don't go overboard with params
            # Count backwards to get around $10 problem.
            while (j-- >= 0) {
                if (index(expand, "${" j "}") > 0) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$\\{" j "\\}", param[j + __off_by], expand)
                 }
                if (index(expand, "$" j) > 0) {
                    if (j > nparam)
                        error("Parameter " j " not supplied in '" m "':" $0)
                    gsub("\\$" j, param[j + __off_by], expand)
                }
            }
            r = expand r

        # Check if it's a sequence
        } else if (nseq_valid_p(fn) && nseq_defined_p(fn)) {
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
                subcmd = param[1 + __off_by]
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

    dbg_print("braces", 3, ("<< expand_braces: returning '" s "'"))
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
            dbg_print("braces", 3, ("<< find_closing_brace: returning " start+offset))
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
# Caller is responsible for ensuring sym name is valid.
# Caller is responsible for ensuring sym is not protected.
function dodef(append_flag,    sym, str, x)
{
    sym = $2
    sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "")  # old bug: last * was +
    str = $0
    while (str ~ /\\$/) {
        if (readline() != OKAY)
            error("Unexpected end of definition:" sym)
        # old bug: sub(/\\$/, "\n" $0, str)
        x = $0
        sub(/^[ \t]+/, "", x)
        str = chop(str) "\n" x
    }
    nsym_store(sym, append_flag ? nsym_fetch(sym) str : str)
}
# Try to read init files: $M2RC, $HOME/.m2rc, and/or ./.m2rc
# M2RC is intended to *override* $HOME (in case HOME is unavailable or
# otherwise unsuitable), so if the variable is specified and the file
# exists, then do that file; only otherwise do $HOME/.m2rc.  An init
# file from the current directory is always attempted in any case.
# No worries or errors if any of them don't exist.
function load_init_files()
{
    # Don't load the init files more than once
    if (__init_files_loaded == TRUE)
        return

    if ("M2RC" in ENVIRON && path_exists_p(ENVIRON["M2RC"]))
        dofile(ENVIRON["M2RC"], FALSE)
    else if ("HOME" in ENVIRON)
        dofile(ENVIRON["HOME"] "/.m2rc", FALSE)
    dofile("./.m2rc", FALSE)

    # Don't count init files in total line/file tally - it's better to
    # keep them in sync with the files from the command line.
    nsym_ll_write("__NFILE__", "", GLOBAL_NAMESPACE, 0)
    nsym_ll_write("__NLINE__", "", GLOBAL_NAMESPACE, 0)
    __init_files_loaded = TRUE
}


# Customize these paths as necessary for correct operation on your system.
# It is important that __PROG__ remain a read-only symbol.  Otherwise,
# some bad person could entice you to evaluate:
#       @define __PROG__[stat]  /bin/rm
#       @include my_precious_file
function setup_prog_paths()
{
    nsym_ll_fiat("__TMPDIR__", "",       FLAGS_WRITABLE_SYMBOL,  "/tmp/")

    nnam_ll_write("__PROG__", GLOBAL_NAMESPACE, TYPE_ARRAY FLAG_READONLY FLAG_SYSTEM)
    nsym_ll_fiat("__PROG__", "basename", FLAGS_READONLY_SYMBOL, "/usr/bin/basename")
    nsym_ll_fiat("__PROG__", "date",     FLAGS_READONLY_SYMBOL, "/bin/date")
    nsym_ll_fiat("__PROG__", "dirname",  FLAGS_READONLY_SYMBOL, "/usr/bin/dirname")
    nsym_ll_fiat("__PROG__", "hostname", FLAGS_READONLY_SYMBOL, "/bin/hostname")
    nsym_ll_fiat("__PROG__", "id",       FLAGS_READONLY_SYMBOL, "/usr/bin/id")
    nsym_ll_fiat("__PROG__", "pwd",      FLAGS_READONLY_SYMBOL, "/bin/pwd")
    nsym_ll_fiat("__PROG__", "rm",       FLAGS_READONLY_SYMBOL, "/bin/rm")
    nsym_ll_fiat("__PROG__", "sh",       FLAGS_READONLY_SYMBOL, "/bin/sh")
    nsym_ll_fiat("__PROG__", "stat",     FLAGS_READONLY_SYMBOL, "/usr/bin/stat")
    nsym_ll_fiat("__PROG__", "uname",    FLAGS_READONLY_SYMBOL, "/usr/bin/uname")
}


# Nothing in this function is user-customizable, so don't touch
function initialize(    get_date_cmd, d, dateout, array, elem, i)
{
    DISCARD_STREAMS      = 0
    E                    = exp(1)
    EOD_INDICATOR        = "EoD1" SUBSEP "eOd2" # Unlikely to occur in normal text
    IDX_NOT_FOUND        = 0
    LOG10                = log(10)
    MAX_DBG_LEVEL        = 10
    MAX_PARAM            = 20
    MAX_STREAM           = 9
    PI                   = atan2(0, -1)
    SEQ_DEFAULT_INCR     = 1
    SEQ_DEFAULT_INIT     = 0
    SHIP_OUT_STREAMS     = 1
    TAU                  = 8 * atan2(1, 1)      # 2 * PI

    __buffer             = EMPTY
    __casenum            = 0
    __fornum             = 0
    __init_files_loaded  = FALSE # Becomes TRUE in load_init_files()
    __if_depth           = 0
    __active[__if_depth] = TRUE
    __namespace          = GLOBAL_NAMESPACE
    __off_by             = 1

    srand()                     # Seed random number generator
    _ord_init()
    setup_prog_paths()

    # Capture m2 run start time.                 1  2  3  4  5  6  7  8
    get_date_cmd = build_prog_cmdline("date", "+'%Y %m %d %H %M %S %z %s'", FALSE)
    get_date_cmd | getline dateout
    split(dateout, d)
    close(get_date_cmd)

    nnam_ll_write("__FMT__",  GLOBAL_NAMESPACE, TYPE_ARRAY               FLAG_SYSTEM)

    if ("PWD" in ENVIRON)
      nsym_ll_fiat("__CWD__",       "", FLAGS_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["PWD"]))
    else
      nsym_delayed_symbol("__CWD__",    FLAGS_READONLY_SYMBOL,  "pwd", "")
    nsym_ll_fiat("__DATE__",        "", FLAGS_READONLY_INTEGER, d[1] d[2] d[3])
    nsym_ll_fiat("__DIVNUM__",      "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__EPOCH__",       "", FLAGS_READONLY_INTEGER, d[8])
    nsym_ll_fiat("__EXPR__",        "", FLAGS_READONLY_NUMERIC, 0.0)
    nsym_ll_fiat("__FILE__",        "", FLAGS_READONLY_SYMBOL,  "")
    nsym_ll_fiat("__FILE_UUID__",   "", FLAGS_READONLY_SYMBOL,  "")
    nsym_ll_fiat("__FMT__",       TRUE, FLAGS_WRITABLE_SYMBOL,  "1")
    nsym_ll_fiat("__FMT__",      FALSE, FLAGS_WRITABLE_SYMBOL,  "0")
    nsym_ll_fiat("__FMT__",     "date", FLAGS_WRITABLE_SYMBOL,  "%Y-%m-%d")
    nsym_ll_fiat("__FMT__",    "epoch", FLAGS_READONLY_SYMBOL,  "%s")
    nsym_ll_fiat("__FMT__",   "number", FLAGS_WRITABLE_SYMBOL,  CONVFMT)
    nsym_ll_fiat("__FMT__",      "seq", FLAGS_WRITABLE_SYMBOL,  "%d")
    nsym_ll_fiat("__FMT__",     "time", FLAGS_WRITABLE_SYMBOL,  "%H:%M:%S")
    nsym_ll_fiat("__FMT__",       "tz", FLAGS_READONLY_SYMBOL,  "%Z")
    nsym_delayed_symbol("__GID__",      FLAGS_READONLY_INTEGER, "id", "-g")
    if ("HOME" in ENVIRON)
      nsym_ll_fiat("__HOME__",      "", FLAGS_READONLY_SYMBOL,  with_trailing_slash(ENVIRON["HOME"]))
    nsym_delayed_symbol("__HOST__",     FLAGS_READONLY_SYMBOL,  "hostname", "-s")
    nsym_delayed_symbol("__HOSTNAME__", FLAGS_READONLY_SYMBOL,  "hostname", "-f")
    nsym_ll_fiat("__INPUT__",       "", FLAGS_WRITABLE_SYMBOL,  EMPTY)
    nsym_ll_fiat("__LINE__",        "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__M2_UUID__",     "", FLAGS_READONLY_SYMBOL,  uuid())
    nsym_ll_fiat("__M2_VERSION__",  "", FLAGS_READONLY_SYMBOL,  __version)
    nsym_ll_fiat("__NFILE__",       "", FLAGS_READONLY_INTEGER, 0)
    nsym_ll_fiat("__NLINE__",       "", FLAGS_READONLY_INTEGER, 0)
    nsym_delayed_symbol("__OSNAME__",   FLAGS_READONLY_SYMBOL,  "uname", "-s")
    nsym_delayed_symbol("__PID__",      FLAGS_READONLY_INTEGER, "sh", "-c 'echo $PPID'")
    nsym_ll_fiat("__STRICT__",      "", FLAGS_WRITABLE_BOOLEAN, TRUE)
    nsym_ll_fiat("__TIME__",        "", FLAGS_READONLY_INTEGER, d[4] d[5] d[6])
    nsym_ll_fiat("__TIMESTAMP__",   "", FLAGS_READONLY_SYMBOL,  d[1] "-" d[2] "-" d[3] \
                                                            "T" d[4] ":" d[5] ":" d[6] d[7])
    nsym_ll_fiat("__TZ__",          "", FLAGS_READONLY_SYMBOL,  d[7])
    nsym_delayed_symbol("__UID__",      FLAGS_READONLY_INTEGER, "id", "-u")
    nsym_delayed_symbol("__USER__",     FLAGS_READONLY_SYMBOL,  "id", "-un")

    # Functions cannot be used as symbol or sequence names.
    split("basename boolval chr date dirname epoch expr getenv lc left len" \
          " ltrim mid ord rem right rtrim sexpr spaces strftime substr time" \
          " trim tz uc uuid", array, " ")
    for (elem in array)
        nnam_ll_write(array[elem], GLOBAL_NAMESPACE, TYPE_FUNCTION FLAG_SYSTEM)

    __flag_label[TYPE_ANY]      = "ANY"
    __flag_label[TYPE_ARRAY]    = "ARR"
    __flag_label[TYPE_BUILTIN]  = "BLT"
    __flag_label[TYPE_COMMAND]  = "CMD"
    __flag_label[TYPE_FUNCTION] = "FUN"
    __flag_label[TYPE_SEQUENCE] = "SEQ"
    __flag_label[TYPE_SYMBOL]   = "SYM"

    __flag_label[FLAG_BOOLEAN]  = "Boolean"
    __flag_label[FLAG_DELAYED]  = "Delayed"
    __flag_label[FLAG_INTEGER]  = "Integer"
    __flag_label[FLAG_NUMERIC]  = "Numeric"
    __flag_label[FLAG_READONLY] = "Read-only"
    __flag_label[FLAG_WRITABLE] = "Writable"
    __flag_label[FLAG_SYSTEM]   = "System"

    # Zero stream buffers
    for (i = 1; i <= MAX_STREAM; i++)
        __streambuf[i] = EMPTY
}


# This function is called automagically (it's baked into nsym_store())
# every time a non-zero value is stored into __DEBUG__.
function initialize_debugging()
{
    dbg_set_level("m2", 1)
    dbg_set_level("for", 4)
}



# The main program occurs in the BEGIN procedure below.
BEGIN {
    initialize()

    # No command line arguments: process standard input.
    if (ARGC == 1) {
        load_init_files()
        __exit_code = dofile("-", FALSE) ? EX_OK : EX_NOINPUT

    # Else, process all command line files/macro definitions.
    } else if (ARGC > 1) {
        # Delay loading $HOME/.m2rc as long as possible.  This allows us
        # to set symbols on the command line which will have taken effect
        # by the time the init file loads.
        for (_i = 1; _i < ARGC; _i++) {
            # Show each arg as we process it
            _arg = ARGV[_i]
            dbg_print("m2", 3, ("BEGIN: ARGV[" _i "]:" _arg))

            # If it's a definition on the command line, define it
            if (_arg ~ /^([^= ][^= ]*)=(.*)/) {
                _eq = index(_arg, "=")
                _name = substr(_arg, 1, _eq-1)
                _val = substr(_arg, _eq+1)
                if (_name == "strict")
                    _name = "__STRICT__"
                else if (_name == "debug")
                    _name = "__DEBUG__"
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
                if (!dofile(rm_quotes(_arg), FALSE)) {
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
            __exit_code = dofile("-", FALSE) ? EX_OK : EX_NOINPUT
        }

    # ARGC < 1, can't happen...
    } else {
        print_stderr("Usage: m2 [NAME=VAL ...] [file ...]")
        __exit_code = EX_USAGE
    }

    end_program(SHIP_OUT_STREAMS)
}


# Prepare to exit.  Normally, flush_diverted_streams has a true value,
# viz. SHIP_OUT_STREAMS, so we usually undivert all pending streams.
# When flush_diverted_streams is false (DISCARD_STREAMS), any diverted
# data is dropped.  Standard output is always flushed, and program exits
# with value from global variable __exit_code.
function end_program(flush_diverted_streams)
{
    # If requested (the normal case), ship out any remaining diverted
    # data.  See "STREAMS & DIVERSIONS" documentation above to see how
    # the user can prevent this if desired.
    if (flush_diverted_streams) {
        nsym_ll_write("__DIVNUM__", "", GLOBAL_NAMESPACE, 0)
        undivert_all()
    }
    flush_stdout()
    exit __exit_code
}


# Functions defined below are merely for testing !!!  Remove for production use.
# @test
function run_latest_tests(tmpval)
{
    # nsymtab["__DEBUG__", "", GLOBAL_NAMESPACE, "symval"] = TRUE
    # dbg_set_level("nnam", 5)
    # dbg_set_level("nsym", 5)
}

# @qq
function do_qq(k, x)
{
    print_stderr("arr[0] method=" nsymtab[0])
    print_stderr("length() method=" length(nsymtab))
}

function raise_namespace()
{
    __namespace++
    dbg_print("namespace", 4, "@raise_namespace: namespace now " __namespace)
}

function lower_namespace()
{
    if (__namespace == GLOBAL_NAMESPACE)
        error("Cannot @lower_namespace from global namespace")
    nsym_purge(__namespace)
    nnam_purge(__namespace)
    __namespace--
    dbg_print("namespace", 4, "@lower_namespace: namespace now " __namespace)
}

function builtin_for(    var, low, high, incr,
                         save_line, save_lineno)
{
    if (!currently_active_p())
        return
    #dbg_print("for", 7, ("@for: $0='" $0 "'"))
    if (NF < 4)
        error("Bad parameters:" $0)
    var = $2
    low = $3
    high = $4
    incr = 1
    dbg_print("for", 1, sprintf("@for: var=%s, low=%d, high=%d", var, low, high))
    save_line = $0
    save_lineno = nsym_ll_read("__LINE__", "", GLOBAL_NAMESPACE)
    __fornum++
    fortab[__fornum, "definition"] = EMPTY

    while (TRUE) {
        if (readline() != OKAY)
            # Whatever happened, the @for didn't finish properly
            error("Delimiter '@next' not found:" save_line, "", save_lineno)
        dbg_print("for", 5, "(builtin_for) readline='" $0 "'")
        if ($1 == "@next")
            # XXX Make sure loop variables are nested properly
            break
        else if ($1 == "@for")
            error("Cannot recursively read '@for'") # maybe someday
        else {
            # Append line to current buffer
            fortab[__fornum, "definition"] = \
            fortab[__fornum, "definition"] $0 "\n"
        }
    }

    # Entire @for structure read okay -- now execute the loop
    if (! emptyp(fortab[__fornum, "definition"]))
        doforloop(__fornum)
    delete fortab[__fornum, "definition"]
}

function builtin_next()
{
}


# TODO
# - ensure you can't shadow a system symbol
