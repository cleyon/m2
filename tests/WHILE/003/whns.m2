@@ While with Namespaces
@define N 4
@while N > 0
@newcmd haha{x}
Twice @x@ is equal to @expr 2*x@
@endcmd
@haha{@{N}}
@decr N
@endwhile
@@
@@ @haha{42}
@haha{42}
