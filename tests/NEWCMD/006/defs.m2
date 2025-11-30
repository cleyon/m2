@newcmd foo{a}{x=BAR}
a='@a@', x='@x@'
@endcmd
@foo{1}{2}
@foo{3}{}
@foo{4}
@foo
