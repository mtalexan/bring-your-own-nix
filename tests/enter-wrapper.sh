#!/bin/sh
# NIX_FLAKE_ENTER_WRAPPER that counts entries, then runs the real nix-flake-enter.
printf '%s\n' "$*" >> "${BYO_TEST_ENTER_LOG:?}"
exec "${BYO_TEST_REAL_ENTER:?}" "$@"
