@define DATA aaa bbb ccc
@array  MYARRAY
DATA='@DATA@'
@split DATA MYARRAY
@dump
