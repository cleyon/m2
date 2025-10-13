@list sum
@define sum[1] 1
@define sum[2] 2
@define sum[3] 3
@incr sum[2]
sum[2] should now be 3 ...  It is actually @sum[2]@
@dump
