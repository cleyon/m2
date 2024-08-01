@define FOO 11
@define BAR 22
Start: FOO=@FOO@ and BAR=@BAR@
@if 1
@local BAR
@define FOO 33
@define BAR 44
Inside IF with local, FOO=@FOO@ and BAR=@BAR@
@fi
@@
Middle: FOO=@FOO@ and BAR=@BAR@
@@
@if 1
@local FOO
@define FOO 55
@define BAR 66
Inside IF without local, FOO=@FOO@ and BAR=@BAR@
@fi
@@
End: FOO=@FOO@ and BAR=@BAR@
