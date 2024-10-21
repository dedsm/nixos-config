attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }: {
  services = {
    flameshot = {
      enable = true;
    };
  };
}
