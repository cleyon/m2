@define __SECURE__ 2
Secure level is @__SECURE__@
@if exists(/etc/passwd)
Password file exists
@else
Password file does not exist
@fi
@shell EOD
date
EOD
It is @time@
@define __SECURE__ 0
Secure level is @__SECURE__@
All done
