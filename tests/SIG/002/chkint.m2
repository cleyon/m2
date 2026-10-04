@comment	n must eventually look like an int at run-time
@comment	First two work, last one fails
@newcmd foo { n:int }
In foo, n=@n@
@endcmd
@foo 5
@foo{@mjd 1945 07 16@}
@foo __TIME__
