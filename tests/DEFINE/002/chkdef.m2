@define foo junk
@define x junk
@@
@list PPP
@data PPP
Line 1
@eod
@@
@newcmd doit{foo}
Inside doit, foo=@foo@
@endcmd
@@
@; @traceon
@; @tracemode +sl
@foreach x PPP
@define foo @PPP[@{x}]@
Globally foo=@foo@
@doit{@{foo}}
@next x
