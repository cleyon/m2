@@      If no shell, just fake it so the test passes
@if defined(__PROG__[sh])
Shell is @__PROG__[sh]@
@else
Shell is /bin/sh
@fi
@define __PROG__[sh]  /bin/bash
