@list foo
@glob foo b* f*
@foreach f foo
@include @foo[@{f}]@
@next f
