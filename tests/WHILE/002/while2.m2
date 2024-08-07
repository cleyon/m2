@sequence X create
@while @X@ < 6
Iteration @X@
@if @X@ == 4
Exiting while loop early
@break
@endif
Keep going...
@sequence X next
@endwhile
Out of while loop
