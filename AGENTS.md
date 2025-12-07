# AGENTS.md

## Project Overview

This is a **Nix configuration flake** for David's personal systems, supporting both **NixOS (Linux)** and **nix-darwin (macOS)**. Built around the modern Nix Flakes architecture with Home Manager integration. The configuration is designed to be:

- **Declarative**: Every aspect of the system and user environment is specified in code
- **Reproducible**: Flake locks ensure consistent builds across different machines and times
- **Modular**: Organized into reusable system and user modules
- **Multi-platform**: Supports both NixOS and Darwin/macOS systems
- **Multi-user/Multi-host ready**: Designed to support different users and systems

### Current Hosts
- **manwe** (NixOS): Framework laptop running x86_64-linux with Hyprland
- **morgoth** (Darwin): MacOS aarch64-darwin with Aerospace window manager

### Key Technologies
- **NixOS 25.11**: Base operating system for Linux hosts
- **nix-darwin 25.11**: macOS system configuration
- **Home Manager 25.11**: User environment and dotfiles management
- **Hyprland**: Wayland compositor (Linux)
- **Aerospace**: Tiling window manager (macOS)
- **Ghostty**: Terminal emulator (macOS)
- **Framework laptop hardware**: Via nixos-hardware module
- **fw-fanctrl**: Fan control for Framework laptops
- **Custom overlays**: For packages not in nixpkgs (Cursor AI, Snyk LSP, Slack wrapper)

## Architecture Overview

```
flake.nix               # Main flake definition with inputs/outputs
├── lib/                # Utilities for host creation
│   ├── default.nix     # Exports nixosHost and darwinHost
│   ├── nixos-host.nix  # NixOS host builder (mkHost)
│   └── darwin-host.nix # Darwin host builder (mkDarwinHost)
├── modules/            # Modular configuration components
│   ├── common/         # Shared modules (both platforms)
│   │   ├── default.nix # Home Manager user configuration bridge
│   │   ├── fonts.nix   # Font configuration
│   │   └── users/common/  # Home Manager user modules
│   │       ├── tmux/
│   │       ├── nvim/
│   │       ├── zsh/
│   │       ├── git/
│   │       ├── hyprland/
│   │       ├── ghostty/
│   │       ├── sketchybar/
│   │       └── ... (many more)
│   ├── nixos/          # NixOS system-level modules
│   │   ├── core/
│   │   ├── defaults/
│   │   ├── laptop/
│   │   ├── gnome-services/
│   │   ├── gnome-programs/
│   │   └── fw-fanctrl/
│   └── darwin/         # Darwin system-level modules
│       ├── default.nix # macOS system defaults
│       └── aerospace/  # Aerospace window manager
├── pkgs/               # Custom package definitions
│   ├── cursor-appimage/
│   ├── snyk-ls/
│   └── slack/
└── custom/             # Custom scripts and utilities
    └── david/
        └── i3xmonadhelper.py
```

### Key Design Patterns

1. **User Configuration Composition**: User configs are built by composing shared settings:
   - `davidShared`: Base settings for all platforms (git, shell, common packages)
   - `davidNixos`: Linux-specific settings extending davidShared
   - `davidDarwin`: macOS-specific settings extending davidShared
   - Host-specific overrides applied on top (e.g., morgothUserConfig)

2. **Host Builder Pattern**: Hosts are created via builder functions:
   - `nixosHost.mkHost { name, system, systemConfig, userConfigFn }`
   - `darwinHost.mkDarwinHost { name, system, user, systemConfig, userConfigFn }`

3. **Conditional Module Loading**: Home Manager modules are conditionally enabled based on user config flags (e.g., `hyprland.enable`, `ghostty.enable`).

4. **Custom Namespace**: System modules use `dedsm.*` options to avoid conflicts with standard NixOS/Darwin options.

5. **Package Overlays**: Custom packages are exposed via `pkgs.local.*` and unstable packages via `pkgs.unstable.*`.

## Setup Commands

### Darwin/macOS Setup (morgoth)
```bash
# Prerequisites:
# 1. Install upstream nix: https://nix.dev/install-nix.html
# 2. Install intl-altgr layout: https://github.com/carjorvaz/macos-us-altgr-intl
# 3. Install hyperkey: https://hyperkey.app/

# Initial nix-darwin install
sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin/nix-darwin-25.11#darwin-rebuild -- switch --flake .#morgoth

# Subsequent rebuilds
darwin-rebuild switch --flake .#morgoth
```

### NixOS Setup (manwe)
```bash
# Clone the repository
git clone <your-repo-url> ~/nixos-config
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
# Format Nix files
nixfmt *.nix **/*.nix

# Validate flake structure
nix flake show

# Build specific configuration without activating
nix build .#nixosConfigurations.manwe.config.system.build.toplevel --dry-run
nix build .#darwinConfigurations.morgoth.config.system.build.toplevel --dry-run
```

## Code Style & Conventions

### Nix Style Guidelines
- Use `nixfmt-rfc-style` for consistent formatting
- Prefer explicit imports over `with` statements in module headers
- Use descriptive variable names, especially for `let` bindings
- Comment complex module logic and conditional expressions

### Module Organization
- **NixOS system modules**: Located in `modules/nixos/`, use `dedsm.*` options namespace
- **Darwin system modules**: Located in `modules/darwin/`, use `dedsm.*` options namespace
- **Home Manager modules**: Located in `modules/common/users/common/`
- **Each module**: Should have a clear enable option and sensible defaults
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
- Each system module should have an enable option that defaults to sensible values
- Test modules individually by temporarily enabling/disabling in host config
- Verify Home Manager modules activate properly by checking generated config files in `~/.config/`

## Host Configuration Management

### Adding a New NixOS Host
1. Create new `<hostname>SystemConfig` and `<hostname>UserConfig` in `flake.nix`
2. Define system options (laptop.enable, etc.) and systemUsers
3. Add to `nixosConfigurations` using `nixosHost.mkHost`
4. Deploy: `sudo nixos-rebuild switch --flake .#new-hostname`

### Adding a New Darwin Host
1. Create new `<hostname>SystemConfig` and `<hostname>UserConfig` in `flake.nix`
2. Define system options (aerospace.enable, etc.)
3. Add to `darwinConfigurations` using `darwinHost.mkDarwinHost`
4. Deploy: `darwin-rebuild switch --flake .#new-hostname`

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
pkgs/cursor-appimage/     # Cursor AI editor AppImage wrapper
pkgs/snyk-ls/             # Snyk Language Server
pkgs/slack/               # Slack wrapper with custom settings

# Testing custom packages
nix build .#cursor-appimage
nix build .#snyk-ls
```

### Package Access
- Custom packages: `pkgs.local.cursor-appimage`, `pkgs.local.slack`
- Unstable packages: `pkgs.unstable.spotify`, `pkgs.unstable.vscode`
- Unfree packages: `pkgs.unfree.dropbox`

### Adding New Packages
1. Create package directory in `pkgs/`
2. Write `default.nix` with proper meta attributes
3. Add to `pkgs/default.nix` overlay
4. Reference in user packages list via `pkgs.local.<package-name>`

## Security Considerations

- **SSH keys**: Managed through Home Manager SSH configuration
- **GPG setup**: Configured for git signing with specified key ID
- **1Password integration**: CLI available in packages
- **Touch ID sudo**: Enabled on Darwin via PAM configuration
- **Firmware updates**: fwupd available for Framework laptop
- **Firewall**: Review settings for production use

## Development Environment Tips

### Nix Development
- Use `nix develop` for temporary development environments
- Leverage Home Manager for consistent developer tooling
- Custom packages should include proper `meta` information

### Editor Integration
- Neovim configuration included with LSP support
- Cursor AI editor available as custom package (Linux)
- LSP servers for Nix, Docker, frontend development included

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
git push origin master
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
- Consider branching for experimental configurations

## Troubleshooting

### Common Issues
- **Flake evaluation errors**: Check syntax with `nix flake check`
- **Module conflicts**: Verify option namespacing in custom modules
- **Build failures**: Check unfree packages are properly handled
- **Home Manager activation**: Verify user has write access to config directories
- **Darwin rebuild fails**: Ensure nix-daemon is running, try `sudo launchctl kickstart -k system/org.nixos.nix-daemon`

### Performance Tips
- Use `home-manager.useGlobalPkgs = true` for shared package cache (enabled by default)
- Enable `nix.settings.auto-optimise-store = true` for disk space
- Regularly run `nix-collect-garbage -d` to clean old generations

### Getting Help
- Check NixOS manual: `nixos-help`
- Home Manager manual: Available online at nix-community/home-manager
- nix-darwin manual: Available online at LnL7/nix-darwin
- Nix language reference: `nix --help` and online documentation
