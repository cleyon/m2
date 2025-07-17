@define TRUE 1
@define FALSE 0
@if FALSE || FALSE || TRUE || @sexpr 1/0@
Should be True - OK
@else
Took False branch - fail test
@fi
