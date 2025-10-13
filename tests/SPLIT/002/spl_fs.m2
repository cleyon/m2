@list ARR
@define DATA One:Two:Three:Four:Five
@split DATA ARR
@foreach i ARR
@i@ = @ARR[@{i}]@
@next i
@split DATA ARR :
@foreach i ARR
@i@ = @ARR[@{i}]@
@next i
