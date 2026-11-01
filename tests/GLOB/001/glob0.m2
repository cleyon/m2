@list foo
@glob foo X*
@foreach f foo
@include @foo[@{f}]@
@next f
