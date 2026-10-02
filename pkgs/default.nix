{
  hyprlandPkgs,
  unstablePkgs,
  antigravityNix,
}:
self: super:
let
  pkgsPath = ./.;

  # Shared arguments for the two Antigravity GUI packages (the 2.0 "hub" app
  # and the legacy IDE), which are the same derivation with a different
  # `appType`.
  antigravityGuiArgs = {
    # The default FHS variant runs the app under bubblewrap, which sets the
    # kernel's no-new-privileges flag and so breaks sudo in the integrated
    # terminal. The non-FHS variant patchelfs the binaries instead, which is
    # also how every other Electron app in this config is built.
    useFHS = false;
    # Don't point the built-in browser agent at the real Chrome profile
    # (`--user-data-dir=$HOME/.config/google-chrome --profile-directory=Default`);
    # let it use its own. Note this does not remove the google-chrome
    # dependency: the wrapper still sets CHROME_BIN, preferring a
    # system-installed google-chrome-stable and falling back to the store one.
    useSystemChromeProfile = false;
  };
in
{
  slack = super.callPackage ./slack { slack = unstablePkgs.slack; };

  cli-notify = super.callPackage ./cli-notify { };

  dstask-note = super.callPackage ./dstask-note { };

  # herdr itself comes from unstable, and the plugin's wrapper has to call the
  # same binary the user runs.
  vim-herdr-navigation = super.callPackage ./vim-herdr-navigation {
    herdr = unstablePkgs.herdr;
  };

  # Google Antigravity, from the `antigravity-nix` input rather than nixpkgs:
  # nixpkgs has no hub package at all (open PR NixOS/nixpkgs#524225) and its
  # antigravity-ide/antigravity-cli trail the upstream releases that input
  # tracks. Built against `unstable`, which is both the nixpkgs the upstream
  # flake is CI-tested against and the only package set here with allowUnfree —
  # every Antigravity artifact is an unfree binary and the GUI packages
  # reference google-chrome.
  #
  # These carry no `passthru.updateScript`: the version pin lives in the
  # input's artifacts/versions.json, so `nix flake update antigravity-nix` is
  # the updater (same as pkgs.local.slack tracking `unstable`).
  antigravity-hub = unstablePkgs.callPackage "${antigravityNix}/pkgs/google-antigravity2.nix" antigravityGuiArgs;
  antigravity-ide = unstablePkgs.callPackage "${antigravityNix}/pkgs/google-antigravity-ide.nix" antigravityGuiArgs;
  antigravity-cli = unstablePkgs.callPackage "${antigravityNix}/pkgs/cli.nix" { };
}
