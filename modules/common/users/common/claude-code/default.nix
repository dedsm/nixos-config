{ lib, homeManagerConfig, pkgs, ... }:
let
  cfg = homeManagerConfig.claude-code or {};
  enable = cfg.enable or false;
  isDarwin = pkgs.stdenv.isDarwin;

  # === Headroom context-compression proxy (opt-in) ===
  # When enabled we (1) install the headroom binary, (2) run the proxy as a
  # persistent per-user service (systemd on Linux, launchd on macOS), and
  # (3) point Claude Code at it via settings.json env — so plain `claude`
  # routes through the proxy with no `headroom wrap` needed.
  headroomCfg = cfg.headroom or {};
  headroomEnable = headroomCfg.enable or false;
  headroomPort = toString (headroomCfg.port or 8787);
  headroomMode = headroomCfg.mode or "cache"; # cache = preserve prompt-cache prefix (right for subscriptions)
  headroomOutputShaper = headroomCfg.outputShaper or true;
  headroomBaseUrl = "http://127.0.0.1:${headroomPort}";
  headroomProxyArgs = [ "proxy" "--no-telemetry" "--mode" headroomMode "--port" headroomPort ];

  # Claude Code package with optional version pin via version.json
  # Run ./update-claude-code.sh to fetch the latest version and hashes
  baseClaudeCode = pkgs.unstable.claude-code;
  versionFile = ./version.json;
  hasVersionPin = builtins.pathExists versionFile;
  claudeCodePkg =
    if hasVersionPin then
      let
        pin = lib.importJSON versionFile;
        platformKey = "${if isDarwin then "darwin" else "linux"}-${if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64"}";
      in
      baseClaudeCode.overrideAttrs (old: rec {
        version = pin.version;
        src = pkgs.fetchurl {
          url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platformKey}/claude";
          sha256 = pin.platforms.${platformKey};
        };
      })
    else
      baseClaudeCode;

  # Nix store paths for commands used only in this file
  jq = "${pkgs.jq}/bin/jq";
  mv = "${pkgs.coreutils}/bin/mv";
  cp = "${pkgs.coreutils}/bin/cp";
  mkdir = "${pkgs.coreutils}/bin/mkdir";

  # Import script modules
  claudeIcon = import ./icon.nix { inherit pkgs; };
  iconPath = if isDarwin then claudeIcon.pngPath else claudeIcon.svgPath;

  fileSuggestionScript = import ./file-suggestion.nix { inherit pkgs; };
  notifyScriptDefault = import ./notify.nix { inherit pkgs isDarwin iconPath; };
  dismissScriptDefault = import ./dismiss.nix { inherit pkgs isDarwin; };
  statusLineScript = import ./statusline.nix { inherit pkgs; };

  notifyScript = cfg.notifyScript or notifyScriptDefault;
  dismissScript = cfg.dismissScript or dismissScriptDefault;

  # === Managed Settings ===
  managedSettings = {
    fileSuggestion = {
      type = "command";
      command = "~/.local/bin/claude-file-suggestion.sh";
    };
    hooks = {
      Stop = [];
      Notification = [{
        hooks = [{
          type = "command";
          command = "~/.local/bin/claude-notify.sh";
        }];
      }];
      UserPromptSubmit = [{
        matcher = "*";
        hooks = [{
          type = "command";
          command = "~/.local/bin/claude-dismiss-notification.sh";
        }];
      }];
    };
    statusLine = {
      type = "command";
      command = "~/.local/bin/claude-statusline.sh";
    };
    alwaysThinkingEnabled = true;
    attribution = {
      commit = "";
      pr = "";
    };
  } // (lib.optionalAttrs headroomEnable {
    # Route all Anthropic API calls through the headroom proxy. ENABLE_TOOL_SEARCH
    # keeps Claude Code's tool deferral on behind the proxy. This is what `headroom
    # init` would persist imperatively — done declaratively here instead.
    env = {
      ANTHROPIC_BASE_URL = headroomBaseUrl;
      ENABLE_TOOL_SEARCH = "true";
    };
  }) // (cfg.extraSettings or {});

  managedSettingsFile = pkgs.writeText "claude-managed-settings.json" (builtins.toJSON managedSettings);

  mergeScript = pkgs.writeShellScript "merge-claude-settings" ''
    SETTINGS="$HOME/.claude/settings.json"
    ${mkdir} -p "$HOME/.claude"
    if [ -f "$SETTINGS" ] && ${jq} empty "$SETTINGS" 2>/dev/null; then
      ${jq} -s '.[0] * .[1]' "$SETTINGS" ${managedSettingsFile} > "$SETTINGS.tmp" && ${mv} "$SETTINGS.tmp" "$SETTINGS"
    else
      ${cp} ${managedSettingsFile} "$SETTINGS"
    fi
  '';

  # User-scope MCP fragment merged into ~/.claude.json so `headroom_retrieve`
  # is available in every Claude session on this machine (not just this repo).
  # Absolute store path so Claude can spawn it regardless of its own PATH; the
  # merge below rewrites it on each rebuild, so upgrades are self-healing.
  managedMcp = {
    mcpServers.headroom = {
      command = "${pkgs.local.headroom}/bin/headroom";
      args = [ "mcp" "serve" ];
    };
  };
  managedMcpFile = pkgs.writeText "claude-managed-mcp.json" (builtins.toJSON managedMcp);

  # Deep-merge just our mcpServers.headroom entry into ~/.claude.json without
  # clobbering the file's other runtime state (or the user's own MCP servers).
  mergeMcpScript = pkgs.writeShellScript "merge-claude-mcp" ''
    CFG="$HOME/.claude.json"
    if [ -f "$CFG" ] && ${jq} empty "$CFG" 2>/dev/null; then
      ${jq} -s '.[0] * .[1]' "$CFG" ${managedMcpFile} > "$CFG.tmp" && ${mv} "$CFG.tmp" "$CFG"
    else
      ${cp} ${managedMcpFile} "$CFG"
    fi
  '';

in
lib.mkIf enable {
  home.packages =
    [ claudeCodePkg ]
    ++ lib.optionals (!isDarwin) [ pkgs.libnotify ]
    ++ lib.optionals headroomEnable [ pkgs.local.headroom ];

  home.file.".local/bin/claude-file-suggestion.sh" = {
    executable = true;
    text = fileSuggestionScript;
  };

  home.file.".local/bin/claude-notify.sh" = {
    executable = true;
    text = notifyScript;
  };

  home.file.".local/bin/claude-statusline.sh" = {
    executable = true;
    text = statusLineScript;
  };

  home.file.".local/bin/claude-dismiss-notification.sh" = {
    executable = true;
    text = dismissScript;
  };

  # Personal "brain" tracking store. We manage exactly two things:
  #   1. the skill + its canonical template (the mechanism and the latest conventions), and
  #   2. a one-time bootstrap that seeds ~/brain from the template if it is missing.
  # The store's living content (pages, index, log) is mutable user data — never
  # symlinked/managed here. The bootstrap is create-if-missing: it never touches an
  # existing store. Existing stores catch up to template changes via `/brain --sync`.
  home.file.".claude/skills/brain/SKILL.md".source = ./skills/brain/SKILL.md;
  home.file.".claude/skills/brain/templates".source = ./skills/brain/templates;

  home.activation.bootstrapBrain = {
    after = ["writeBoundary"];
    before = [];
    data = ''
      brain="$HOME/brain"
      if [ ! -d "$brain" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -R ${./skills/brain/templates}/. "$brain"/
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$brain"
        $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$brain" init -q
      fi
    '';
  };

  home.activation.mergeClaudeSettings = {
    after = ["writeBoundary"];
    before = [];
    data = ''
      $DRY_RUN_CMD ${mergeScript}
    '';
  };

  # Register the headroom MCP server globally (user scope) when headroom is on.
  home.activation.mergeClaudeMcp = lib.mkIf headroomEnable {
    after = ["writeBoundary"];
    before = [];
    data = ''
      $DRY_RUN_CMD ${mergeMcpScript}
    '';
  };

  # Persistent headroom proxy — Linux (systemd user service).
  systemd.user.services = lib.mkIf (headroomEnable && !isDarwin) {
    headroom-proxy = {
      Unit = {
        Description = "Headroom context-compression proxy for Claude Code";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = "${pkgs.local.headroom}/bin/headroom ${lib.concatStringsSep " " headroomProxyArgs}";
        Environment = lib.optionals headroomOutputShaper [ "HEADROOM_OUTPUT_SHAPER=1" ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  # Persistent headroom proxy — macOS (launchd user agent).
  launchd.agents = lib.mkIf (headroomEnable && isDarwin) {
    headroom-proxy = {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.local.headroom}/bin/headroom" ] ++ headroomProxyArgs;
        EnvironmentVariables = lib.optionalAttrs headroomOutputShaper {
          HEADROOM_OUTPUT_SHAPER = "1";
        };
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/headroom-proxy.log";
        StandardErrorPath = "/tmp/headroom-proxy.log";
      };
    };
  };
}
