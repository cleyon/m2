M2="$1"
file="$2"
TZ=UTC date +"%Y-%m-%dT%H:%M:%S%z" >utc.expected_out &
${M2} ${file}
