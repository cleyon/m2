@define __SECURITY__ 2
Secure level is @__SECURITY__@
@if exists(/etc/passwd)
Password file exists
@else
Password file does not exist
@fi
@shell EOD
date
EOD
@define __SECURITY__ 0
Secure level is @__SECURITY__@
All done
