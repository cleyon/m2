@newcmd FOO
Foo on you!
@endcmd
@newcmd hello{name}
Hello, @name@!
@endcmd
@newcmd guilty{who}
@for i 1 4
That's guilty, @who@, guilty!
@next i
@endcmd
@dump commands
