@@      If basename(1) is not in external program list, @xbasename@
@@      will not work.  So fake the result to keep check.sh happy.
@@
@if ! xbasename in __PROG__
@error Apparently /usr/bin/basename is not present
@fi
@@
@define SYM /dir/subdir/file
@xbasename SYM@
