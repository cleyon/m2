@newcmd sigdemo { ACTION LUCKY:int :repeat :opt items }
I see @items@ objects to @ACTION@@ifx{items > 0}{:}{.}@
@foreach this items
@format{#%d = '%s'}{@{this}}{@{items[@{this}]}}@
@next this
Lucky number @LUCKY@
---
@endcmd
@;
@sigdemo{Contemplate the nothingness of}{7}
@sigdemo{Beat}{42}{It}{The clock}{Your high score}
@sigdemo{Whoops}{BAD INT}{@{expr 1/0}}{Not evaluated}
