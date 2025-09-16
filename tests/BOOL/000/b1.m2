@comment	Simple boolean expressions
@define TRUE 1
@if defined(__M2_UUID__) && TRUE
True
@else
False
@fi
@if defined(__M2_UUID__) && FALSE
True
@else
False
@fi
