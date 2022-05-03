In memory of Jon Bentley's mini macro processor "m1".  Alas, I have
embiggened it beyond all hope of reason, and I pine for the AWK pearl
that was m1.  It can still be found in the core of m2 though.

# /etc/

Bentley's initial development of m1, from m1.ps.

- m0a/ : simple substitutions of @string@
- m0b/ : simple @include support
- m0c/ : nested macros: call dosubs() until
- m0d/ : support conditions @if...@fi  (buggy)

# /etc/m1/

The final version from Bentley's m1.ps paper.

- This version supports nested @if statements.
- @unless is the opposite of @if: it includes text (up to @fi)
  if the variable is undefined or zero.
- Supports multi-line @define: end each line with a backslash.
- Because macro expansion can generate lines that need to be read
  by dofile(), the new readline() is implemented.
  + This function reads a line from the text "buffer", if it is
    not empty, and otherwise reads from the current file.
  + String "s" can be `pushed back' onto the input stream by
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

# References

## M1: A Micro Macro Processor
Jon Bentley, AT&T Bell Laboratories
- [[file:etc/m1.pdf]]

## Dr Dobbs Journal
m1: A Mini Macro Processor
Jon Bentley, July 03, 2007
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=1
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=2
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=3
- https://www.drdobbs.com/open-source/m1-a-mini-macro-processor/200001791?pgno=4

## O'Reilly: _sed & awk_
13.10.  m1 -- Simple Macro Processor
- https://docstore.mik.ua/orelly/unix3/sedawk/ch13_10.htm

## Dave Bucklin
- https://davebucklin.com/play/2020/10/13/mac.html
- etc/m1.awk.dave_bucklin :: https://gitlab.com/davebucklin/m1

## Lawker
- etc/m1.awk.lawker :: https://github.com/timm/lawker/blob/master/fridge/lib/awk/m1.awk
