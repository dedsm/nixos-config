# Herdr: herdr-desktop (`herdr-app`), the GUI app, and herdr-core (`hc`), the
# headless server that runs its terminals and keeps them alive with no window
# open. Solarized from ../theme/solarized.nix, in foot's font; see
# docs/herdr.md.
{
  config,
  lib,
  pkgs,
  self,
  nixpkgs,
  ...
}:
let
  cfg = config.dedsm.herdr;

  # How long herdr-core waits after a person's last keystroke in a terminal
  # before it types anything into it (`hc send`, `hc keys`); upstream's default
  # is 3000 ms. edge-nav forwards ctrl+h/j/k/l into Neovim with `hc keys`, so
  # at 3 s the first move after typing (leaving insert mode, say) stalled for
  # up to three seconds. The pause guards against an agent's input landing in
  # the middle of yours; since herdr-core 0.1.20 a separate draft wait (agent
  # messages hold while unsent text sits at a prompt) covers the worst case,
  # so a short pause loses little. See docs/herdr.md.
  quietMs = "250";

  # The core reads HC_QUIET_MS from its own environment, which is whatever
  # started it: herdr-app (launched from the desktop) or `hc` in a shell. So
  # the app gets it from a wrapper and shells from home.sessionVariables (and,
  # on macOS, from launchd; see launchd.agents.herdr-env below).
  # A wrapper's variables reach every terminal the core starts; this one is
  # harmless there (nixpkgs avoids a wrapper only for LD_LIBRARY_PATH).
  herdrApp = pkgs.symlinkJoin {
    name = "herdr-desktop-${pkgs.unstable.herdr-desktop.version}";
    paths = [ pkgs.unstable.herdr-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/herdr-app --set-default HC_QUIET_MS ${quietMs}
    '';
    inherit (pkgs.unstable.herdr-desktop) meta;
  };

  # ---- Resuming Claude Code after a lost terminal -------------------------
  #
  # When herdr-core loses a terminal (logout, reboot, `hc server stop`), it
  # restarts it as a fresh shell under the same address ($HC_TERMINAL_ID) and
  # in its last folder, but never reruns its program, and it records no agent
  # session. So Claude Code's own hooks record one: which session runs in
  # which terminal, kept when Claude is killed and dropped when it is quit.
  # The restarted shell resumes it. See docs/herdr.md.
  claudeRecords = "\${XDG_STATE_HOME:-$HOME/.local/state}/herdr-claude";
  claudeHookCommand = "~/.local/bin/claude-herdr-session.sh";

  # Claude Code hook: `start` (SessionStart) or `end` (SessionEnd), with the
  # hook's JSON on stdin. Fail-open and silent: it never blocks a session.
  claudeHook = ''
    #!/bin/sh
    [ -n "''${HC_TERMINAL_ID:-}" ] || exit 0
    dir="${claudeRecords}"
    record="$dir/$HC_TERMINAL_ID.json"
    input=$(cat) || exit 0
    session=$(printf '%s' "$input" | ${jq} -r '.session_id // empty' 2>/dev/null)
    [ -n "$session" ] || exit 0

    case "''${1:-}" in
      start)
        # Interactive sessions only (`claude -p` and the SDK set another).
        [ "''${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] || exit 0
        # Only a Claude started at the terminal's own shell, the program
        # herdr-core restarts: that shell's parent is herdr-core's holder. A
        # Claude a script or another Claude starts is left alone.
        claude=''${CLAUDE_PID:-}
        if [ -z "$claude" ]; then
          pid=$PPID
          for _ in 1 2 3 4; do
            case "$(ps -o comm= -p "$pid" 2>/dev/null)" in *claude*) claude=$pid; break ;; esac
            pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
            [ -n "$pid" ] || break
          done
        fi
        [ -n "$claude" ] || exit 0
        shell=$(ps -o ppid= -p "$claude" 2>/dev/null | tr -d ' ')
        holder=$(ps -o ppid= -p "''${shell:-0}" 2>/dev/null | tr -d ' ')
        case "$(ps -o comm= -p "''${holder:-0}" 2>/dev/null)" in *herdr-core) ;; *) exit 0 ;; esac
        mkdir -p "$dir" || exit 0
        printf '%s' "$input" | ${jq} '{session_id, cwd, transcript_path}' > "$record.tmp" \
          && mv "$record.tmp" "$record"
        # Terminals closed with Claude still running leave a record behind.
        find "$dir" -name '*.json' -mtime +30 -delete 2>/dev/null
        ;;
      end)
        # A kill (SIGHUP or SIGTERM as the session or the holder ends) ends a
        # session with reason "other": keep the record. Any other reason is a
        # quit (/exit, ctrl-d, logout) or a switch (/clear, /resume, which
        # record the next session themselves): drop it, if it is still ours.
        [ "$(printf '%s' "$input" | ${jq} -r '.reason // empty')" = other ] && exit 0
        [ "$(${jq} -r '.session_id // empty' "$record" 2>/dev/null)" = "$session" ] && rm -f "$record"
        ;;
    esac
    exit 0
  '';

  # Runs before the first prompt of a terminal's own shell: once, and only
  # where a record says a Claude session was running when the terminal was
  # lost. The record is consumed first, so a resume that fails is not retried
  # by every later shell; the resumed session records itself again.
  claudeResume = ''
    if [[ -n $HC_TERMINAL_ID && -o interactive ]]; then
      _herdr_claude_resume() {
        add-zsh-hook -d precmd _herdr_claude_resume
        unfunction _herdr_claude_resume
        local rec="${claudeRecords}/$HC_TERMINAL_ID.json"
        [[ -f $rec ]] || return 0
        # The terminal's own shell, which herdr-core's holder starts; a zsh
        # run inside it leaves the record for that one.
        [[ $(ps -o comm= -p $PPID 2>/dev/null) == *herdr-core ]] || return 0
        local id cwd transcript
        id=$(${jq} -r '.session_id // empty' $rec 2>/dev/null)
        cwd=$(${jq} -r '.cwd // empty' $rec 2>/dev/null)
        transcript=$(${jq} -r '.transcript_path // empty' $rec 2>/dev/null)
        rm -f $rec
        # A session from another folder can't be resumed here (and the record
        # can't be ours if herdr-core's state was wiped and addresses reused).
        [[ -n $id && -n $cwd && ''${cwd:A} == ''${PWD:A} && -f $transcript ]] || return 0
        print -P "%F{yellow}herdr: resuming the Claude session this terminal had ($id)%f"
        claude --resume $id
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd _herdr_claude_resume
    fi
  '';

  appDir = "${config.xdg.configHome}/herdr-app";
  stateDir = "${config.xdg.stateHome}/herdr-desktop";

  edgeNav = pkgs.local.herdr-app-edge-nav;

  # The edge-nav mod with its options set: stop at the last pane, as
  # vim-tmux-navigator does under tmux, instead of crossing into the next tab
  # or space and wrapping around. Upstream keeps the options as constants at the
  # top of main.js; --replace-fail breaks the build if they are renamed.
  edgeNavMod = pkgs.runCommand "herdr-app-edge-nav-mod" { } ''
    cp -r ${edgeNav}/mods/edge-nav $out
    chmod -R u+w $out
    substituteInPlace $out/main.js \
      --replace-fail 'const TRAVERSE_TABS = true;' 'const TRAVERSE_TABS = false;' \
      --replace-fail 'const TRAVERSE_SPACES = true;' 'const TRAVERSE_SPACES = false;' \
      --replace-fail 'const WRAP = true;' 'const WRAP = false;'
  '';

  # A personal copy of the shipped `main` layout with an edge-nav block in it.
  # The app docks a new mod into the shown layout by itself, but never into
  # a shipped one (`sync_folders` in its src/window.rs skips them), and a key
  # bound to `edge-nav.*` reaches only a docked copy. Generated from the
  # installed version's own main.json on every switch, so it follows upstream
  # changes to `main`, unlike a `layout.clone`, which is frozen. The block goes
  # at the bottom of the `work` column, which has no divider or gap, so at 0px
  # it is invisible; jq -e fails the build if that column is gone.
  navLayoutName = "herdr-nav";
  navLayout =
    pkgs.runCommand "herdr-app-${navLayoutName}.json" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          if any(.children[]; .id == "work" and .type == "column") then
            (.children[] | select(.id == "work") | .children) += [{
              id: "edge-nav", type: "block", size: { px: 0 },
              content: { mod: "edge-nav" }
            }]
          else error("main.json has no work column") end
        ' ${pkgs.unstable.herdr-desktop.src}/defaults/layouts/main.json > $out
      '';

  # ---- Keys ---------------------------------------------------------------
  #
  # herdr-app's own shortcuts (ctrl-shift-*, alt-*, ctrl-1..9; see
  # docs/herdr.md) are prefix-free. The module adds only what they lack.
  #
  # Ctrl+L's byte, for "clear screen" (`send:` types it into the terminal).
  # Nix strings have no \f escape; JSON's decoder supplies it.
  formFeed = builtins.fromJSON ''"\u000c"'';

  # Bindings asserted on every switch. Everything else in keys.json is the
  # app's or the user's.
  managedKeys = {
    global = {
      # Pane movement through edge-nav, whose Neovim half maps whichever
      # chords keys.json binds to it: the chords vim-tmux-navigator uses under
      # tmux, so muscle memory carries over. herdr-app's own alt-h/j/k/l stay
      # bound to plain pane.go.
      "ctrl-h" = "edge-nav.left";
      "ctrl-j" = "edge-nav.down";
      "ctrl-k" = "edge-nav.up";
      "ctrl-l" = "edge-nav.right";
      # ctrl-l above takes the shell's clear screen, and no default gives it
      # back, so tmux's `prefix C-l` survives (with the ctrl-f prefix) as the
      # one key sequence: GPUI holds ctrl-f as pending input for up to a
      # second.
      "ctrl-f ctrl-l" = "send:${formFeed}";
    };
  };

  # The app's shipped keys.json, from the source of the exact version
  # installed. The app compiles it in and writes it out only when keys.json is
  # missing, and keys.json holds every binding (not overrides on top of the
  # defaults), so a file with only managedKeys in it would drop all the rest.
  # macOS builds ship a different set, keys.macos.json (cmd rather than
  # ctrl-shift, plus Mac terminal editing keys; `DEFAULTS` in src/keys.rs).
  # Copied out so the closure holds this one file, not the whole source tree.
  shippedKeysName = if pkgs.stdenv.isDarwin then "keys.macos.json" else "keys.json";
  shippedKeys = pkgs.runCommand "herdr-app-shipped-keys.json" { } ''
    cp ${pkgs.unstable.herdr-desktop.src}/defaults/${shippedKeysName} $out
  '';

  # ---- Settings and look --------------------------------------------------
  #
  # settings.json holds overrides only (an absent key is the default), so it
  # needs no shipped base. The main layout sets no look of its own, so these
  # decide it. Solarized, as a {light, dark} pair that follows the system's
  # appearance, which DMS drives. The font is foot's (InconsolataGo Nerd Font
  # Mono at 12pt); herdr-app sizes in px at zoom 1, and 12pt is 16px at
  # 96 dpi.
  managedSettings = {
    theme = {
      light = "solarized-light";
      dark = "solarized";
    };
    font = "InconsolataGo Nerd Font Mono";
    font_size = 16;
  };

  # The two themes, from the shared Solarized terminal palette (the same one
  # foot uses, so a terminal looks alike in both). herdr-app's theme files
  # take the 16 ANSI colours in order, with `#`.
  terminalPalette = (import ../theme/solarized.nix).terminal;
  themeFrom =
    mode:
    let
      hex = c: "#${c}";
    in
    builtins.toJSON {
      background = hex mode.background;
      foreground = hex mode.foreground;
      cursor = hex mode.cursor;
      selection = hex mode.selection;
      ansi = map hex mode.ansi;
    };
  themes = pkgs.linkFarm "herdr-app-themes" {
    "solarized.json" = pkgs.writeText "solarized.json" (themeFrom terminalPalette.dark);
    "solarized-light.json" = pkgs.writeText "solarized-light.json" (themeFrom terminalPalette.light);
  };

  jq = lib.getExe pkgs.jq;

  # Same approach as the Claude Code settings (docs/claude-code.md): a jq deep
  # merge into the file the app owns, rather than a store symlink. For
  # keys.json the shipped defaults go first, then the existing file, then the
  # managed keys: user changes survive, managed keys are reasserted, and a
  # default shortcut added in a newer release still arrives even though the
  # file is no longer the untouched default the app would refresh itself. The
  # cost is that a deleted default comes back; bind it to "terminal" instead
  # to hand the key to the program.
  mergeJson =
    name: base: managed:
    let
      managedFile = pkgs.writeText "herdr-app-managed-${name}" (builtins.toJSON managed);
    in
    ''
      file=${lib.escapeShellArg appDir}/${name}
      if [ ! -e "$file" ]; then
        ${jq} -s '.[0] * .[1]' ${base} ${managedFile} > "$file.tmp" && mv "$file.tmp" "$file"
      elif ${jq} empty "$file" 2>/dev/null; then
        ${jq} -s '.[0] * .[1] * .[2]' ${base} "$file" ${managedFile} > "$file.tmp" && mv "$file.tmp" "$file"
      else
        # Mid-edit, most likely. The app keeps its last good version meanwhile.
        echo "warning: $file is not valid JSON; the managed ${name} entries were not merged into it" >&2
      fi
    '';

  emptyJson = pkgs.writeText "empty.json" "{}";

  mergeFiles = pkgs.writeShellScript "merge-herdr-app-files" ''
    mkdir -p ${lib.escapeShellArg appDir}
    ${mergeJson "keys.json" shippedKeys managedKeys}
    ${mergeJson "settings.json" emptyJson managedSettings}
  '';

  # Copied, not linked: the app does not hot-reload a symlinked mod folder,
  # and every file here is one it watches. Each is rewritten only when it
  # changed, since an identical rewrite still makes the app reload it.
  installFiles = pkgs.writeShellScript "install-herdr-app-files" ''
    app=${lib.escapeShellArg appDir}
    stamp=${lib.escapeShellArg stateDir}/edge-nav.source

    # The mod folder is this module's alone: replaced whole when it changes.
    if [ "$(cat "$stamp" 2>/dev/null)" != ${edgeNavMod} ] || [ ! -d "$app/mods/edge-nav" ]; then
      mkdir -p "$app/mods" "$(dirname "$stamp")"
      rm -rf "$app/mods/edge-nav.new"
      cp -r ${edgeNavMod} "$app/mods/edge-nav.new"
      chmod -R u+w "$app/mods/edge-nav.new"
      rm -rf "$app/mods/edge-nav"
      mv "$app/mods/edge-nav.new" "$app/mods/edge-nav"
      echo ${edgeNavMod} > "$stamp"
    fi

    mkdir -p "$app/themes"
    for theme in ${themes}/*.json; do
      dest="$app/themes/$(basename "$theme")"
      cmp -s "$theme" "$dest" || install -m644 "$theme" "$dest"
    done

    mkdir -p "$app/layouts"
    dest="$app/layouts/${navLayoutName}.json"
    cmp -s ${navLayout} "$dest" || install -m644 ${navLayout} "$dest"
  '';
in
{
  options.dedsm.herdr.enable = lib.mkEnableOption "Herdr (the herdr-desktop app and herdr-core)";

  config = lib.mkIf cfg.enable {
    # Straight from nixpkgs-unstable, which builds both from source and has
    # them in the binary cache. The app already finds this herdr-core through
    # a path nixpkgs patches in; installing it too puts `hc` on PATH for
    # shells, agents and edge-nav's Neovim half, at the same version.
    home.packages = [
      herdrApp
      pkgs.unstable.herdr-core
    ];

    home.sessionVariables.HC_QUIET_MS = quietMs;

    # On macOS, Herdr.app opened from the Dock or Spotlight runs the bundle's
    # own executable, not the bin/ wrapper, and gets launchd's environment,
    # never a shell's. `launchctl setenv` puts the variable into the GUI
    # session's launchd domain, so the app and every core it starts see it.
    # Run at login and on every activation that changes the agent.
    launchd.agents.herdr-env = {
      enable = pkgs.stdenv.isDarwin;
      config = {
        ProgramArguments = [
          "/bin/launchctl"
          "setenv"
          "HC_QUIET_MS"
          quietMs
        ];
        RunAtLoad = true;
      };
    };

    # edge-nav's Neovim half. It does nothing outside a terminal herdr-desktop
    # shows ($HC_TERMINAL_ID unset), leaving the keys to vim-tmux-navigator.
    programs.neovim.plugins = lib.mkIf config.dedsm.nvim.enable [ edgeNav ];

    # Inside one, both plugins map <C-h/j/k/l> from plugin/, and
    # vim-tmux-navigator loads after edge-nav, so its mappings would win.
    # after/plugin runs once every plugin/ has, so re-running edge-nav's
    # setup() here makes it the last mapping. The nvim module links
    # `config/` recursively and has no `after/`, so this is the only file
    # there.
    xdg.configFile."nvim/after/plugin/herdr-edge-nav.lua" = lib.mkIf config.dedsm.nvim.enable {
      text = ''
        if vim.env.HC_TERMINAL_ID and vim.env.HC_TERMINAL_ID ~= "" then
          local ok, edge_nav = pcall(require, "herdr-app-edge-nav")
          if ok then
            edge_nav.setup()
          end
        end
      '';
    };

    # Resuming Claude Code in a terminal herdr-core restarted (see the let
    # block). The hook is linked under ~/.local/bin/claude-*, which the
    # claude-code merge recognises as its own, so a rebuild replaces its
    # SessionStart entry instead of adding a second one.
    home.file.".local/bin/claude-herdr-session.sh" = lib.mkIf config.dedsm.claude-code.enable {
      executable = true;
      text = claudeHook;
    };
    dedsm.claude-code.extraHooks = lib.mkIf config.dedsm.claude-code.enable {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookCommand} start";
            }
          ];
        }
      ];
      SessionEnd = [
        {
          hooks = [
            {
              type = "command";
              command = "${claudeHookCommand} end";
            }
          ];
        }
      ];
    };
    programs.zsh.initContent = lib.mkIf config.dedsm.claude-code.enable (lib.mkOrder 1500 claudeResume);

    # The hook and zsh resume above are meant to go: herdr-core resumes kept
    # programs through OSC 7577 (herdrdev/herdr-core#429 and #433, on master
    # 2026-11-26, in no release yet), so a SessionStart hook that sends one
    # can replace all of it. This makes sure the switch is looked at.
    assertions =
      let
        # 2026-12-11T00:00:00Z. Pure evaluation has no clock, so "now" is the
        # newer of this repo's last commit and the locked nixpkgs: the build
        # fails on the first commit or `nix flake update` after that date.
        expires = 1796947200;
        now = lib.max self.lastModified nixpkgs.lastModified;
      in
      [
        {
          assertion = !config.dedsm.claude-code.enable || now < expires;
          message = ''
            herdr's Claude Code resume (claude-herdr-session.sh and the zsh
            precmd resume in modules/home/herdr) expired on 2026-12-11. Check
            whether a herdr-core release with OSC 7577 resume (#429/#433) is out
            and in use here; if so, replace both with a hook that sends OSC 7577
            (see docs/herdr.md, "Resuming Claude Code"), or move `expires` on
            deliberately.
          '';
        }
      ];

    # The mod and themes first: keys.json binds edge-nav, and settings.json
    # names the themes, so both should exist when the app reloads those.
    home.activation.herdrDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${installFiles}
      $DRY_RUN_CMD ${mergeFiles}
    '';
  };
}
