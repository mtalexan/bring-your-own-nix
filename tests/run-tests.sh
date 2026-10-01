#!/bin/sh
# Branch coverage for bring-your-own-nix.
# The portable devShell section downloads nix-portable and nixpkgs and can take a long time.
# It needs /var/run/nscd/socket and network access.

SOURCE=$(CDPATH= cd "$(dirname "$0")" && pwd)
BYO_DIR=$(CDPATH= cd "$SOURCE/.." && pwd)
BYO=$BYO_DIR/byo-nix
ENTER=$BYO_DIR/nix-flake-enter
TRAMP=$BYO_DIR/nix-shebang-trampoline

# Nix treats a flake inside a Git work tree as a Git input. It then ignores
# untracked files, and the Git shipped with nix-portable cannot read this
# checkout's index. Stage the suite outside the work tree. Shebangs look for
# nix-shebang-trampoline two directories above the nested scripts.
STAGE=$(mktemp -d /tmp/byo-nix-stage.XXXXXX)
cleanup_stage() {
    rm -rf "$STAGE"
}
trap cleanup_stage EXIT INT TERM
mkdir -p "$STAGE/tests"
cp -a "$SOURCE/." "$STAGE/tests/"
rm -rf "$STAGE/tests/tmp"
ln -s "$BYO" "$STAGE/byo-nix"
ln -s "$ENTER" "$STAGE/nix-flake-enter"
ln -s "$TRAMP" "$STAGE/nix-shebang-trampoline"
ROOT=$STAGE/tests

export ROOT BYO_DIR BYO ENTER TRAMP
OLD_PATH=$PATH
export OLD_PATH

rm -rf "$ROOT/tmp"
mkdir -p "$ROOT/tmp"

# shellcheck disable=SC1091
. "$ROOT/lib.sh"
# shellcheck disable=SC1091
. "$ROOT/bootstrap-env.sh"
# shellcheck disable=SC1091
. "$ROOT/errors.sh"
# shellcheck disable=SC1091
. "$ROOT/functional.sh"

bootstrap_env
errors_and_stack
functional

printf '%s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
