@newcmd foo{a=AA}{b=BB}{c=CC}
a='@a@', b='@b@', c='@c@'
@endcmd
@foo
@foo{1}{2}{3}
@foo{1}{}{3}
@foo{1}{2}{}
@foo{1}{2}
@foo{1}
