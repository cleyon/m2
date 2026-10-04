@define n 42
@newcmd foo { n:int }
@while n > 0
Down to @n@
@decr n
@endwhile
All done
@endcmd
@foo{3}
@undefine foo
At end, n=@n@
