@comment        @line{n} produces one data line of the table
@newcmd line{n}
| @format %2d @{n}@ @\
| @format %3d @{expr n^2}@ @\
| @format %7.4f @{expr sqrt(n)}@ |
@endcmd
@;
@comment        @table prints the entire table
@newcmd table{n}
This table will have @n@ lines:
|  N | N^2 | sqrt(N) |
|----|-----|---------|
@for i 1 @n@
@line{@{i}}
@next i
@endcmd
@;
@table{9}
