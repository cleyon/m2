@newcmd line{n}
| @format %2d @{n}@ | @format %3d @{expr n^2}@ | @format %7.4f @{expr sqrt(n)}@ |
@endcmd
@@
@newcmd table
|  N | N^2 | sqrt(N) |
|----|-----|---------|
@for i 1 5
@line{@{i}}
@next i
@endcmd
@@
@table
