@list List
@data List
12
22
32
42
52
@eod
@comment	val shows we don't need @List[@{k}]@ anymore
@foreach k List
k=@k@, val=@_List_VAL_@
@next k
