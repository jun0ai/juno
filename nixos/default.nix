{ config, pkgs, lib, ... }:

let
  cfg = config.services.juno;
  repoPath = "/root/juno-repo";

in {
  options.services.juno = {
    enable = lib.mkEnableOption "Juno autonomous sidekick";

    telegramBotTokenPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to file containing Telegram bot token (bind-mounted)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Clone/update the Juno repo ──
    system.activationScripts.junoRepo = ''
      if [ ! -d ${repoPath}/.git ]; then
        echo "Cloning juno repo..."
        ${pkgs.git}/bin/git clone https://github.com/jun0ai/juno.git ${repoPath}
      fi
    '';

    # ── Symlink config files into /root from the repo ──
    systemd.tmpfiles.rules = [
      "L+ /root/SOUL.md - - - - ${repoPath}/config/SOUL.md"
      "L+ /root/AGENTS.md - - - - ${repoPath}/config/AGENTS.md"
      "L+ /root/.config/opencode/opencode-mem.jsonc - - - - ${repoPath}/config/opencode-mem.jsonc"
      "L+ /root/.config/opencode/skills/nixos/SKILL.md - - - - ${repoPath}/config/skills/nixos/SKILL.md"
      "L+ /root/.config/opencode/skills/find-skills/SKILL.md - - - - ${repoPath}/config/skills/find-skills/SKILL.md"
      "L+ /root/.config/opencode/skills/web-search/SKILL.md - - - - ${repoPath}/config/skills/web-search/SKILL.md"
      "L+ /root/projects/juno-bridge - - - - ${repoPath}/bridge"
    ];

    # ── juno-bridge (Telegram bot) ──
    systemd.services.juno-bridge = {
      description = "Juno Telegram Bridge";
      documentation = [ "https://t.me/jun0aibot" ];
      after = [ "network-online.target" "opencode-server.service" ];
      requires = [ "opencode-server.service" ];
      wantedBy = [ "multi-user.target" ];

      # Ensure deps installed (idempotent)
      preStart = ''
        ${pkgs.bun}/bin/bun install --cwd ${repoPath}/bridge
        printf 'TELEGRAM_BOT_TOKEN=%s\n' "$(tr -d '\n' < ${cfg.telegramBotTokenPath})" > /run/juno-bridge-env
        chmod 600 /run/juno-bridge-env
      '';

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "${repoPath}/bridge";
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
