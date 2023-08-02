In memory of Jon Bentley's mini macro processor "m1".  Alas, I have
embiggened it beyond all hope of reason, and I pine for the AWK pearl
that it was.  m2 retains the "fast substitution function" which is at
the core of m1; and fragments of even earlier versions can be found if
you look closely.

# m2

## m2/etc/

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
