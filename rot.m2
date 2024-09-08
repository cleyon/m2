@while 1
@secho Enter some text to rotate: 
@input
@if @len __INPUT__@ == 0
@echo
@break
@fi
Rot13: @rot13 __INPUT__@
@endwhile
