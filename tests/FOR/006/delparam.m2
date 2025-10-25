@newcmd foo{n}
@for i 1 @{n}
In foo, i=@i@
@next i
@endcmd
@foo{3}
