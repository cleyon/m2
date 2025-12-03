@newcmd foo{a}{b}
@local product
@define product @expr a*b@
Product is @product@
@return @product@
@endcmd
@foo{6}{8}
Foo says "@foo{3}{5}@"
