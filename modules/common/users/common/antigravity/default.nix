{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  cfg = homeManagerConfig.antigravity or { };
  enable = cfg.enable or false;

  ideEnable = cfg.ide.enable or true;
  cliEnable = cfg.cli.enable or true;
  hubEnable = cfg.hub.enable or true;

  # All three components come from the `antigravity-nix` input (see
  # pkgs/default.nix), not nixpkgs. Linux only: the toggle is set in
  # `davidNixos`, and upstream's macOS derivations are experimental and unpack
  # the DMG into `$out/Applications` with nothing on PATH — so enabling this on
  # Darwin would need work first.
  #
  # The IDE keeps credentials in the desktop keyring, and Electron's
  # autodetection doesn't reliably find it outside a GNOME session. The local
  # package takes no `commandLineArgs` argument the way nixpkgs' Electron
  # packages do, so add the flag by wrapping the wrapper it installs.
  idePkg = pkgs.local.antigravity-ide.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/antigravity-ide --add-flags "--password-store=gnome-libsecret"
    '';
  });

  # Antigravity PreToolUse hook script:
  # 1. Rewrites raw commands with `rtk hook antigravity` for token savings (e.g. `git status` -> `rtk git status`).
  # 2. Transparently wraps commands with `eval "$(${pkgs.unstable.direnv}/bin/direnv export bash)" && `
  #    so per-project devShells (such as Nix flakes with xelatex) are active in agent tool executions.
  antigravityHookScript = pkgs.writeScript "antigravity-pre-tool-use" ''
    #!${pkgs.python3}/bin/python3
    import sys, json, subprocess

    raw = sys.stdin.read()
    if not raw.strip():
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    try:
        payload = json.loads(raw)
    except Exception:
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    cmd = payload.get("toolCall", {}).get("args", {}).get("CommandLine", "")
    if not cmd:
        print(json.dumps({"decision": "allow"}))
        sys.exit(0)

    res = {}
    try:
        proc = subprocess.run(
            ["${pkgs.unstable.rtk}/bin/rtk", "hook", "antigravity"],
            input=raw,
            text=True,
            capture_output=True,
            timeout=5
        )
        if proc.returncode == 0 and proc.stdout.strip():
            res = json.loads(proc.stdout)
    except Exception:
        pass

    rewritten = res.get("overwrite", {}).get("CommandLine") or cmd
    res.setdefault("decision", "allow")

    direnv_bin = "${pkgs.unstable.direnv}/bin/direnv"
    prefix = f'eval "$({direnv_bin} export bash)" && '

    if (
        not rewritten.startswith(prefix)
        and not rewritten.startswith('eval "$(direnv export bash)"')
        and not rewritten.startswith("direnv exec")
    ):
        if "overwrite" not in res:
            res["overwrite"] = {}
        res["overwrite"]["CommandLine"] = f"{prefix}{rewritten}"

    print(json.dumps(res))
  '';

in
lib.mkIf enable {
  home.packages =
    lib.optional hubEnable pkgs.local.antigravity-hub
    ++ lib.optional ideEnable idePkg
    ++ lib.optional cliEnable pkgs.local.antigravity-cli;

  home.file.".gemini/config/plugins/rtk/plugin.json".text = builtins.toJSON {
    name = "rtk";
    version = "1.0.0";
    description = "Antigravity plugin for transparent command rewriting and token optimization using rtk and direnv";
  };

  home.file.".gemini/config/plugins/rtk/hooks.json".text = builtins.toJSON {
    rtk-rewrite = {
      enabled = true;
      PreToolUse = [
        {
          matcher = "run_command";
          hooks = [
            {
              type = "command";
              command = "${antigravityHookScript}";
              timeout = 10;
            }
          ];
        }
      ];
    };
  };

  home.file.".gemini/config/plugins/rtk/rules/AGENTS.md".text = ''
    # Command output

    Command output here is condensed to save tokens, keeping every signal and
    dropping costly noise. Treat it as the complete result: run commands
    normally, and batch related commands into one call to avoid extra turns.
    Truncated results state their recovery path in their own output. Re-run a
    command as `rtk bypass <cmd>` only when its result is unusable: empty when
    output was clearly expected, contradicting its exit code, or garbled.
  '';
}
