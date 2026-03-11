In memory of Jon Bentley's mini macro processor "m1".  Alas, I have
embiggened it beyond all hope of reason, and I pine for the AWK pearl
that it was.  m2 retains the "fast substitution function" which is at
the core of m1; and fragments of even earlier versions can be found if
you look closely.

# Installation

m2 is a standalone Awk program and does not require any special
installation procedure: just put it somewhere in your PATH.

Before installing m2, there are a few configuration changes a user
may choose to make.  Except for item 1 which ensures correct operation,
no other adjustments are required; the defaults are suitable for running
on a typical Unix system.

1. You might need to adjust the first line of the source file (the
   "shebang line") which controls the Awk interpreter to use.

2. Feel free to change the paths stored in the PROG[] array, to reflect
   those needed for correct operation on your system.  If a program is
   not available, it's okay to remove the entry entirely.

3. Choose a security level.  0 (the default) permits the user to invoke
   commands in subshells.  1 prevents this but does allow safe commands
   from PROG[].  2 prohibits invoking any external programs.

# Test Suite

m2 includes a test suite which exercises most commands and functions.
Simply run the command

        make test

to run the tests, or for more verbose output

        make test-verbose

Individual tests are stored under the "tests" directory in a
subdirectory path structed as CATEGORY/SERIES/TESTNAME.  CATEGORY is an
alphabetic tag which broadly describes the area under test; examples
include EVAL, IF, NEWCMD, etc.  By convention, category names are in all
caps.  SERIES is a three digit integer, with leading zeros.  TESTNAME is
a name associated with the files which comprise the test.  At a minimum,
files named TESTNAME.m2 and TESTNAME.out are required to exist.

"make test" invokes the shell script check.sh which actually runs the
tests.  If check.sh is invoked with no arguments, all tests will be run.
If there is one argument, it must be in one of these three forms:

- CATEGORY
- CATEGORY/SERIES
- CATEGORY/SERIES/TESTNAME

This will run either all tests in a category, all tests in a specific
series, or one particular test, respectively, all depending on the
number of slashes.  Other files may optionally be present to control the
details of running a particular test.  For example, TESTNAME.err should
contain expected error text, if any; and TESTNAME.disabled will prevent
a test from executing at all.  See comments in check.sh for further
information on the file naming convention.

# M1 versions by Jon Bentley

## m2/etc/m0/

Bentley's initial development of m1, from m1.ps.

- m0a/ :: simple substitutions of @string@
- m0b/ :: simple @include support
- m0c/ :: nested macros: dosubs() expands string
          until no more expansions are made
- m0d/ :: support conditions @if...@fi  (buggy)

## m2/etc/m1/

The final version from Appendix 2 of Bentley's paper.

- This version supports nested @if statements.
- @unless is the opposite of @if: it includes text (up to @fi)
  if the variable is undefined or zero.
- Supports multi-line @define: end each line with a backslash.
- Because macro expansion can generate lines that need to be read
  by dofile(), the new readline() is implemented.
  - This function reads a line from the text "buffer", if it is
    not empty, and otherwise reads from the current file.
  - String "s" can be `pushed back' onto the input stream by
    concatenating it on the front (left) of "buffer" with:
        buffer = s buffer
- @comment ... is supported.
- error() function reports weird conditions.
- @default is like @define but only takes effect if the variable
  is not previously defined.

Complete m1 language:

        @comment Any text
        @define name value
        @default name value     Set if name undefined
        @include filename
        @if varname             Include subsequent text if varname != 0
        @fi                     Terminate @if or unless
        @unless varname         Include subsequent text if varname == 0
        Anywhere in line @name@

# M1: A Micro Macro Processor
Jon Bentley, AT&T Bell Laboratories
- [[file:etc/m1.pdf]]

# Online References

Alas, these are starting to disappear from the Internet...
At one time, they were reachable at the addresses shown.
I've tried to preserve some things in m2/etc/x-*.

## Dr Dobbs Journal
m1: A Mini Macro Processor
Jon Bentley, July 03, 2007
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=1
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=2
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=3
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=4

## O'Reilly: _sed & awk_
- https://docstore.mik.ua/orelly/unix3/sedawk/ch13_10.htm
  # Ch 13.10 : m1 -- Simple Macro Processor
- m2/etc/x-oreilly/

## Dave Bucklin

He writes: "I have enhanced my version of m1 with the suggested
`@longdefine` and `@undefine` macros, and a `@calc` macro that
incorporates functionality from my Awk-based emulation of dc."

- https://davebucklin.com/play/2020/10/13/mac.html
- https://gitlab.com/davebucklin/m1
- m2/etc/x-bucklin/

## Lawker
- https://github.com/timm/lawker/blob/master/fridge/lib/awk/m1.awk
- m2/etc/x-lawker/
