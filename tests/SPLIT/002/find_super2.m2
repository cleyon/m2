@newcmd check_backdoor{line}
@array fld
@split line fld :
@if @fld@ != 7
@return
@fi
@if @fld[3]@ == 0
Found superuser "@fld[1]@", with shell = @fld[7]@
@fi
@endcmd
@@
@array PASSWD
@sfiledata PASSWD /etc/passwd
@foreach user PASSWD
@define line @PASSWD[@{user}]@
@check_backdoor{@{line}}
@next user
