# byo-nix environment and bootstrap branches. No real nix-portable download.

bootstrap_env() {
    printf '== bootstrap environment ==\n'
    FAKE_DL=$ROOT/fake-dl.sh

    reset_env
    new_work
    default_portable=$BYO_DIR/.nix-portable/nix-portable
    if [ -e "$default_portable" ]; then
        default_before=$(stat -c %Y "$default_portable")
    else
        default_before=absent
    fi
    export BYO_SELF_TEST=1
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "self-test defaults exit 1" "$rc" 1
    assert_contains "default portable path" "$text" "$BYO_DIR/.nix-portable/nix-portable"
    if [ -d "$BYO_DIR/.nix-portable/nix-store" ]; then
        assert_contains "default store path" "$text" "nix-portable store present at $BYO_DIR/.nix-portable/nix-store"
    else
        assert_contains "default store path" "$text" "nix-portable store not present at $BYO_DIR/.nix-portable/nix-store"
    fi
    if [ ! -e "$default_portable" ]; then
        assert_contains "default URL" "$text" "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m)"
        assert_contains "default curl command" "$text" "curl -sSLf -o"
    fi
    if [ "$default_before" = absent ]; then
        if [ -e "$default_portable" ]; then
            fail "self-test creates nothing" "$default_portable appeared"
        else
            pass "self-test creates nothing"
        fi
    else
        if [ "$(stat -c %Y "$default_portable")" = "$default_before" ]; then
            pass "self-test creates nothing"
        else
            fail "self-test creates nothing" "default portable mtime changed"
        fi
    fi

    reset_env
    new_work
    export BYO_SELF_TEST=1
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/empty-root
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "default URL self-test exit 1" "$rc" 1
    assert_contains "default URL" "$text" "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-$(uname -m)"
    assert_contains "default curl command" "$text" "curl -sSLf -o"
    if [ -e "$WORK/empty-root" ]; then
        fail "default URL self-test creates nothing"
    else
        pass "default URL self-test creates nothing"
    fi

    reset_env
    new_work
    write_stub "$WORK/stub"
    export BYO_TEST_STUB=$WORK/stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE_URL=https://example.test/nix-portable-custom
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/root
    export BYO_NIX_PORTABLE=rel/nix-portable
    export BYO_NIX_PORTABLE_STORE=rel/nix-store
    export BYO_ONLY_GET=1
    run_byo
    rc=$?
    assert_rc "relative cache root download" "$rc" 0
    if [ -x "$WORK/root/rel/nix-portable" ]; then
        pass "relative portable path created"
    else
        fail "relative portable path created"
    fi
    if [ -d "$WORK/root/rel/nix-store" ] || [ -e "$WORK/root/rel/nix-store.lock" ]; then
        fail "only-get skips store" "store artifacts appeared"
    else
        pass "only-get skips store"
    fi
    assert_contains "custom URL recorded" "$(cat "$BYO_TEST_RECORD/url")" "https://example.test/nix-portable-custom"
    dest_recorded=$(cat "$BYO_TEST_RECORD/dest")
    case "$dest_recorded" in
        /*) pass "downloader got an absolute destination" ;;
        *) fail "downloader got an absolute destination" "$dest_recorded" ;;
    esac

    sum_before=$(cksum "$WORK/root/rel/nix-portable")
    export BYO_TEST_DL_FAIL=1
    run_byo
    rc=$?
    unset BYO_TEST_DL_FAIL
    assert_rc "second only-get reuses binary" "$rc" 0
    if [ "$(cksum "$WORK/root/rel/nix-portable")" = "$sum_before" ] && [ "$(cat "$BYO_TEST_RECORD/count")" = 1 ]; then
        pass "second only-get did not download"
    else
        fail "second only-get did not download" "count=$(cat "$BYO_TEST_RECORD/count")"
    fi

    export BYO_FORCE_DOWNLOAD=1
    unset BYO_TEST_DL_FAIL
    run_byo
    rc=$?
    unset BYO_FORCE_DOWNLOAD
    assert_rc "force download" "$rc" 0
    if [ "$(cat "$BYO_TEST_RECORD/count")" = 2 ]; then
        pass "force download called downloader"
    else
        fail "force download called downloader" "count=$(cat "$BYO_TEST_RECORD/count")"
    fi

    reset_env
    new_work
    write_stub "$WORK/stub"
    export BYO_TEST_STUB=$WORK/stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE=$WORK/custom/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/custom/nix-store///
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/unused-root
    export BYO_ONLY_GET=1
    run_byo
    rc=$?
    assert_rc "absolute portable download" "$rc" 0
    if [ -x "$WORK/custom/nix-portable" ]; then
        pass "absolute portable path"
    else
        fail "absolute portable path"
    fi
    if [ -e "$WORK/unused-root/.nix-portable/nix-portable" ] || [ -d "$WORK/unused-root" ]; then
        fail "absolute path ignores cache root" "cache root was used"
    else
        pass "absolute path ignores cache root"
    fi
    export BYO_TEST_DL_FAIL=1
    run_byo
    rc=$?
    unset BYO_TEST_DL_FAIL
    assert_rc "custom location already populated" "$rc" 0
    if [ "$(cat "$BYO_TEST_RECORD/count")" = 1 ]; then
        pass "populated custom location skipped download"
    else
        fail "populated custom location skipped download" "count=$(cat "$BYO_TEST_RECORD/count")"
    fi

    reset_env
    new_work
    write_stub "$WORK/stub"
    cp "$WORK/stub" "$WORK/plain-stub"
    export BYO_TEST_STUB=$WORK/plain-stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store///
    run_byo extra-arg
    rc=$?
    text=$(captured)
    assert_rc "stub exec" "$rc" 0
    assert_contains "arguments follow nix" "$text" "ARGS: [nix] [extra-arg]"
    assert_contains "NP_LOCATION keeps caller spelling" "$text" "NP_LOCATION:$WORK/store/nix-store///"
    assert_contains "NP_GIT is not set" "$text" "NP_GIT:"
    assert_not_contains "NP_GIT is not a host path" "$text" "NP_GIT:/"
    if [ -f "$WORK/store/nix-store.lock" ]; then
        pass "trailing slash stripped from store lock"
    else
        fail "trailing slash stripped from store lock"
    fi
    if [ -e "$WORK/store/nix-store/.lock" ]; then
        fail "no lock inside store path"
    else
        pass "no lock inside store path"
    fi
    if [ -f "$WORK/bin/nix-portable.lock" ]; then
        pass "portable lock created"
    else
        fail "portable lock created"
    fi

    reset_env
    new_work
    write_stub "$WORK/stub"
    export BYO_TEST_STUB=$WORK/stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    export BYO_NO_LOCK=1
    run_byo
    rc=$?
    assert_rc "no-lock exec" "$rc" 0
    if [ -e "$WORK/bin/nix-portable.lock" ] || [ -e "$WORK/store/nix-store.lock" ]; then
        fail "no-lock creates no lockfiles"
    else
        pass "no-lock creates no lockfiles"
    fi

    reset_env
    new_work
    write_np_stub "$WORK/bin/nix-portable"
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    export BYO_TEST_LOCK=$WORK/store/nix-store.lock
    export BYO_SELF_TEST=1
    run_byo
    text=$(captured)
    assert_contains "self-test new store needs setup" "$text" "nix-portable store needs first-use setup: $WORK/store/nix-store"
    unset BYO_SELF_TEST
    run_byo extra-arg
    rc=$?
    text=$(captured)
    assert_rc "first use exec" "$rc" 0
    assert_contains "first use runs requested command" "$text" "ARGS: [nix] [extra-arg]"
    if [ "$(cat "$BYO_TEST_RECORD/init" 2>/dev/null)" = "lock-held" ]; then
        pass "first-use setup runs under store lock"
    else
        fail "first-use setup runs under store lock" "$(cat "$BYO_TEST_RECORD/init" 2>&1)"
    fi
    run_byo extra-arg
    rc=$?
    assert_rc "second use exec" "$rc" 0
    if [ "$(wc -l < "$BYO_TEST_RECORD/init" | tr -d ' ')" = 1 ]; then
        pass "second use skips first-use setup"
    else
        fail "second use skips first-use setup" "$(cat "$BYO_TEST_RECORD/init")"
    fi
    export BYO_SELF_TEST=1
    run_byo
    text=$(captured)
    assert_contains "self-test set-up store" "$text" "nix-portable store first-use setup done: $WORK/store/nix-store"
    printf '%s' other > "$WORK/store/nix-store/.nix-portable/conf/fingerprint"
    run_byo
    text=$(captured)
    assert_contains "self-test other nix-portable needs setup" "$text" "nix-portable store needs first-use setup"
    printf '%s' "$NP_STUB_FINGERPRINT" > "$WORK/store/nix-store/.nix-portable/conf/fingerprint"
    rm -rf "$WORK/store/nix-store/.nix-portable/nix/store/$NP_STUB_GIT"
    run_byo
    text=$(captured)
    assert_contains "self-test missing gitMinimal needs setup" "$text" "nix-portable store needs first-use setup"
    unset BYO_SELF_TEST

    # The caller holds the store lock and says so; byo-nix must not wait on it.
    exec 7>>"$BYO_TEST_LOCK"
    flock -x 7
    BYO_NIX_PORTABLE_STORE_LOCKED=1 timeout 20 "$BYO" extra-arg >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
    rc=$?
    exec 7>&-
    assert_rc "caller-held lock exec" "$rc" 0
    if [ "$(tail -n 1 "$BYO_TEST_RECORD/init")" = "lock-held" ] && [ "$(wc -l < "$BYO_TEST_RECORD/init" | tr -d ' ')" = 2 ]; then
        pass "caller-held lock runs first-use setup"
    else
        fail "caller-held lock runs first-use setup" "$(cat "$BYO_TEST_RECORD/init")"
    fi

    # Without the caller saying so, byo-nix waits for another holder of the store lock.
    rm -rf "$WORK/store/nix-store/.nix-portable/nix/store/$NP_STUB_GIT"
    (
        exec 7>>"$BYO_TEST_LOCK"
        flock -x 7
        touch "$WORK/holder-started"
        sleep 2
    ) &
    holder=$!
    while ! [ -e "$WORK/holder-started" ]; do
        sleep 0.1
    done
    start=$(date +%s)
    run_byo extra-arg
    rc=$?
    end=$(date +%s)
    wait "$holder"
    assert_rc "waits for store lock exec" "$rc" 0
    if [ $((end - start)) -ge 1 ]; then
        pass "first-use setup waits for store lock"
    else
        fail "first-use setup waits for store lock" "waited $((end - start))s"
    fi

    reset_env
    new_work
    write_np_stub "$WORK/bin/nix-portable"
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    export BYO_TEST_LOCK=$WORK/unused.lock
    export BYO_NO_LOCK=1
    run_byo extra-arg
    rc=$?
    assert_rc "no-lock first use exec" "$rc" 0
    if [ -e "$BYO_TEST_RECORD/init" ]; then
        fail "no-lock skips first-use setup"
    else
        pass "no-lock skips first-use setup"
    fi

    reset_env
    new_work
    write_stub "$WORK/stub"
    mkdir -p "$WORK/bin"
    cp "$WORK/stub" "$WORK/bin/nix-portable"
    chmod a-x "$WORK/bin/nix-portable"
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_TEST_STUB=$WORK/stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_TEST_DL_FAIL=1
    run_byo
    rc=$?
    text=$(captured)
    unset BYO_TEST_DL_FAIL
    assert_rc "chmod existing binary" "$rc" 0
    if [ -x "$WORK/bin/nix-portable" ]; then
        pass "existing binary made executable"
    else
        fail "existing binary made executable"
    fi
    if [ -f "$BYO_TEST_RECORD/count" ]; then
        fail "chmod path did not download"
    else
        pass "chmod path did not download"
    fi
    assert_contains "chmod path still execs" "$text" "ARGS: [nix]"

    reset_env
    new_work
    write_stub "$WORK/stub"
    mkdir -p "$WORK/bin"
    cp "$WORK/stub" "$WORK/bin/nix-portable"
    chmod a-x "$WORK/bin/nix-portable"
    mode_before=$(stat -c %a "$WORK/bin/nix-portable")
    export BYO_SELF_TEST=1
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "self-test non-executable exits 1" "$rc" 1
    assert_contains "self-test missing execute" "$text" "nix-portable missing execute permission"
    if [ "$(stat -c %a "$WORK/bin/nix-portable")" = "$mode_before" ]; then
        pass "self-test does not chmod"
    else
        fail "self-test does not chmod"
    fi

    reset_env
    new_work
    write_stub "$WORK/bin/nix-portable"
    mkdir -p "$WORK/store/nix-store"
    touch "$WORK/store/nix-store.lock"
    export BYO_SELF_TEST=1
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "self-test found exits 1" "$rc" 1
    assert_contains "self-test found" "$text" "nix-portable found at $WORK/bin/nix-portable"
    assert_contains "self-test store present" "$text" "nix-portable store present at $WORK/store/nix-store"
    assert_contains "self-test lock present" "$text" "Lockfile for nix-portable store exists: $WORK/store/nix-store.lock"

    export BYO_NO_LOCK=1
    run_byo
    text=$(captured)
    assert_not_contains "self-test no-lock hides existing lock line" "$text" "Lockfile for nix-portable store exists"
    unset BYO_NO_LOCK

    reset_env
    new_work
    export BYO_SELF_TEST=1
    export BYO_FORCE_DOWNLOAD=1
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/root
    export BYO_NIX_PORTABLE=nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/missing-store
    run_byo
    text=$(captured)
    assert_contains "self-test forced missing" "$text" "nix-portable not found (forced) at $WORK/root/nix-portable"
    assert_contains "self-test store missing" "$text" "nix-portable store not present at $WORK/missing-store"
    assert_contains "self-test lock missing" "$text" "No lockfile for nix-portable store: $WORK/missing-store.lock"
    if [ -e "$WORK/root/nix-portable" ]; then
        fail "forced self-test does not download"
    else
        pass "forced self-test does not download"
    fi

    reset_env
    new_work
    tool_dir=$WORK/tools
    link_tools "$tool_dir" $BASE_TOOLS
    # Self-test only checks that a command named wget is on PATH. It never runs it.
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$tool_dir/wget"
    chmod a+x "$tool_dir/wget"
    export BYO_SELF_TEST=1
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/root
    PATH=$tool_dir
    export PATH
    run_byo
    rc=$?
    PATH=$OLD_PATH
    export PATH
    text=$(captured)
    assert_rc "wget self-test exit 1" "$rc" 1
    assert_contains "wget fallback command" "$text" "wget --tries 5 -O"
    assert_not_contains "wget fallback is not curl" "$text" "curl -sSLf"

    reset_env
    new_work
    tool_dir=$WORK/tools
    link_tools "$tool_dir" $BASE_TOOLS
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/root
    PATH=$tool_dir
    export PATH
    run_byo
    rc=$?
    PATH=$OLD_PATH
    export PATH
    text=$(captured)
    assert_rc "no downloader fails" "$rc" 1
    assert_contains "no curl or wget" "$text" "No curl or wget present"

    reset_env
    new_work
    export BYO_NIX_PORTABLE_DL_CMD=/bin/false
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/root
    export BYO_ONLY_GET=1
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "downloader failure" "$rc" 1
    assert_contains "downloader failure message" "$text" "Downloading nix-portable to temporary location"
    if [ -e "$WORK/root/.nix-portable/nix-portable" ]; then
        fail "failed download leaves no binary"
    else
        pass "failed download leaves no binary"
    fi

    reset_env
    new_work
    export BYO_SELF_TEST=1
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE_URL=https://example.test/from-self-test
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/root
    run_byo
    text=$(captured)
    assert_contains "self-test prints custom downloader" "$text" "$FAKE_DL \"https://example.test/from-self-test\""

    reset_env
    new_work
    write_stub "$WORK/stub"
    export BYO_TEST_STUB=$WORK/stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    export BYO_ONLY_GET=1
    export BYO_TEST_DL_SLEEP=1
    "$BYO" >"$WORK/p1.out" 2>"$WORK/p1.err" &
    p1=$!
    "$BYO" >"$WORK/p2.out" 2>"$WORK/p2.err" &
    p2=$!
    wait "$p1"
    r1=$?
    wait "$p2"
    r2=$?
    unset BYO_TEST_DL_SLEEP
    assert_rc "parallel download first" "$r1" 0
    assert_rc "parallel download second" "$r2" 0
    if [ "$(cat "$BYO_TEST_RECORD/count")" = 1 ]; then
        pass "parallel download runs once"
    else
        fail "parallel download runs once" "count=$(cat "$BYO_TEST_RECORD/count" 2>/dev/null)
$(cat "$WORK/p1.err" "$WORK/p2.err")"
    fi
    if [ -f "$WORK/bin/nix-portable.lock" ]; then
        pass "parallel download lock exists"
    else
        fail "parallel download lock exists"
    fi

    reset_env
    new_work
    tool_dir=$WORK/tools
    link_tools "$tool_dir" $BASE_TOOLS
    write_stub "$WORK/stub"
    cp "$WORK/stub" "$tool_dir/nix-portable-stub"
    # Place the stub via a download using the normal PATH, then re-exec with git hidden.
    export BYO_TEST_STUB=$WORK/stub
    export BYO_TEST_RECORD=$BYO_TEST_RECORD
    export BYO_NIX_PORTABLE_DL_CMD=$FAKE_DL
    export BYO_NIX_PORTABLE=$WORK/bin/nix-portable
    export BYO_NIX_PORTABLE_STORE=$WORK/store/nix-store
    PATH=$tool_dir
    export PATH
    run_byo
    rc=$?
    PATH=$OLD_PATH
    export PATH
    text=$(captured)
    assert_rc "git hidden exec" "$rc" 0
    assert_contains "NP_GIT empty without git" "$text" "NP_GIT:"
    assert_not_contains "NP_GIT empty has no path" "$text" "NP_GIT:/"

    reset_env
    new_work
    export BYO_NIX=/bin/echo
    export BYO_NIX_PORTABLE_CACHE_ROOT=$WORK/unused
    run_byo hello world
    rc=$?
    text=$(captured)
    assert_rc "BYO_NIX exec" "$rc" 0
    assert_contains "BYO_NIX arguments" "$text" "hello world"
    if [ -e "$WORK/unused" ]; then
        fail "BYO_NIX skips portable cache" "$WORK/unused appeared"
    else
        pass "BYO_NIX skips portable cache"
    fi

    reset_env
    new_work
    export BYO_NIX=$WORK/missing-nix
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "missing BYO_NIX" "$rc" 1
    assert_contains "missing BYO_NIX message" "$text" "Not found/executable BYO_NIX=$WORK/missing-nix"

    printf '#!/bin/sh\nexit 0\n' > "$WORK/nix-noexec"
    export BYO_NIX=$WORK/nix-noexec
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "non-executable BYO_NIX" "$rc" 1
    assert_contains "non-executable BYO_NIX message" "$text" "Not found/executable BYO_NIX=$WORK/nix-noexec"

    export BYO_SELF_TEST=1
    export BYO_NIX=/bin/echo
    run_byo
    rc=$?
    text=$(captured)
    assert_rc "self-test executable BYO_NIX exits 1" "$rc" 1
    assert_contains "self-test BYO_NIX found" "$text" "Nix found and executable: /bin/echo"

    export BYO_NIX=$WORK/missing-nix
    run_byo
    text=$(captured)
    assert_contains "self-test BYO_NIX missing" "$text" "Nix not found or not executable: $WORK/missing-nix"

    reset_env
}
