@newcmd foo {a b c}
a='@a@'  b='@b@'  c='@c@'
@endcmd
@sig foo@
@foo 1 2 3
@foo{1}{2}{3}
