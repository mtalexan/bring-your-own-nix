#!/bin/sh
# Fake BYO_NIX_PORTABLE_DL_CMD. Records the URL and destination, then copies the stub.
url=$1
dest=$2
record=${BYO_TEST_RECORD:?}
stub=${BYO_TEST_STUB:?}

mkdir -p "$record"
if [ -f "$record/count" ]; then
    n=$(cat "$record/count")
else
    n=0
fi
n=$((n + 1))
printf '%s\n' "$n" > "$record/count"
printf '%s\n' "$url" > "$record/url"
printf '%s\n' "$dest" > "$record/dest"

if [ -n "${BYO_TEST_DL_SLEEP:-}" ]; then
    sleep "$BYO_TEST_DL_SLEEP"
fi
if [ -n "${BYO_TEST_DL_FAIL:-}" ]; then
    exit 1
fi

cp "$stub" "$dest"
chmod a+x "$dest"
