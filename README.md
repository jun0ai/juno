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
| `~/.config/opencode/opencode.jsonc` | Symlinked from repo (`config/opencode.jsonc`) |
| `~/.config/opencode/opencode-mem.jsonc` | Symlinked from repo (`config/opencode-mem.jsonc`) |
| `/root/SOUL.md` | Symlinked from repo (`config/SOUL.md`) |
| `/root/AGENTS.md` | Symlinked from repo (`config/AGENTS.md`) |
| `~/.config/opencode/skills/*/SKILL.md` | Symlinked from repo (`config/skills/*/SKILL.md`) |

All files in `config/` are the source of truth. Editing them in the repo and committing/pushing deploys changes on next rebuild.
