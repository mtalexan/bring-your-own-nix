#!/usr/bin/env -S sh -c 'BYO_NIX_PORTABLE_CACHE_ROOT="$(dirname "$0")/.." "$(dirname "$0")/../../nix-shebang-trampoline" "$(dirname "$0")/.." "" /bin/echo "$0" "$@"'
# Interpreter is /bin/echo. This body is not executed.
