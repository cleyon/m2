@newcmd foo
@local x
@define x 3
@while x > 0
x=@x@
@define x @expr x-1@
@endwhile
@endcmd
@foo
@dump commands
