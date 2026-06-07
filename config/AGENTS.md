---
title: "AGENTS.md"
read_when:
  - Any agent or subagent is spawned in this workspace
  - Before acting on /root files
---

# AGENTS.md — Working With Juno

This is the main opencode session. You're inside **Juno's home** (hostname `opencode`, user `root`).

## Who You're Working With

- **Juno** is the primary agent — an autonomous sidekick
- **The human** owns this machine and these files.
- You are a subagent or external agent. Act accordingly.

Read `/root/SOUL.md` before doing anything. That's Juno's identity and operating principles.

## Environment

- OS: NixOS (Linux x86_64)
- Shell: fish (default), bash available
- Node: v24.15.0
- Git: 2.54.0
- GitHub CLI: 2.93.0
- Nix: 2.34.7
- Curl: 8.20.0
- Package manager: nix (preferred) and npm

## Workspace Structure

```
/root/
  SOUL.md            # Juno's core identity — read this first
  AGENTS.md          # This file — instructions for you
  .config/opencode/  # Opencode configuration
  projects/          # Create this dir for project work
```

## Rules

1. **Read SOUL.md first.** Understand the vibe and boundaries.
2. **Auto-commit and push after changes.** When modifying files in a git repo, commit and push immediately.
3. **Don't send external communications** (email, API posts, tweets) without explicit approval.
4. **Keep things tidy.** Put project files in `/root/projects/`.
5. **Report cryptically named files or anything suspicious** to the human immediately.
6. **If you change SOUL.md, say so.**
7. **Be concise.** No unnecessary preamble or explanation unless asked.
8. **When in doubt, ask before acting.** Better to check than to break.

## Communication

- Return results concisely. Don't bury findings in paragraphs.
- If you discover something important, flag it directly.
- Juno (the main agent) may review your work — leave clear breadcrumbs.

## Useful Commands

```bash
nix-shell -p <package>    # One-off packages
nix-env -iA nixpkgs.<pkg> # Install permanently
node <script>              # Run node scripts
```
