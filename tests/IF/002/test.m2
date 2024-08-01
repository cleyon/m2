START
@define FOO 1
@define BAR 1
@define BAZ 0
@if FOO
Foo
@if BAR
Bar
@if BAZ
Baz
@else
! Baz
@endif
@else
! Bar
@if BAZ
Baz
@else
! Baz
@endif
@endif
@else
! Foo
@if BAZ
Baz
@else
! Baz
@endif
@endif
END
