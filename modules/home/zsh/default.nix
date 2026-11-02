{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  options.dedsm.zsh = {
    enable = lib.mkEnableOption "zsh";
    extraInit = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Host-specific lines spliced into initContent, after the tmux/herdr hooks.";
    };
  };

  config = lib.mkIf config.dedsm.zsh.enable {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      # 26.05 XDG default: move zsh config to ~/.config/zsh.
      # history.path defaults to "${dotDir}/.zsh_history", so it follows automatically.
      dotDir = "${config.home.homeDirectory}/.config/zsh";
      autosuggestion = {
        enable = true;
      };
      enableVteIntegration = true;
      plugins = [
        {
          name = "zsh-completion-sync";
          src = pkgs.zsh-completion-sync;
          file = "share/zsh-completion-sync/zsh-completion-sync.plugin.zsh";
        }
      ];
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
      # 1050: between Home Manager's integrations and its aliases, as in
      # ssh/default.nix.
      initContent = lib.mkOrder 1050 ''
        # If running in foot, ensure the correct theme is applied on startup (interactive only)
        if [[ -o interactive ]] && [[ "$TERM" == "foot" ]]; then
          if [[ "$(ps -p $PPID -o comm= 2>/dev/null | tr -d ' ')" == "foot" ]]; then
            # foot 1.27: SIGUSR1 = dark ([colors-dark]), SIGUSR2 = light ([colors-light])
            if [[ "$(theme-get)" == "dark" ]]; then
              kill -USR1 $PPID
            else
              kill -USR2 $PPID
            fi
          fi
        fi

        # Enable PATH-based discovery for nix-shell compatibility
        zstyle ':completion-sync:path' enabled true

        ${config.dedsm.zsh.extraInit}
        any-nix-shell zsh --info-right | source /dev/stdin
        ${
          if config.programs.zoxide.enable then
            ''
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
                  result="$(\command zoxide query --list --exclude "$(__zoxide_pwd)" | fzf --filter="$*" --no-sort | head -n1)"
                  if [[ -n "$result" ]]; then
                    __zoxide_cd "$result"
                  fi
                fi
              }
            ''
          else
            ""
        }
      '';
    };
  };
}
