@newcmd myrpt { ACTION :repeat :optional arrgh }
I see @arrgh@ objects to @ACTION@:
@foreach arg arrgh
@format{#%d = '%s'}{@{arg}}{@{arrgh[@{arg}]}}@
@next arg
@endcmd
@comment  Wow that @format line is ugly
@@
@myrpt Meditate
@myrpt Squanch Xlerb Xylophone Xyzzy
