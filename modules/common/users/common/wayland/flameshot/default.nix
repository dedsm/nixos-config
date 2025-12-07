attrs@{ lib, homeManagerConfig, pkgs, ... }: {
  services = {
    flameshot = {
      enable = true;
    };
  };
}
