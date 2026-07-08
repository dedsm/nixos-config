{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.fwupd;
in {
  options.dedsm.fwupd = {
    enable = mkOption {
      description = "Firmware updates (fwupd)";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    services.fwupd = {
      enable = true;
      extraRemotes = [ "lvfs-testing" ];
    };

    environment.etc."fwupd/uefi_capsule.conf".text = lib.mkForce ''
      [uefi_capsule]
      OverrideESPMountPoint=${config.boot.loader.efi.efiSysMountPoint}
      DisableCapsuleUpdateOnDisk=true
    '';
  };
}
