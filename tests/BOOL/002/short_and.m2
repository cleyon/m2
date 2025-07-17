@define TRUE 12
@define FALSE 0
@if FALSE && @sexpr 1/0@
Took True branch OK
@else
Took False branch OK
@fi
@if TRUE && @sexpr 1/0@
Took True branch OK
@else
Took False branch OK
@fi
