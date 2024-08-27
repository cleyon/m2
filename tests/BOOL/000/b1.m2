@comment	Simple boolean expressions
@define TRUE 1
@booltest defined(__TIME__) && TRUE
@booltest defined(__TIME__) && FALSE
