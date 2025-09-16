@@      If basename(1) is not in external program list, @xbasename@
@@      will not work.  So fake the result to keep check.sh happy.
@@
@if ! basename in __PROG__
file
@exit
@fi
@@
@define SYM /dir/subdir/file
@xbasename SYM@
