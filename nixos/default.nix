{ config, pkgs, lib, ... }:

let
  cfg = config.services.juno;

  # Source files relative to this module (flake copies them to store)
  soulsMd         = builtins.readFile ../config/SOUL.md;
  agentsMd        = builtins.readFile ../config/AGENTS.md;
  opencodeMemCfg  = builtins.readFile ../config/opencode-mem.jsonc;
  skillNixos      = builtins.readFile ../config/skills/nixos/SKILL.md;
  skillFind       = builtins.readFile ../config/skills/find-skills/SKILL.md;
  skillWebSearch  = builtins.readFile ../config/skills/web-search/SKILL.md;

  # Seed script — only writes files that don't already exist
  seedScript = pkgs.writeShellApplication {
    name = "juno-seed-config";
    text = ''
      seed() { [ -f "$2" ] || printf '%s\n' "$1" > "$2"; }

      seed '${soulsMd}'          /root/SOUL.md
      seed '${agentsMd}'         /root/AGENTS.md
      seed '${opencodeMemCfg}'   /root/.config/opencode/opencode-mem.jsonc

      mkdir -p /root/.config/opencode/skills/nixos
      seed '${skillNixos}'       /root/.config/opencode/skills/nixos/SKILL.md

      mkdir -p /root/.config/opencode/skills/find-skills
      seed '${skillFind}'        /root/.config/opencode/skills/find-skills/SKILL.md

      mkdir -p /root/.config/opencode/skills/web-search
      seed '${skillWebSearch}'   /root/.config/opencode/skills/web-search/SKILL.md
    '';
  };

in {
  options.services.juno = {
    enable = lib.mkEnableOption "Juno autonomous sidekick";

    deepseekApiKeyPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to file containing DeepSeek API key (bind-mounted)";
    };
    telegramBotTokenPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to file containing Telegram bot token (bind-mounted)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Seed mutable config files (first boot only) ──
    systemd.services.juno-seed-config = {
      description = "Seed Juno mutable config files on first boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "opencode-server.service" ];
      serviceConfig.Type = "oneshot";
      script = "${seedScript}/bin/juno-seed-config";
    };

    # ── juno-bridge (Telegram bot) ──
    systemd.services.juno-bridge = {
      description = "Juno Telegram Bridge";
      documentation = [ "https://t.me/jun0aibot" ];
      after = [ "network-online.target" "opencode-server.service" ];
      requires = [ "opencode-server.service" ];
      wantedBy = [ "multi-user.target" ];

      # Read token from bind-mounted secret and create env file
      preStart = ''
        printf 'TELEGRAM_BOT_TOKEN=%s\n' "$(tr -d '\n' < ${cfg.telegramBotTokenPath})" > /run/juno-bridge-env
        chmod 600 /run/juno-bridge-env
      '';

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/root/projects/juno-bridge";
        ExecStart = "${pkgs.bun}/bin/bun run src/index.ts";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "HOME=/root"
          "OPENCODE_URL=http://127.0.0.1:4096"
        ];
        EnvironmentFile = "/run/juno-bridge-env";
      };
    };
  };
}
