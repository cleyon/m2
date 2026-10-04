@define __SEC_LEVEL__ 2
Secure level is @__SEC_LEVEL__@
@if exists(/etc/passwd)
Password file exists
@else
Password file does not exist
@fi
@shell EOD
date
EOD
@define __SEC_LEVEL__ 0
Secure level is @__SEC_LEVEL__@
All done
