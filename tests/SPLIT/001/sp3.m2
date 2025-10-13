@define __STRICT__[def]  0
@define DATA aaa bbb ccc
@list  MYARRAY
DATA='@DATA@'
@split DATA MYARRAY
@dump
MYARRAY=@MYARRAY@
MYARRAY[1]=@MYARRAY[1]@
MYARRAY[2]=@MYARRAY[2]@
MYARRAY[3]=@MYARRAY[3]@
@define __STRICT__[key] 0
MYARRAY[4]=@MYARRAY[4]@
@define __STRICT__[key] 1
MYARRAY[4]=@MYARRAY[4]@
