@@      If dirname(1) is not in external program list, @xdirname@
@@      will not work.  So fake the result to keep check.sh happy.
@@
@if ! dirname in __PROG__
/dir/subdir
@exit
@fi
@@
@define SYM /dir/subdir/file
@xdirname SYM@
