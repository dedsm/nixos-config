# nixos-config

David's personal system configuration, as a single Nix flake covering both **NixOS** (Linux) and **nix-darwin** (macOS), with [Home Manager](https://github.com/nix-community/home-manager) for the user environment on both platforms.

- **manwe** — NixOS (`x86_64-linux`), a Framework laptop running Hyprland
- **morgoth** — nix-darwin (`aarch64-darwin`), with Aerospace as the window manager

## Structure

```
flake.nix               # Inputs, each host's system config and Home Manager users, outputs
lib/
├── default.nix          # Exports nixosHost / darwinHost builders
├── nixos-host.nix        # mkHost: a NixOS system from the shared modules plus the host's own
├── darwin-host.nix       # mkDarwinHost: same, for nix-darwin
└── pkgs.nix              # mkPkgs: nixpkgs plus the pkgs.unstable/.unfree/.local overlay

hosts/                  # One module per machine: hardware, dedsm toggles, users
├── manwe/
│   ├── default.nix                  # imports its hardware; system toggles, users, Home Manager users
│   └── hardware-configuration.nix   # Disk layout (nixos-generate-config output)
└── morgoth/
    └── default.nix

users/                  # Each user's Home Manager config, as modules layered with `imports`
├── david/                # shared.nix (every host), nixos.nix and darwin.nix (per platform)
└── root.nix

modules/
├── common/               # Used by both NixOS and nix-darwin: fonts, nix registry, Home Manager settings
├── home/                 # Home Manager modules: tmux, herdr, nvim, zsh, hyprland, ghostty, claude-code, ...
├── nixos/                 # NixOS system modules (dedsm.<name>.enable toggles)
│   ├── core/                # Always-on baseline: networking, audio, xdg, base packages
│   ├── laptop/               # Power management, lid/sleep behaviour
│   ├── performance/          # sched_ext scheduler, ananicy, writeback sysctls
│   ├── hyprland/ greetd/ bluetooth/ printing/ scanning/ fingerprint-policy/
│   ├── virtualisation/ onepassword/ gnupg/ peripherals/ fwupd/ ddclient/
│   └── gnome-services/ gnome-programs/
└── darwin/                # nix-darwin system modules
    └── aerospace/

pkgs/                    # Custom package overlays (pkgs.local.*)
├── cli-notify/            # Native notification helper
├── dstask-note/           # pty-wrapped `dstask note`
├── vim-herdr-navigation/  # herdr plugin: vim-aware ctrl+h/j/k/l navigation
├── granola/               # Granola's macOS Electron app, repackaged for Linux (manwe only)
└── default.nix            # The overlay itself

scripts/                 # Maintenance scripts
├── update-packages.sh     # Bump every hand-pinned source (`--list` to see them)
├── updaters/              # Per-thing updaters run by the above (update-<name>.sh)
└── power-summary.sh, sleep-drain-test.sh   # Diagnostics
```

Every module, system or Home Manager, lives under the `dedsm.*` option namespace and follows the same shape:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.dedsm.mymodule;
in {
  options.dedsm.mymodule.enable = lib.mkEnableOption "my module";
  config = lib.mkIf cfg.enable { /* ... */ };
}
```

Each host is a module in `hosts/<name>/default.nix`: it imports its hardware, sets the system modules' `dedsm.*` toggles and its users, and sets `home-manager.users`, where each user is a Home Manager module that imports a layer from `users/` (`users/david/shared.nix` for every host, `nixos.nix`/`darwin.nix` per platform) and adds what is specific to the host. The module system merges the layers, so an override names only what it changes. `flake.nix` only lists the hosts.

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
2. Write `hosts/<name>/default.nix` (start from `hosts/manwe/`): import the hardware file and any matching `nixos-hardware` module, turn on whichever `dedsm.*` system modules the host needs (`hyprland`, `printing`, `bluetooth`, etc. are all opt-in), set `users.users` and `system.stateVersion`, and have each `home-manager.users` entry import a layer from `users/` (e.g. `users/david/nixos.nix`).
3. Register it under `nixosConfigurations` via `nixosHost.mkHost { name; system; modules = [ ./hosts/<name> ]; }` — see the `manwe` entry for reference.
4. `sudo nixos-rebuild switch --flake .#<name>`.

## Documentation

Deeper dives on the more involved pieces live in [`docs/`](./docs/):

- [`docs/claude-code.md`](./docs/claude-code.md) — package pinning, the managed-settings merge strategy, hooks, status line, editor integration
- [`docs/playwright-mcp.md`](./docs/playwright-mcp.md) — how the Playwright MCP server is pointed at a Nix-managed browser instead of downloading its own
- [`docs/antigravity.md`](./docs/antigravity.md) — the Antigravity hub, IDE and `agy` CLI: why they come from nixpkgs again after a spell on a third-party flake input, how nixpkgs builds them, and why macOS doesn't get them
- [`docs/granola.md`](./docs/granola.md) — Granola (macOS/Windows only upstream) running on nixpkgs' Electron: what's patched and why, the native-module rebuild, system-audio capture (it works, via the default output's monitor), what doesn't work on Linux, and how updates are pulled from Granola's own update feed
- [`docs/agent-harness.md`](./docs/agent-harness.md) — rtk (including its PostToolUse output compression), direnv and the `brain` skill wired into Claude Code and Antigravity from one module, switchable per agent, with rtk's instructions generated from the pinned rtk so they can't go stale
- [`docs/nvim.md`](./docs/nvim.md) — the hand-rolled (no plugin manager) Neovim config
- [`docs/herdr.md`](./docs/herdr.md) — the agent-aware terminal multiplexer running alongside tmux: settings rationale, the local patch that lets pane apps (Claude Code's "auto" theme) follow light/dark switches, restart behaviour, why its activation-time commands are best-effort-with-a-warning, and what is deliberately left unmanaged
- [`docs/brain-skill.md`](./docs/brain-skill.md) — the personal "second brain" agent skill (Claude Code + Antigravity) and how its store is bootstrapped/synced
- [`docs/dms.md`](./docs/dms.md) — DankMaterialShell (Dux Shell since 2.0): the bar, notifications, control centre, launcher and lock screen, the screenshot and screen-recording pickers, how it is configured declaratively (a read-only `config.d/` drop-in over a writable `settings.json`), and what not to let it manage
- [`docs/theme.md`](./docs/theme.md) — scheduled dark/light switching, why one owner must have the `color-scheme`/`gtk-theme` dconf keys, and how the mode reaches Firefox/Slack, Hyprland, foot and tmux
- [`docs/login-flow.md`](./docs/login-flow.md) — the DMS greeter as the auth gate, the macOS-modelled fingerprint policy, keyring unlock, boot-speed rationale
- [`docs/hibernation.md`](./docs/hibernation.md) — s2idle drain floor on 128 GiB, suspend-then-hibernate settings, why `boot.resumeDevice` is set explicitly, resume reliability caveats
- [`docs/performance.md`](./docs/performance.md) — desktop responsiveness tuning ported from CachyOS: sched_ext (`scx_lavd`), ananicy-cpp with the CachyOS rule set, writeback sysctls sized for 128 GiB, and what was deliberately left out

**Keep this README and `docs/` up to date.** Whenever a change here alters something they describe — a module moves, a toggle's default changes, a script's behavior changes, a new host or documented subsystem is added — update the relevant doc (or add a new one under `docs/` and link it from here) in the same change. See [`CLAUDE.md`](./CLAUDE.md) for the same rule applied to agent-facing docs.

## License

MIT — see [LICENSE](./LICENSE).
