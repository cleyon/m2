@comment	Check :rest in signatures
@newcmd rest1 { r:rest }
In rest1, r='@r@'
@endcmd
@rest1{This is the first argument}
@rest1 I am large, I contain multitudes
@rest1{first}{second}
