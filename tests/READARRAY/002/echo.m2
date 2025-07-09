@array mydata
@readarray mydata lines.dat
@foreach line mydata
@line@: @mydata[@{line}]@
@next line
