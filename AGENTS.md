# AGENTS.md

## Project Overview

This is a **NixOS configuration flake** for David's personal NixOS systems, built around the modern Nix Flakes architecture with Home Manager integration. The configuration is designed to be:

- **Declarative**: Every aspect of the system and user environment is specified in code
- **Reproducible**: Flake locks ensure consistent builds across different machines and times
- **Modular**: Organized into reusable system and user modules
- **Multi-user/Multi-host ready**: Designed to support different users and systems (currently "manwe" host with "david" user)

### Key Technologies
- **NixOS 25.05**: Base operating system with flakes enabled
- **Home Manager 25.05**: User environment and dotfiles management
- **Hyprland**: Wayland compositor (primary) with Sway as alternative
- **Custom overlays**: For packages not in nixpkgs (Cursor AI, Snyk LSP)

## Architecture Overview

```
flake.nix               # Main flake definition with inputs/outputs
├── lib/                # Utilities for host creation
├── modules/            # Modular configuration components
│   ├── system/         # NixOS system-level modules
│   └── home-manager/   # User environment modules
├── pkgs/               # Custom package definitions
└── custom/             # Custom scripts and utilities
```

### Key Design Patterns

1. **Unified Configuration**: Host configs are centralized in `flake.nix` using a `config` pattern that separates system attributes, users, and home-manager configurations.

2. **Conditional Module Loading**: System modules are conditionally enabled based on user preferences (e.g., Sway vs Hyprland detection).

3. **Shared Common Config**: User configurations inherit from `davidCommon` baseline with host-specific overrides.

4. **Custom Namespace**: System modules use `dedsm.*` options to avoid conflicts with standard NixOS options.

## Setup Commands

### Initial Setup (New System)
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
# Rebuild system from flake directory
sudo nixos-rebuild switch --flake .#manwe

# Rebuild from any location
sudo nixos-rebuild switch --flake /home/david/nixos-config#manwe

# Update flake inputs
nix flake update

# Check flake without building
nix flake check --no-build

# Test configuration before switching
sudo nixos-rebuild test --flake .#manwe
```

### Development Workflow
```bash
# Format Nix files
nixfmt *.nix **/*.nix

# Check individual modules
nix-instantiate --eval --expr 'import ./modules/system/default.nix {}'

# Validate flake structure
nix flake show
```

## Code Style & Conventions

### Nix Style Guidelines
- Use `nixfmt-rfc-style` for consistent formatting
- Prefer explicit imports over `with` statements in module headers
- Use descriptive variable names, especially for `let` bindings
- Comment complex module logic and conditional expressions

### Module Organization
- **System modules**: Located in `modules/system/`, use `dedsm.*` options namespace
- **Home Manager modules**: Located in `modules/home-manager/users/common/`, use standard HM options
- **Each module**: Should have a clear enable option and sensible defaults
- **Module imports**: Use `lib.mkMerge` for combining multiple configurations

### Configuration Patterns
```nix
# Good: Clear module structure
{ lib, config, pkgs, ... }:
with lib;
let cfg = config.dedsm.mymodule;
in {
  options.dedsm.mymodule = {
    enable = mkEnableOption "my module";
    # other options...
  };
  
  config = mkIf cfg.enable {
    # configuration here
  };
}

# Good: Conditional system features
mkIf anyHyprland {
  programs.hyprland.enable = true;
}
```

## Testing Instructions

### Flake Validation
```bash
# Check flake syntax and structure
nix flake check --no-build

# Show flake outputs
nix flake show

# Validate specific configuration
nix build .#nixosConfigurations.manwe.config.system.build.toplevel --dry-run
```

### System Testing
```bash
# Test configuration without switching
sudo nixos-rebuild test --flake .#manwe

# Build configuration without activating
sudo nixos-rebuild build --flake .#manwe

# Check for warnings/errors
journalctl -b | grep -i error
```

### Module Testing
- Each system module should have an enable option that defaults to sensible values
- Test modules individually by temporarily enabling/disabling in host config
- Verify Home Manager modules activate properly by checking generated config files in `~/.config/`

## Host Configuration Management

### Adding a New Host
1. Create new host config in `flake.nix` following the `manweConfig` pattern
2. Define `systemAttrs`, `systemUsers`, and `homeManagerUsers`
3. Add to `nixosConfigurations` output
4. Deploy: `sudo nixos-rebuild switch --flake .#new-hostname`

### Adding a New User
1. Add user to `systemUsers` in host config
2. Create user-specific Home Manager config in `homeManagerUsers`
3. Base on `davidCommon` or `rootCommon` as appropriate
4. Override/extend packages and module settings as needed

### Module Development
- System modules go in `modules/system/`
- Home Manager modules go in `modules/home-manager/users/common/`
- Use the existing module patterns (enable options, conditional config)
- Test new modules on a single host before generalizing

## Custom Packages

### Package Development
Custom packages are defined in `pkgs/` with an overlay system:

```bash
# Package locations
pkgs/cursor-appimage/     # Cursor AI editor AppImage wrapper
pkgs/snyk-ls/            # Snyk Language Server

# Testing custom packages
nix build .#cursor-appimage
nix build .#snyk-ls
```

### Adding New Packages
1. Create package directory in `pkgs/`
2. Write `default.nix` with proper meta attributes
3. Add to `pkgs/default.nix` overlay
4. Reference in user packages list

## Security Considerations

- **SSH keys**: Managed through Home Manager git configuration
- **GPG setup**: Configured for git signing with specified key ID
- **1Password integration**: CLI and GUI packages with polkit policies
- **Firmware updates**: fwupd enabled with LVFS testing repository
- **Firewall**: Disabled by default (review for production use)

## Development Environment Tips

### Nix Development
- Use `nix develop` for temporary development environments
- Leverage Home Manager for consistent developer tooling
- Custom packages should include proper `meta` information

### Editor Integration
- Neovim configuration included with LSP support
- Cursor AI editor available as custom package
- LSP servers for Nix, Docker, frontend development included

### Debugging
- Check Nix log files: `journalctl -u nix-daemon`
- Home Manager logs: `journalctl --user -u home-manager-<username>`
- System generation comparison: `nix profile diff-closures --profile /nix/var/nix/profiles/system`

## Backup and Recovery

### Configuration Backup
```bash
# Git-based backup (recommended)
git add . && git commit -m "Update configuration"
git push origin master

# Generate configuration backup
sudo tar -czf nixos-config-backup.tar.gz /etc/nixos
```

### System Recovery
```bash
# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# List available generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Boot into specific generation
sudo nixos-rebuild switch --switch-generation <generation-number>
```

### Git Workflow
- Commit configuration changes before major system updates
- Use descriptive commit messages for tracking changes
- Consider branching for experimental configurations
- The system tracks one generation ahead of `origin/master` currently

## Troubleshooting

### Common Issues
- **Flake evaluation errors**: Check syntax with `nix flake check`
- **Module conflicts**: Verify option namespacing in custom modules
- **Build failures**: Check unfree packages are properly handled
- **Home Manager activation**: Verify user has write access to config directories

### Performance Tips
- Use `home-manager.useGlobalPkgs = true` for shared package cache
- Enable `nix.settings.auto-optimise-store = true` for disk space
- Regularly run `nix-collect-garbage -d` to clean old generations

### Getting Help
- Check NixOS manual: `nixos-help`
- Home Manager manual: Available online at nix-community/home-manager
- Nix language reference: `nix --help` and online documentation
