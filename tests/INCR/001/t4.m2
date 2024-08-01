@comment Error if symbol is not an array but sym has array[key] syntax
@define FOO 3
@incr FOO[junk]
