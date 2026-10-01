#!/bin/sh
# BYO_NIX_WRAPPER used while two devShell builds share one store.
# For build --no-link, record whether the store lock is already held and how long the build ran.
printf '%s\n' "$*" >> "${BYO_TEST_LOG:?}"

if [ "$1" = "build" ] && [ "$2" = "--no-link" ]; then
    start=$(date +%s%N)
    held=lock-not-held
    exec 8>>"${BYO_TEST_LOCK:?}"
    if flock -n 8; then
        flock -u 8
    else
        held=lock-held
    fi
    exec 8>&-
    if [ -n "${BYO_TEST_SLEEP:-}" ]; then
        sleep "$BYO_TEST_SLEEP"
    fi
    "${BYO_TEST_REAL_BYO:?}" "$@"
    rc=$?
    end=$(date +%s%N)
    printf 'BUILD %s %s %s %s\n' "$start" "$end" "$held" "$3" >> "$BYO_TEST_LOG"
    exit "$rc"
fi

exec "${BYO_TEST_REAL_BYO:?}" "$@"
