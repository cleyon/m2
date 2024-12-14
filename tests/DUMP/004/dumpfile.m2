@define DMPFILE dumpfile.out
@wrap @syscmd rm -f @DMPFILE@
@define a aa
@define b bb
@define c cc
@dump symbols @DMPFILE@
@@ @shell EOD
@@ ls -l @DMPFILE@
@@ EOD
@syscmd cmp -s @DMPFILE@ dumpfile.target
@if __SYSVAL__ == 0
Success!
@else
@error Test failed, sorry
@endif
