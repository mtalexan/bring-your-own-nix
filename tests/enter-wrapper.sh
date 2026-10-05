#!/bin/sh
# NIX_DEVSHELL_ENTER_WRAPPER that counts entries, then runs the real nix-devshell-enter.
printf '%s\n' "$*" >> "${BYO_TEST_ENTER_LOG:?}"
exec "${BYO_TEST_REAL_ENTER:?}" "$@"
