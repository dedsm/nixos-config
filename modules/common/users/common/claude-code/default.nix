{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  cfg = homeManagerConfig.claude-code or { };
  enable = cfg.enable or false;
  isDarwin = pkgs.stdenv.isDarwin;

  # Claude Code package with optional version pin via version.json
  # Run ./update-claude-code.sh to fetch the latest version and hashes
  baseClaudeCode = pkgs.unstable.claude-code;
  versionFile = ./version.json;
  hasVersionPin = builtins.pathExists versionFile;
  claudeCodePkg =
    if hasVersionPin then
      let
        pin = lib.importJSON versionFile;
        platformKey = "${if isDarwin then "darwin" else "linux"}-${
          if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
        }";
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

  # `brain` CLI — deterministic frontmatter tooling for the ~/brain store
  # (schema/check/reindex/query + the constrained writers new/set/done). Stdlib
  # Python only, so no dependency wiring; patchShebangs points it at the Nix
  # python3. This binary is the single source of truth for the store schema and
  # the pre-commit gate below; it must only ever change via this repo.
  brainPkg = pkgs.runCommandLocal "brain-cli" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    install -Dm755 ${./skills/brain/brain.py} $out/bin/brain
    patchShebangs $out/bin/brain
  '';

  # The pre-commit gate installed into ~/brain/.git/hooks by the activation
  # script. It regenerates index.md from frontmatter and stages it (so the
  # catalog can never drift in a commit — no reliance on anyone remembering to
  # reindex), then validates the staged pages. All real logic lives in brainPkg,
  # so the hook file itself never needs to change.
  brainPreCommitHook = pkgs.writeShellScript "brain-pre-commit" ''
    ${brainPkg}/bin/brain reindex >/dev/null 2>&1 || true
    ${pkgs.git}/bin/git add -- index.md >/dev/null 2>&1 || true
    exec ${brainPkg}/bin/brain check --staged
  '';

  # === Managed Settings ===
  managedSettings = {
    fileSuggestion = {
      type = "command";
      command = "~/.local/bin/claude-file-suggestion.sh";
    };
    hooks = {
      Stop = [ ];
      Notification = [
        {
          hooks = [
            {
              type = "command";
              command = "~/.local/bin/claude-notify.sh";
            }
          ];
        }
      ];
      UserPromptSubmit = [
        {
          matcher = "*";
          hooks = [
            {
              type = "command";
              command = "~/.local/bin/claude-dismiss-notification.sh";
            }
          ];
        }
      ];
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
  }
  // (cfg.extraSettings or { });

  managedSettingsFile = pkgs.writeText "claude-managed-settings.json" (
    builtins.toJSON managedSettings
  );

  mergeScript = pkgs.writeShellScript "merge-claude-settings" ''
    SETTINGS="$HOME/.claude/settings.json"
    ${mkdir} -p "$HOME/.claude"
    if [ -f "$SETTINGS" ] && ${jq} empty "$SETTINGS" 2>/dev/null; then
      ${jq} -s '.[0] * .[1]' "$SETTINGS" ${managedSettingsFile} > "$SETTINGS.tmp" && ${mv} "$SETTINGS.tmp" "$SETTINGS"
    else
      ${cp} ${managedSettingsFile} "$SETTINGS"
    fi
  '';

in
lib.mkIf enable {
  home.packages = [
    claudeCodePkg
    brainPkg
  ]
  ++ lib.optionals (!isDarwin) [ pkgs.libnotify ];

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

  # Personal "brain" tracking store. We manage exactly three things:
  #   1. the skill + its canonical template (the mechanism and the latest conventions),
  #   2. the `brain` CLI (schema/gate/writers, added to home.packages above), and
  #   3. a one-time bootstrap that seeds ~/brain from the template if it is missing,
  #      plus idempotent (re)installation of the pre-commit gate on every switch.
  # The store's living content (pages, index, log) is mutable user data — never
  # symlinked/managed here. The bootstrap is create-if-missing: it never touches an
  # existing store's content. Existing stores catch up to template changes via
  # `/brain --sync`. The pre-commit hook is refreshed unconditionally so its store
  # path always points at the current brainPkg.
  home.file.".claude/skills/brain/SKILL.md".source = ./skills/brain/SKILL.md;
  home.file.".claude/skills/brain/templates".source = ./skills/brain/templates;

  home.activation.bootstrapBrain = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      brain="$HOME/brain"
      if [ ! -d "$brain" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -R ${./skills/brain/templates}/. "$brain"/
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$brain"
        $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$brain" init -q
      fi
      # Install/refresh the pre-commit gate (points at the Nix-managed brain check).
      if [ -d "$brain/.git" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain/.git/hooks"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m755 ${brainPreCommitHook} "$brain/.git/hooks/pre-commit"
      fi
    '';
  };

  home.activation.mergeClaudeSettings = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      $DRY_RUN_CMD ${mergeScript}
    '';
  };
}
