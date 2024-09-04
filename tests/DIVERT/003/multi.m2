@sequence h1count
@@
@newcmd h1{h1_arg_txt}
@divert 9
@sequence h1count next
<li><a href="#H1_@h1count@">@h1_arg_txt@</a></li>
@divert 1
<h1 id="H1_@h1count@">@h1_arg_txt@</h1>
@divert
@endcmd
@@
@newcmd p{p_arg_txt}
@divert 1
<p>
@p_arg_txt@
</p>
@divert
@endcmd
@@
@include multi.cmds
@@
<strong>Table of contents:</strong>
<ol>
@undivert 9
</ol>
@undivert 1
