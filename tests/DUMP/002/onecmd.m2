@newcmd one
@define FOO 1
Begin
@case FOO
Preamble
Of clauses may print in different order - that's okay
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
