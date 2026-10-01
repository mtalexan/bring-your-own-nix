#!/usr/bin/env -S sh -c 'BYO_NIX_PORTABLE_CACHE_ROOT="$(dirname "$0")" "$(dirname "$0")/../nix-shebang-trampoline" "$(dirname "$0")" "" nim e --hints:off "$0" "$@"'
echo "byo-nix-nimscript-ok"
echo paramStr(paramCount())
