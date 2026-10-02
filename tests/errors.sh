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
    assert_rc "nix-devshell-enter too few args" "$rc" 1
    assert_contains "nix-devshell-enter usage" "$text" "Too few arguments"

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

    export NSCD_SOCKET=$WORK/no-nscd-socket
    run_enter "$ROOT" "" true
    rc=$?
    unset NSCD_SOCKET
    text=$(captured)
    assert_rc "missing nscd socket fails" "$rc" 1
    assert_contains "missing nscd message" "$text" "nscd or nsncd are required"
    assert_not_contains "missing nscd does not pre-build" "$text" "Pre-building devShell"

    reset_env
    new_work
    run_tramp() {
        "$TRAMP" "$@" >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
    }
    export NIX_DEVSHELL_ENTER_WRAPPER=$WORK/missing-enter
    run_tramp "$ROOT" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "missing NIX_DEVSHELL_ENTER_WRAPPER" "$rc" 1
    assert_contains "missing enter wrapper message" "$text" "No such nix-devshell-enter"

    printf '#!/bin/sh\nexit 0\n' > "$WORK/enter"
    export NIX_DEVSHELL_ENTER_WRAPPER=$WORK/enter
    run_tramp "$ROOT" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "non-executable NIX_DEVSHELL_ENTER_WRAPPER" "$rc" 1
    assert_contains "non-executable enter wrapper message" "$text" "Not executable nix-devshell-enter"

    unset NIX_DEVSHELL_ENTER_WRAPPER
    export NIX_FLAKE_ENTER_WRAPPER=$WORK/missing-enter
    run_tramp "$ROOT"
    rc=$?
    text=$(captured)
    assert_rc "old wrapper variable is ignored" "$rc" 1
    assert_contains "old wrapper variable still reaches usage" "$text" "Too few arguments"
    assert_not_contains "old wrapper variable is not read" "$text" "No such nix"
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
printf 'STACK<%s>\n' "${__NIX_SHEBANG_STACK-}" >> "${BYO_TEST_ENTER_LOG:?}"
printf 'ARG<%s>\n' "$@" >> "${BYO_TEST_ENTER_LOG:?}"
exit 0
EOF
    chmod a+x "$WORK/enter-log.sh"
    export NIX_DEVSHELL_ENTER_WRAPPER=$WORK/enter-log.sh
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
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a#default"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "unlisted named devShell forces enter"
    else
        fail "unlisted named devShell forces enter"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a#cowsay|$flake_a#default"
    run_tramp "$flake_a" "" /bin/echo marker
    text=$(cat "$BYO_TEST_STDOUT")
    assert_contains "merge listed devShells runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "merge listed devShells skips enter"
    else
        fail "merge listed devShells skips enter" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE=",$flake_a#cowsay|$flake_a#default,"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "blank comma merge entries ignored"
    else
        fail "blank comma merge entries ignored" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a"
    export __NIX_SHEBANG_STACK="$flake_a#cowsay|$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    text=$(cat "$BYO_TEST_STDOUT")
    assert_contains "flake dir shorthand runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "flake dir shorthand skips enter"
    else
        fail "flake dir shorthand skips enter" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE=",$flake_a,"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "blank comma around flake dir shorthand ignored"
    else
        fail "blank comma around flake dir shorthand ignored" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a"
    export __NIX_SHEBANG_STACK="$flake_b#default|$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "flake dir shorthand does not cover another flake"
    else
        fail "flake dir shorthand does not cover another flake"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a|$flake_b#default"
    export __NIX_SHEBANG_STACK="$flake_b#cowsay|$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "named entry does not cover other shells in that flake"
    else
        fail "named entry does not cover other shells in that flake"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a|$flake_b#default"
    export __NIX_SHEBANG_STACK="$flake_b#default|$flake_a#cowsay|"
    run_tramp "$flake_a" cowsay /bin/echo marker
    text=$(cat "$BYO_TEST_STDOUT")
    assert_contains "mixed shorthand runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "bare flake dir mixes with a named devShell"
    else
        fail "bare flake dir mixes with a named devShell" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    unset __NIX_SHEBANG_STACK
    unset NIX_SHEBANG_DEVSHELL_MERGE
    run_tramp "$flake_a/" "" /bin/echo marker
    enter_log=$(cat "$WORK/enter.log")
    if printf '%s\n' "$enter_log" | grep -F -x -q "ARG<$flake_a>"; then
        pass "trailing slash argument is recorded without the slash"
    else
        fail "trailing slash argument is recorded without the slash" "$enter_log"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a/"
    export __NIX_SHEBANG_STACK="$flake_a#cowsay|$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "trailing slash on flake dir shorthand is ignored"
    else
        fail "trailing slash on flake dir shorthand is ignored" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a/#cowsay|$flake_a/#default"
    run_tramp "$flake_a/" "" /bin/echo marker
    text=$(cat "$BYO_TEST_STDOUT")
    assert_contains "trailing slash on named devShell runs interpreter" "$text" "marker"
    if [ ! -s "$WORK/enter.log" ]; then
        pass "trailing slash on named devShell is ignored"
    else
        fail "trailing slash on named devShell is ignored" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a"
    export __NIX_SHEBANG_STACK="$flake_a/#cowsay|$flake_a/#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "trailing slash on stack entry is ignored"
    else
        fail "trailing slash on stack entry is ignored" "$(cat "$WORK/enter.log")"
    fi

    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a#"
    export __NIX_SHEBANG_STACK="$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    rc=$?
    text=$(captured)
    assert_rc "merge entry with empty devShell name" "$rc" 1
    assert_contains "merge entry form message" "$text" "absolute_flake_path#devShell"

    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a#default||$flake_b#default"
    export __NIX_SHEBANG_STACK="$flake_a#default|"
    run_tramp "$flake_a" "" /bin/echo marker
    rc=$?
    text=$(captured)
    assert_rc "blank pipe merge entry" "$rc" 1
    assert_contains "blank pipe message" "$text" "pipe-separated flake+devShell entries cannot be blank"

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$flake_a#default|$flake_b#default,$flake_b#default|$flake_c#default"
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

    printf '#!/bin/sh\nexit 0\n' > "$WORK/wrapper"
    chmod a+x "$WORK/wrapper"
    export BYO_NIX_WRAPPER=$WORK/wrapper
    run_enter() {
        "$ENTER" "$@" >"$BYO_TEST_STDOUT" 2>"$BYO_TEST_STDERR"
    }

    mkdir -p "$WORK/only-classic"
    printf '{ }\n' > "$WORK/only-classic/shell.nix"
    run_tramp "$WORK/only-classic" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "directory with only a nix file" "$rc" 1
    assert_contains "directory with only a nix file message" "$text" "No 'flake.nix' in flake directory"
    assert_contains "directory with only a nix file tells caller to pass the file" "$text" "Pass the .nix file explicitly."
    run_enter "$WORK/only-classic" "" true
    rc=$?
    text=$(captured)
    assert_rc "enter rejects directory with only a nix file" "$rc" 1
    assert_contains "enter directory with only a nix file message" "$text" "Pass the .nix file explicitly."

    mkdir -p "$WORK/foo.nix"
    printf '%s\n' '{ outputs = _: {}; }' > "$WORK/foo.nix/flake.nix"
    run_tramp "$WORK/foo.nix" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "directory named .nix" "$rc" 1
    assert_contains "directory named .nix message" "$text" "Invalid .nix file"
    run_enter "$WORK/foo.nix" "" true
    rc=$?
    text=$(captured)
    assert_rc "enter rejects directory named .nix" "$rc" 1
    assert_contains "enter directory named .nix message" "$text" "Invalid .nix file"

    mk_flake_dir "$WORK/both"
    printf '{ }\n' > "$WORK/both/shell.nix"
    printf '{ }\n' > "$WORK/both/default.nix"
    printf '{ }\n' > "$WORK/both/dev.nix"
    printf 'not nix\n' > "$WORK/both/notes.txt"
    shell_nix=$(CDPATH= cd "$WORK/both" && pwd)/shell.nix
    default_nix=$(CDPATH= cd "$WORK/both" && pwd)/default.nix
    dev_nix=$(CDPATH= cd "$WORK/both" && pwd)/dev.nix
    both_dir=$(CDPATH= cd "$WORK/both" && pwd)

    : > "$WORK/enter.log"
    unset __NIX_SHEBANG_STACK
    unset NIX_SHEBANG_DEVSHELL_MERGE
    run_tramp "$shell_nix" "" /bin/echo marker
    rc=$?
    enter_log=$(cat "$WORK/enter.log")
    assert_rc "explicit shell.nix next to flake.nix" "$rc" 0
    assert_contains "blank classic attribute is forwarded blank" "$enter_log" "ARG<>"
    assert_contains "blank classic attribute records default" "$enter_log" "STACK<$shell_nix#default|"

    : > "$WORK/enter.log"
    unset __NIX_SHEBANG_STACK
    run_tramp "$default_nix" "" /bin/echo marker
    rc=$?
    enter_log=$(cat "$WORK/enter.log")
    assert_rc "explicit default.nix" "$rc" 0
    assert_contains "default.nix records default" "$enter_log" "STACK<$default_nix#default|"

    : > "$WORK/enter.log"
    unset __NIX_SHEBANG_STACK
    run_tramp "$dev_nix" cowsay /bin/echo marker
    rc=$?
    enter_log=$(cat "$WORK/enter.log")
    assert_rc "named classic attribute" "$rc" 0
    assert_contains "named classic attribute is forwarded" "$enter_log" "ARG<cowsay>"
    assert_contains "named classic attribute records cowsay" "$enter_log" "STACK<$dev_nix#cowsay|"

    run_tramp "$WORK/both/notes.txt" "" /bin/echo "$WORK/script"
    rc=$?
    text=$(captured)
    assert_rc "non-nix file" "$rc" 1
    assert_contains "non-nix file message" "$text" "Flake directory doesn't exist"

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$dev_nix"
    export __NIX_SHEBANG_STACK="$dev_nix#cowsay|$dev_nix#default|"
    run_tramp "$dev_nix" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "bare nix file covers the unnamed derivation"
    else
        fail "bare nix file covers the unnamed derivation" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export __NIX_SHEBANG_STACK="$dev_nix#default|$dev_nix#cowsay|"
    run_tramp "$dev_nix" cowsay /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "bare nix file covers a named attribute"
    else
        fail "bare nix file covers a named attribute" "$(cat "$WORK/enter.log")"
    fi

    : > "$WORK/enter.log"
    export __NIX_SHEBANG_STACK="$both_dir#default|"
    run_tramp "$dev_nix" "" /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "bare nix file does not cover the flake directory"
    else
        fail "bare nix file does not cover the flake directory"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$dev_nix#cowsay"
    export __NIX_SHEBANG_STACK="$dev_nix#hello|"
    run_tramp "$dev_nix" cowsay /bin/echo marker
    if [ -s "$WORK/enter.log" ]; then
        pass "named classic attribute does not cover another attribute"
    else
        fail "named classic attribute does not cover another attribute"
    fi

    : > "$WORK/enter.log"
    export NIX_SHEBANG_DEVSHELL_MERGE="$both_dir|$dev_nix"
    export __NIX_SHEBANG_STACK="$dev_nix#default|$both_dir#default|"
    run_tramp "$both_dir" "" /bin/echo marker
    if [ ! -s "$WORK/enter.log" ]; then
        pass "one merge set mixes a flake directory and a nix file"
    else
        fail "one merge set mixes a flake directory and a nix file" "$(cat "$WORK/enter.log")"
    fi

    export NIX_SHEBANG_DEVSHELL_MERGE="$dev_nix#"
    export __NIX_SHEBANG_STACK="$dev_nix#default|"
    run_tramp "$dev_nix" "" /bin/echo marker
    rc=$?
    text=$(captured)
    assert_rc "classic merge entry with empty name" "$rc" 1
    assert_contains "classic merge entry with empty name message" "$text" "absolute_flake_path#devShell"

    reset_env
    system=$system
}
