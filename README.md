# Bring Your Own Nix

The purpose of this project is to provide tools that can non-persistently bootstrap nix and allow it to be used for a Bring Your Own Tools set of development tools.

## Background

### What is Bring Your Own Tools?

A common issue with development tools is consistency between environments, and the setup and maintenance costs. The historical solution was always to try and automate setup and maintenance of those environments, but solutions like Ansible, Chef, Puppet, Salt, etc bring their own maintenance headaches and often aren't appropriate for an individual developer's system (especially if you're an open source project). Since it's critical that a developer's environment and any CI environment be as close as possible, this usually boils down to a lowest-common-denominator approach. An ultra-minimized set of tools is all that's allowed, ideally limiting to ones that are usually already installed by default on workstations.  
Limiting to tools that are usually already installed on workstations means that most tools end up written in bash script, or even POSIX shell script, which can quickly become a nightmare for any particularly complex toolset. 

In a "Bring Your Own Tool" solution, you instead bring your tools with you. Either you include statically compiled binary versions of tools in your project itself and have your tools reference those (which introduces cross-arch support issues and bloats your project repo quite quickly), or you have your minimal tools get standalone copies of more advanced tools from remote locations (which introduces security and reliability issues).  The latter is preferred from a performance perspective because it ensures only the tools that are actually needed are present, doesn't bloat the git repo unnecessarily, and allows for the possibility of users configuring a system cache location for these tools so they can be shared across a number of related projects or workspaces, but requires an "installation" step to detect if tools are already present and obtain them if not.

### Shebang Tricks

In Linux, the "shebang" line is the line a the start of a file that beings with `#!`. It is a directive to the kernel that tells it what interpreter to use to execute the file. Classically this just serves to set `bash`, POSIX `sh`, `python3`, `ruby`, etc as the interpreter for the script if one isn't manually specified on the command line. More recently advanced shebangs that invoke tools to do both cached bootstrapping of an environment for the script and then execution of the script have been growing, especially in the Python world.  Tools like `pipx` and `uv` now have supported use cases where they're used as the shebang of a python script and inline definitions for the modules that need to be imported are used (PEP 723). The interpreters create a venv and install the dependencies into it before running the body of the script within it (usually caching the venv). 

Other languages have been investigating similar solutions since it allows standaline "scripts" to be supplied to users that have these minimal tools like `pipx` or `uv` installed, and they can simply call the script directly as if it were a bash script.  

The shebang tricks however are not just limited to these special purpose tools, they can be used to invoke any arbitrary script or tool as the "interpreter".  

### Nix and "Bring Your Own Tools"

Nix provides an excellent basis for a Bring Your Own Tool solution because it inhertently manages a global cache of tools and dependencies using a content-addressed store so there are guaranteed to be no conflicts between different tool versions or even different configurations of the same tool version. Using Nix flakes to define the needed environment also come with flake.lock files that pin the environment to ensure reproducibility as well.  

The main negative of Nix is the difficult installation process (all the available installers require extensive hand-holding on any non-trivial system), the onerous system configuration requirements (the nix store must be in `/nix` and cannot be anywhere else), and the opaque specification syntax.

The [nix-portable](https://github.com/DavHau/nix-portable) project provides an excellent solution for the difficult installation and onerous system configuration requirements for cases where a full system install isn't justifiable, with only some minor trade-offs.


## Provides

This project provides 3 utilities as minimal POSIX shell scripts that can be copied, or submoduled into a project.  

### `byo-nix`

This tool is effectively just a wrapper around a `nix` call. It will handle making sure you have a copy of `nix-portable`, and then will run that `nix-portable` tool invoke the `nix` command. This includes locking to ensure obtaining the `nix-portable` tool is safe against multiple parallel calls to the tool.

Arguments to this script are just passed thru to the underlying `nix` command exactly as is.

Configuration of the tool makes use of environment variables:
- `BYO_NIX_PORTABLE_CACHE_ROOT` is a root path to where your `nix-portable` binary should be stored, and where the store is uses should be created. It only applies when the `BYO_NIX_PORTABLE` and/or `BYO_NIX_PORTABLE_STORE` are not absolute paths, and makes it easy to create per-project or per-workspace locations for the tool and store while still using consistent names and folder structure for them in each workspace and project. It defaults to the current directory, but is something you'll very likely override.
- `BYO_NIX_PORTABLE` the path and name of the file to cache the `nix-portable` binary to. If this is a relative path, it's relative to `BYO_NIX_PORTABLE_CACHE_ROOT`. A modifiable `*.lock` file of the same name and location will also need to be able to be created here for managing parallel invocations when no prior cached copy of the tool is present.
- `BYO_NIX_PORTABLE_STORE` is the location of the store `nix-portable` should use. If this is a relative path, it's relative to `BYO_NIX_PORTABLE_CACHE_ROOT`. A modifiable `*.lock` file of the same name as this directory will be created next to it, which is required for managing independent 
- `BYO_NIX_PORTABLE_URL` is the URL to download `nix-portable` from. By default the latest official GitHub Release link is used, but if you wanted to get it from somewhere else, or cache it for your CI systems to use, you can set this to point to that location.
- `BYO_NIX_PORTABLE_DL_CMD` is for when you have non-trivial download requirements for the `BYO_NIX_PORTABLE_URL`. The default is to look for `curl` or `wget` and do a regular download of the URL using the default system settings. If you need to authenticate to a caching server or something more complicated, you can put that into your own script and point to that script with this variable. The script is always passed th `BYO_NIX_PORTABLE_URL` as the first argument, and the absolute path and name of the file it should be downloaded to as the second argument. 
- `BYO_FORCE_DOWNLOAD` can be set (to anything non-blank) if you want to force a download of `nix-portable` to occur. Instead of looking to see if it already exists, the download will always occur and may overwrite an existing file.
- `BYO_NO_LOCK` skips all locking or lockfile creation. This should only be used if an existing `nix-portable` and store associated with a `flake.lock` are all being deployed together via  read-only folder. Creation or updates to the `nix-portable` and store are required to be managed via write locks to ensure parallel calls to `byo-nix` don't simultaneously try to create/modify them.
- `BYO_NIX` This can be set to point to a system-install of `nix`, allowing existing tooling designed primarily for use with `nix-portable` to be used as-is on top of a system-install `nix` instead. The `byo-nix` script effectively turns into just an `exec "$BYO_NIX" "$@"` call when this is set.

**WARNING:** This tool does not perform write locking of the store!  
This script is intended for one-off manual operations on a store that doesn't have any other activity going on, or for more advanced tools to use.  
It is safe to to perform any number of read operations of existing content from a store without needing to lock. And it's even safe to perform writes to the store at the same time reads of preexisting content are happening since the context hash addressing ensures the store objects being read and written won't conflict. It is not safe however to perform multiple actions that write, or actions that might read content that's still being written. A write lock for the store is created by this tool for the purposes of locking the store during writes, but the tool is not capable of detecting every case where a write to the store might occur.  

#### `byo-nix` Use Cases

_Direct use of `byo-nix` should be limited to cases where one-off manual commands are needed on a store that is guaranteed not to otherwise be be in use._

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
byo-nix flake build '.'
```

- Updating a local nix flake's lockfile

```shell
byo-nix flake update '.'
```

### `nix-flake-enter`

Designed for entering a `devShell` of a nix flake using `byo-nix` by calling `nix develop` on it.  This wrapper pre-checks if the devShell environment is already fully built and in the store, and will grab the store write lock and pre-build it if not. 

**WARNING:** `nscd` or `nsncd` daemon are REQUIRED to be present and running on your system!  
With nix, all packages are fully deterministic, which includes its own copy of glibc. That glibc is pretty much guaranteed to differ from the one present on the host system, either in version, toolchain used to build it, or configuration. For a number of system commands/tools however, the nsswitch.conf specifies plugin libraries that should be loaded to extend the normal logic. This includes things like user name lookups for example, and they are not optional on a Linux system. These plugin libraries get dynamically loaded into the glibc, which means they have to exactly match the version, toolchain, etc of the glibc they're used with. This mismatch issue was forseen however, and glibc includes hardcoded support for an `nscd` daemon. The `nscd` daemon accepts glibc requests on a hardcoded socket, and will run those requests using the native glibc and any plugin libraries. This allows a different glibc to effectively front for a host glibc with plugin modules. The original `nscd` daemon supports a number of additional features as well, and presents somewhat of a security risk in system design. Some distros, like Fedora, have chosen to stop including it despite having no alternative solution for this necessary use case. The `nscncd` daemon is a Rust-based rewrite of the minimal glibc functionality from the original `nscd` and is available as a single stand-alone binary. For systems that don't have `nscd` available thru their native package managers anymore, `nsncd` is the preferred alternative. Only one of the two can be present on a system, they both open the specific hardcoded socket name compiled into all versions of glibc, but one of them is explicitly required by this tool since flake devShells can very rarely function properly without.


The arguments to this script are:
1. The path to the folder containing the `flake.nix`. 
2. The name of the devShell in the flake to enter. If this is blank it is assumed to be the default devShell.
3. The command to run in the devShell.
4. (and all additional arguments) Optionally, any additional arguments to pass to the command being run within the devShell

- All `byo-nix` options are passed thru to the underlying `byo-nix`.  A few of the options have additional effects in this script too:
  - `BYO_NO_LOCK` if set, the pre-check and possible pre-build of the devShell is skipped because it's unnecessary if no explicit locking is going to occur. It will rely on the `nix develop` call to do any store updates, which will occur unsafely and unlocked if they are needed.
  - `BYO_NIX` if set, the pre-check and possible pre-build of the devShell is skipped since system nix safely manages it during the `nix develop` call already.
- `BYO_NIX_WRAPPER` If your `byo-nix` script isn't in the same folder as this script, you will need to specify the path to it in this variable.

#### `nix-flake-enter` Use Cases

### `nix-shebang-trampoline`

For use in the shebang of scripts, this wraps `nix-flake-enter` and handles managing when the requested flake devShell is already the current environment or not.  

When using a script like this in the shebang of some tool, it's likely that it might call another tool that also uses this in its shebang. When both those tools are within the same project, there's a very good chance the devShell being requested in both tools is the same one. However it may have called a tool that needs a different devShell instead, and that tool may then call a tool that needs the first devShell back. This leads to an effective stack of nested devShells that need to be tracked to determine if a newly requested devShell is already the one we're in or not, and handling for simply acting as a passthru for the original command when we're already in the correct devShell.

Unfortunately the syntax of shebangs is limited and there's no way to reference a path relative to the calling directory or script the shebang is in for picking the interpreter. The solution is that a `sh`, `bash` or similar interpreter be specified in the shebang, but with arguments that direct it to run this script from its relative path using a specific interpreter.  Shebang lines are entirely ignored if an interpreter is explicitly specified, so this avoids this script accidentally calling itself recurisvely.
