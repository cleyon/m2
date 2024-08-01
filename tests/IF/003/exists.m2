@if exists(existing-file)
Existing file okay
@else
Existing file failed
@fi
@if exists(non-existing-file)
Failed to detect non-existent file
@else
Non-existent file okay
@fi
