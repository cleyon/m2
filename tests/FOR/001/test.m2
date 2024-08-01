@for I 1 3
@for J 1 3
@if I == J
@define DIAG 1
@else
@define DIAG 0
@endif
LET M7[@I@,@J@] = @DIAG@
@next J
@next I
