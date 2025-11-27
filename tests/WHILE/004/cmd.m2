@newcmd foo
@local n
@define n 3
@while n > 0
Down to @n@
@decr n
@endwhile
All done
@endcmd
@foo
@undefine foo
