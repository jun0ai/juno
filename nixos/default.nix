{ config, pkgs, lib, ... }:

let
  cfg = config.services.juno;
  repoPath = "/var/lib/juno";

  opencodeConfig = pkgs.writeText "opencode.jsonc" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      instructions = [ "/root/AGENTS.md" ];
      model = "deepseek/deepseek-v4-pro";
      plugin = [ "opencode-mem" ];
      permission = {
        "*" = "allow";
        bash = { "*" = "allow"; };
      };
      mcp = {
        searxng = {
          type = "local";
          command = [
            "npx"
            "-y"
            "mcp-searxng"
          ];
          environment = {
            SEARXNG_URL = "http://searxng:8888";
          };
          enabled = true;
        };
      };
    }
  );

  opencodeMemConfig = pkgs.writeText "opencode-mem.jsonc" (
    builtins.toJSON {
      storagePath = "~/.opencode-mem/data";
      userEmailOverride = "";
      userNameOverride = "";
      embeddingModel = "Xenova/all-MiniLM-L6-v2";
      webServerEnabled = true;
      webServerPort = 4747;
      webServerHost = "127.0.0.1";
      maxVectorsPerShard = 50000;
      autoCleanupEnabled = true;
      autoCleanupRetentionDays = 30;
      deduplicationEnabled = true;
      deduplicationSimilarityThreshold = 0.90;
      memory.defaultScope = "project";
      opencodeProvider = "deepseek";
      opencodeModel = "deepseek-chat";
      autoCaptureEnabled = true;
      memoryProvider = "openai-chat";
      memoryModel = "deepseek-chat";
      memoryApiUrl = "https://api.deepseek.com/v1";
      memoryApiKey = "env://DEEPSEEK_API_KEY";
      autoCaptureMaxIterations = 5;
      autoCaptureIterationTimeout = 30000;
      aiSessionRetentionDays = 7;
      memoryTemperature = 0.3;
      showAutoCaptureToasts = true;
      showUserProfileToasts = true;
      showErrorToasts = true;
      userProfileAnalysisInterval = 10;
      userProfileMaxPreferences = 20;
      userProfileMaxPatterns = 15;
      userProfileMaxWorkflows = 10;
      userProfileConfidenceDecayDays = 30;
      userProfileChangelogRetentionCount = 5;
      similarityThreshold = 0.6;
      maxMemories = 10;
      injectProfile = true;
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
      LD_LIBRARY_PATH = "${pkgs.gcc.cc.lib}/lib";
    };

    # ═══════════════════════════════════════
    # Workspace
    # ═══════════════════════════════════════
    system.activationScripts.junoWorkspace = ''
      mkdir -p /workspace /root/projects
      chmod 0755 /workspace /root/projects
    '';

    # ═══════════════════════════════════════
    # Repo + auth seeding
    # ═══════════════════════════════════════
    system.activationScripts.junoRepo = ''
      # Clone/update Juno config repo (SOUL.md, AGENTS.md, skills, bridge)
      if [ ! -d ${repoPath}/.git ]; then
        echo "Cloning juno repo..."
        ${pkgs.git}/bin/git clone https://github.com/jun0ai/juno.git ${repoPath}
      fi

      # Seed opencode auth on first boot only (so /connect is never needed)
      if [ ! -f /root/.local/share/opencode/auth.json ]; then
        mkdir -p /root/.local/share/opencode
        cat > /root/.local/share/opencode/auth.json << AEOF
      {
        "deepseek": {
          "type": "api",
          "key": "$(cat ${cfg.deepseekApiKeyPath})"
        }
      }
      AEOF
        chmod 600 /root/.local/share/opencode/auth.json
      fi
    '';

    # ═══════════════════════════════════════
    # File provisioning
    # ═══════════════════════════════════════
    # Static config files are baked into the Nix closure via writeText.
    # Content files (SOUL.md, AGENTS.md, skills, bridge) are symlinked
    # from the git repo so they can evolve independently of nix rebuilds.
    systemd.tmpfiles.rules = [
      # ── Config files (Nix-managed, no git dependency) ──
      "f /root/.config/opencode/opencode.jsonc 0644 root root - ${opencodeConfig}"
      "f /root/.config/opencode/opencode-mem.jsonc 0644 root root - ${opencodeMemConfig}"

      # ── Content from git repo ──
      "L+ /root/SOUL.md - - - - ${repoPath}/config/SOUL.md"
      "L+ /root/AGENTS.md - - - - ${repoPath}/config/AGENTS.md"
      "L+ /root/projects/juno-bridge - - - - ${repoPath}/bridge"
      "L+ /root/.config/opencode/skills/nixos/SKILL.md - - - - ${repoPath}/config/skills/nixos/SKILL.md"
      "L+ /root/.config/opencode/skills/find-skills/SKILL.md - - - - ${repoPath}/config/skills/find-skills/SKILL.md"
      "L+ /root/.config/opencode/skills/web-search/SKILL.md - - - - ${repoPath}/config/skills/web-search/SKILL.md"
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
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/workspace";
        Environment = [
          "HOME=/root"
          "LD_LIBRARY_PATH=${pkgs.gcc.cc.lib}/lib"
        ];
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
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        # Kill any competing bridge on this token (from previous launch)
        ${pkgs.procps}/bin/pkill -f "bun run src/index" 2>/dev/null || true
        sleep 1

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
        EnvironmentFile = "-/run/juno-bridge-env";
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
