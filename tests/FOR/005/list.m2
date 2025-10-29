@list L
@define L[1] Foo
@define L[2] Bar
@define L[3] Baz
@foreach I L
I=@I@; @L[@{I}]@
@next I
