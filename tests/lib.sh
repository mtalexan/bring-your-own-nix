# Shared helpers for the byo-nix test suite. Sourced by run-tests.sh.

PASSES=0
FAILURES=0

pass() {
    PASSES=$((PASSES + 1))
    printf 'PASS %s\n' "$1"
}

fail() {
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %s\n' "$1" >&2
    if [ -n "${2:-}" ]; then
        printf '%s\n' "$2" >&2
    fi
}

reset_env() {
    unset BYO_NIX BYO_NIX_PORTABLE_URL BYO_NIX_PORTABLE_DL_CMD BYO_FORCE_DOWNLOAD \
        BYO_NIX_PORTABLE_CACHE_ROOT BYO_NIX_PORTABLE BYO_NIX_PORTABLE_STORE \
        BYO_NO_LOCK BYO_ONLY_GET BYO_SELF_TEST BYO_NIX_WRAPPER \
        NIX_DEVSHELL_ENTER_WRAPPER NIX_SHEBANG_DEVSHELL_MERGE __NIX_SHEBANG_STACK \
        NP_GIT NP_LOCATION BYO_NIX_PORTABLE_STORE_LOCKED __BYO_NIX_INSIDE_STORE \
        BYO_TEST_DL_SLEEP BYO_TEST_DL_FAIL BYO_TEST_DRY BYO_TEST_SLEEP \
        BYO_TEST_LOG BYO_TEST_LOCK BYO_TEST_REAL_BYO BYO_TEST_ENTER_LOG \
        BYO_TEST_REAL_ENTER BYO_TEST_STUB BYO_TEST_RECORD \
        NSCD_SOCKET
}

# Stop processes whose command line contains the needle. Reads /proc so the
# suite does not need pkill. The second argument is a pid to leave alone.
kill_matching() {
    _needle=$1
    _spare=${2:-$$}
    for _cmdfile in /proc/[0-9]*/cmdline; do
        [ -r "$_cmdfile" ] || continue
        _pid=${_cmdfile#/proc/}
        _pid=${_pid%/cmdline}
        [ "$_pid" = "$_spare" ] && continue
        _cmd=$(tr '\0' ' ' < "$_cmdfile" 2>/dev/null) || continue
        case "$_cmd" in
            *"$_needle"*)
                kill "$_pid" 2>/dev/null || true
                ;;
        esac
    done
}

new_work() {
    WORK=$(mktemp -d "$ROOT/tmp/case.XXXXXX")
    BYO_TEST_STDOUT=$WORK/stdout
    BYO_TEST_STDERR=$WORK/stderr
    BYO_TEST_RECORD=$WORK/record
    mkdir -p "$BYO_TEST_RECORD"
    : > "$BYO_TEST_STDOUT"
    : > "$BYO_TEST_STDERR"
}

abs_dir() {
    (CDPATH= cd "$1" && pwd)
}

assert_contains() {
    _name=$1
    _haystack=$2
    _needle=$3
    if printf '%s\n' "$_haystack" | grep -F -q -- "$_needle"; then
        pass "$_name"
    else
        fail "$_name" "missing [$_needle] in:
$_haystack"
    fi
}

assert_not_contains() {
    _name=$1
    _haystack=$2
    _needle=$3
    if printf '%s\n' "$_haystack" | grep -F -q -- "$_needle"; then
        fail "$_name" "unexpected [$_needle] in:
$_haystack"
    else
        pass "$_name"
    fi
}

assert_rc() {
    _name=$1
    _got=$2
    _want=$3
    if [ "$_got" -eq "$_want" ]; then
        pass "$_name"
    else
        fail "$_name" "exit $_got, expected $_want
stdout:
$(cat "$BYO_TEST_STDOUT" 2>/dev/null)
stderr:
$(cat "$BYO_TEST_STDERR" 2>/dev/null)"
    fi
}

captured() {
    cat "$BYO_TEST_STDOUT" "$BYO_TEST_STDERR"
}

run_byo() {
    "$BYO" "$@" >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
}

link_tools() {
    _dest=$1
    shift
    mkdir -p "$_dest"
    for _cmd in "$@"; do
        if [ -x "/usr/bin/$_cmd" ]; then
            ln -sf "/usr/bin/$_cmd" "$_dest/$_cmd"
        elif [ -x "/bin/$_cmd" ]; then
            ln -sf "/bin/$_cmd" "$_dest/$_cmd"
        else
            fail "link tool $_cmd" "not found in /usr/bin or /bin"
            return 1
        fi
    done
}

BASE_TOOLS="dirname grep sed mktemp mkdir touch chmod mv rm flock uname cat true false cp sleep"

write_stub() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" << 'EOF'
#!/bin/sh
printf 'ARGS:'
printf ' [%s]' "$@"
printf '\n'
printf 'NP_LOCATION:%s\n' "${NP_LOCATION-}"
printf 'NP_GIT:%s\n' "${NP_GIT-}"
exit 0
EOF
    chmod a+x "$1"
}

# A stand-in for nix-portable's first-use behavior. It carries the fingerprint and gitMinimal
# lines byo-nix reads, and `nix --version` records whether the store lock is held and then
# writes what nix-portable writes on first use.
NP_STUB_FINGERPRINT=0123abcd
NP_STUB_GIT=aaaa-git-minimal-test

write_np_stub() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" << EOF
#!/bin/sh
: << 'NP'
fingerprint="$NP_STUB_FINGERPRINT"
if \$doInstallGit && [ ! -e \$store/$NP_STUB_GIT ] ; then
NP
EOF
    cat >> "$1" << 'EOF'
if [ "$1 $2" = "nix --version" ]; then
    held=lock-not-held
    exec 8>>"${BYO_TEST_LOCK:?}"
    if flock -n 8; then
        flock -u 8
    else
        held=lock-held
    fi
    exec 8>&-
    printf '%s\n' "$held" >> "${BYO_TEST_RECORD:?}/init"
    d="$NP_LOCATION/.nix-portable"
    mkdir -p "$d/conf" "$d/nix/store/aaaa-git-minimal-test"
    printf '%s' 0123abcd > "$d/conf/fingerprint"
    exit 0
fi
printf 'ARGS:'
printf ' [%s]' "$@"
printf '\n'
exit 0
EOF
    chmod a+x "$1"
}

nix_system() {
    case "$(uname -m)" in
        x86_64) printf '%s\n' x86_64-linux ;;
        aarch64) printf '%s\n' aarch64-linux ;;
        armv7l) printf '%s\n' armv7l-linux ;;
        i686) printf '%s\n' i686-linux ;;
        *) printf '%s\n' unknown ;;
    esac
}
