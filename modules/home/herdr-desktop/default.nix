# herdr-desktop (`herdr-app`), Herdr's GUI app, and herdr-core (`hc`), the
# headless server that runs its terminals. A trial alongside the terminal
# herdr (modules/home/herdr). Its theme and font are carried over from that
# herdr and foot; see docs/herdr.md, "herdr-desktop (trial)".
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dedsm.herdr-desktop;

  # How long herdr-core waits after a person's last keystroke in a terminal
  # before it types anything into it (`hc send`, `hc keys`); upstream's default
  # is 3000 ms. edge-nav forwards ctrl+h/j/k/l into Neovim with `hc keys`, so
  # at 3 s the first move after typing (leaving insert mode, say) stalled for
  # up to three seconds. The pause guards against an agent's input landing in
  # the middle of yours; herdr-core 0.1.20 adds a separate draft wait (agent
  # messages hold while unsent text sits at a prompt), so a short pause loses
  # little once that version is in nixpkgs. See docs/herdr.md.
  quietMs = "250";

  # The core reads HC_QUIET_MS from its own environment, which is whatever
  # started it: herdr-app (launched from the desktop) or `hc` in a shell. So
  # the app gets it from a wrapper and shells from home.sessionVariables.
  # A wrapper's variables reach every terminal the core starts; this one is
  # harmless there (nixpkgs avoids a wrapper only for LD_LIBRARY_PATH).
  # The terminal herdr's per-pane variables. The core hands its environment
  # to every terminal it starts, so an app launched from inside a terminal
  # herdr pane would have every herdr-desktop shell claim to be that pane
  # (Claude Code's herdr hook reports sessions to HERDR_PANE_ID). Stripped
  # here; a core started by `hc` from such a pane still inherits them.
  herdrPaneVars = [
    "HERDR_ENV"
    "HERDR_PANE_ID"
    "HERDR_TAB_ID"
    "HERDR_WORKSPACE_ID"
    "HERDR_SOCKET_PATH"
    "HERDR_BIN_PATH"
  ];

  herdrApp = pkgs.symlinkJoin {
    name = "herdr-desktop-${pkgs.unstable.herdr-desktop.version}";
    paths = [ pkgs.unstable.herdr-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/herdr-app --set-default HC_QUIET_MS ${quietMs} \
        ${lib.concatMapStringsSep " " (v: "--unset ${v}") herdrPaneVars}
    '';
    inherit (pkgs.unstable.herdr-desktop) meta;
  };

  appDir = "${config.xdg.configHome}/herdr-app";
  stateDir = "${config.xdg.stateHome}/herdr-desktop";

  edgeNav = pkgs.local.herdr-app-edge-nav;

  # The edge-nav mod with its options set: stop at the last pane, as the
  # terminal herdr's navigation does, instead of crossing into the next tab or
  # space and wrapping around. Upstream keeps the options as constants at the
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
  # docs/herdr.md) stand in for the terminal herdr's ctrl+f prefix, which is
  # not carried over. The module adds only what they lack.
  #
  # Ctrl+L's byte, for "clear screen" (`send:` types it into the terminal).
  # Nix strings have no \f escape; JSON's decoder supplies it.
  formFeed = builtins.fromJSON ''"\u000c"'';

  # Bindings asserted on every switch. Everything else in keys.json is the
  # app's or the user's.
  managedKeys = {
    global = {
      # Pane movement through edge-nav, whose Neovim half maps whichever
      # chords keys.json binds to it: the chords tmux and the terminal herdr
      # use, so muscle memory carries over. herdr-app's own alt-h/j/k/l stay
      # bound to plain pane.go.
      "ctrl-h" = "edge-nav.left";
      "ctrl-j" = "edge-nav.down";
      "ctrl-k" = "edge-nav.up";
      "ctrl-l" = "edge-nav.right";
      # ctrl-l above takes the shell's clear screen, and no default gives it
      # back, so the terminal herdr's `prefix+ctrl+l` survives as the one key
      # sequence: GPUI holds ctrl-f as pending input for up to a second.
      "ctrl-f ctrl-l" = "send:${formFeed}";
    };
  };

  # The app's shipped keys.json, from the source of the exact version
  # installed. The app compiles it in and writes it out only when keys.json is
  # missing, and keys.json holds every binding (not overrides on top of the
  # defaults), so a file with only managedKeys in it would drop all the rest.
  # Copied out so the closure holds this one file, not the whole source tree.
  shippedKeys = pkgs.runCommand "herdr-app-shipped-keys.json" { } ''
    cp ${pkgs.unstable.herdr-desktop.src}/defaults/keys.json $out
  '';

  # ---- Settings and look --------------------------------------------------
  #
  # settings.json holds overrides only (an absent key is the default), so it
  # needs no shipped base. The main layout sets no look of its own, so these
  # decide it. The terminal herdr's theme (solarized, auto-switching to
  # solarized-light) becomes a {light, dark} pair that follows the system's
  # appearance, which DMS drives. The font is foot's: herdr ran inside foot
  # (InconsolataGo Nerd Font Mono at 12pt); herdr-app sizes in px at zoom 1,
  # and 12pt is 16px at 96 dpi.
  managedSettings = {
    theme = {
      light = "solarized-light";
      dark = "solarized";
    };
    font = "InconsolataGo Nerd Font Mono";
    font_size = 16;
  };

  # The two themes, built from foot's palettes (modules/home/linux-desktop) so
  # a terminal looks the same in herdr-app as in foot. herdr-app's theme files
  # take the 16 ANSI colours in order: foot's regular0..7, then bright0..7.
  # Selection is the matching base02/base2, which foot leaves to inversion.
  footColors = config.programs.foot.settings;
  themeFrom =
    colors: selection:
    let
      hex = c: "#${c}";
    in
    builtins.toJSON {
      background = hex colors.background;
      foreground = hex colors.foreground;
      cursor = hex (lib.last (lib.splitString " " colors.cursor));
      selection = hex selection;
      ansi =
        map (i: hex colors."regular${toString i}") (lib.range 0 7)
        ++ map (i: hex colors."bright${toString i}") (lib.range 0 7);
    };
  themes = pkgs.linkFarm "herdr-app-themes" {
    "solarized.json" = pkgs.writeText "solarized.json" (themeFrom footColors.colors-dark "073642");
    "solarized-light.json" = pkgs.writeText "solarized-light.json" (
      themeFrom footColors.colors-light "eee8d5"
    );
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
  options.dedsm.herdr-desktop.enable = lib.mkEnableOption "the herdr-desktop app and herdr-core";

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

    # edge-nav's Neovim half. It does nothing outside a terminal herdr-desktop
    # shows. The terminal herdr's navigation file in after/plugin defers to it
    # there (modules/home/herdr).
    programs.neovim.plugins = lib.mkIf config.dedsm.nvim.enable [ edgeNav ];

    # The mod and themes first: keys.json binds edge-nav, and settings.json
    # names the themes, so both should exist when the app reloads those.
    home.activation.herdrDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${installFiles}
      $DRY_RUN_CMD ${mergeFiles}
    '';
  };
}
