@newcmd one
@define FOO 1
Begin
@case FOO
Preamble
@of 1
One
@of 2
Two
@of 3
Three
@otherwise
Not matched
@endcase
End
@endcmd
@one
@dump commands