@define X 111
@newcmd leaving
We are leaving now, X=@X@
@endcmd
@newcmd bye
That's all folks!
@endcmd
@wrap @leaving
@wrap @bye
@divert 3
In stream 3, X is @X@
@divert
Start of file
@define X 222
In main, X=@X@
@divert 1
In stream 1, X is @X@
@divert
@define X 333
End of file
