@newcmd sigdemo { ACTION LUCKY:int :repeat :opt ITEMS }
I see @ITEMS@ object@ifelse{@{ITEMS}}{1}{}{s}@ to @ACTION@@ifx{ITEMS > 0}{:}{.}@
@foreach itm ITEMS
@format{#%d = '%s'}{@{itm}}{@{_ITEMS_VAL_}}@
@next itm
Lucky number: @LUCKY@
---
@endcmd
@;
@sigdemo{Contemplate the nothingness of}{42}
@sigdemo{seek}{3}{The Holy Grail}
@sigdemo{Beat}{7}{It}{The clock}{Your high score}
@sigdemo{Whoops}{BAD INT}{@{expr 1/0}}{Not evaluated}
