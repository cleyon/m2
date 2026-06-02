@newcmd test
Just testing
@endcmd
@newcmd foo::one
Foo 1
@endcmd
@newcmd foo::two
Foo 2
@endcmd
@newcmd bar::one
Bar 1
@endcmd
@newcmd bar::two
Bar 2
@endcmd
@foo::one
@foo::two
@bar::one
@bar::two
@namespace foo
@one
@two
@namespace bar
@one
@two
@namespace m2
@test
