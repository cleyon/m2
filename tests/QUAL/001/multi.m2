@namespace foo
@define x1 foo-x1
@namespace bar
@define x1 bar-x1
@namespace foo
@x1@ - @bar::x1@
@namespace bar
@foo::x1@ - @x1@
@namespace m2
@foo::x1@ - @bar::x1@
@x1@
