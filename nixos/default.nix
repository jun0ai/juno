{ config, pkgs, lib, ... }:

let
  cfg = config.services.juno;
  repoPath = "/root/juno-repo";

  # ── opencode.jsonc ────────────────────
  opencodeJson = pkgs.writeText "opencode.jsonc" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      instructions = [ "/root/AGENTS.md" ];
      plugin = [ "opencode-mem" ];
      permission = {
        "*" = "allow";
        bash = { "*" = "allow"; };
      };
      mcp = {
        searxng = {
          type = "local";
          command = [ "npx" "-y" "mcp-searxng" ];
          environment = { SEARXNG_URL = "http://searxng:8888"; };
          enabled = true;
        };
      };
    }
  );

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
    # ═══════════════════════════════════════
    # Packages
    # ═══════════════════════════════════════
    environment.systemPackages = with pkgs; [
      bun
      curl
      fish
      gcc.cc.lib
      gh
      git
      jq
      nix
      nixd
      nixfmt
      nodejs_24
      opencode
      ripgrep
    ];

    # ═══════════════════════════════════════
    # Nix
    # ═══════════════════════════════════════
    nix.channel.enable = true;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    environment.variables = {
      EDITOR = "nvim";
      SHELL = "${pkgs.fish}/bin/fish";
    };

    # ═══════════════════════════════════════
    # Workspace
    # ═══════════════════════════════════════
    system.activationScripts.junoWorkspace = ''
      mkdir -p /workspace /root/projects
      chmod 0755 /workspace /root/projects
    '';

    # ═══════════════════════════════════════
    # Repo + symlinks
    # ═══════════════════════════════════════
    system.activationScripts.junoRepo = ''
      if [ ! -d ${repoPath}/.git ]; then
        echo "Cloning juno repo..."
        ${pkgs.git}/bin/git clone https://github.com/jun0ai/juno.git ${repoPath}
      fi
    '';

    systemd.tmpfiles.rules = [
      # opencode main config (managed, not agent-editable)
      "L+ /root/.config/opencode/opencode.jsonc - - - - ${opencodeJson}"

      # Agent-editable files — symlinked from live repo clone
      "L+ /root/SOUL.md - - - - ${repoPath}/config/SOUL.md"
      "L+ /root/AGENTS.md - - - - ${repoPath}/config/AGENTS.md"
      "L+ /root/.config/opencode/opencode-mem.jsonc - - - - ${repoPath}/config/opencode-mem.jsonc"
      "L+ /root/.config/opencode/skills/nixos/SKILL.md - - - - ${repoPath}/config/skills/nixos/SKILL.md"
      "L+ /root/.config/opencode/skills/find-skills/SKILL.md - - - - ${repoPath}/config/skills/find-skills/SKILL.md"
      "L+ /root/.config/opencode/skills/web-search/SKILL.md - - - - ${repoPath}/config/skills/web-search/SKILL.md"
      "L+ /root/projects/juno-bridge - - - - ${repoPath}/bridge"
    ];

    # ═══════════════════════════════════════
    # opencode environment
    # ═══════════════════════════════════════
    systemd.services.opencode-env = {
      description = "Provision opencode environment variables";
      before = [ "opencode-server.service" ];
      requiredBy = [ "opencode-server.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        printf "DEEPSEEK_API_KEY=%s\n" "$(cat ${cfg.deepseekApiKeyPath})" > /run/opencode-env
        chmod 600 /run/opencode-env
      '';
    };

    # ═══════════════════════════════════════
    # opencode server
    # ═══════════════════════════════════════
    systemd.services.opencode-server = {
      description = "OpenCode Agent Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "opencode-env.service" ];
      requires = [ "opencode-env.service" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/workspace";
        Environment = [ "HOME=/root" ];
        EnvironmentFile = "/run/opencode-env";
        ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
        Restart = "always";
        RestartSec = "10";
      };
    };

    # ═══════════════════════════════════════
    # juno-bridge (Telegram bot)
    # ═══════════════════════════════════════
    systemd.services.juno-bridge = {
      description = "Juno Telegram Bridge";
      documentation = [ "https://t.me/jun0aibot" ];
      after = [ "network-online.target" "opencode-server.service" ];
      requires = [ "opencode-server.service" ];
      wantedBy = [ "multi-user.target" ];

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

    # ═══════════════════════════════════════
    # Firewall
    # ═══════════════════════════════════════
    networking.firewall.allowedTCPPorts = [
      22     # SSH
      4096   # OpenCode
    ];
  };
}
