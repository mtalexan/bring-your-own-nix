#!/usr/bin/env -S sh -c 'BYO_NIX_PORTABLE_CACHE_ROOT="$(dirname "$0")/.." "$(dirname "$0")/../../nix-shebang-trampoline" "$(dirname "$0")/.." "" sh "$0" "$@"'
hello
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
case "${1:-}" in
    inner)
        "$here/inner.sh"
        ;;
    chain)
        "$here/cowsay.sh"
        ;;
    merge)
        flake=$(CDPATH= cd "$here/.." && pwd)
        NIX_SHEBANG_DEVSHELL_MERGE=$flake
        export NIX_SHEBANG_DEVSHELL_MERGE
        "$here/cowsay.sh"
        ;;
esac
