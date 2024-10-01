@define OUTFILE  simple.data
@wrap @syscmd rm -f @OUTFILE@
@divert 2
This is the data
And there are multiple lines!
@divert
@undivert 2 @OUTFILE@
@@ @shell EOD
@@ ls -l @OUTFILE@
@@ EOD
@syscmd cmp -s @OUTFILE@ simple.target
@if __SYSVAL__ == 0
Success!
@else
@error Test failed, sorry
@fi
