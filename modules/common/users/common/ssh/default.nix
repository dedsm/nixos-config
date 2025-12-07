{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.ssh.enable or false) {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      controlMaster = "auto";
      controlPath = "~/.ssh/sockets/%r@%h-%p";
      controlPersist = "60";
      hashKnownHosts = true;
      extraOptions = {
        UseRoaming = "no";
        SetEnv = "TERM=xterm-256color";
      };
    };
  };

  home.file.ssh_sockets = {
    target = ".ssh/sockets/.nixkeep";
    text = "SSH sockets directory";
  };

  programs.zsh.initContent = ''
    if [ $EUID -ne 0 ]; then
      export GPG_TTY="$(tty)"
      gpg-connect-agent /bye
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
    fi
  '';
}
