{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.ssh.enable or false) {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # 26.05: matchBlocks deprecated in favour of settings with upstream directive names.
    # UseRoaming dropped — removed from OpenSSH since the CVE-2016-0777 fix.
    settings."*" = {
      ControlMaster = "auto";
      ControlPath = "~/.ssh/sockets/%r@%h-%p";
      ControlPersist = "60";
      HashKnownHosts = true;
      SetEnv = { TERM = "xterm-256color"; };
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
