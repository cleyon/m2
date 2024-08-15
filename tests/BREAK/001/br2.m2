@for i 1 5
I=@i@
@if i > 3
@break
@fi
@for j 1 3
J=@j@
@next j
@next i
