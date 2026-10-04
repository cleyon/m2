@newcmd foo {a=AA :optional b=BB :optional c=CC}
a='@a@', b='@b@', c='@c@'
@endcmd
@@ @foo
@foo{1}{2}
@foo{1}
