@define __SECURE__ 1
Secure level is @__SECURE__@
@if exists(/etc/passwd)
Password file exists
@else
Password file does not exist
@fi
@shell EOD
date
EOD
@define __SECURE__ 0
Secure level is @__SECURE__@
All done
