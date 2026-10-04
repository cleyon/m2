@@ While with levels
@define N 4
@while N > 0
@newcmd twice {x}
Twice @x@ = @expr 2*x@
@endcmd
@twice{@{N}}
@decr N
@endwhile
@@  @twice should not be defined here, so should print literally:
@twice{42}
