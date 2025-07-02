@# Related to AAA/000/foo, but uses improved syntax
@define foo Arg1='$1' Arg2='$2' Arg3='$3'  narg=$#
@foo "a b" c@
@foo{a b}{c}@
@foo{a b}{c}{}@
