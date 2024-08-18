#!/bin/sh

grep '[^_]error(' m2 | sed 's/^ *//' | sed 's/^if (.*) *error(/error(/' | sed 's/sprintf(//' | sed 's/("([a-zA-Z_]*) /("/' | sort | uniq
