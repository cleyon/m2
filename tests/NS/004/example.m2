@define X A very normal @define command
@namespace ns1
@define X This is ns1 symbol 'X'
In @ns@, X=@X@
@namespace ns2
@define X This is ns2 symbol 'X'
In @ns@, X=@X@
@namespace m2
Now in namespace @ns@
ns1::X=@ns1::X@
ns2::X=@ns2::X@
In m2, X=@X@
