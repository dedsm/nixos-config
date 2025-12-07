# NixOS Configuration

## Manual steps to start with a darwin setup

- Install the upstream nix: https://nix.dev/install-nix.html
- Install the intl-altgr layout: https://github.com/carjorvaz/macos-us-altgr-intl
- install hyperkey: https://hyperkey.app/
- Run the darwin install: `sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin/nix-darwin-25.11#darwin-rebuild -- switch --flake .#<machine_name>`
