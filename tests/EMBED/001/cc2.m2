@newcmd greet{who}
@newcmd private{name}
Hello, @name@
@endcmd
@private{@{who}}
@endcmd
@@
@greet{fancy-world}
@dump commands
