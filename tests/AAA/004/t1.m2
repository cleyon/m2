@list L
@define L[1] 1
@define L[2] 2
@if 1 in L
L[1] = @L[1]@
@fi
@if ! 3 in L
But there is no 3
@fi
