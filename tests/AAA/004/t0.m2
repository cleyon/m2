@array A
@define A[foo] 1
@define A[bar] 2
@if foo in A
A[foo] = @A[foo]@
@fi
@if ! quux in A
But there is no quux
@fi
