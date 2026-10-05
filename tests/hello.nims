#!/usr/bin/env -S sh -c 'd=$(dirname "$0");"$d"/../nix-bang "$d" "" nim e --hints:off "$0" "$@"'
echo "byo-nix-nimscript-ok"
echo paramStr(paramCount())
