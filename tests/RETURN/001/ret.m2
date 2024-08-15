@newcmd foo
Start
@for i 1 5
In loop, i=@i@
@if i > 2
@return
@fi
@next i
End, not reached
@endcmd
Foo
@foo
All done!
