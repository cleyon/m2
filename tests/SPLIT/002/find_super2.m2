Some BSD-based systems might find a superuser named "toor" - that's okay
@newcmd check_backdoor{line}
@list fld
@split line fld :
@if @fld@ != 7
@return
@fi
@if @fld[3]@ == 0
Found superuser "@fld[1]@", with shell = @fld[7]@
@fi
@endcmd
@@
@list PASSWD
@sfiledata PASSWD /etc/passwd
@foreach user PASSWD
@define line @PASSWD[@{user}]@
@check_backdoor{@{line}}
@next user
