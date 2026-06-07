# Juno NixOS Module

Import in your host NixOS config:

```nix
# flake.nix
{
  inputs.juno.url = "github:yourname/juno";  # or local path
  # ...
}

# container config
{ inputs, ... }:
{
  imports = [ inputs.juno.nixosModules.juno ];

  services.juno = {
    enable = true;
    deepseekApiKeyPath = "${opnixSecrets}/deepseekApiKey";
    telegramBotTokenPath = "${opnixSecrets}/telegramBotToken";
  };
}
```

## Files managed by this module

| File | Behavior |
|---|---|
| `~/.config/opencode/opencode.jsonc` | Managed by host (L+ symlink) |
| `~/.config/opencode/opencode-mem.jsonc` | Seeded on first boot, agent-editable |
| `/root/SOUL.md` | Seeded on first boot, agent-editable |
| `/root/AGENTS.md` | Seeded on first boot, agent-editable |
| `~/.config/opencode/skills/*/SKILL.md` | Seeded on first boot, agent-editable |

Editable files use `[ -f ] || write` — never overwritten on rebuild.
