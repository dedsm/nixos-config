# david's settings on every host; imported by ./nixos.nix and ./darwin.nix.
# Each dedsm.<name> toggle is declared by modules/home/<name>.
{ pkgs, ... }:
{
  dedsm = {
    tmux.enable = true;
    herdr.enable = true;
    nvim.enable = true;
    zsh.enable = true;
    starship.enable = true;
    claude-code.enable = true;
    playwright.enable = true;
    theme.enable = true;
    direnv.enable = true;
    ssh.enable = true;
    gh.enable = true;

    # Plugins shared by the coding-agent harnesses, per harness. Each flag
    # only takes effect where that harness's own module is enabled (all
    # default to true). See docs/agent-harness.md.
    agent-harness = {
      rtk = {
        claude-code = true;
        antigravity = true;
      };
      direnv.antigravity = true;
      rtk-posthook.claude-code = true;
      brain.antigravity = true;
    };
  };

  programs.git = {
    enable = true;
    lfs = {
      enable = true;
      skipSmudge = true;
    };
    ignores = [
      ".envrc"
      ".python-version"
      ".mypy_cache"
      ".direnv"
      ".tool-versions"
      "shell.nix"
    ];
    settings = {
      user = {
        email = "davidesousa@gmail.com";
        name = "David De Sousa";
        signingkey = "8655217C8614EB611CF2259DF287187DBA42E303";
      };
      commit.gpgsign = true;
      tag.gpgsign = true;
      push = {
        default = "simple";
      };
      diff = {
        tool = "vimdiff";
      };
      pull = {
        ff = "only";
      };
      init = {
        defaultBranch = "master";
      };
      worktree = {
        guessRemote = true;
      };
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # zsh/default.nix runs its own `zoxide init zsh --cmd j`, with an fzf-backed
  # `z`, so the stock integration stays off.
  programs.zoxide = {
    enable = true;
    enableZshIntegration = false;
  };

  home.packages = with pkgs; [
    gnumake
    docker-credential-helpers
    httpie
    kubectl
    stern
    p7zip
    sops
    (pkgs.unstable.google-cloud-sdk.withExtraComponents (
      with pkgs.unstable.google-cloud-sdk.components;
      [
        gke-gcloud-auth-plugin
      ]
    ))
    docker-credential-gcr
    amazon-ecr-credential-helper
    jq
    yq
    fzf
    krew
    prettier

    # Personal task tracker (git-backed); used by the `brain` Claude skill.
    # `dstask-note` wraps `dstask note` in a pty — the bare command
    # silently no-ops without a TTY (see pkgs/dstask-note/default.nix).
    dstask
    pkgs.local.dstask-note

    # K8S
    k9s

    # On PATH by name for herdr's agent integration: the hook it installs
    # into Claude Code is `sh` + a `python3` heredoc (herdr itself is
    # Rust), and it exits 0 without reporting when `command -v python3`
    # fails — which silently costs agent session recovery. See
    # "Restart behaviour" in docs/herdr.md. Same store path `brain`
    # already pins via patchShebangs, so this costs no extra build.
    python3
  ];
}
