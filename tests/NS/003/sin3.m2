@import church church.lib
@include math.lib
Mathematical: sin=@math::sin@
Ecclesiastical: sin=@church::sin@
(unadorned): sin=@sin@
@define sin This is m2..sin
@sin@
@church::sin@
@math::sin@
@sin@
