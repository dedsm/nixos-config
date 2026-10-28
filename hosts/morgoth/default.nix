# morgoth: macOS with Aerospace. Everything specific to this machine: which
# dedsm system modules it runs and its user's Home Manager config. Built by
# darwinHost.mkDarwinHost in flake.nix, which also sets the user's home path.
{
  dedsm.aerospace.enable = true;

  home-manager.users."david.de.sousa" = {
    imports = [ ../../users/david/darwin.nix ];
    programs.git.includes = [
      {
        path = "~/Develop/Carv/.gitconfig";
        condition = "gitdir:~/Develop/Carv/";
      }
    ];
    dedsm.zsh.extraInit = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
      eval "$(docker completion zsh)"
    '';
  };
}
