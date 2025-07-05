@define DATA aaa bbb ccc
@array  ARR
DATA='@DATA@'
@split DATA ARR
@dump
