@define foo FOODEF
@longdef bar
BARDEF 1
BARDEF 2
@endlong
@define baz BAZDEF
@dumpdef foo bar baz
