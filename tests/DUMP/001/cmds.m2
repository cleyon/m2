@newcmd FOO
Foo on you!
@endcmd
@newcmd greet{name}
Hello, @name@!
@endcmd
@newcmd pronounce{who}{judgment}
@for i 1 4
That's @judgment@, @who@, @judgment@!
@next i
@endcmd
@greet{Mr Smith}
@pronounce{Trump}{guilty}
@dump commands
