#!/bin/sh
# Branch coverage for bring-your-own-nix.
# The portable devShell section downloads nix-portable and nixpkgs and can take a long time.
# It needs /var/run/nscd/socket and network access.
#
# bwrap and proot must be on PATH. The nested devShell tests run under each of
# them, and a missing executable is a setup failure reported before any test runs.
# Flags:
#   --skip-bwrap   Do not require bwrap, and do not run the bwrap nested devShell tests.
#   --skip-proot   Do not require proot, and do not run the proot nested devShell tests.

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

SKIP_BWRAP=
SKIP_PROOT=
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-bwrap)
            SKIP_BWRAP=1
            ;;
        --skip-proot)
            SKIP_PROOT=1
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            printf 'Usage: %s [--skip-bwrap] [--skip-proot]\n' "$0" >&2
            exit 1
            ;;
    esac
    shift
done

# A missing or unusable sandbox tool has to fail here. Later nested-devShell
# failures are about the scripts under test, not about the machine setup.
require_runtime() {
    _cmd=$1
    _package=$2
    _skip_flag=$3
    _skipped=$4
    shift 4
    if [ -n "$_skipped" ]; then
        return 0
    fi
    if ! command -v "$_cmd" >/dev/null 2>&1; then
        cat >&2 <<EOF
ERROR: ${_cmd} was not found.
This is a test environment setup problem. The ${_cmd} tests were not run.
Install the ${_package} package, or pass ${_skip_flag}.
EOF
        exit 1
    fi
    _probe_out=$(mktemp)
    if ! "$@" >"$_probe_out" 2>&1; then
        cat >&2 <<EOF
ERROR: ${_cmd} failed to start.
This is a test environment setup problem. The ${_cmd} tests were not run.
EOF
        cat "$_probe_out" >&2
        rm -f "$_probe_out"
        exit 1
    fi
    rm -f "$_probe_out"
}

require_runtime bwrap bubblewrap --skip-bwrap "$SKIP_BWRAP" bwrap --bind / / -- /bin/true
require_runtime proot proot --skip-proot "$SKIP_PROOT" proot -r / /bin/true

if [ -n "$SKIP_BWRAP" ]; then
    BYO_TEST_SKIP_BWRAP=1
    export BYO_TEST_SKIP_BWRAP
else
    NP_BWRAP=$(command -v bwrap)
    export NP_BWRAP
fi
if [ -n "$SKIP_PROOT" ]; then
    BYO_TEST_SKIP_PROOT=1
    export BYO_TEST_SKIP_PROOT
else
    NP_PROOT=$(command -v proot)
    export NP_PROOT
fi

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
