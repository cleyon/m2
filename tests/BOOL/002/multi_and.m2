@define TRUE 1
@define FALSE 0
@if TRUE && TRUE && FALSE && @sexpr 1/0@
Took True branch - fail test
@else
Should be False - OK
@fi
