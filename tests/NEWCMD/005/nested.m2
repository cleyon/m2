@newcmd foo{x}
Start foo, x=@x@
@newcmd bar{x}
In bar, x=@x@
@endcmd
@local xyzzy
@define xyzzy @expr x*2@
In foo, bar(@xyzzy@)
@bar{@xyzzy@}
End foo, x=@x@
@endcmd
@@
@foo{3}
