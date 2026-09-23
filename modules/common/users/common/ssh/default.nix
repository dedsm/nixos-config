{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
with lib;
mkIf (homeManagerConfig.ssh.enable or false) {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # 26.05: matchBlocks deprecated in favour of settings with upstream directive names.
    # UseRoaming dropped — removed from OpenSSH since the CVE-2016-0777 fix.
    settings."*" = {
      ControlMaster = "auto";
      ControlPath = "~/.ssh/sockets/%r@%h-%p";
      ControlPersist = "60";
      HashKnownHosts = true;
      SetEnv = {
        TERM = "xterm-256color";
      };
    };
  };

  home.file.ssh_sockets = {
    target = ".ssh/sockets/.nixkeep";
    text = "SSH sockets directory";
  };

  programs.zsh.initContent = ''
    if [ $EUID -ne 0 ]; then
      export GPG_TTY="$(tty)"
      gpg-connect-agent /bye
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
    fi
  '';

  # Refresh gpg-agent's pinentry on every activation.
  #
  # gpg-agent resolves pinentry to a /nix/store path once, at startup. Nothing
  # recycles the agent across a rebuild — the zsh hook above only attaches to
  # whatever is already running, and neither darwin-rebuild nor nixos-rebuild
  # restarts a user agent — so an agent that outlives a gnupg or pinentry bump
  # keeps pointing at the old path. Once GC drops that path, every passphrase
  # prompt dies with "No pinentry" while the agent still answers `getinfo
  # version` and looks healthy, which is what makes it so confusing to diagnose.
  # And since `enableSSHSupport` routes SSH_AUTH_SOCK through that same agent,
  # it takes ssh down with it, not just git signing.
  #
  # The two platforms need different remedies, because they pin pinentry in
  # different places:
  #
  #   NixOS  — `programs.gnupg.agent.pinentryPackage` writes the path into
  #            /etc/gnupg/gpg-agent.conf, which the rebuild has just rewritten,
  #            so a SIGHUP is enough: the agent re-reads the file and picks up
  #            the new path. Reloading also stays out of the way of the
  #            systemd socket activation that owns the agent there, and keeps
  #            cached passphrases and unlocked ssh keys.
  #
  #   Darwin — there is no gpg-agent.conf at all; pinentry is gnupg's built-in
  #            default, compiled into the binary the agent is still executing.
  #            A reload re-reads nothing, so the process itself has to go. It
  #            comes back on demand via the zsh hook, at the cost of dropping
  #            cached passphrases and unlocked ssh keys — cheap next to an agent
  #            that is silently broken.
  #
  # Both verbs already exit 0 with no agent running; the `|| true` is for the
  # genuinely broken cases (an unreadable homedir, say). It matters because
  # activation runs under `set -eu`, where a non-zero exit here would abort the
  # whole rebuild over a detail this peripheral.
  home.activation.refreshGpgAgentPinentry = {
    after = [ "writeBoundary" ];
    before = [ ];
    data =
      let
        gpgconf = "${pkgs.gnupg}/bin/gpgconf";
      in
      if pkgs.stdenv.isDarwin then
        ''
          $DRY_RUN_CMD ${gpgconf} --kill gpg-agent scdaemon || true
        ''
      else
        ''
          $DRY_RUN_CMD ${gpgconf} --reload gpg-agent || true
        '';
  };
}
