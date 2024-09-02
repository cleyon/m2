@sequence count
@newcmd header{text}
@divert 9
@sequence count next
(in stream 9) count=@count@, text=@text@
@divert
@endcmd
@header{First Header}
@header{Second Header}
@header{Third Header}
Table of Contents
@undivert 9
All done
