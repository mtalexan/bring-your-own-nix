# Bring Your Own Nix

Bootstrap a workspace/project-local nix instance on-demand, including from a script shebang.

## Uses

- Write directly callable scripts that bootstrap their own environment automatically (i.e. what `uv` did for Python, but now for almost any language and/or tools)
- Use deterministic and reproducible nix flake devShells for a project build environment instead of containerized environments (e.g. dev-containers)
- Use Nix without installing it (via `nix-portable`, but with an easier-to-use interface)

### Considerations

- You still need `bash` natively installed in your host environment, this is unavoidable
- You enter an overlay environment, there is no file system isolation, network isolation, etc like with containers
- You need to define a `flake.nix` that includes a `devShell` with all the tools you need for the overlay environment
- The first time running a script in a workspace can take longer while it downloads and installs packages (in a workspace store) for your overlay environment

## Background

### What is Bring Your Own Tools?

A common issue with development tools is consistency between environments, and the setup and maintenance costs. The historical solution was always to try and automate setup and maintenance of those environments, but solutions like Ansible, Chef, Puppet, Salt, etc. bring their own maintenance headaches and often aren't appropriate for an individual developer's system (especially if you're an open source project). Since it's critical that a developer's environment and any CI environment be as close as possible, this usually boils down to a lowest-common-denominator approach. An ultra-minimized set of tools is all that's allowed, ideally limited to ones that are usually already installed by default on workstations.  
Limiting to tools that are usually already installed on workstations means that most tools end up written in bash script, or even POSIX shell script, which can quickly become a nightmare for any particularly complex toolset. 

In a "Bring Your Own Tool" solution, you instead bring your tools with you. Either you include statically compiled binary versions of tools in your project itself and have your tools reference those (which introduces cross-arch support issues and bloats your project repo quite quickly), or you have your minimal tools get standalone copies of more advanced tools from remote locations (which introduces security and reliability issues).  The latter is preferred from a performance perspective because it ensures only the tools that are actually needed are present, doesn't bloat the git repo unnecessarily, and allows for the possibility of users configuring a system cache location for these tools so they can be shared across a number of related projects or workspaces, but requires an "installation" step to detect if tools are already present and obtain them if not.

### Shebang Tricks

In Linux, the "shebang" line is the line at the start of a file that begins with `#!`. It is a directive to the kernel that tells it what interpreter to use to execute the file. Classically this just serves to set `bash`, POSIX `sh`, `python3`, `ruby`, etc. as the interpreter for the script if one isn't manually specified on the command line. More recently, advanced shebangs that invoke tools to do both cached bootstrapping of an environment for the script and then execution of the script have been growing, especially in the Python world.  Tools like `pipx` and `uv` now have supported use cases where they're used as the shebang of a Python script and inline definitions for the modules that need to be imported are used (PEP 723). The interpreters create a venv and install the dependencies into it before running the body of the script within it (usually caching the venv). 

Other languages have been investigating similar solutions since it allows standalone "scripts" to be supplied to users that have these minimal tools like `pipx` or `uv` installed, and they can simply call the script directly as if it were a bash script.  

The shebang tricks, however, are not limited to these special-purpose tools; they can be used to invoke any arbitrary script or tool as the "interpreter".  

### Nix and "Bring Your Own Tools"

Nix provides an excellent basis for a Bring Your Own Tool solution because it inherently manages a global cache of tools and dependencies using a content-addressed store so there are guaranteed to be no conflicts between different tool versions or even different configurations of the same tool version. Using Nix flakes to define the needed environment also comes with `flake.lock` files that pin the environment to ensure reproducibility as well.  

The main negative of Nix is the difficult installation process (all the available installers require extensive hand-holding on any non-trivial system), the onerous system configuration requirements (the nix store must be in `/nix` and cannot be anywhere else), and the opaque specification syntax.

The [nix-portable](https://github.com/DavHau/nix-portable) project provides an excellent solution for the difficult installation and onerous system configuration requirements for cases where a full system install isn't justifiable, with only some minor trade-offs.


## Provides

This project provides 3 utilities as minimal POSIX shell scripts that can be copied or submoduled into a project.  

### `byo-nix`

This tool is effectively just a wrapper around a `nix` call. It will handle making sure you have a copy of `nix-portable`, and then will run that `nix-portable` tool to invoke the `nix` command. This includes locking to ensure obtaining the `nix-portable` tool is safe against multiple parallel calls to the tool.

Arguments to this script are just passed thru to the underlying `nix` command exactly as is.

Configuration of the tool makes use of environment variables:
- `BYO_NIX_PORTABLE_CACHE_ROOT` is a root path to where your `nix-portable` binary should be stored, and where the store it uses should be created. It only applies when the `BYO_NIX_PORTABLE` and/or `BYO_NIX_PORTABLE_STORE` are not absolute paths, and makes it easy to create per-project or per-workspace locations for the tool and store while still using consistent names and folder structure for them in each workspace and project. It defaults to the directory this script is in, but is something you'll very likely override.
- `BYO_NIX_PORTABLE` is the path and name of the file to cache the `nix-portable` binary to. It defaults to `.nix-portable/nix-portable`. If this is a relative path, it's relative to `BYO_NIX_PORTABLE_CACHE_ROOT`. A modifiable `*.lock` file of the same name and location will also need to be able to be created here for managing parallel invocations when no prior cached copy of the tool is present. This is ignored when `BYO_NIX` is set, since `nix-portable` is not used.
- `BYO_NIX_PORTABLE_STORE` is the location of the store `nix-portable` should use. It defaults to `.nix-portable/nix-store`. If this is a relative path, it's relative to `BYO_NIX_PORTABLE_CACHE_ROOT`. A modifiable `*.lock` file of the same name as this directory will be created next to it, which is required for managing independent parallel writes to the store. This script creates that lockfile so callers can take it; holding the lock for a particular `nix` command is left to the caller. When `BYO_NIX` is set, this value is ignored and the system store is used. This should never point to a system nix store, since the two tools do not share locking or store ownership.
- `BYO_NIX_PORTABLE_URL` is the URL to download `nix-portable` from. By default the latest official GitHub Release link is used, but if you wanted to get it from somewhere else, or cache it for your CI systems to use, you can set this to point to that location.
- `BYO_NIX_PORTABLE_DL_CMD` is for when you have non-trivial download requirements for the `BYO_NIX_PORTABLE_URL`. The default is to look for `curl` or `wget` and do a regular download of the URL using the default system settings. If you need to authenticate to a caching server or something more complicated, you can put that into your own script and point to that script with this variable. The script is always passed the `BYO_NIX_PORTABLE_URL` as the first argument, and the absolute path and name of the file it should be downloaded to as the second argument. 
- `BYO_FORCE_DOWNLOAD` can be set (to anything non-blank) if you want to force a download of `nix-portable` to occur. Instead of looking to see if it already exists, the download will always occur and may overwrite an existing file.
- `BYO_NO_LOCK` skips all locking or lockfile creation. This should only be used if an existing `nix-portable` and store associated with a `flake.lock` are all being deployed together via a read-only folder. Creation or updates to the `nix-portable` and store are required to be managed via write locks to ensure parallel calls to `byo-nix` don't simultaneously try to create/modify them.
- `BYO_NIX` can be set to point to a system install of `nix`, allowing existing tooling designed primarily for use with `nix-portable` to be used as-is on top of a system-installed `nix` instead. The `byo-nix` script effectively turns into just an `exec "$BYO_NIX" "$@"` call when this is set. The system install must have flakes and the `nix` command enabled so it accepts the same arguments as `nix-portable`.
- `BYO_NIX_PORTABLE_STORE_LOCKED` is for a caller that already holds the `BYO_NIX_PORTABLE_STORE` write lock when it calls `byo-nix`. The first-use check described below then runs without taking that lock again, which would otherwise wait forever. `nix-flake-enter` sets it for the calls it makes while holding the lock. It is not passed on to `nix-portable`.
- `BYO_ONLY_GET` can be set (to anything non-blank) to stop once `nix-portable` is present and executable. The store lockfile is not created and `nix` is not invoked. This can be combined with `BYO_FORCE_DOWNLOAD` to refresh a cached binary. It is ignored when `BYO_NIX` is set.
- `BYO_SELF_TEST` can be set (to anything non-blank) to skip downloads, lockfile creation, and the `nix` invocation. The script checks what it would do, prints that to stderr, and exits with an error. When `BYO_NIX` is set it checks that the given binary exists and is executable.

**WARNING:** This tool does not perform write locking of the store!  
This script is intended for one-off manual operations on a store that doesn't have any other activity going on, or for more advanced tools to use.  
It is safe to perform any number of read operations of existing content from a store without needing to lock. It's even safe to perform writes to the store at the same time reads of preexisting content are happening, since the content hash addressing ensures the store objects being read and written won't conflict. It is not safe, however, to perform multiple actions that write, or actions that might read content that's still being written. A write lock for the store is created by this tool for the purposes of locking the store during writes, but the tool is not capable of detecting every case where a write to the store might occur.

**Note:** `byo-nix` does not set nix-portable's `NP_GIT`, and it clears an inherited value before invoking nix-portable. Nix needs a `git` for flakes. Pointing `NP_GIT` at a host `git` would avoid installing another copy, but nix-portable implements that by deleting and recreating `$NP_LOCATION/.nix-portable/tmpbin` on every start and then creating `tmpbin/git` with `ln -s`. That directory is shared by every process using the store. Overlapping nix-portable invocations race on it and fail with `File exists`. These tools do overlap: `nix-flake-enter` holds the store lock only around the devShell pre-build and releases it before `nix develop`, and a shebang script can be running in one devShell while another command uses the same store. No lock can cover that startup step for every invocation, since commands in a devShell run outside the lock. Leaving `NP_GIT` unset makes nix-portable install its own `gitMinimal` into the portable store once, on first use, and later invocations of that same store reuse it.

**Note:** The first use of nix-portable is a store write to do initial store population. It must protect that initial setup, which requires holding the write-lock. Callers of the script that already hold the write lock need to set `BYO_NIX_PORTABLE_STORE_LOCKED` to avoid deadlocks.

#### `byo-nix` Use Cases

_Direct use of `byo-nix` should be limited to cases where one-off manual commands are needed on a store that is guaranteed not to otherwise be in use._

- Running a command using an ad-hoc specified tool.

```shell
byo-nix run 'nixpkgs#cowsay' -- cowsay "Hello world"
```

- Creating an ad-hoc specified environment and running a script in it

```shell
byo-nix run 'nixpkgs#{jq,yq-go,python311}' -- ./myscript
```

- Building a local nix flake

```shell
byo-nix build '.'
```

- Updating a local nix flake's lockfile

```shell
byo-nix flake update '.'
```

### `nix-flake-enter`

Designed for entering a `devShell` of a nix flake using `byo-nix` by calling `nix develop` on it.  This wrapper pre-checks if the devShell environment is already fully built and in the store, and will grab the store write lock and pre-build it if not. 

**WARNING:** The `nscd` or `nsncd` daemon is REQUIRED to be present and running on your system!  
With nix, all packages are fully deterministic, which includes its own copy of glibc. That glibc is pretty much guaranteed to differ from the one present on the host system, either in version, toolchain used to build it, or configuration. For a number of system commands/tools, however, the `nsswitch.conf` specifies plugin libraries that should be loaded to extend the normal logic. This includes things like user name lookups for example, and they are not optional on a Linux system. These plugin libraries get dynamically loaded into the glibc, which means they have to exactly match the version, toolchain, etc of the glibc they're used with. This mismatch issue was foreseen, however, and glibc includes hardcoded support for an `nscd` daemon. The `nscd` daemon accepts glibc requests on a hardcoded socket, and will run those requests using the native glibc and any plugin libraries. This allows a different glibc to effectively front for a host glibc with plugin modules. The original `nscd` daemon supports a number of additional features as well, and presents somewhat of a security risk in system design. Some distros, like Fedora, have chosen to stop including it despite having no alternative solution for this necessary use case. The `nsncd` daemon is a Rust-based rewrite of the minimal glibc functionality from the original `nscd` and is available as a single stand-alone binary. For systems that don't have `nscd` available thru their native package managers anymore, `nsncd` is the preferred alternative. Only one of the two can be present on a system, since they both open the specific hardcoded socket name compiled into all versions of glibc, but one of them is explicitly required by this tool since flake devShells can very rarely function properly without it.


The arguments to this script are:
1. The path to the folder containing the `flake.nix` describing your devShell(s).
2. The name of the devShell in the flake to enter. If this is blank it is assumed to be the default devShell.
3. The command to run in the devShell.
4. (and all additional arguments) Optionally, any additional arguments to pass to the command being run within the devShell.

A blank devShell name selects `devShells.<system>.default`. The `<system>` value is detected from the host and will be one of `x86_64-linux`, `aarch64-linux`, `armv7l-linux`, or `i686-linux`. Only that `devShells.<system>.<name>` output is recognized.

The store write lock is held across the dry-run and any pre-build, and `BYO_NIX_PORTABLE_STORE_LOCKED` is set for those two `byo-nix` calls. `byo-nix` therefore runs any `nix-portable` first-use setup under that same lock.

- All `byo-nix` environment variables are passed thru to the underlying `byo-nix`.  A few of the variables have additional effects in this script too:
  - `BYO_NO_LOCK` if set, the pre-check and possible pre-build of the devShell is skipped because it's unnecessary if no explicit locking is going to occur. It will rely on the `nix develop` call to do any store updates, which will occur unsafely and unlocked if they are needed.
  - `BYO_NIX` if set, the pre-check and possible pre-build of the devShell is skipped since system nix safely manages it during the `nix develop` call already.
- `BYO_NIX_WRAPPER` if your `byo-nix` script isn't in the same folder as this script, you will need to specify the path to it in this variable.

#### `nix-flake-enter` Use Cases

_Use `nix-flake-enter` when a command should run inside a flake devShell, including when that devShell may still need to be built into the store._

A blank devShell name still has to be passed, as `""`, so the command stays in argument 3.

- Running a command in the default devShell of the flake in the current directory.

```shell
nix-flake-enter . "" python3 ./myscript.py arg1
```

- Running a command in a named devShell.

```shell
nix-flake-enter ./flake_dir myRubyShell ruby ./script.rb
```

- Opening an interactive shell in the default devShell. Pass the shell as the command.

```shell
nix-flake-enter . "" bash
```

- Running a container tool from a named devShell that provides it.

```shell
nix-flake-enter . isolatedPodmanShell podman info
```

### `nix-shebang-trampoline`

For use in the shebang of scripts, this wraps `nix-flake-enter` and manages whether or not the requested flake devShell is already the current environment.  

When using a script like this in the shebang of some tool, it's likely that it might call another tool that also uses this in its shebang. When both those tools are within the same project, there's a very good chance the devShell being requested in both tools is the same one. However it may have called a tool that needs a different devShell instead, and that tool may then call a tool that needs the first devShell back. This leads to an effective stack of nested devShells that need to be tracked to determine if a newly requested devShell is already the one we're in or not, and for simply acting as a passthru for the original command when we're already in the correct devShell.

Unfortunately the syntax of shebangs is limited and there's no way to reference a path relative to the calling directory or script the shebang is in for picking the interpreter. The solution is that a `sh`, `bash` or similar interpreter be specified in the shebang, but with arguments that direct it to run this script from its relative path using a specific interpreter.  Shebang lines are entirely ignored if an interpreter is explicitly specified, so this avoids this script accidentally calling itself recursively.

The arguments to this script are:
1. The path to the folder containing the `flake.nix` describing your devShell(s). A relative path is converted to an absolute path without resolving symlinks. Flake identity is a text match on that absolute path, so the same flake reached through a different symlink is a different flake for the purposes of detecting if it has been entered yet.
2. The name of the devShell in the flake to enter. If this is blank it is assumed to be the default devShell (`devShells.<system>.default`). Only that `devShells.<system>.<name>` output is recognized, with `<system>` detected the same way as in `nix-flake-enter`.
3. The interpreter to run once the devShell is the current environment. For example `python3`, `ruby`, `bash`, etc.
4. The first argument to that interpreter. In a shebang this is always `"$0"`, the script being executed.
5. (and all additional arguments) Arguments for the interpreter. In a shebang this is always `"$@"`.

You may call other scripts that use this special shebang from within scripts that also use it, even if they need different flakes and/or devShells. The overhead for entering the devShell is skipped if it's not needed. \
The flake-specific devShells you've already entered are tracked as a call stack in a reserved `__NIX_SHEBANG_STACK` environment variable. The flakes are identified by their absolute path without symlink resolution, so they can only be matched if they aren't accessed via a different symlink. \
There are 3 possibilities for what needs to happen, with the `NIX_SHEBANG_DEVSHELL_MERGE` environment variable controlling how one of the possibilities is handled:
1. The flake+devShell is not in the stack: build and enter it.
2. The flake+devShell is already at the top of the stack: we don't need to re-enter.
3. The flake+devShell is present in the stack, but not at the top of the stack:
   1. If `NIX_SHEBANG_DEVSHELL_MERGE` indicates the flake+devShells between the top and the one we need are "mergeable", we don't need to re-enter.
   2. Otherwise, we re-enter.

`NIX_SHEBANG_DEVSHELL_MERGE` is a comma-separated list of pipe-separated flake+devShells. Each flake+devShell is of the form `${flake_abs_path}#${devShell}`. The default devShell is simplified to just `default`. The flake's absolute path must not have symlinks resolved, and empty comma-separated values are silently ignored, including leading and trailing ones, to make the list easier to generate programmatically. \
Each comma-separated set of pipe-separated flake+devShells is a declaration that those flake+devShells can be entered in any order and will always produce the same effective resulting devShell. In other words, each of them only makes non-overlapping changes. \
The benefit of specifying this when known is that it can significantly reduce the overhead of flake+devShell re-entry when using scripts with shebangs that call each other back and forth between different flakes and/or devShells. A simple example is if `scriptA` and `scriptC` need `${PWD}#devShell1` and `scriptB` needs `${PWD}#devShell2`. If `scriptA` calls `scriptB` which calls `scriptC` you can eliminate re-entering `${PWD}#devShell1` when executing `scriptC` because you already entered it for `scriptA` and overlaying `${PWD}#devShell2` for `scriptB` doesn't conflict with it.


Environment variables:
- All `byo-nix` and `nix-flake-enter` environment variables are passed thru when a devShell is entered. `BYO_NO_LOCK` and `BYO_NIX` still skip the pre-build inside `nix-flake-enter`. When the requested devShell is already in effect, none of that runs, and the interpreter is executed in the current environment.
- `NIX_FLAKE_ENTER_WRAPPER` is the path to `nix-flake-enter`. If this script and `nix-flake-enter` are not in the same folder, set it. The default is `nix-flake-enter` next to this script.
- `NIX_SHEBANG_DEVSHELL_MERGE` is the comma-separated list of mergeable sets described above.
- `__NIX_SHEBANG_STACK` is reserved for the devShell stack. Leave it unset in the environment you start from.

#### `nix-shebang-trampoline` Use Cases

_Put `nix-shebang-trampoline` in the shebang of a script whose interpreter lives in a flake devShell, including when that script may call another script that wants the same devShell or a different one._

These examples assume the three utilities live in a `tools/` directory next to the script, and the flake is in `flake_dir` next to the script. The merge paths are computed the same way this script absolutizes its flake argument, so the text matches.

- As the shebang of a Python script, using the default devShell.

```shell
#!/usr/bin/env -S sh -c '"$(dirname "$0")"/tools/nix-shebang-trampoline "$(dirname "$0")/flake_dir" "" python3 "$0" "$@"'
```

- As the shebang of a Ruby script, using a named devShell.

```shell
#!/usr/bin/env -S sh -c '"$(dirname "$0")"/tools/nix-shebang-trampoline "$(dirname "$0")/flake_dir" "myRubyShell" ruby "$0" "$@"'
```

- As a direct call, using the flake in the current directory to run a command in a named devShell. The interpreter and its first argument are still required.

```shell
./tools/nix-shebang-trampoline . "isolatedPodmanShell" podman info
```

- As the shebang of a shell script whose flake contains only independent devShells, so they may be overlaid in any order.

```shell
#!/usr/bin/env -S sh -c 'NIX_SHEBANG_DEVSHELL_MERGE="${NIX_SHEBANG_DEVSHELL_MERGE},$(cd "$(dirname "$0")/flake_dir" && pwd)" "$(dirname "$0")"/tools/nix-shebang-trampoline "$(dirname "$0")/flake_dir" "" bash "$0" "$@"'
```

- As the shebang of a shell script where every devShell in `flake_a` and `flake_b` is independent of the others, so those two flakes may be overlaid in any order. The script itself uses `flake_a`.

```shell
#!/usr/bin/env -S sh -c 'd=$(dirname "$0"); NIX_SHEBANG_DEVSHELL_MERGE="${NIX_SHEBANG_DEVSHELL_MERGE},$(cd "$d/flake_a" && pwd)|$(cd "$d/flake_b" && pwd)" "$d"/tools/nix-shebang-trampoline "$d/flake_a" "" bash "$0" "$@"'
```

