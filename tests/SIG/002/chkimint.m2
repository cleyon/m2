@comment	n must immediately look like an int at parse-time.
@comment	First one works, second one fails, third would have also
@newcmd ifoo { n:int! }
In ifoo, n=@n@
@endcmd
@ifoo 5
@ifoo @__TIME__@
@ifoo __TIME__
