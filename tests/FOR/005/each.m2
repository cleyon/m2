@@ Keys might be output in arbitrary order but in practice
@@ they seem stable enough for testing
@array A
@define A[foo] Foo
@define A[bar] Bar
@define A[baz] Baz
Items may print in different order - that's okay
@foreach I A
I=@I@; @A[@{I}]@
@next I
