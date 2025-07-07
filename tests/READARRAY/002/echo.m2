@array data
@readarray data lines.dat
@foreach line data
@line@: @data[@{line}]@
@next line
