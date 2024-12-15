@define DUMPFILE dumpfile.list
@wrap @syscmd rm -f @DUMPFILE@
@define a aa
@define b bb
@define c cc
@dump symbols @DUMPFILE@
@@ @shell EOD
@@ ls -l @DUMPFILE@
@@ EOD
@syscmd cmp -s @DUMPFILE@ dumpfile.target
@if __SYSVAL__ == 0
Success!
@else
@error Test failed, sorry
@endif
