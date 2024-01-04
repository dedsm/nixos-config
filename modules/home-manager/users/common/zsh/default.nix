{ lib, homeManagerConfig, ... }:
with lib;
mkIf homeManagerConfig.zsh.enable {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = false;
    enableVteIntegration = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "docker-compose"
        "helm"
        "pip"
        "python"
        "systemd"
        "tmux"
      ];
    };
    history = {
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      save = 1000000;
      share = true;
      size = 100000;
    };
    initExtra = ''
      if [ $EUID -ne 0 ]; then
        export GPG_TTY="$(tty)"
        gpg-connect-agent /bye
        export SSH_AUTH_SOCK="/run/user/$UID/gnupg/S.gpg-agent.ssh"
        export PATH="$PATH:$HOME/.krew/bin"
      fi
      any-nix-shell zsh --info-right | source /dev/stdin
    '';
  };
}
