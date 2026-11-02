{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  options.dedsm.ssh = {
    enable = lib.mkEnableOption "the ssh client config and gpg-agent socket";
  };

  config = lib.mkIf config.dedsm.ssh.enable {
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

    # 1050: after Home Manager's integrations (starship, direnv, ...; 1000)
    # and before its aliases (1100), where these lines have always sat.
    # Equal-order snippets would otherwise be ordered by module position.
    programs.zsh.initContent = lib.mkOrder 1050 ''
      if [ $EUID -ne 0 ]; then
        export GPG_TTY="$(tty)"
        gpg-connect-agent /bye
        export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
      fi
    '';

    # Refresh gpg-agent's pinentry when an activation changes it.
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
    #            systemd socket activation that owns the agent there. But SIGHUP
    #            flushes the agent's whole cache, including the YubiKey's PINs,
    #            so the next ssh and the next signed commit each prompt again.
    #            So the reload only happens when it fixes something: when the
    #            file differs from the copy saved at the last reload. The whole
    #            file is compared because a reload is also what applies any other
    #            option in it. No saved copy means reloading once, to be safe. The
    #            copy lives in the persistent state directory so that the first
    #            switch after a boot doesn't flush the cache for nothing: an agent
    #            started since the last activation read the current file anyway.
    #            The check only runs when activation does, which a switch skips
    #            if the Home Manager unit is unchanged. A pinentry bump changes
    #            the unit too in practice, since both come from one package set.
    #
    #            A reload that does happen can't restore a PIN, so it asks for
    #            it straight away instead of in the middle of later work. Before
    #            reloading, `gpg-card-pins probe` tests each PIN with pinentry
    #            mode `cancel`, which succeeds silently if it is unlocked and
    #            fails before anything reaches the card if not, so it can't use
    #            a retry. Only the PINs that were unlocked are asked for again,
    #            from a transient user unit so that the switch doesn't wait on
    #            someone typing. No CLI reports the sign PIN's state, so probing
    #            and unlocking it each make one discarded signature, which adds
    #            to the card's signature counter.
    #
    #   Darwin — there is no gpg-agent.conf at all; pinentry is gnupg's built-in
    #            default, compiled into the binary the agent is still executing.
    #            A reload re-reads nothing, so the process itself has to go. It
    #            comes back on demand via the zsh hook, at the cost of dropping
    #            cached passphrases — and, with the keys on a YubiKey, the card's
    #            PIN state: killing scdaemon resets the card, and the sign and
    #            auth PINs are verified separately, so the next ssh and the next
    #            signed commit each prompt again (more than once, if requests
    #            queue up behind the first pinentry). So the kill only happens
    #            when it fixes something: when the running agent's executable is
    #            not this generation's gnupg. pinentry is a build input of gnupg,
    #            so a pinentry bump changes that store path too, while a rebuild
    #            that leaves gnupg alone leaves the agent and the card unlocked.
    #            No agent running means nothing to do (`--no-autostart`, so the
    #            check doesn't start one); an agent whose executable can't be
    #            read is killed, as before.
    #
    # Both verbs already exit 0 with no agent running; the `|| true` is for the
    # genuinely broken cases (an unreadable homedir, say). It matters because
    # activation runs under `set -eu`, where a non-zero exit here would abort the
    # whole rebuild over a detail this peripheral.
    home.activation.refreshGpgAgentPinentry = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        gpgconf = "${pkgs.gnupg}/bin/gpgconf";
        gpgConnectAgent = "${pkgs.gnupg}/bin/gpg-connect-agent";
        gpgAgentConf = "/etc/gnupg/gpg-agent.conf";
        loadedGpgAgentConf = "${config.xdg.stateHome}/gpg-agent.conf.loaded";
        gpgCardPins = pkgs.writeShellApplication {
          name = "gpg-card-pins";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnupg
            pkgs.gnused
          ];
          text = ''
            serial=$(gpg-connect-agent --no-autostart 'SCD SERIALNO openpgp' /bye 2>/dev/null \
              | sed -n 's/^S SERIALNO \([0-9A-F]*\).*/\1/p') || true
            [ -n "$serial" ] || exit 0

            auth() {
              [ "$(gpg-connect-agent --no-autostart "OPTION pinentry-mode=$1" \
                'SCD SERIALNO openpgp' "SCD CHECKPIN $serial" /bye 2>/dev/null \
                | tail -n 1)" = OK ]
            }

            sign() {
              local fpr
              fpr=$(gpg --batch --no-tty --card-status --with-colons 2>/dev/null \
                | sed -n 's/^fpr:\([0-9A-F]*\):.*/\1/p') || return 1
              [ -n "$fpr" ] || return 1
              printf 'gpg-card-pins' | gpg --batch --no-tty --yes --pinentry-mode "$1" \
                --local-user "$fpr" --clearsign -o /dev/null 2>/dev/null
            }

            case "''${1:-}" in
              probe)
                if auth cancel; then echo auth; fi
                if sign cancel; then echo sign; fi
                ;;
              unlock)
                shift
                for pin in "$@"; do
                  "$pin" ask || true
                done
                ;;
              *)
                echo "usage: gpg-card-pins probe | unlock [auth] [sign]" >&2
                exit 2
                ;;
            esac
          '';
        };
      in
      if pkgs.stdenv.isDarwin then
        ''
          gpgAgentPid=$(${gpgConnectAgent} --no-autostart 'getinfo pid' /bye 2>/dev/null \
            | ${pkgs.gnused}/bin/sed -n 's/^D //p' || true)
          if [ -n "$gpgAgentPid" ]; then
            # The first `txt` entry lsof reports for a process is its executable.
            gpgAgentBin=$(/usr/sbin/lsof -a -p "$gpgAgentPid" -d txt -Fn 2>/dev/null \
              | ${pkgs.gnused}/bin/sed -n 's/^n//p' | ${pkgs.coreutils}/bin/head -n 1 || true)
            if [ "$gpgAgentBin" != "${pkgs.gnupg}/bin/gpg-agent" ]; then
              $DRY_RUN_CMD ${gpgconf} --kill gpg-agent scdaemon || true
            fi
          fi
        ''
      else
        ''
          if [ -r ${gpgAgentConf} ] \
            && ! ${pkgs.diffutils}/bin/cmp -s ${gpgAgentConf} "${loadedGpgAgentConf}"; then
            unlockedPins=""
            if [ -z "$DRY_RUN_CMD" ]; then
              unlockedPins=$(${lib.getExe gpgCardPins} probe 2>/dev/null || true)
            fi
            if $DRY_RUN_CMD ${gpgconf} --reload gpg-agent \
              && $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -D -m 0644 \
                ${gpgAgentConf} "${loadedGpgAgentConf}"; then
              if [ -n "$unlockedPins" ]; then
                # shellcheck disable=SC2086 # one word per PIN
                XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}" \
                  ${pkgs.systemd}/bin/systemd-run --user --collect --no-block --quiet \
                  --unit=gpg-card-unlock ${lib.getExe gpgCardPins} unlock $unlockedPins || true
              fi
            fi
          fi
        ''
    );
  };
}
