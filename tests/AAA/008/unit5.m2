@include unit4.include
@define name @lastname@, @firstname@
@define xdate @month@/@day@/@year@
NAME:         @name@
DATE:         @xdate@
SEMESTER:     @semester@
LIST OF COURSES:
@for i 1 3
         @i@.   @{courses[@{i}]}
@next i
