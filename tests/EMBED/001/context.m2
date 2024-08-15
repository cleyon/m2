@newcmd greet{who}
@newcmd private{name}
Hello, @name@
@endcmd
@private{@{who}}
@endcmd
@@
@greet{fancy-world}
@@ @private should no longer be defined, so next line
@@ will be printed as-is.
@private{basic-world}
