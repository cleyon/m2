@newcmd foo
@local bar
@define bar 3
Inside, bar=@bar@
@endcmd
@foo
Outside, bar=@bar@
