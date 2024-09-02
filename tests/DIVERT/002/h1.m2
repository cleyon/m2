@sequence h1count
@newcmd h1{h1_text}
@divert 9
@sequence h1count next
<li><a href="#H1_@h1count@">@h1_text@</a></li>
@divert 1
<h1 id="H1_@h1count@">@h1_text@</h1>
@divert
@endcmd
@@
@h1{First header}
@h1{Second header}
@h1{Third header}
<strong>Table of contents</strong>
<ol>
@undivert 9
</ol>
@undivert 1
