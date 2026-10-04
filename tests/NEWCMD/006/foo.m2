@newcmd foo {a :optional b=BB}
a='@a@'  b='@b@'
@endcmd
@sig foo@
@foo{1}{2}
@foo{1}
