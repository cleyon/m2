@define __TRACE__ 1
@tracemode +ifl
Start
@include incl1
Again...
@tracemode -i
@include incl1
This time for real!
@tracemode +i
@include incl1
Now Off
@define __TRACE__ 0
@include incl1
Done
