{ lib, pkgs, config, username, homeManagerConfig, ... }:
with lib;
mkIf (homeManagerConfig.zsh.enable or false) {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    # 26.05 XDG default: move zsh config to ~/.config/zsh.
    # history.path defaults to "${dotDir}/.zsh_history", so it follows automatically.
    dotDir = "${config.users.users.${username}.home}/.config/zsh";
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
    initContent = ''
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

      # Auto-rename tmux window to directory basename (with dedup)
      # For git worktrees, shows "repo:dir" when dir differs from repo name
      function _tmux_rename_window() {
        [[ -z "$TMUX" || -z "$TMUX_PANE" ]] && return

        local dir_name repo_name name
        dir_name=$(basename "$PWD")

        # Detect git repo name (use common dir for worktrees and bare repos)
        local git_dir
        git_dir=$(realpath "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)
        if [[ -n "$git_dir" ]]; then
          if [[ "$(basename "$git_dir")" == ".git" ]]; then
            # Normal repo: .git dir lives inside the repo root
            repo_name=$(basename "$(dirname "$git_dir")")
          else
            # Bare repo: the git dir IS the repo
            repo_name=$(basename "$git_dir")
          fi
          if [[ "$repo_name" != "$dir_name" ]]; then
            name="''${repo_name}:''${dir_name}"
          else
            name="$dir_name"
          fi
        else
          name="$dir_name"
        fi

        local current_window
        current_window=$(tmux display-message -p -t "$TMUX_PANE" '#{window_index}')

        # collect names from OTHER windows
        local taken
        taken=$(tmux list-windows -F '#{window_index} #{window_name}' \
          | awk -v cur="$current_window" '$1 != cur { $1=""; print substr($0,2) }' \
          | grep -E "^''${name}( [0-9]+)?$" || true)

        if [[ -z "$taken" ]]; then
          tmux rename-window -t "$TMUX_PANE" "$name"
        elif ! echo "$taken" | grep -qE "^''${name}$"; then
          tmux rename-window -t "$TMUX_PANE" "$name"
        else
          local n=2
          while echo "$taken" | grep -qE "^''${name} ''${n}$"; do
            ((n++))
          done
          tmux rename-window -t "$TMUX_PANE" "$name $n"
        fi
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook chpwd _tmux_rename_window
      _tmux_rename_window  # run once on shell init

      ${lib.optionalString (homeManagerConfig.claude-code.headroom.enable or false) ''
        # headroom: tag each `claude` launch with its git repo so the proxy can
        # attribute compression savings per project. Worktree-stable via
        # --git-common-dir (all worktrees of a repo roll up to the repo name);
        # falls back to "common" outside a repo. Passed as a one-shot prefix
        # assignment (no global env pollution); read once at claude startup,
        # which is fine since a session's project is fixed by its launch dir.
        function claude() {
          local git_dir repo
          git_dir=$(realpath "$(command git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)
          if [[ -n "$git_dir" ]]; then
            if [[ "$(basename "$git_dir")" == ".git" ]]; then
              repo=$(basename "$(dirname "$git_dir")")
            else
              repo=$(basename "$git_dir")
            fi
          else
            repo=common
          fi
          ANTHROPIC_CUSTOM_HEADERS="X-Headroom-Project: $repo" command claude "$@"
        }
      ''}

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
            result="$(\command zoxide query --list --exclude "$(__zoxide_pwd)" | fzf --filter="$*" --no-sort | head -n1)"
            if [[ -n "$result" ]]; then
              __zoxide_cd "$result"
            fi
          fi
        }
      '' else ""}
    '';
  };
}
