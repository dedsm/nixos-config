# root on NixOS hosts: the shell and editor setup, nothing else.
{
  dedsm = {
    tmux.enable = true;
    nvim.enable = true;
    zsh.enable = true;
    starship.enable = true;
  };

  home.stateVersion = "22.05";
}
