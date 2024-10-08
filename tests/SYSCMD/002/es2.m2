@esyscmd /usr/bin/false
$?=@__SYSVAL__@
@if __SYSVAL__ == 1
Very good!
@else
Supposed to be 1, not @__SYSVAL__@ !
@fi
