# nixos-config

David's personal system configuration, as a single Nix flake covering both **NixOS** (Linux) and **nix-darwin** (macOS), with [Home Manager](https://github.com/nix-community/home-manager) for the user environment on both platforms.

- **manwe** — NixOS (`x86_64-linux`), a Framework laptop running Hyprland
- **morgoth** — nix-darwin (`aarch64-darwin`), with Aerospace as the window manager

## Structure

```
flake.nix               # Inputs, host definitions, user-config composition
lib/
├── default.nix          # Exports nixosHost / darwinHost builders
├── nixos-host.nix        # mkHost: assembles a NixOS system from systemConfig + userConfigFn + hardwareModules
└── darwin-host.nix       # mkDarwinHost: same, for nix-darwin

hosts/
└── manwe/
    └── hardware-configuration.nix   # Per-host hardware/disk layout (nixos-generate-config output)

modules/
├── common/               # Home Manager modules, shared across platforms
│   └── users/common/       # tmux, nvim, zsh, git, hyprland, ghostty, sketchybar, claude-code, ...
├── nixos/                 # NixOS system modules (dedsm.<name>.enable toggles)
│   ├── core/                # Always-on baseline: networking, fonts, audio, xdg, base packages
│   ├── laptop/               # Power management, lid/sleep behaviour
│   ├── hyprland/ greetd/ bluetooth/ printing/ scanning/
│   ├── virtualisation/ onepassword/ gnupg/ peripherals/ fwupd/ ddclient/
│   └── gnome-services/ gnome-programs/
└── darwin/                # nix-darwin system modules
    └── aerospace/

pkgs/                    # Custom package overlays (pkgs.local.*)
├── cursor-appimage/       # Cursor AI editor
├── slack/                 # Slack wrapper
├── snyk-ls/                # Snyk Language Server
└── cli-notify/

custom/                  # One-off scripts referenced by modules (e.g. i3xmonadhelper.py)
scripts/                 # Maintenance scripts (update pins, power/sleep diagnostics)
```

Every system module lives under the `dedsm.*` option namespace and follows the same shape:

```nix
{ lib, config, pkgs, ... }:
with lib;
let cfg = config.dedsm.mymodule;
in {
  options.dedsm.mymodule.enable = mkOption { type = types.bool; default = false; };
  config = mkIf cfg.enable { /* ... */ };
}
```

Host-level composition happens in `flake.nix`: `davidShared` holds settings common to every platform, `davidNixos`/`davidDarwin` extend it per-platform, and each host's `<name>UserConfig`/`<name>SystemConfig` extends/overrides on top of that.

## Setup

### Prerequisites (all platforms)

- [Install Nix](https://nix.dev/install-nix.html) with flakes enabled

### NixOS

```bash
git clone git@github.com:dedsm/nixos-config.git ~/nixos-config
cd ~/nixos-config

sudo mv /etc/nixos /etc/nixos.bak
sudo ln -s ~/nixos-config /etc/nixos

sudo nixos-rebuild switch --flake .#manwe
```

### macOS (nix-darwin)

```bash
# Also install the intl-altgr layout (https://github.com/carjorvaz/macos-us-altgr-intl)
# and hyperkey (https://hyperkey.app/) first.

sudo nix --extra-experimental-features "nix-command flakes" \
  run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#morgoth
```

### Everyday use

```bash
sudo nixos-rebuild switch --flake .#manwe     # NixOS
darwin-rebuild switch --flake .#morgoth       # Darwin

nix flake check --no-build                    # Validate without building
nix flake update                              # Bump input pins
```

## Adding a new host

1. Run `nixos-generate-config` on the target machine and copy the resulting `hardware-configuration.nix` into `hosts/<name>/`.
2. Add a `<name>SystemConfig` / `<name>UserConfig` pair in `flake.nix`, composing from `davidShared`/`davidNixos` and turning on whichever `dedsm.*` modules the host needs (`hyprland`, `printing`, `bluetooth`, etc. are all opt-in).
3. Register it under `nixosConfigurations` via `nixosHost.mkHost`, passing `hardwareModules` for that host's disk layout and any matching `nixos-hardware` module — see the `manwe` entry for reference.
4. `sudo nixos-rebuild switch --flake .#<name>`.

## License

MIT — see [LICENSE](./LICENSE).
