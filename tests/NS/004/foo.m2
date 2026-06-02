@namespace aa
@define foo [aa,foo]
@namespace bb
@define foo [bb,foo]
@include default.lib
AA=@aa::foo@
BB=@bb::foo@
__=@foo@
m2=@m2::foo@
@namespace m2
__=@foo@
