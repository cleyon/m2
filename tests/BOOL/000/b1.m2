@comment	Simple boolean expressions
@define TRUE 1
@if defined(__TIME__) && TRUE
True
@else
False
@fi
@if defined(__TIME__) && FALSE
True
@else
False
@fi
