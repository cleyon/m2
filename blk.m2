@@  Dump user specified blocks.  Enter 0 to quit.
@while 1
@echo
@secho Block number?	
@input BLK
@@  BLK='@BLK@'
@if @len BLK@ == 0
@echo
@break
@fi
@if @BLK@ <= 0
@break
@fi
@dumpall @BLK@
@endwhile
