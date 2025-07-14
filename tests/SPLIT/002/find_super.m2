@array PASSWD
@array fld
@sfiledata PASSWD /etc/passwd
@foreach user PASSWD
@define line @PASSWD[@{user}]@
@@ Line = @line@
@split line fld :
@if @fld@ >= 7
@if @fld[3]@ == 0
Found superuser "@fld[1]@", with shell = @fld[7]@
@fi
@fi
@next user
