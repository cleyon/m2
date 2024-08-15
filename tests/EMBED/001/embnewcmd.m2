@newcmd quux
Quux!
@endcmd
@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@newcmd foo{x}
@newcmd bar
Bar: x=@x@
@endcmd
Foo: x=@x@
@quux
@bar
@endcmd
@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@foo{A}
