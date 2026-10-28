@include foo
@if seen(foo)
Seen foo
@else
Not seen foo
@fi
@if seen(bar)
Seen bar
@else
Not seen bar
@fi
@sinclude baz
@if seen(baz)
Seen baz
@else
Not seen baz
@fi
