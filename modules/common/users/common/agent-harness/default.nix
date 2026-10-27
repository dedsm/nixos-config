# Plugins shared across coding-agent harnesses (Claude Code, Antigravity),
# each switchable per harness via `agent-harness.<plugin>.<harness>` in the
# user config. See docs/agent-harness.md.
{
  lib,
  pkgs,
  homeManagerConfig,
  ...
}:
let
  harness = import ./lib.nix { inherit lib pkgs homeManagerConfig; };
  inherit (harness) active rtk;

  claudeEnable = homeManagerConfig.claude-code.enable or false;
  rtkConfigDir = if pkgs.stdenv.isDarwin then "Library/Application Support/rtk" else ".config/rtk";
  antigravityRtk = active.rtk.antigravity;
  antigravityDirenv = active.direnv.antigravity;

  # ~/.claude/CLAUDE.md is the user's own global memory file, so it is never
  # replaced by a store symlink: this only adds the `@RTK.md` import line when
  # rtk is on and removes exactly that line when it is off.
  grep = "${pkgs.gnugrep}/bin/grep";
  claudeMdScript = pkgs.writeShellScript "agent-harness-claude-md" ''
    f="$HOME/.claude/CLAUDE.md"
    if [ -L "$f" ]; then
      echo "agent-harness: $f is a symlink, not touching its @RTK.md import" >&2
      exit 0
    fi
    ${
      if active.rtk.claude-code then
        ''
          ${grep} -qxF '@RTK.md' "$f" 2>/dev/null && exit 0
          ${pkgs.coreutils}/bin/mkdir -p "$HOME/.claude"
          # Don't glue the import onto a last line that lacks its newline.
          if [ -s "$f" ] && [ -n "$(${pkgs.coreutils}/bin/tail -c1 "$f")" ]; then
            echo >> "$f"
          fi
          echo '@RTK.md' >> "$f"
        ''
      else
        ''
          ${grep} -qxF '@RTK.md' "$f" 2>/dev/null || exit 0
          ${grep} -vxF '@RTK.md' "$f" > "$f.tmp" || true
          ${pkgs.coreutils}/bin/mv "$f.tmp" "$f"
        ''
    }
  '';

  antigravityPluginName = if antigravityRtk then "rtk" else "direnv";
  antigravityHook = import ./antigravity-hook.nix {
    inherit pkgs;
    rtkPkg = rtk.package;
    rtk = antigravityRtk;
    direnv = antigravityDirenv;
  };
in
lib.mkMerge [
  (lib.mkIf (lib.any lib.id (lib.attrValues active.rtk)) {
    home.packages = [ rtk.package ];
  })

  # rtk reads its user pipeline from its config dir, which on macOS is
  # ~/Library/Application Support/rtk rather than ~/.config/rtk. Only this one
  # file is linked: config.toml and filters.toml next to it stay writable.
  (lib.mkIf active.rtk-posthook.claude-code {
    home.file."${rtkConfigDir}/pipeline.toml".source = rtk.pipelineFile;
  })

  (lib.mkIf active.rtk.claude-code {
    home.file.".claude/RTK.md".source = "${rtk.agentFiles}/claude-code/RTK.md";
  })

  (lib.mkIf claudeEnable {
    home.activation.agentHarnessClaudeMd = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        $DRY_RUN_CMD ${claudeMdScript}
      '';
    };
  })

  # Antigravity loads every directory under ~/.gemini/config/plugins. The
  # plugin keeps rtk's own name whenever rtk is part of it, which is what
  # `rtk init --agent antigravity` would install and what rtk looks for.
  (lib.mkIf (antigravityRtk || antigravityDirenv) {
    home.file.".gemini/config/plugins/${antigravityPluginName}/plugin.json".text = builtins.toJSON {
      name = antigravityPluginName;
      version = "1.0.0";
      description =
        "Nix-managed agent-harness plugin: "
        + lib.concatStringsSep " and " (
          lib.optional antigravityRtk "rtk command rewriting"
          ++ lib.optional antigravityDirenv "direnv environment loading"
        );
    };

    home.file.".gemini/config/plugins/${antigravityPluginName}/hooks.json".text = builtins.toJSON {
      "${antigravityPluginName}-rewrite" = {
        enabled = true;
        PreToolUse = [
          {
            matcher = "run_command";
            hooks = [
              {
                type = "command";
                command = "${antigravityHook}";
                timeout = 10;
              }
            ];
          }
        ];
      };
    };
  })

  (lib.mkIf antigravityRtk {
    home.file.".gemini/config/plugins/rtk/rules/AGENTS.md".source =
      "${rtk.agentFiles}/antigravity/AGENTS.md";
  })
]
