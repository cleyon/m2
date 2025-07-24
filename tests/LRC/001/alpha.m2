@include ../../test-data/alphabet
@for i 0 40
>@center ALPHABET @{i}@<
@next i
@for i 40 0 -1
>@center ALPHABET @{i}@<
@next i
