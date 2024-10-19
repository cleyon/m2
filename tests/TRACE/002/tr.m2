@define foo bar
@traceon foo
@define __TRACE__ 0
@tracemode +T
@foo@
@tracemode -T
@foo@
End
