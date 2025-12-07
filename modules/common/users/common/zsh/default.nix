{ lib, homeManagerConfig, ... }:
with lib;
mkIf (homeManagerConfig.zsh.enable or false) {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
    };
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
    initContent = ''
      ${homeManagerConfig.zsh.initContent or ""}
      any-nix-shell zsh --info-right | source /dev/stdin
      ${if (homeManagerConfig.zoxide.enable or false) then ''
        export _ZO_FZF_OPTS="--scheme=path --tiebreak=end,chunk,index --bind=ctrl-z:ignore,btab:up,tab:down --cycle --keep-right --border=sharp --height=45% --info=inline --layout=reverse --tabstop=1 --exit-0 --select-1"
        eval "$(zoxide init zsh --cmd j)"

        # Override the default z function to use fzf for fuzzy matching
        function __zoxide_z() {
          __zoxide_doctor
          if [[ "$#" -eq 0 ]]; then
            __zoxide_cd ~
          elif [[ "$#" -eq 1 ]] && { [[ -d "$1" ]] || [[ "$1" = '-' ]] || [[ "$1" =~ ^[-+][0-9]$ ]]; }; then
            __zoxide_cd "$1"
          elif [[ "$#" -eq 2 ]] && [[ "$1" = "--" ]]; then
            __zoxide_cd "$2"
          else
            \builtin local result
            result="$(\command zoxide query --list | fzf --filter="$*" | head -n1)"
            if [[ -n "$result" ]]; then
              __zoxide_cd "$result"
            fi
          fi
        }
      '' else ""}
    '';
  };
}
