@define A A very normal @define command
@namespace ns1
@define A This is ns1 symbol 'A'
In @ns@, A=@A@
@namespace ns2
@define A This is ns2 symbol 'A'
In @ns@, A=@A@
@namespace m2
Now in namespace @ns@
ns1::A=@ns1::A@
ns2::A=@ns2::A@
In m2, A=@A@
