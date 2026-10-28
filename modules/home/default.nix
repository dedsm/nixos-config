# Every Home Manager module, registered for all users through
# home-manager.sharedModules (modules/common/default.nix). Each one declares
# dedsm.<name>.enable and does nothing until a user's config sets it.
{
  imports = [
    ./tmux
    ./herdr
    ./nvim
    ./zsh
    ./hyprland
    ./dms
    ./starship
    ./gh
    ./direnv
    ./ssh
    ./ghostty
    ./theme
    ./claude-code
    ./playwright
    ./antigravity
    ./agent-harness
    ./cli-notify
    ./linux-desktop
  ];
}
