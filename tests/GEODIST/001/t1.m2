PART 1
@@ #     print sprintf("%9.3f", vincenty_distance(    \
@@ #         50.06632, -5.71475,
@@ #         58.64402, -3.07009))
Expect: 969.954166 km
Actual: @geodist 50.06632 -5.71475    58.64402 -3.07009@ km
@@

PART 2
@comment        (50°_03′_58.76″N , 005°_42′_53.10″W)
@comment        (58°_38′_38.48″N , 003°_04′_12.34″W)
@define lat1 @hr  50 03 58.76@
@define lon1 @hr 005 42 53.10@
@define lat2 @hr  58 38 38.48@
@define lon2 @hr 003 04 12.34@
Distance from (@{lat1},@{lon1}) to (@{lat2},@{lon2})
Expect: 969.954114 km
Actual: @geodist @{lat1} @{lon1} @{lat2} @{lon2}@ km
Control:@geodist 50.06632222 5.71475 58.64402222 3.070094444@
    dist from (50.06632222,5.71475) to (58.64402222,3.070094444)
@@

PART 3
Flinders Peak	37°57′03.72030″S, 144°25′29.52440″E
@define lat1 @hr  37 57 03.72030@
@define lon1 @hr 144 25 29.52440@
@@
Buninyong		37°39′10.15610″S, 143°55′35.38390″E
@define lat2 @hr  37 39 10.15610@
@define lon2 @hr 143 55 35.38390@
Distance from (@{lat1},@{lon1}) to (@{lat2},@{lon2})
Expect: 54.972271 km
Actual: @geodist @{lat1} @{lon1} @{lat2} @{lon2}@ km
Control:@geodist 37.95103342  144.4248678    37.65282114  143.9264953@
    dist from (37.95103342,144.4248678) to (37.65282114,143.9264953)
@ignore COMMENT
#     print sprintf("%9.3f", vincenty_distance(                            \
#         (37 + 57/60 + 03.72030/3600), (144 + 25/60 + 29.52440/3600),
#         (37 + 39/60 + 10.15610/3600), (143 + 55/60 + 35.38390/3600)))
# # s     54 972.271 m
# # α1    306°52′05.37″
COMMENT

PART 4
@comment        The expected result of this test is a little suspect
@comment        but I'll accept the difference for now...
@define lat1 55.9521
@define lon1 -3.1965
@define lat2 -41.2866
@define lon2 174.7756
Distance from (@{lat1},@{lon1}) to (@{lat2},@{lon2})
Expect: 18364.45 km
Actual: @geodist @{lat1} @{lon1} @{lat2} @{lon2}@ km
