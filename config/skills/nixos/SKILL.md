---
name: nixos
description: NixOS system knowledge — nix-shell ephemeral environments, nix-env persistent installs, package search, shell.nix dev environments, Nix language patterns, and container constraints. Use when the agent needs to install tools, create dev environments, or interact with NixOS/Nix.
---

# NixOS / Nix Skill

This skill covers how to work with NixOS as a container/VM where you don't control the system-level configuration. Focus on user-level and ephemeral tooling.

## Environment Constraints

- This is a NixOS container. You do NOT own `/etc/nixos/configuration.nix`.
- Can't run `nixos-rebuild`. System changes require the parent host admin.
- YOU CAN use `nix-shell`, `nix-env`, `nix profile`, and `nix run`.

## Ephemeral Packages (Preferred)

Use `nix-shell -p` for throwaway tool access. No install — disappears when the shell exits.

```bash
# Single package, single command
nix-shell -p bun --run "bun run script.ts"
nix-shell -p python3 --run "python -c 'print(42)'"
nix-shell -p nodejs_24 --run "node script.js"
nix-shell -p gh --run "gh pr list"

# Interactive shell (exit when done)
nix-shell -p bun nodejs_24
```

### Bun (JavaScript/TypeScript Runtime)

Bun is NOT installed on the system. Always use nix-shell:

```bash
# Run a script
nix-shell -p bun --run "bun run file.ts"

# Install dependencies + run
nix-shell -p bun --run "cd /path/to/project && bun install && bun run dev"

# For persistent work (interactive)
nix-shell -p bun
# then: bun run file.ts
```

**IMPORTANT: NEVER use `node`, `npm`, or `npx` directly. Always spawn bun via nix-shell.**
**Exception: `npx skills` for the skills.sh CLI is fine since it's a one-off npm package runner.**

## Persistent Installs (When Needed)

Use `nix-env` for tools needed across sessions:

```bash
nix-env -iA nixpkgs.bun          # Install bun permanently
nix-env -iA nixpkgs.ripgrep      # Install ripgrep
nix-env -e bun                    # Remove
nix-env -q                        # List installed
```

Use `nix profile` (newer, preferred):

```bash
nix profile install nixpkgs#bun
nix profile list
nix profile remove bun
```

## Package Search

```bash
nix search nixpkgs <term>        # CLI search
https://search.nixos.org/packages # Web search (better UX)
```

Common packages:
- `nodejs_24` — Node.js 24.x
- `bun` — Bun runtime
- `python3` — Python 3
- `gh` — GitHub CLI
- `ripgrep` (rg) — Fast grep
- `git` — Git
- `fish` — Fish shell
- `caddy` / `nginx` — Reverse proxies

## Dev Environments with shell.nix

For projects needing a reproducible environment, create `shell.nix`:

```nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    bun
    nodejs_24
    git
  ];
  shellHook = ''
    echo "Dev environment ready. bun $(bun --version)"
  '';
}
```

Then:
```bash
nix-shell           # Enter the environment
nix-shell --run "bun run dev"
```

## Nix Language Basics (for reading/editing .nix files)

```nix
# Function with default argument
{ pkgs ? import <nixpkgs> {} }:

# Let bindings
let
  foo = "bar";
in ...

# With expressions
with pkgs; [ git bun nodejs ]

# Lists
[ pkg1 pkg2 pkg3 ]

# Attribute sets
{ name = "value"; another = 123; }

# Inherit (bring into scope)
inherit (pkgs) bun nodejs;
```

## Key NixOS Concepts

- **Declarative** — Everything defined in config files, not imperative commands
- **Generations** — Every system change creates a generation you can roll back to
- **Channels** — NixOS release channels (nixos-24.11, nixos-unstable, etc.)
- **Store** — Everything lives under `/nix/store/` with content-addressed paths
- **Garbage collection** — `nix-collect-garbage` to free space

## Common Patterns on This Machine

```bash
# Get bun for one command
nix-shell -p bun --run "bun run script.ts"

# Install a tool permanently
nix profile install nixpkgs#bun

# Check what's available
nix search nixpkgs <package-name>

# One-off package (no install)
nix run nixpkgs#cowsay -- "hello"
```
