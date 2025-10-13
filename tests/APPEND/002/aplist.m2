@list L
@data L
One
Two
Three
@eod
Size is @L@
@append L Four
Size is @L@
@foreach x L
@x@ = @L[@{x}]@
@next x
