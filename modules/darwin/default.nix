{ pkgs, ... }: {
  imports = [
    # Add darwin specific modules here
  ];

  # Basic Darwin defaults
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  programs.zsh.enable = true;
  
  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
}