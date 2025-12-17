{ lib, pkgs, homeManagerConfig, ... }:
with lib;
mkIf (homeManagerConfig.starship.enable or false) {
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = lib.concatStrings [
        "$username"
        "$hostname"
        "$nix_shell"
        "$shlvl"
        "$directory"
        "$git_branch"
        "$git_commit"
        "$git_state"
        "$git_status"
        "$docker_context"
        "$kubernetes"
        "$golang"
        "$helm"
        "$python"
        "$rust"
        "$memory_usage"
        "$cmd_duration"
        "$line_break"
        "$jobs"
        "$battery"
        "$character"
      ];
      scan_timeout = 10;
      command_timeout = 50;
      add_newline = false;

      kubernetes = { disabled = false; };

      battery = {
        display = [{
          threshold = 100;
          style = "red bold";
        }];
      };

      character = {
        format = "$symbol ";
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vicmd_symbol = "[❮](bold green)";
        disabled = false;
      };

      cmd_duration = {
        min_time = 2000;
        format = "took [$duration]($style) ";
        style = "yellow bold";
        show_milliseconds = true;
        disabled = false;
        # Notifications cause shell to hang on macOS after long-running commands
        # https://github.com/starship/starship/issues/7128
        show_notifications = !pkgs.stdenv.isDarwin;
        min_time_to_notify = 45000;
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        fish_style_pwd_dir_length = 0;
        use_logical_path = true;
        format = "[cwd:$path]($style)[$read_only]($read_only_style) ";
        style = "cyan bold";
        disabled = false;
        read_only = "🔒";
        read_only_style = "red";
        truncation_symbol = "";
        home_symbol = "~";
      };

      docker_context = {
        symbol = "🐳 ";
        style = "blue bold";
        format = "via [$symbol$context]($style) ";
        only_with_files = true;
        disabled = false;
        detect_extensions = [ ];
        detect_files =
          [ "docker-compose.yml" "docker-compose.yaml" "Dockerfile" ];
        detect_folders = [ ];
      };

      git_branch = {
        format = "on [$symbol$branch]($style)(:[$remote]($style)) ";
        symbol = " ";
        style = "bold purple";
        truncation_length = 9223372036854775807;
        truncation_symbol = "…";
        only_attached = false;
        always_show_remote = false;
        disabled = false;
      };

      git_commit = {
        commit_hash_length = 7;
        format = "[($hash$tag)]($style) ";
        style = "green bold";
        only_detached = true;
        disabled = false;
        tag_symbol = "🏷  ";
        tag_disabled = true;
      };

      git_state = {
        rebase = "REBASING";
        merge = "MERGING";
        revert = "REVERTING";
        cherry_pick = "CHERRY-PICKING";
        bisect = "BISECTING";
        am = "AM";
        am_or_rebase = "AM/REBASE";
        style = "bold yellow";
        format = "([$state( $progress_current/$progress_total)]($style)) ";
        disabled = false;
      };

      git_status = {
        format = "([$all_status$ahead_behind]($style) )";
        style = "red bold";
        stashed = "%";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        conflicted = "=";
        deleted = "✘";
        renamed = "»";
        modified = "!";
        staged = "+";
        untracked = "?";
        disabled = false;
      };

      golang = {
        format = "via [$symbol($version )]($style)";
        symbol = "🐹 ";
        style = "bold cyan";
        disabled = false;
        detect_extensions = [ "go" ];
        detect_files = [
          "go.mod"
          "go.sum"
          "glide.yaml"
          "Gopkg.yml"
          "Gopkg.lock"
          ".go-version"
        ];
        detect_folders = [ "Godeps" ];
      };

      helm = {
        format = "via [$symbol($version )]($style)";
        symbol = "⎈ ";
        style = "bold white";
        disabled = false;
        detect_extensions = [ ];
        detect_files = [ "helmfile.yaml" "Chart.yaml" ];
        detect_folders = [ ];
      };

      hostname = {
        ssh_only = false;
        trim_at = ".";
        format = "[$hostname]($style) ";
        style = "green dimmed bold";
        disabled = false;
      };

      jobs = {
        threshold = 1;
        format = "[$symbol$number]($style) ";
        symbol = "✦";
        style = "bold blue";
        disabled = false;
      };

      memory_usage = {
        threshold = 75;
        format = "via $symbol[$ram( | $swap)]($style) ";
        style = "white bold dimmed";
        symbol = "🐏 ";
        disabled = true;
      };

      nix_shell = {
        format = "via [$symbol$state( ($name))]($style) ";
        symbol = "❄️  ";
        style = "bold blue";
        impure_msg = "impure";
        pure_msg = "pure";
        disabled = false;
      };

      python = {
        pyenv_version_name = false;
        pyenv_prefix = "pyenv ";
        python_binary = [ "python" "python3" "python2" ];
        format =
          "[\${symbol}\${pyenv_prefix}(\${version} )(($virtualenv) )]($style)";
        version_format = "v\${raw}";
        style = "yellow bold";
        symbol = "🐍 ";
        disabled = false;
        detect_extensions = [ "py" ];
        detect_files = [
          "requirements.txt"
          ".python-version"
          "pyproject.toml"
          "Pipfile"
          "tox.ini"
          "setup.py"
          "__init__.py"
        ];
        detect_folders = [ ];
      };

      rust = {
        format = "via [$symbol($version )]($style)";
        version_format = "v\${raw}";
        symbol = "🦀 ";
        style = "bold red";
        disabled = false;
        detect_extensions = [ "rs" ];
        detect_files = [ "Cargo.toml" ];
        detect_folders = [ ];
      };
      shlvl = {
        threshold = 2;
        format = "[$symbol$shlvl]($style) ";
        symbol = "↕️  ";
        repeat = false;
        style = "bold yellow";
        disabled = true;
      };

      username = {
        format = "[$user]($style)@";
        style_root = "red bold";
        style_user = "yellow bold";
        show_always = true;
        disabled = false;
      };
    };
  };
}
