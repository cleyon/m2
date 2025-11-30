@newcmd foo{a}{b}
foo: a='@a@', b='@b@'
@endcmd
foo 1 2:
@foo{1}{2}
foo 3 4 5:
@foo{3}{4}{5}
@comment	@foo{6} -> insufficient parameters
@comment	so we'll save it for later
@@
@@
@@
@newcmd bar{a}{b=QUUX}
bar: a='@a@', b='@b@'
@endcmd
bar 1 2:
@bar{1}{2}
bar 3 4 5:
@bar{3}{4}{5}
bar 6:
@bar{6}
Here is foo 6:
@foo{6}
