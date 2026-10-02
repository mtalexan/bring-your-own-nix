#!/usr/bin/env -S sh -c 'd=$(dirname "$0");"$d"/../../nix-bang "$d"/.. "" sh "$0" "$@"'
# Keep this shebang within 127 characters. Ubuntu's proot 5.1.0 truncates a
# longer line, and env -S then exits 125 with "no terminating quote".
hello
