@define __INPUT__ Foo
@for I 1 2
@local __INPUT__
@define __INPUT__ Bar
@next I
Afterward, __INPUT__ is @__INPUT__@
