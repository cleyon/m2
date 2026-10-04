@@      If dirname(1) is not in external program list, @xdirname@
@@      will not work.  So fake the result to keep check.sh happy.
@@
@if ! xdirname in __PROG__
@error Apparently /usr/bin/dirname is not present
@fi
@@
@define SYM /dir/subdir/file
@xdirname SYM@
