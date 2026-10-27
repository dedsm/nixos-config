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

  brain = import ./brain.nix { inherit pkgs; };
  brainAnywhere = lib.any lib.id (lib.attrValues active.brain);
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

  # Personal "brain" tracking store. Whichever harness has the skill, we manage
  # exactly three things:
  #   1. the skill + its canonical template (the mechanism and the latest conventions),
  #   2. the `brain` CLI (schema/gate/writers), and
  #   3. a one-time bootstrap that seeds ~/brain from the template if it is missing,
  #      plus idempotent (re)installation of the commit hooks (pre-commit gate +
  #      post-commit auto-push) on every switch — Nix is their sole installer.
  # The store's living content (pages, index, log) is mutable user data — never
  # symlinked/managed here. The bootstrap is create-if-missing: it never touches an
  # existing store's content. Existing stores catch up to template changes via
  # `/brain --sync`. The hooks are refreshed unconditionally so their store paths
  # always point at the current CLI.
  (lib.mkIf brainAnywhere {
    home.packages = [ brain.cli ];

    home.activation.bootstrapBrain = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        brain="$HOME/brain"
        if [ ! -d "$brain" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -R ${brain.skillDir}/templates/. "$brain"/
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$brain"
          $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$brain" init -q
          # Scaffold pages ship with a sentinel date (a static template cannot know
          # the seeding date); normalize restamps them, then record the version so
          # a fresh store isn't reported as behind.
          $DRY_RUN_CMD env BRAIN_DIR="$brain" ${brain.cli}/bin/brain normalize >/dev/null || true
          $DRY_RUN_CMD env BRAIN_DIR="$brain" ${brain.cli}/bin/brain version --stamp >/dev/null || true
        fi
        # Install/refresh the Nix-managed commit hooks: the pre-commit gate
        # (reindex + validate) and the post-commit auto-push (backup + sync).
        if [ -d "$brain/.git" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain/.git/hooks"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m755 ${brain.preCommitHook} "$brain/.git/hooks/pre-commit"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m755 ${brain.postCommitHook} "$brain/.git/hooks/post-commit"
        fi
      '';
    };
  })

  # Weekly `brain health` notification — the ambient half of the surfacing
  # story: the SessionStart hooks cover sessions, this covers the days when
  # none happen. optionalAttrs rather than mkIf: each platform lacks the
  # other's option.
  (lib.mkIf brainAnywhere (
    lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
      systemd.user.services.brain-health = {
        Unit.Description = "brain store health check";
        Service = {
          Type = "oneshot";
          ExecStart = "${brain.healthNotify}";
        };
      };
      systemd.user.timers.brain-health = {
        Unit.Description = "weekly brain store health notification";
        Timer = {
          OnCalendar = "Mon 10:00";
          Persistent = true; # laptop: fire on next wake if the slot was missed
        };
        Install.WantedBy = [ "timers.target" ];
      };
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      launchd.agents.brain-health = {
        enable = true;
        config = {
          ProgramArguments = [ "${brain.healthNotify}" ];
          StartCalendarInterval = [
            {
              Weekday = 1;
              Hour = 10;
              Minute = 0;
            }
          ];
        };
      };
    }
  ))

  # Claude Code: the skill under ~/.claude/skills, and the health hook at the
  # stable path the claude-code module's SessionStart merge keys on (lib.nix).
  (lib.mkIf active.brain.claude-code {
    home.file.".claude/skills/brain/SKILL.md".source = "${brain.skillDir}/SKILL.md";
    home.file.".claude/skills/brain/templates".source = "${brain.skillDir}/templates";
    home.file.".local/bin/claude-brain-health.sh".source = brain.claudeHealthHook;
  })

  # Antigravity: a plugin rather than a loose ~/.gemini/config/skills entry, so
  # the skill and its health hook switch on and off together.
  (lib.mkIf active.brain.antigravity {
    home.file.".gemini/config/plugins/brain/plugin.json".text = builtins.toJSON {
      name = "brain";
      version = "1.0.0";
      description = "Nix-managed agent-harness plugin: the ~/brain personal tracking store skill and its session-start health line";
    };

    home.file.".gemini/config/plugins/brain/skills/brain/SKILL.md".source =
      "${brain.skillDir}/SKILL.md";
    home.file.".gemini/config/plugins/brain/skills/brain/templates".source =
      "${brain.skillDir}/templates";

    home.file.".gemini/config/plugins/brain/hooks.json".text = builtins.toJSON {
      brain-health = {
        enabled = true;
        SessionStart = [
          {
            type = "command";
            command = "${brain.antigravityHealthHook}";
            timeout = 15;
          }
        ];
      };
    };
  })
]
