# CLAUDE.md

## Documentation mandate

**This file, `README.md`, and everything under `docs/` must stay accurate.** Whenever a change touches something they describe — a module moves/renames, a toggle's default changes, a host is added/removed, a script's behavior changes, `lib/nixos-host.nix`'s `mkHost` signature changes, etc. — update the relevant doc **in the same change**, not as follow-up. If a subsystem is significant enough to need explaining and isn't covered by an existing doc, add one under `docs/` and link it from the "Further documentation" section below and from `README.md`. A stale doc is worse than no doc: don't leave one behind.

## Project Overview

This is a **Nix configuration flake** for David's personal systems, supporting both **NixOS (Linux)** and **nix-darwin (macOS)**. Built around Nix Flakes with Home Manager integration. The configuration is designed to be:

- **Declarative**: Every aspect of the system and user environment is specified in code
- **Reproducible**: Flake locks ensure consistent builds across different machines and times
- **Modular**: Organized into reusable, individually-toggleable system and user modules
- **Multi-platform**: Supports both NixOS and Darwin/macOS systems
- **Multi-host ready**: Hardware config and module enablement are per-host, so adding a host doesn't require touching another host's config

### Current Hosts
- **manwe** (NixOS): Framework laptop, `x86_64-linux`, Hyprland
- **morgoth** (Darwin): macOS, `aarch64-darwin`, Aerospace window manager

### Key Technologies
- **NixOS 26.05** / **nix-darwin 26.05** / **Home Manager 26.05**
- **Hyprland**: Wayland compositor (Linux) — the only Linux WM this repo supports (sway was dropped)
- **Aerospace**: Tiling window manager (macOS)
- **Ghostty**: Terminal emulator (macOS)
- **Framework laptop hardware**: Via a `nixos-hardware` module, wired per-host (see "Host Configuration Management" below)
- **Custom overlays**: For packages not in nixpkgs (Slack wrapper, `cli-notify`, `dstask-note`, `vim-herdr-navigation`)

## Architecture Overview

```
flake.nix                # Inputs, host definitions, user-config composition (davidShared/davidNixos/davidDarwin)
├── lib/                 # Utilities for host creation
│   ├── default.nix        # Exports nixosHost and darwinHost
│   ├── nixos-host.nix      # NixOS host builder (mkHost), takes hardwareModules per host
│   └── darwin-host.nix     # Darwin host builder (mkDarwinHost)
├── hosts/                # Per-host hardware configuration
│   └── manwe/
│       └── hardware-configuration.nix
├── modules/              # Modular configuration components
│   ├── common/             # Shared modules (both platforms)
│   │   ├── default.nix       # Home Manager user configuration bridge
│   │   ├── fonts.nix          # Font configuration
│   │   └── users/common/      # Home Manager user modules — tmux, herdr, nvim, zsh, git, hyprland,
│   │                            ghostty, sketchybar, theme, claude-code, playwright, brain skill, ...
│   ├── nixos/               # NixOS system-level modules, each an opt-in dedsm.<name>.enable
│   │   ├── core/               # Always-on baseline (no toggle): networking, fonts, xserver/xkb,
│   │   │                         dbus, xdg portals, audio, home-manager wiring, base packages
│   │   ├── laptop/ performance/ gnome-services/ gnome-programs/
│   │   ├── hyprland/ greetd/ bluetooth/ printing/ scanning/
│   │   └── virtualisation/ onepassword/ gnupg/ peripherals/ fwupd/ ddclient/
│   └── darwin/              # Darwin system-level modules
│       ├── default.nix       # macOS system defaults
│       └── aerospace/         # Aerospace window manager
├── pkgs/                  # Custom package overlays
│   ├── slack/ cli-notify/ dstask-note/ vim-herdr-navigation/
├── docs/                  # Deeper docs for specific subsystems — see "Further documentation"
└── custom/                # Custom scripts and utilities
    └── david/
        └── i3xmonadhelper.py
```

### Key Design Patterns

1. **User Configuration Composition**: User configs are built by composing shared settings:
   - `davidShared`: Base settings for all platforms (git, shell, common packages)
   - `davidNixos`: Linux-specific settings extending `davidShared`
   - `davidDarwin`: macOS-specific settings extending `davidShared`
   - Host-specific overrides applied on top (e.g., `morgothUserConfig`)

2. **Host Builder Pattern**: Hosts are created via builder functions:
   - `nixosHost.mkHost { name, system, systemConfig, userConfigFn, hardwareModules ? [] }` — `hardwareModules` is a list (typically a `nixos-hardware` module + that host's `hosts/<name>/hardware-configuration.nix`), so hardware is never shared across hosts by accident.
   - `darwinHost.mkDarwinHost { name, system, user, systemConfig, userConfigFn }`

3. **Conditional Module Loading**: Both NixOS system modules and Home Manager modules are opt-in, enabled via config flags (`dedsm.<name>.enable` for NixOS/Darwin system modules, `<name>.enable` in the composed user config for Home Manager modules — e.g. `hyprland.enable`, `ghostty.enable`). Only `modules/nixos/core` is unconditional.

4. **Custom Namespace**: System modules use `dedsm.*` options to avoid conflicts with standard NixOS/Darwin options.

5. **Package Overlays**: Custom packages are exposed via `pkgs.local.*`, unstable packages via `pkgs.unstable.*`, unfree packages via `pkgs.unfree.*`.

## Setup Commands

### Darwin/macOS Setup (morgoth)
```bash
# Prerequisites:
# 1. Install upstream nix: https://nix.dev/install-nix.html
# 2. Install intl-altgr layout: https://github.com/carjorvaz/macos-us-altgr-intl
# 3. Install hyperkey: https://hyperkey.app/

# Initial nix-darwin install
sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake .#morgoth

# Subsequent rebuilds
darwin-rebuild switch --flake .#morgoth
```

### NixOS Setup (manwe)
```bash
# Clone the repository
git clone git@github.com:dedsm/nixos-config.git ~/nixos-config
cd ~/nixos-config

# Backup existing system config and create symlink
sudo mv /etc/nixos /etc/nixos.bak
sudo ln -s ~/nixos-config /etc/nixos

# Deploy the configuration
sudo nixos-rebuild switch --flake .#manwe
```

### Regular Operations
```bash
# NixOS rebuild
sudo nixos-rebuild switch --flake .#manwe

# Darwin rebuild
darwin-rebuild switch --flake .#morgoth

# Update flake inputs
nix flake update

# Check flake without building
nix flake check --no-build

# Test configuration before switching (NixOS only)
sudo nixos-rebuild test --flake .#manwe
```

### Development Workflow
```bash
# Format Nix files — `formatter` is declared in flake.nix, so this is the
# authoritative invocation; `nix fmt -- --check .` verifies without writing
nix fmt

# Validate flake structure
nix flake show

# Build specific configuration without activating
nix build .#nixosConfigurations.manwe.config.system.build.toplevel --dry-run
nix build .#darwinConfigurations.morgoth.config.system.build.toplevel --dry-run
```

**Before/after comparisons for a refactor**: if a change is supposed to be behavior-preserving, don't just trust `nix flake check` (it only validates evaluation). Build the real `system.build.toplevel` for the affected host before and after (e.g. via a throwaway `git worktree` for "before") and run `nix store diff-closures <before> <after>` — an empty diff means no package/version changes made it through.

## Code Style & Conventions

### Nix Style Guidelines
- **Format with `nix fmt`** (nixfmt, the RFC 166 standard style — `pkgs.nixfmt`, *not* `nixfmt-classic`). It is the flake's `formatter` output and the `nix` formatter in the Neovim `conform` config, so the editor and the CLI cannot disagree. The repo was formatted with alejandra until the switch; don't reintroduce it
- Prefer explicit imports over `with` statements in module headers
- Use descriptive variable names, especially for `let` bindings
- Comment complex module logic and conditional expressions

### Module Organization
- **NixOS system modules**: Located in `modules/nixos/`, use `dedsm.*` options namespace
- **Darwin system modules**: Located in `modules/darwin/`, use `dedsm.*` options namespace
- **Home Manager modules**: Located in `modules/common/users/common/`
- **Each module**: Should have a clear enable option and sensible defaults — the one exception is `modules/nixos/core`, which is the unconditional baseline every NixOS host gets
- **Module imports**: Use `lib.mkMerge` for combining multiple configurations

### Configuration Patterns
```nix
# System module pattern (NixOS/Darwin)
{ lib, config, pkgs, ... }:
with lib;
let cfg = config.dedsm.mymodule;
in {
  options.dedsm.mymodule = {
    enable = mkOption {
      description = "my module";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # configuration here
  };
}

# Home Manager module pattern
{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.mymodule.enable or false) {
  # home-manager configuration here
}
```

### User Configuration Pattern
```nix
# Composing user configs in flake.nix
davidShared = pkgs: {
  tmux.enable = true;
  git = { enable = true; /* settings */ };
  packages = pkgs: with pkgs; [ /* common packages */ ];
};

davidDarwin = pkgs: (davidShared pkgs) // {
  ghostty.enable = true;
  packages = pkgs: ((davidShared pkgs).packages pkgs) ++ [ /* darwin packages */ ];
};

morgothUserConfig = pkgs: {
  "david.de.sousa" = (davidDarwin pkgs) // {
    # Host-specific overrides
  };
};
```

## Testing Instructions

### Flake Validation
```bash
# Check flake syntax and structure
nix flake check --no-build

# Show flake outputs
nix flake show

# Validate NixOS configuration
nix build .#nixosConfigurations.manwe.config.system.build.toplevel --dry-run

# Validate Darwin configuration
nix build .#darwinConfigurations.morgoth.config.system.build.toplevel --dry-run
```

### System Testing
```bash
# Test NixOS configuration without switching
sudo nixos-rebuild test --flake .#manwe

# Build NixOS configuration without activating
sudo nixos-rebuild build --flake .#manwe

# Check for warnings/errors (Linux)
journalctl -b | grep -i error
```

### Module Testing
- Each system module should have an enable option that defaults to sensible values (except `core`, see above)
- Test modules individually by temporarily enabling/disabling in host config
- Verify Home Manager modules activate properly by checking generated config files in `~/.config/`

## Host Configuration Management

### Adding a New NixOS Host
1. Run `nixos-generate-config` on the target machine, copy the resulting `hardware-configuration.nix` into `hosts/<hostname>/`.
2. Create new `<hostname>SystemConfig` and `<hostname>UserConfig` in `flake.nix`. Define system options (`laptop.enable`, and whichever `dedsm.*` modules the host needs — `hyprland`, `printing`, `bluetooth`, etc. are all opt-in) and `systemUsers`.
3. Add to `nixosConfigurations` using `nixosHost.mkHost`, passing `hardwareModules = [ <matching nixos-hardware module if any> ./hosts/<hostname>/hardware-configuration.nix ]`.
4. Deploy: `sudo nixos-rebuild switch --flake .#<hostname>`.

### Adding a New Darwin Host
1. Create new `<hostname>SystemConfig` and `<hostname>UserConfig` in `flake.nix`
2. Define system options (`aerospace.enable`, etc.)
3. Add to `darwinConfigurations` using `darwinHost.mkDarwinHost`
4. Deploy: `darwin-rebuild switch --flake .#<hostname>`

### Adding a New User
1. Add user to `systemUsers` in host's systemConfig (NixOS) or use `users.users` (Darwin)
2. Create user-specific config function based on `davidShared`, `davidNixos`, or `davidDarwin`
3. Add to host's `userConfigFn`
4. Override/extend packages and module settings as needed

### Module Development
- System modules go in `modules/nixos/` or `modules/darwin/`
- Home Manager modules go in `modules/common/users/common/`
- Use the existing module patterns (enable options, conditional config)
- Test new modules on a single host before generalizing

## Custom Packages

### Package Development
Custom packages are defined in `pkgs/` with an overlay system:

```bash
# Package locations
pkgs/slack/               # Slack wrapper with custom settings
pkgs/cli-notify/          # Native notification helper (used by the claude-code module on Darwin)
pkgs/dstask-note/         # pty-wrapped `dstask note` (bare command silently no-ops without a TTY)
pkgs/vim-herdr-navigation/ # herdr plugin: vim-aware ctrl+h/j/k/l navigation, registered by the herdr module

# Testing custom packages — the `pkgs/` overlay is exposed as the flake's
# `packages` output, filtered per system (cli-notify is Darwin-only)
nix build .#vim-herdr-navigation
nix build .#slack
nix flake show
```

### Updating pinned packages

```bash
scripts/update-packages.sh --list        # what can be updated, and how
scripts/update-packages.sh               # update everything
scripts/update-packages.sh claude-code   # or just one
```

The runner collects two kinds of updater and needs no list of its own for the first:

- **`passthru.updateScript` on a `pkgs/` package** — the nixpkgs convention, discovered
  from the flake's `packages` output. In practice a `nix-update --flake <attr>` invocation
  (`--version=branch` for pins that follow a branch rather than tags). Adding one to a
  package is all that's needed for the runner to pick it up.
- **`scripts/updaters/update-<name>.sh`** — for things that aren't packages in `pkgs/`.
  The directory *is* the registry: any executable script matching that name is discovered
  and exposed as `<name>`. Currently just `claude-code`, whose `version.json` pin (two
  platform hashes, version from a release manifest) is beyond what `nix-update` can rewrite
  — nixpkgs' own `claude-code` uses a bespoke `update.sh` for the same reason.

`MANUAL_ONLY` records anything that deliberately has no updater, with the reason. It is
currently empty — it exists so a package that can't be automated is documented rather than
silently missing.

Two traps worth knowing: a package that *wraps* a nixpkgs package inherits **nixpkgs'**
`updateScript`, which would try to update a nixpkgs checkout — strip it with
`passthru = builtins.removeAttrs (oldAttrs.passthru or { }) [ "updateScript" ];`, as
`pkgs/slack` does. And nothing here runs automatically: review with `git diff`, then rebuild.

### Package Access
- Custom packages: `pkgs.local.slack`, `pkgs.local.vim-herdr-navigation`
- Unstable packages: `pkgs.unstable.spotify`, `pkgs.unstable.vscode`
- Unfree packages: `pkgs.unfree.dropbox`

### Adding New Packages
1. Create package directory in `pkgs/`
2. Write `default.nix` with proper meta attributes
3. If the source is pinned by `rev`/`hash`, add `passthru.updateScript` (see "Updating
   pinned packages" above) so `scripts/update-packages.sh` picks it up — or add it to that
   script's `MANUAL_ONLY` with the reason it can't be automated
4. Add to `pkgs/default.nix` overlay
5. Reference in user packages list via `pkgs.local.<package-name>`

## Security Considerations

- **Login/lock flow**: greetd autologins into Hyprland (`dedsm.greetd.autologinUser`); hyprlock is the actual auth gate (password-only after boot/suspend, fingerprint otherwise) and unlocks gnome-keyring via PAM — see [`docs/login-flow.md`](./docs/login-flow.md)
- **SSH keys**: Managed through Home Manager SSH configuration
- **GPG setup**: Configured for git signing with a specified key ID; agent enablement is opt-in via the `gnupg` NixOS module
- **1Password integration**: CLI + GUI, opt-in via the `onepassword` NixOS module
- **YubiKey / fingerprint / Ledger**: Opt-in via the `peripherals` NixOS module
- **Firmware updates**: Opt-in via the `fwupd` NixOS module
- **Firewall**: Review settings for production use — `core` currently disables it for the trusted-network laptop use case

## Development Environment Tips

### Nix Development
- Use `nix develop` for temporary development environments
- Leverage Home Manager for consistent developer tooling
- Custom packages should include proper `meta` information

### Editor Integration
- Neovim: hand-rolled config (no plugin manager, all plugins declared in Nix), LSP/formatting/linting all Nix-provisioned — see [`docs/nvim.md`](./docs/nvim.md)
- Claude Code: pinned version, managed-but-mergeable settings, hooks, status line, `brain` skill — see [`docs/claude-code.md`](./docs/claude-code.md) and [`docs/brain-skill.md`](./docs/brain-skill.md)
- Playwright MCP: points at a Nix-managed Chromium instead of downloading its own — see [`docs/playwright-mcp.md`](./docs/playwright-mcp.md)

### Debugging
```bash
# Check Nix daemon logs (Linux)
journalctl -u nix-daemon

# Home Manager logs (Linux)
journalctl --user -u home-manager-<username>

# System generation comparison (NixOS)
nix profile diff-closures --profile /nix/var/nix/profiles/system

# Darwin system profile
ls -la /nix/var/nix/profiles/system*
```

## Backup and Recovery

### Configuration Backup
```bash
# Git-based backup (recommended)
git add . && git commit -m "Update configuration"
git push origin main
```

### System Recovery (NixOS)
```bash
# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# List available generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Boot into specific generation
sudo nixos-rebuild switch --switch-generation <generation-number>
```

### System Recovery (Darwin)
```bash
# Rollback to previous generation
darwin-rebuild switch --rollback

# List available generations
ls -la /nix/var/nix/profiles/system-*-link
```

### Git Workflow
- Commit configuration changes before major system updates
- Use descriptive commit messages for tracking changes
- Default branch is `main`
- Consider branching for experimental configurations

## Troubleshooting

### Common Issues
- **Flake evaluation errors**: Check syntax with `nix flake check`
- **Module conflicts**: Verify option namespacing in custom modules
- **Build failures**: Check unfree packages are properly handled
- **Home Manager activation**: Verify user has write access to config directories
- **Darwin rebuild fails**: Ensure nix-daemon is running, try `sudo launchctl kickstart -k system/org.nixos.nix-daemon`

### Performance Tips
- `home-manager.useGlobalPkgs`/`useUserPackages` are set in `modules/nixos/core` for shared package cache
- `nix.settings.auto-optimise-store = true` (NixOS) / `nix.optimise.automatic = true` (Darwin) dedupe the store
- Garbage collection is automatic via `nix.gc` — weekly `--delete-older-than 30d` in `modules/nixos/core` (systemd timer) and in `modules/darwin/default.nix` (launchd, `interval` instead of `dates`). Because home-manager is embedded in the system generation (`useUserPackages`, `enableLegacyProfileManagement` left at its default `false`), pruning system generations reclaims old home closures too — no separate user-context GC is needed. NixOS also caps the boot menu via `boot.loader.systemd-boot.configurationLimit`.
- **Dev shells are not reclaimed by GC while their `.direnv` exists**: `nix-direnv` (`use flake`) registers the devShell closure and its flake inputs as live gcroots under `/nix/var/nix/gcroots/auto/`, which are protected regardless of `--delete-older-than`. They are reclaimed automatically only after the flake input is superseded (on `flake.lock` update + reload) or the `.direnv` is removed. To reclaim a stale project's shell, `rm -rf <project>/.direnv` then let the next GC run
- For a manual sweep you can still run `nix-collect-garbage -d`

### Getting Help
- Check NixOS manual: `nixos-help`
- Home Manager manual: Available online at nix-community/home-manager
- nix-darwin manual: Available online at LnL7/nix-darwin
- Nix language reference: `nix --help` and online documentation

## Further documentation

- [`README.md`](./README.md) — human-facing overview and setup instructions
- [`docs/claude-code.md`](./docs/claude-code.md) — Claude Code package pinning, settings-merge strategy, hooks, status line
- [`docs/playwright-mcp.md`](./docs/playwright-mcp.md) — Playwright MCP browser wiring
- [`docs/nvim.md`](./docs/nvim.md) — Neovim configuration
- [`docs/herdr.md`](./docs/herdr.md) — the `herdr` agent-aware multiplexer: why it coexists with tmux, settings rationale (prefix, vim-aware prefix-free `ctrl+h/j/k/l` pane movement and what it costs, sidebar layout), restart semantics, how plugins are packaged and registered from an activation script (and why every herdr command there is wrapped to warn instead of failing — an out-of-date running server used to abort the whole home-manager activation), and the agent-integration bits deliberately left unmanaged
- [`docs/brain-skill.md`](./docs/brain-skill.md) — the personal "second brain" Claude Code skill
- [`docs/theme.md`](./docs/theme.md) — scheduled dark/light switching: darkman as the **sole** owner of the `color-scheme`/`gtk-theme` dconf keys (and the list of home-manager options that must therefore stay unset), the darkman → dconf → xdg-desktop-portal-gtk → Firefox/Slack chain, the post-`dconfSettings` activation guard, and the Hyprland/foot/tmux transition mechanics
- [`docs/login-flow.md`](./docs/login-flow.md) — greetd autologin, hyprlock as the auth gate, fingerprint policy, gnome-keyring PAM unlock, boot-speed rationale
- [`docs/performance.md`](./docs/performance.md) — the `dedsm.performance` module: sched_ext/`scx_lavd`, ananicy-cpp with CachyOS rules, writeback sysctls sized for 128 GiB, and what was deliberately *not* ported from CachyOS
- [`docs/hibernation.md`](./docs/hibernation.md) — s2idle drain floor on 128 GiB RAM, suspend-then-hibernate settings, why `boot.resumeDevice` must be set explicitly with a systemd initrd, `pm_async=0` resume workaround

Remember the mandate at the top of this file: these all need to stay current.
