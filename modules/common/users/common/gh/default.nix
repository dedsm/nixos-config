{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  options.dedsm.gh = {
    enable = lib.mkEnableOption "the GitHub CLI";
  };

  config = lib.mkIf config.dedsm.gh.enable {
    programs.gh = {
      enable = true;

      # Extensions are symlinked into ~/.local/share/gh/extensions by `pname`,
      # so `gh extension install/upgrade` no longer applies — add them here.
      extensions = [ pkgs.gh-stack ];

      # `hosts` is deliberately left unset: home-manager only writes
      # gh/hosts.yml when it is non-empty, which keeps the `gh auth login`
      # credentials out of the store and under gh's own control.
      settings = {
        git_protocol = "https";
        aliases = {
          co = "pr checkout";
        };
      };
    };
  };
}
