@newcmd double{x}
Double @x@ is @expr 2*x@
@endcmd
@for i 1 3
@double{@{i}}
@next i
