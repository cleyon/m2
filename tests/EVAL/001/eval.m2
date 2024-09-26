@newcmd showme
@for i 1 3
And a @i@
@next i
@endcmd
@define myfunc showme
@eval @@{myfunc}
