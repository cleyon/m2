Begin
@define FOO 2
@define BAR 3
@@
@case FOO
Pre-Foo
@of 1
Foo One
@@
@case BAR
Pre-Bar:Foo 1
@of 1
Foo 1 Bar One
@of 2
Foo 1 Bar Two
@of 3
Foo 1 Bar Three
@esac	@srem BAR@
@@
@of 2
Foo Two
@@
@case BAR
Pre-Bar:Foo 2
@of 1
Foo 2 Bar One
@of 2
Foo 2 Bar Two
@of 3
Foo 2 Bar Three
@esac	@srem BAR@
@@
@of 3
Foo Three
@@
@case BAR
Pre-Bar:Foo 3
@of 1
Foo 3 Bar One
@of 2
Foo 3 Bar Two
@of 3
Foo 3 Bar Three
@esac	@srem BAR@
@@
@endcase
End
