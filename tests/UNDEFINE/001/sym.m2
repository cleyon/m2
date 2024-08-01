@define foo 10
foo is @foo@
@undefine foo
@ifdef foo
BAD - foo is still around
@else
GOOD - foo is gone
@fi
