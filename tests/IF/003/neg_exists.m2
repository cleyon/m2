@if !exists(non-existing-file)
GOOD Non-Existing file okay
@else
BAD Non-Existing file failed
@fi
@if !exists(existing-file)
BAD Failed to detect existing file
@else
GOOD Existent file okay
@fi
