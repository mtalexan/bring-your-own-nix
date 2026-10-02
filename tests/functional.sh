# DevShell entry, real nix-portable, host nix, and nested shebang runs.
# The nested different-devShell chain runs under bwrap and under proot.
# run-tests.sh requires those executables unless --skip-bwrap or --skip-proot is passed.

write_dry_wrapper() {
    cat > "$WORK/dry-wrapper.sh" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BYO_TEST_LOG"
if [ "$1" = "build" ] && [ "$2" = "--dry-run" ]; then
    case "${BYO_TEST_DRY:-built}" in
        fail)
            exit 1
            ;;
        empty)
            exit 0
            ;;
        fetched)
            printf '%s\n' "these 1 paths will be fetched"
            mkdir -p "$(dirname "$BYO_TEST_LOCK")"
            touch "$BYO_TEST_LOCK"
            exit 0
            ;;
        remove-lock)
            printf '%s\n' "these 1 derivations will be built"
            rm -f "$BYO_TEST_LOCK"
            exit 0
            ;;
        build-fail)
            printf '%s\n' "these 1 derivations will be built"
            mkdir -p "$(dirname "$BYO_TEST_LOCK")"
            touch "$BYO_TEST_LOCK"
            exit 0
            ;;
        *)
            printf '%s\n' "these 1 derivations will be built"
            mkdir -p "$(dirname "$BYO_TEST_LOCK")"
            touch "$BYO_TEST_LOCK"
            exit 0
            ;;
    esac
fi
if [ "$1" = "build" ] && [ "$2" = "--no-link" ]; then
    if [ "${BYO_TEST_DRY:-}" = "build-fail" ]; then
        exit 1
    fi
    exit 0
fi
exit 0
EOF
    chmod a+x "$WORK/dry-wrapper.sh"
}

run_enter_captured() {
    "$ENTER" "$@" >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
}

show_tails() {
    _label=$1
    _err=$2
    printf '%s stderr:\n' "$_label"
    tail -n 40 "$_err" 2>/dev/null
}

# One shebang script enters the default devShell and calls another shebang script
# that enters the cowsay devShell, which calls a third that asks for default again.
# NP_RUNTIME forces the nix-portable sandbox used for those entries.
# BYO_TEST_SKIP_BWRAP and BYO_TEST_SKIP_PROOT are set by run-tests.sh.
# Args:
#   1: bwrap or proot
#   2: Absolute path of the store's .nix-portable directory
run_nested_chain_for_runtime() {
    _rt_name=$1
    _rt_dir=$2

    case "$_rt_name" in
        bwrap)
            if [ -n "${BYO_TEST_SKIP_BWRAP:-}" ]; then
                printf 'SKIP bwrap nested different devShell (--skip-bwrap)\n'
                return 0
            fi
            ;;
        proot)
            if [ -n "${BYO_TEST_SKIP_PROOT:-}" ]; then
                printf 'SKIP proot nested different devShell (--skip-proot)\n'
                return 0
            fi
            ;;
    esac

    printf 'RUN %s nested different devShell\n' "$_rt_name"

    export NP_RUNTIME="$_rt_name"
    : > "$BYO_TEST_ENTER_LOG"
    "$ROOT/nested/outer.sh" chain >"$WORK/${_rt_name}-chain.out" 2>"$WORK/${_rt_name}-chain.err"
    _rt_rc=$?
    _rt_enters=$(wc -l < "$BYO_TEST_ENTER_LOG" | tr -d ' ')
    _rt_out=$(cat "$WORK/${_rt_name}-chain.out")
    _rt_log=$(cat "$BYO_TEST_ENTER_LOG")
    _rt_used=$(cat "$_rt_dir/conf/last_runtime" 2>/dev/null || true)
    if [ "$_rt_rc" -eq 0 ] && [ "$_rt_enters" -eq 3 ]; then
        pass "$_rt_name nested different devShell re-enters"
    else
        fail "$_rt_name nested different devShell re-enters" "exit $_rt_rc enters $_rt_enters
$(show_tails "$_rt_name-chain" "$WORK/${_rt_name}-chain.err")
$_rt_log"
    fi
    assert_contains "$_rt_name chain runs default devShell" "$_rt_out" "Hello, world!"
    assert_contains "$_rt_name chain runs cowsay devShell" "$_rt_out" "< hello >"
    assert_contains "$_rt_name chain prints marker" "$_rt_out" "marker"
    assert_contains "$_rt_name chain enters cowsay devShell" "$_rt_log" " cowsay "
    if [ "$_rt_used" = "$_rt_name" ]; then
        pass "$_rt_name runtime selected"
    else
        fail "$_rt_name runtime selected" "last_runtime [${_rt_used}]"
    fi
}

check_serialized_builds() {
    _log=$1
    if awk '
        BEGIN { n = 0 }
        $1 == "BUILD" {
            s[n] = $2
            e[n] = $3
            h[n] = $4
            n++
        }
        END {
            if (n < 2) {
                printf "only %d builds\n", n > "/dev/stderr"
                exit 1
            }
            for (i = 0; i < n; i++) {
                if (h[i] != "lock-held") {
                    printf "build %d lock %s\n", i, h[i] > "/dev/stderr"
                    exit 1
                }
            }
            for (i = 0; i < n; i++) {
                for (j = i + 1; j < n; j++) {
                    if ((s[i] < e[j]) && (s[j] < e[i])) {
                        printf "overlap %d %d\n", i, j > "/dev/stderr"
                        exit 1
                    }
                }
            }
            exit 0
        }
    ' "$_log" 2>"$WORK/serialize.err"; then
        pass "parallel builds serialized"
    else
        fail "parallel builds serialized" "$(cat "$WORK/serialize.err")
$(cat "$_log")"
    fi
}

functional() {
    printf '== functional ==\n'
    system=$(nix_system)

    if [ ! -S /var/run/nscd/socket ]; then
        fail "nscd socket required" "/var/run/nscd/socket is missing, so devShell tests were not run"
        return
    fi
    pass "nscd socket present"

    reset_env
    new_work
    write_dry_wrapper
    export BYO_NIX_WRAPPER=$WORK/dry-wrapper.sh
    export BYO_TEST_LOG=$WORK/dry.log
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/cache
    export BYO_NIX_PORTABLE_STORE=nix-store
    export BYO_TEST_LOCK=$WORK/cache/nix-store.lock
    : > "$BYO_TEST_LOG"

    export BYO_TEST_DRY=empty
    run_enter_captured "$ROOT" "" hello extra-arg
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "empty dry-run enters" "$rc" 0
    assert_contains "empty name dry-run attr" "$log" "build --dry-run $ROOT#devShells.$system.default"
    assert_contains "command args forwarded" "$log" "develop $ROOT --command hello extra-arg"
    assert_not_contains "empty dry-run skips pre-build" "$log" "--no-link"

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=built
    run_enter_captured "$ROOT" cowsay cowsay hello
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "will-be-built pre-builds" "$rc" 0
    assert_contains "named dry-run attr" "$log" "build --dry-run $ROOT#devShells.$system.cowsay"
    assert_contains "named develop arg" "$log" "develop $ROOT#cowsay --command cowsay hello"
    assert_contains "will-be-built runs no-link" "$log" "build --no-link $ROOT#devShells.$system.cowsay"
    if [ -f "$BYO_TEST_LOCK" ]; then
        pass "pre-build saw store lock"
    else
        fail "pre-build saw store lock"
    fi

    : > "$BYO_TEST_LOG"
    rm -f "$BYO_TEST_LOCK"
    export BYO_TEST_DRY=fetched
    run_enter_captured "$ROOT" "" hello
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "will-be-fetched pre-builds" "$rc" 0
    assert_contains "will-be-fetched runs no-link" "$log" "--no-link"

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=fail
    run_enter_captured "$ROOT" "" hello
    rc=$?
    text=$(captured)
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "dry-run failure" "$rc" 1
    assert_contains "dry-run failure message" "$text" "Getting store status"
    assert_not_contains "dry-run failure skips develop" "$log" "develop "

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=remove-lock
    run_enter_captured "$ROOT" "" hello
    rc=$?
    text=$(captured)
    assert_rc "missing store lock" "$rc" 1
    assert_contains "missing store lock message" "$text" "no nix-portable store write lock"

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=build-fail
    run_enter_captured "$ROOT" "" hello
    rc=$?
    text=$(captured)
    assert_rc "pre-build failure" "$rc" 1
    assert_contains "pre-build failure message" "$text" "Pre-building the devShell"

    classic_file=$WORK/shell.nix
    printf '{ }\n' > "$classic_file"
    classic_abs=$(CDPATH= cd "$(dirname "$classic_file")" && pwd)/$(basename "$classic_file")
    classic_dir=$(dirname "$classic_abs")

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=empty
    run_enter_captured "$classic_file" "" hello extra-arg
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "classic blank dry-run enters" "$rc" 0
    assert_contains "classic blank dry-run attr" "$log" "build --dry-run -f $classic_abs inputDerivation"
    assert_contains "classic blank develop" "$log" "develop -f $classic_abs --command hello extra-arg"
    assert_contains "classic blank uses -f" "$log" "-f"
    assert_not_contains "classic blank is not a flake installable" "$log" "#devShells."
    assert_not_contains "classic blank does not develop the directory" "$log" "develop $classic_dir "
    assert_not_contains "classic blank does not build the directory" "$log" "build --dry-run $classic_dir#"

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=built
    run_enter_captured "$classic_file" cowsay cowsay hello
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "classic named dry-run enters" "$rc" 0
    assert_contains "classic named dry-run attr" "$log" "build --dry-run -f $classic_abs cowsay.inputDerivation"
    assert_contains "classic named develop" "$log" "develop -f $classic_abs cowsay --command cowsay hello"
    assert_contains "classic named pre-builds" "$log" "build --no-link -f $classic_abs cowsay.inputDerivation"
    assert_not_contains "classic named is not a flake installable" "$log" "#devShells."

    : > "$BYO_TEST_LOG"
    export BYO_TEST_DRY=fail
    run_enter_captured "$classic_file" "" hello
    rc=$?
    text=$(captured)
    assert_rc "classic dry-run failure" "$rc" 1
    assert_contains "classic dry-run failure requires mkShell" "$text" "pkgs.mkShell"

    : > "$BYO_TEST_LOG"
    export BYO_NIX=/bin/true
    export BYO_TEST_DRY=built
    run_enter_captured "$classic_file" "" hello
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "classic BYO_NIX skips pre-build status" "$rc" 0
    assert_not_contains "classic BYO_NIX skips dry-run" "$log" "--dry-run"
    assert_contains "classic BYO_NIX still develops" "$log" "develop -f $classic_abs --command hello"
    unset BYO_NIX

    : > "$BYO_TEST_LOG"
    export BYO_NIX=/bin/true
    export BYO_TEST_DRY=built
    run_enter_captured "$ROOT" "" hello
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "BYO_NIX skips pre-build status" "$rc" 0
    assert_not_contains "BYO_NIX skips dry-run" "$log" "--dry-run"
    assert_contains "BYO_NIX still develops" "$log" "develop $ROOT --command hello"
    unset BYO_NIX

    : > "$BYO_TEST_LOG"
    export BYO_NO_LOCK=1
    run_enter_captured "$ROOT" "" hello
    rc=$?
    log=$(cat "$BYO_TEST_LOG")
    assert_rc "BYO_NO_LOCK skips pre-build status" "$rc" 0
    assert_not_contains "BYO_NO_LOCK skips dry-run" "$log" "--dry-run"
    assert_contains "BYO_NO_LOCK still develops" "$log" "develop $ROOT --command hello"
    unset BYO_NO_LOCK
    unset BYO_NIX_WRAPPER

    reset_env
    new_work
    export BYO_NIX=/bin/echo
    run_enter_captured "$ROOT" "" hello extra-arg
    rc=$?
    text=$(captured)
    assert_rc "default wrapper status" "$rc" 0
    assert_contains "default wrapper develop" "$text" "develop $ROOT --command hello extra-arg"

    reset_env
    new_work
    export BYO_NIX=/bin/echo
    "$TRAMP" "$ROOT" "" /bin/echo marker >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
    rc=$?
    text=$(captured)
    assert_rc "default enter wrapper status" "$rc" 0
    assert_contains "default enter wrapper reaches byo-nix" "$text" "develop $ROOT --command /bin/echo marker"

    printf 'RUN parallel cold devShells\n'
    reset_env
    new_work
    # A short store path. nix-portable rewrites this path inside its sandbox, and a
    # long workspace path makes those names exceed PATH_MAX.
    cache=/tmp/byo-nix
    if [ -e "$cache" ]; then
        chmod -R u+w "$cache" 2>/dev/null || true
        rm -rf "$cache"
    fi
    mkdir -p "$cache"
    (
        while true; do
            if find "$cache" -path '*/x/*/x/*' -print -quit 2>/dev/null | grep -q .; then
                echo exploded > "$WORK/exploded"
                kill_matching "$cache/nix-store/.nix-portable" "$$"
                exit 0
            fi
            sleep 2
        done
    ) &
    watch_pid=$!
    export BYO_NIX_PORTABLE=$cache/nix-portable
    export BYO_NIX_PORTABLE_STORE=$cache/nix-store
    export BYO_NIX_WRAPPER=$ROOT/lock-wrapper.sh
    export BYO_TEST_LOG=$WORK/lock.log
    export BYO_TEST_LOCK=$cache/nix-store.lock
    export BYO_TEST_REAL_BYO=$BYO
    export BYO_TEST_SLEEP=1
    : > "$BYO_TEST_LOG"
    "$ROOT/nested/outer.sh" >"$WORK/outer.out" 2>"$WORK/outer.err" &
    p_outer=$!
    "$ROOT/nested/cowsay.sh" >"$WORK/cowsay.out" 2>"$WORK/cowsay.err" &
    p_cowsay=$!
    wait "$p_outer"
    r_outer=$?
    wait "$p_cowsay"
    r_cowsay=$?
    if [ "$r_outer" -eq 0 ] && grep -F -q 'Hello, world!' "$WORK/outer.out"; then
        pass "parallel outer hello"
    else
        fail "parallel outer hello" "$(show_tails outer "$WORK/outer.err")"
    fi
    if [ "$r_cowsay" -eq 0 ] && grep -F -q '< hello >' "$WORK/cowsay.out" && grep -F -q 'marker' "$WORK/cowsay.out"; then
        pass "parallel cowsay"
    else
        fail "parallel cowsay" "$(show_tails cowsay "$WORK/cowsay.err")
stdout:
$(cat "$WORK/cowsay.out")"
    fi
    lock_log=$(cat "$BYO_TEST_LOG")
    assert_contains "parallel built default" "$lock_log" "devShells.$system.default"
    assert_contains "parallel built cowsay" "$lock_log" "devShells.$system.cowsay"
    check_serialized_builds "$BYO_TEST_LOG"
    if [ -f "$WORK/exploded" ]; then
        fail "nix-portable store path stayed bounded"
    else
        pass "nix-portable store path stayed bounded"
    fi
    if [ -x "$cache/nix-portable" ] && [ -d "$cache/nix-store" ] && [ -f "$cache/nix-store.lock" ]; then
        pass "absolute portable store created"
    else
        fail "absolute portable store created" "$(ls -la "$cache" 2>&1)"
    fi
    git_minimal=
    for d in "$cache"/nix-store/.nix-portable/nix/store/*-git-minimal-*; do
        if [ -d "$d" ]; then
            git_minimal=$d
        fi
    done
    if [ -n "$git_minimal" ]; then
        pass "cold store installed gitMinimal"
    else
        fail "cold store installed gitMinimal"
    fi
    BYO_SELF_TEST=1 "$BYO" >"$WORK/selftest.out" 2>&1
    assert_contains "real store first-use setup done" "$(cat "$WORK/selftest.out")" "nix-portable store first-use setup done: $cache/nix-store"

    printf 'RUN warm parallel devShells\n'
    : > "$BYO_TEST_LOG"
    unset BYO_TEST_SLEEP
    "$ROOT/nested/outer.sh" >"$WORK/warm-outer.out" 2>"$WORK/warm-outer.err" &
    p_outer=$!
    "$ROOT/nested/cowsay.sh" >"$WORK/warm-cowsay.out" 2>"$WORK/warm-cowsay.err" &
    p_cowsay=$!
    wait "$p_outer"
    r_outer=$?
    wait "$p_cowsay"
    r_cowsay=$?
    warm_log=$(cat "$BYO_TEST_LOG")
    if [ "$r_outer" -eq 0 ] && [ "$r_cowsay" -eq 0 ]; then
        pass "warm parallel status"
    else
        fail "warm parallel status" "$(show_tails warm-outer "$WORK/warm-outer.err")
$(show_tails warm-cowsay "$WORK/warm-cowsay.err")"
    fi
    assert_not_contains "warm parallel does not pre-build" "$warm_log" "build --no-link"

    printf 'RUN reuse and relative store\n'
    unset BYO_NIX_WRAPPER BYO_TEST_SLEEP
    export BYO_NIX_PORTABLE_DL_CMD=/bin/false
    "$BYO" run 'nixpkgs#hello' >"$WORK/reuse.out" 2>"$WORK/reuse.err"
    rc=$?
    if [ "$rc" -eq 0 ] && grep -F -q 'Hello, world!' "$WORK/reuse.out"; then
        pass "reuse portable binary"
    else
        fail "reuse portable binary" "$(show_tails reuse "$WORK/reuse.err")"
    fi

    unset BYO_NIX_PORTABLE BYO_NIX_PORTABLE_STORE BYO_NIX_PORTABLE_DL_CMD
    export BYO_NIX_PORTABLE_CACHE_ROOT=$cache
    export BYO_NIX_PORTABLE=nix-portable
    export BYO_NIX_PORTABLE_STORE=nix-store
    run_enter_captured "$ROOT" "" hello
    rc=$?
    text=$(cat "$BYO_TEST_STDOUT")
    if [ "$rc" -eq 0 ] && printf '%s\n' "$text" | grep -F -q 'Hello, world!'; then
        pass "relative store hello"
    else
        fail "relative store hello" "$(show_tails relative "$BYO_TEST_STDERR")"
    fi
    if [ -f "$cache/nix-store.lock" ]; then
        pass "relative store uses cache root lock"
    else
        fail "relative store uses cache root lock"
    fi

    export BYO_NIX_PORTABLE=$cache/nix-portable
    export BYO_NIX_PORTABLE_STORE=$cache/nix-store
    "$ROOT/hello.nims" token >"$WORK/nim.out" 2>"$WORK/nim.err"
    rc=$?
    nim_out=$(cat "$WORK/nim.out")
    if [ "$rc" -eq 0 ]; then
        assert_contains "nimscript marker" "$nim_out" "byo-nix-nimscript-ok"
        assert_contains "nimscript argument" "$nim_out" "token"
    else
        fail "nimscript" "$(show_tails nim "$WORK/nim.err")"
    fi

    printf 'RUN classic nix-portable shell\n'
    "$ENTER" "$ROOT/classic/shell.nix" "" hello >"$WORK/classic.out" 2>"$WORK/classic.err"
    rc=$?
    if [ "$rc" -eq 0 ] && grep -F -q 'Hello, world!' "$WORK/classic.out"; then
        pass "classic nix-portable hello"
    else
        fail "classic nix-portable hello" "$(show_tails classic "$WORK/classic.err")"
    fi

    printf 'RUN nested shebang stack\n'
    unset BYO_NIX_WRAPPER
    export NIX_DEVSHELL_ENTER_WRAPPER=$ROOT/enter-wrapper.sh
    export BYO_TEST_REAL_ENTER=$ENTER
    export BYO_TEST_ENTER_LOG=$WORK/enter.log

    : > "$BYO_TEST_ENTER_LOG"
    "$ROOT/nested/outer.sh" inner >"$WORK/inner.out" 2>"$WORK/inner.err"
    rc=$?
    inner_out=$(cat "$WORK/inner.out")
    enter_count=$(wc -l < "$BYO_TEST_ENTER_LOG" | tr -d ' ')
    if [ "$rc" -eq 0 ] && [ "$enter_count" -eq 1 ]; then
        pass "inner shebang stays in devShell"
    else
        fail "inner shebang stays in devShell" "exit $rc enters $enter_count
$(show_tails inner "$WORK/inner.err")"
    fi
    hello_count=$(printf '%s\n' "$inner_out" | grep -c 'Hello, world!' || true)
    if [ "$hello_count" -eq 2 ]; then
        pass "inner shebang ran hello"
    else
        fail "inner shebang ran hello" "count $hello_count
$inner_out"
    fi

    : > "$BYO_TEST_ENTER_LOG"
    "$ROOT/nested/outer.sh" chain >"$WORK/chain.out" 2>"$WORK/chain.err"
    rc=$?
    enter_count=$(wc -l < "$BYO_TEST_ENTER_LOG" | tr -d ' ')
    chain_out=$(cat "$WORK/chain.out")
    if [ "$rc" -eq 0 ] && [ "$enter_count" -eq 3 ]; then
        pass "nested different devShell re-enters"
    else
        fail "nested different devShell re-enters" "exit $rc enters $enter_count
$(show_tails chain "$WORK/chain.err")"
    fi
    assert_contains "chain prints marker" "$chain_out" "marker"

    : > "$BYO_TEST_ENTER_LOG"
    "$ROOT/nested/outer.sh" merge >"$WORK/merge.out" 2>"$WORK/merge.err"
    rc=$?
    enter_count=$(wc -l < "$BYO_TEST_ENTER_LOG" | tr -d ' ')
    merge_out=$(cat "$WORK/merge.out")
    if [ "$rc" -eq 0 ] && [ "$enter_count" -eq 2 ]; then
        pass "merge skips compatible devShell"
    else
        fail "merge skips compatible devShell" "exit $rc enters $enter_count
$(show_tails merge "$WORK/merge.err")
$(cat "$BYO_TEST_ENTER_LOG")"
    fi
    assert_contains "merge still prints marker" "$merge_out" "marker"

    # run-tests.sh has already required each executable, unless its skip flag was passed.
    _saved_np_runtime=${NP_RUNTIME-}
    for _runtime in bwrap proot; do
        run_nested_chain_for_runtime "$_runtime" "$cache/nix-store/.nix-portable"
    done
    if [ -n "$_saved_np_runtime" ]; then
        NP_RUNTIME=$_saved_np_runtime
        export NP_RUNTIME
    else
        unset NP_RUNTIME
    fi

    printf 'RUN host nix\n'
    reset_env
    new_work
    host_nix=$(command -v nix) || host_nix=
    if [ -z "$host_nix" ]; then
        fail "host nix present"
    else
        pass "host nix present"
        # --store is required. A multi-user client talks to the system daemon, which
        # ignores NIX_STORE_DIR and would still write /nix/store.
        cat > "$WORK/nix-store-wrapper.sh" << 'EOF'
#!/bin/sh
exec "$BYO_TEST_REAL_NIX" --store "local?root=${BYO_TEST_NIX_ROOT}" "$@"
EOF
        chmod a+x "$WORK/nix-store-wrapper.sh"
        export BYO_TEST_REAL_NIX=$host_nix
        export BYO_TEST_NIX_ROOT=$WORK/nix-root
        export BYO_NIX=$WORK/nix-store-wrapper.sh
        export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/host-cache
        export BYO_NIX_PORTABLE=nix-portable
        export BYO_NIX_PORTABLE_STORE=nix-store
        wrapper_text=$(cat "$WORK/nix-store-wrapper.sh")
        assert_contains "isolating wrapper passes --store" "$wrapper_text" '--store "local?root=${BYO_TEST_NIX_ROOT}"'
        "$BYO" run 'nixpkgs#hello' >"$WORK/host-hello.out" 2>"$WORK/host-hello.err"
        rc=$?
        if [ "$rc" -eq 0 ] && grep -F -q 'Hello, world!' "$WORK/host-hello.out"; then
            pass "host nix hello"
        else
            fail "host nix hello" "$(show_tails host-hello "$WORK/host-hello.err")"
        fi
        "$ENTER" "$ROOT" "" hello >"$WORK/host-enter.out" 2>"$WORK/host-enter.err"
        rc=$?
        if [ "$rc" -eq 0 ] && grep -F -q 'Hello, world!' "$WORK/host-enter.out"; then
            pass "host nix devShell hello"
        else
            fail "host nix devShell hello" "$(show_tails host-enter "$WORK/host-enter.err")"
        fi
        "$ROOT/hello.nims" token >"$WORK/host-nim.out" 2>"$WORK/host-nim.err"
        rc=$?
        host_nim=$(cat "$WORK/host-nim.out")
        if [ "$rc" -eq 0 ]; then
            assert_contains "host nix nimscript marker" "$host_nim" "byo-nix-nimscript-ok"
            assert_contains "host nix nimscript argument" "$host_nim" "token"
        else
            fail "host nix nimscript" "$(show_tails host-nim "$WORK/host-nim.err")"
        fi
        if [ -e "$WORK/host-cache/nix-portable" ] || [ -e "$WORK/host-cache/nix-store" ] || [ -e "$ROOT/.nix-portable/nix-portable" ]; then
            fail "host nix creates no portable store"
        else
            pass "host nix creates no portable store"
        fi
        if find "$WORK/nix-root/nix/store" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
            pass "private store received builds"
        else
            fail "private store received builds" "$WORK/nix-root"
        fi

        printf 'RUN classic file without flakes\n'
        cat > "$WORK/nix-no-flakes.sh" << 'EOF'
#!/bin/sh
exec "$BYO_TEST_REAL_NIX" --store "local?root=${BYO_TEST_NIX_ROOT}" --option experimental-features nix-command --option extra-experimental-features '' "$@"
EOF
        chmod a+x "$WORK/nix-no-flakes.sh"
        noflakes_text=$(cat "$WORK/nix-no-flakes.sh")
        assert_contains "flakes-disabled wrapper passes --store" "$noflakes_text" '--store "local?root=${BYO_TEST_NIX_ROOT}"'
        export BYO_NIX=$WORK/nix-no-flakes.sh
        unset NIX_PATH
        "$ENTER" "$ROOT/classic/pinned.nix" "" hello >"$WORK/noflakes-classic.out" 2>"$WORK/noflakes-classic.err"
        rc=$?
        if [ "$rc" -eq 0 ] && grep -F -q 'Hello, world!' "$WORK/noflakes-classic.out"; then
            pass "classic file without flakes"
        else
            fail "classic file without flakes" "$(show_tails noflakes-classic "$WORK/noflakes-classic.err")"
        fi
        "$BYO" config show experimental-features >"$WORK/noflakes-features.out" 2>"$WORK/noflakes-features.err"
        features=$(cat "$WORK/noflakes-features.out")
        if printf '%s\n' "$features" | grep -F -q flakes; then
            fail "flakes feature is unset" "$features"
        else
            pass "flakes feature is unset"
        fi
        "$ENTER" "$ROOT" "" hello >"$WORK/noflakes-flake.out" 2>"$WORK/noflakes-flake.err"
        rc=$?
        noflakes_flake=$(cat "$WORK/noflakes-flake.out" "$WORK/noflakes-flake.err")
        if [ "$rc" -ne 0 ] && printf '%s\n' "$noflakes_flake" | grep -F -q flakes; then
            pass "flake directory fails without flakes"
        elif [ "$rc" -eq 0 ]; then
            # Some Nix builds still accept a flake directory after the flakes
            # feature is removed from the setting. The unset feature list is
            # the control that the classic enter did not turn flakes on.
            pass "flake directory is accepted without the flakes feature"
        else
            fail "flake directory fails without flakes" "$noflakes_flake"
        fi
    fi

    printf 'RUN broken flake\n'
    reset_env
    export BYO_NIX_PORTABLE=$cache/nix-portable
    export BYO_NIX_PORTABLE_STORE=$cache/nix-store
    "$ENTER" "$ROOT/broken" "" hello >"$WORK/broken.out" 2>"$WORK/broken.err"
    rc=$?
    broken_text=$(cat "$WORK/broken.out" "$WORK/broken.err")
    if [ "$rc" -ne 0 ]; then
        pass "broken flake fails"
    else
        fail "broken flake fails" "$broken_text"
    fi
    if printf '%s\n' "$broken_text" | grep -F -q 'Getting store status' || printf '%s\n' "$broken_text" | grep -F -q 'Pre-building the devShell'; then
        pass "broken flake reports pre-build error"
    else
        fail "broken flake reports pre-build error" "$broken_text"
    fi

    reset_env
    if [ -n "${watch_pid:-}" ]; then
        kill "$watch_pid" 2>/dev/null || true
        wait "$watch_pid" 2>/dev/null || true
    fi
}
