@comment	Simple boolean expressions
@define TRUE 1
@if defined(XLERB) && TRUE
True
@else
False
@fi
@if defined(XLERB) && FALSE
True
@else
False
@fi
