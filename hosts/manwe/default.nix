# manwe: Framework 13 (AMD Ryzen AI 300) running Hyprland. Everything specific
# to this machine: its hardware, which dedsm system modules it runs, its users
# and their Home Manager config. Built by nixosHost.mkHost in flake.nix.
{ nixos-hardware, ... }:
{
  imports = [
    nixos-hardware.nixosModules.framework-amd-ai-300-series
    ./hardware-configuration.nix
  ];

  dedsm = {
    laptop.enable = true;
    performance.enable = true;
    gnome-programs.enable = true;
    gnome-services.enable = true;
    hyprland.enable = true;
    greetd.enable = true;
    bluetooth.enable = true;
    printing.enable = true;
    scanning.enable = true;
    virtualisation.enable = true;
    onepassword.enable = true;
    gnupg.enable = true;
    peripherals.enable = true;
    fingerprintPolicy = {
      enable = true;
      # Using dedsm.fingerprintPolicy's defaults. Fingerprint is refused,
      # and the password required, after a restart or logout, after 5
      # failed matches, after 48h with no unlock, or when the password is
      # over 156h old and there has been no fingerprint unlock for 4h.
      # See docs/login-flow.md.
      # The lock screen authenticates as david, not root, so its password
      # unlock can only refresh the clock if david may write the state.
      users = [ "david" ];
    };
    fwupd.enable = true;
    ddclient.enable = true;
    dms.enable = true;
  };

  users.users.david = {
    isNormalUser = true;
    extraGroups = [
      "disk"
      "wheel"
      "video"
      "docker"
      "networkmanager"
      "lp"
      "scanner"
      "uinput" # solaar
    ];
  };

  # Each user is a Home Manager module: a layer from users/ plus whatever is
  # specific to this host.
  home-manager.users = {
    david =
      { pkgs, ... }:
      {
        imports = [ ../../users/david/nixos.nix ];
        dedsm.hyprland.enable = true;
        home.packages = [
          pkgs.local.slack
          pkgs.local.granola
          pkgs.unstable.spotify
          (pkgs.unstable.vscode.override {
            commandLineArgs = "--password-store=gnome-libsecret";
          })
          pkgs.unstable.synology-drive-client
          pkgs.unstable.ledger-live-desktop
          pkgs.unstable.awscli2
        ];
      };
    root = ../../users/root.nix;
  };

  system.stateVersion = "21.05";
}
