# Failure exits and shebang stack decisions that do not build a devShell.

mk_flake_dir() {
    _dir=$1
    mkdir -p "$_dir"
    printf '%s\n' '{ outputs = _: {}; }' > "$_dir/flake.nix"
}

errors_and_stack() {
    printf '== errors and shebang stack ==\n'
    system=$(nix_system)

    reset_env
    new_work
    export BYO_NIX_WRAPPER=$WORK/missing-wrapper
    run_enter() {
        "$ENTER" "$@" >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
    }
    run_enter "$ROOT" "" true
    rc=$?
    text=$(captured)
    assert_rc "missing BYO_NIX_WRAPPER" "$rc" 1
    assert_contains "missing wrapper message" "$text" "Missing byo-nix tool"

    printf '#!/bin/sh\nexit 0\n' > "$WORK/wrapper"
    export BYO_NIX_WRAPPER=$WORK/wrapper
    run_enter "$ROOT" "" true
    rc=$?
    text=$(captured)
    assert_rc "non-executable BYO_NIX_WRAPPER" "$rc" 1
    assert_contains "non-executable wrapper message" "$text" "Non-executable byo-nix tool"
    unset BYO_NIX_WRAPPER

    run_enter
    rc=$?
    text=$(captured)
    assert_rc "nix-flake-enter too few args" "$rc" 1
    assert_contains "nix-flake-enter usage" "$text" "Too few arguments"

    run_enter "$WORK/no-such-flake" "" true
    rc=$?
    text=$(captured)
    assert_rc "missing flake directory" "$rc" 1
    assert_contains "missing flake directory message" "$text" "Flake directory doesn't exist"

    mkdir -p "$WORK/empty-flake"
    run_enter "$WORK/empty-flake" "" true
    rc=$?
    text=$(captured)
    assert_rc "missing flake.nix" "$rc" 1
    assert_contains "missing flake.nix message" "$text" "No 'flake.nix' in flake directory"

    cat > "$WORK/uname" << 'EOF'
#!/bin/sh
if [ "$1" = "-m" ]; then
    echo ppc64le
    exit 0
fi
exec /usr/bin/uname "$@"
EOF
    chmod a+x "$WORK/uname"
    PATH="$WORK:$OLD_PATH"
    export PATH
    run_enter "$ROOT" "" true
    rc=$?
    PATH=$OLD_PATH
    export PATH
    text=$(captured)
    assert_rc "unknown uname" "$rc" 1
    assert_contains "unknown uname message" "$text" "Unrecognized host system type"

    if unshare --mount --map-root-user true >"$WORK/unshare.out" 2>"$WORK/unshare.err"; then
        unshare --mount --map-root-user sh -c '
            empty=$1
            enter=$2
            flake=$3
            out=$4
            err=$5
            rcfile=$6
            mkdir -p "$empty"
            if [ -d /var/run/nscd ]; then
                mount --bind "$empty" /var/run/nscd || exit 90
            else
                mkdir -p /var/run/nscd
                mount -t tmpfs tmpfs /var/run/nscd || exit 90
            fi
            if [ -S /var/run/nscd/socket ]; then
                exit 91
            fi
            "$enter" "$flake" "" true >"$out" 2>"$err"
            printf "%s\n" "$?" > "$rcfile"
        ' sh "$WORK/empty-nscd" "$ENTER" "$ROOT" "$WORK/nscd.out" "$WORK/nscd.err" "$WORK/nscd.rc"
        hide_rc=$?
        if [ "$hide_rc" -eq 0 ]; then
            nscd_rc=$(cat "$WORK/nscd.rc")
            nscd_text=$(cat "$WORK/nscd.out" "$WORK/nscd.err")
            assert_rc "hidden nscd socket fails" "$nscd_rc" 1
            assert_contains "hidden nscd message" "$nscd_text" "nscd or nsncd are required"
            assert_not_contains "hidden nscd does not call nix" "$nscd_text" "Pre-building devShell"
        else
            fail "hidden nscd socket" "unshare mount failed ($hide_rc)
$(cat "$WORK/nscd.err" 2>/dev/null)"
        fi
    else
        fail "hidden nscd socket" "unshare unavailable
$(cat "$WORK/unshare.err")"
    fi

    reset_env
    new_work
    run_tramp() {
        "$TRAMP" "$@" >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
    }
    export NIX_FLAKE_ENTER_WRAPPER=$WORK/missing-enter
    run_tramp "$ROOT" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "missing NIX_FLAKE_ENTER_WRAPPER" "$rc" 1
    assert_contains "missing enter wrapper message" "$text" "No such nix-flake-enter"

    printf '#!/bin/sh\nexit 0\n' > "$WORK/enter"
    export NIX_FLAKE_ENTER_WRAPPER=$WORK/enter
    run_tramp "$ROOT" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "non-executable NIX_FLAKE_ENTER_WRAPPER" "$rc" 1
    assert_contains "non-executable enter wrapper message" "$text" "Not executable nix-flake-enter"

    unset NIX_FLAKE_ENTER_WRAPPER
    run_tramp "$ROOT"
    rc=$?
    text=$(captured)
    assert_rc "trampoline too few args" "$rc" 1
    assert_contains "trampoline usage" "$text" "Too few arguments"

    run_tramp "$WORK/no-such-flake" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "trampoline missing flake dir" "$rc" 1
    assert_contains "trampoline missing flake dir message" "$text" "Flake directory doesn't exist"

    mkdir -p "$WORK/empty-flake"
    run_tramp "$WORK/empty-flake" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "trampoline missing flake.nix" "$rc" 1
    assert_contains "trampoline missing flake.nix message" "$text" "No 'flake.nix' in flake directory"

    mk_flake_dir "$WORK/a"
    mk_flake_dir "$WORK/b"
    mk_flake_dir "$WORK/c"
    mk_flake_dir "$WORK/other"
    flake_a=$(abs_dir "$WORK/a")
    flake_b=$(abs_dir "$WORK/b")
    flake_c=$(abs_dir "$WORK/c")
    flake_other=$(abs_dir "$WORK/other")

    cat > "$WORK/enter-log.sh" << 'EOF'
#!/bin/sh
printf 'ARG<%s>\n' "$@" >> "${BYO_TEST_ENTER_LOG:?}"
exit 0
EOF
    chmod a+x "$WORK/enter-log.sh"
    export NIX_FLAKE_ENTER_WRAPPER=$WORK/enter-log.sh
    export BYO_TEST_ENTER_LOG=$WORK/enter.log

    : > "$WORK/enter.log"
    unset __NIX_SHEBANG_STACK
    unset NIX_SHEBANG_DEVSHELL_MERGE
    run_tramp "$flake_a" "" /bin/echo marker
    rc=$?
    enter_log=$(cat "$WORK/enter.log")
    assert_rc "empty stack enter status" "$rc" 0
    assert_contains "empty stack records flake" "$enter_log" "ARG<$flake_a>"
    assert_contains "empty devShell name is blank" "$enter_log" "ARG<>"
    assert_contains "empty stack passes interpreter" "$enter_log" "ARG</bin/echo>"
    assert_not_contains "empty stack does not run interpreter" "$(cat "$BYO_TEST_STDOUT")" "marker"

    : > "$WORK/enter.log"
    run_tramp "$flake_a" cowsay /bin/echo marker
    enter_log=$(cat "$WORK/enter.log")
    assert_contains "named devShell is forwarded" "$enter_log" "ARG<cowsay>"

    : > "$WORK/enter.log"
    export __NIX_SHEBANG_STACK="$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    rc=$?
    text=$(cat "$BYO_TEST_STDOUT")
    assert_rc "exact top match status" "$rc" 0
    assert_contains "exact top match runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "exact top match skips enter"
    else
        fail "exact top match skips enter" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export __NIX_SHEBANG_STACK="$flake_a#cowsay|$flake_a#default|"
    unset NIX_SHEBANG_DEVSHELL_MERGE
    run_tramp "$flake_a" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "different shell without merge enters"
    else
        fail "different shell without merge enters"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a"
    run_tramp "$flake_a" "" /bin/echo marker
    text=$(cat "$BYO_TEST_STDOUT")
    assert_contains "merge same flake runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "merge same flake skips enter"
    else
        fail "merge same flake skips enter" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE=",$flake_a,"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "blank comma merge entries ignored"
    else
        fail "blank comma merge entries ignored" "$(cat "$WORK/enter.log")"
    fi

    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a||$flake_b"
    export __NIX_SHEBANG_STACK="$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    rc=$?
    text=$(captured)
    assert_rc "blank pipe merge entry" "$rc" 1
    assert_contains "blank pipe message" "$text" "pipe-separated flake set entries cannot be blank"

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a|$flake_b,$flake_b|$flake_c"
    export __NIX_SHEBANG_STACK="$flake_c#default|$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "A is not compatible with C"
    else
        fail "A is not compatible with C"
    fi

    : > "$WORK/enter.log"
    export __NIX_SHEBANG_STACK="$flake_a#default|$flake_b#default|"
    run_tramp "$flake_b" "" /bin/echo marker
    text=$(cat "$BYO_TEST_STDOUT")
    assert_contains "B compatible with A runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "B is compatible with A"
    else
        fail "B is compatible with A" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export __NIX_SHEBANG_STACK="$flake_c#default|$flake_b#default|"
    run_tramp "$flake_b" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "B is compatible with C"
    else
        fail "B is compatible with C" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    unset NIX_SHEBANG_DEVSHELL_MERGE
    export __NIX_SHEBANG_STACK="$flake_other#default|$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "incompatible flake on top forces enter"
    else
        fail "incompatible flake on top forces enter"
    fi

    reset_env
    system=$system
}
