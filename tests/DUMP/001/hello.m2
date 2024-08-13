@newcmd aaa{What}
You are likely to be eaten by a @What@.
@endcmd
@newcmd hello{name}
Hello, @name@!
@for i 1 3
i=@i@
@if i == 2
Duple
@else
Non
@fi
@aaa{Quux}
@next i
@aaa{grue}
@endcmd
@hello{world}
@dump commands
