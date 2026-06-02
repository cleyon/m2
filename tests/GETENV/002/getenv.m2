FOO is '@ENV::FOO@'
@define __STRICT__[env]  0
BAR is '@ENV::BAR@'
@if defined(ENV::BAZ)
BAZ is '@ENV::BAZ@'
@else
Sorry, BAZ is not defined
@fi
@comment  Expected to fail:
@define __STRICT__[env]  1
@ENV::QUUX@
