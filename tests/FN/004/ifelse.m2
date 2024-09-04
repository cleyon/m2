@define A 12
@define B @expr 6*2@
A=@A@, B=@B@
A and B are @ifelse{A == B}{Equal}{Not equal}@!
A and B+1 are @ifelse{A == B+1}{Equal}{Not equal}@!
A+1 and B+1 are @ifelse{A+1 == B+1}{Equal}{Not equal}@!
@incr A
@incr B
A=@A@, B=@B@
A and B are @ifelse{A == B}{Equal}{Not equal}@!
