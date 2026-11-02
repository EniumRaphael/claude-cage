# claude-cage

[🇫🇷 Français](README.fr.md) · 🇬🇧 English

A Nix flake that runs [Claude Code](https://claude.com/claude-code) inside a sandbox ([bubblewrap](https://github.com/containers/bubblewrap)): Claude can only see and modify your project directory.

## How it works

The flake provides a `claude` command that replaces the usual binary. Instead of launching Claude Code directly, it runs it in a `bwrap` container with:

- **Isolated filesystem**: only `/nix/store` (read-only), a few `/etc` files (`resolv.conf`, `hosts`, `passwd`, `group`, read-only) and the project root (read/write) are visible. Your `$HOME`, SSH keys, other projects, etc. are **inaccessible**.
- **Clean environment** (`--clearenv`): no host environment variable is passed through (tokens, API keys…). Only the necessary variables are set.
- **Network kept**: Claude can reach the Anthropic API (`--share-net`).
- **Sensitive files protected**: `flake.nix`, `flake.lock`, `.envrc`, `.git/hooks` and `.git/config` are mounted **read-only**, so Claude cannot alter the cage itself or install a git hook that would run outside the sandbox.
- **Process tied to its parent** (`--die-with-parent`, `--new-session`): the cage shuts down with your terminal.
- **Fake `$HOME`**: `/home/sandbox` is an empty tmpfs, and so is `/tmp`.

Claude's configuration (login, history, settings) is stored in `~/.local/state/claude-cage` (or `$XDG_STATE_HOME/claude-cage`) and mounted in the cage under `/claude-config`. You only have to log in once, and this configuration is shared across all your projects using claude-cage.

## Requirements

- Linux (`x86_64-linux` or `aarch64-linux`)
- [Nix](https://nixos.org/download) with *flakes* enabled (`experimental-features = nix-command flakes`)
- Unprivileged *user namespaces* must be allowed (the default on most distributions)
- Recommended: [direnv](https://direnv.net/) (and [nix-direnv](https://github.com/nix-community/nix-direnv))

> The `claude-code` package is unfree; the flake explicitly allows it via `allowUnfreePredicate`, so there is nothing to configure.

## Usage

### With direnv (recommended)

The repository already contains an `.envrc`:

```
use flake
```

1. Place `flake.nix` and `flake.lock` (and the `.envrc`) at the root of the project to protect.
2. Allow direnv:
   ```sh
   direnv allow
   ```
3. When you enter the directory, direnv loads the development shell: the cage's `claude` command is put in your `PATH` and the `CLAUDE_CAGE_ROOT` variable is set to the project root.
4. Simply run:
   ```sh
   claude
   ```
   You will see `claude-cage: confined to /path/to/project`.

You can run `claude` from the root **or from any subdirectory** of the project. All arguments are passed to Claude Code (`claude --resume`, `claude -p "..."`, etc.).

### Without direnv

```sh
nix develop      # opens a shell with the confined `claude` command
claude
```

The project root is then the current directory at the time of `nix develop`, so run it from the root.

### From another project, without copying the flake

```sh
nix develop /path/to/claude-cage
```

> `CLAUDE_CAGE_ROOT` is then the current directory at the time of the call.

This flake is designed to be used only through its `devShell`: it is the `shellHook` that sets `CLAUDE_CAGE_ROOT`, which the `claude` command needs. Without it, the command refuses to start.

## Using claude-cage in another project

In the project to protect, create an `.envrc` pointing to this flake:

```
use flake /path/to/claude-cage
```

then run `direnv allow`. The cage root will be that project.

You can also copy `flake.nix`, `flake.lock` and `.envrc` directly into the project: they will then be protected read-only inside the cage.

## Common error messages

| Message | Cause | Fix |
| --- | --- | --- |
| `CLAUDE_CAGE_ROOT is not set` | The flake's shell is not loaded. | Use `direnv allow` or `nix develop`. |
| `current directory is outside the project root` | You are running `claude` outside the project. | `cd` into the project (or one of its subdirectories). |
| `bwrap: No permissions to create new namespace` | User namespaces are disabled. | Enable them (e.g. `sysctl kernel.unprivileged_userns_clone=1` on some distributions). |

## Customization

Everything is configured in `flake.nix`:

- **Protected files**: `protected` list (paths relative to the project root, mounted read-only if they exist).
- **Tools available in the cage**: `binPath` function (default: bash, coreutils, git, ripgrep, grep, sed, find, tar, gzip). Add a package (e.g. `nodejs`, `python3`) if Claude needs it.
- **Environment variables**: add `--setenv NAME value` to the `bwrap` call.
- **Network access**: remove `--share-net` to cut the network entirely (Claude then cannot reach the API: only useful for testing).
- **Supported systems**: `systems` list.

After changing it, reload the environment (`direnv reload` or exit and re-run `nix develop`).

To update nixpkgs (and therefore the Claude Code version):

```sh
nix flake update
```

> `DISABLE_AUTOUPDATER` is enabled: Claude Code does not update itself, its version depends on nixpkgs.

## Limitations

- The sandbox protects the **filesystem** and the **environment**, not the network: Claude can still make outgoing requests.
- Everything in the project root is readable and writable by Claude (except files listed in `protected`), including any `.env` file or secrets stored there.
- The `~/.local/state/claude-cage` directory is shared across all your projects: it contains Claude's login credentials and conversation history.
- This is not an absolute security guarantee: `bubblewrap` provides good isolation, but it is not a virtual machine.
