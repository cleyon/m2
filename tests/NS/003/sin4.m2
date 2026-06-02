@include lib1.lib
@import lib2 lib2.lib
Lib1: sym = @lib1::sym@
Lib2: sym = @lib2::sym@
(unadorned) sym = @sym@
@define sym Maybe_m2_sym
(unadorned) sym = @sym@
m2: sym = @m2::sym@
Lib1: sym = @lib1::sym@
Lib2: sym = @lib2::sym@
(unadorned) sym = @sym@
