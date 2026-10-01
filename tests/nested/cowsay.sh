#!/usr/bin/env -S sh -c 'BYO_NIX_PORTABLE_CACHE_ROOT="$(dirname "$0")/.." "$(dirname "$0")/../../nix-shebang-trampoline" "$(dirname "$0")/.." cowsay sh "$0" "$@"'
cowsay hello
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
"$here/again.sh" marker
