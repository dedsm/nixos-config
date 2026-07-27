{
  lib,
  writeShellApplication,
  dstask,
  util-linux,
  stdenv,
}:

# `dstask note <id> "<text>"` gates on a controlling TTY: run headlessly (as an
# agent or any non-interactive shell does) it exits 0, prints nothing, and
# writes nothing — no commit, no note, no error. Every other dstask verb the
# brain skill uses (add/start/stop/done/modify) works fine without a TTY; only
# `note` is affected, and its silent-success failure mode makes it invisible
# unless you re-read the task YAML afterwards.
#
# Fix: run it under a pty via script(1). The two platforms disagree on how to
# spell that, which is the real reason this is a package and not a documented
# one-liner — a hand-written incantation is correct on exactly one of the two
# hosts and silently wrong on the other:
#
#   util-linux (manwe/NixOS): script -qec "<cmd string>" /dev/null
#   BSD        (morgoth/macOS): script -q /dev/null <cmd> <args...>
writeShellApplication {
  name = "dstask-note";

  runtimeInputs = [ dstask ] ++ lib.optionals stdenv.isLinux [ util-linux ];

  text =
    if stdenv.isLinux then
      ''
        # util-linux script takes the command as a single string; %q-quote each
        # argument so note text with spaces/quotes survives the round trip.
        # -e propagates dstask's exit status instead of script's own.
        exec script -qec "$(printf '%q ' dstask note "$@")" /dev/null </dev/null
      ''
    else
      ''
        # BSD script takes the typescript file first, then argv directly — no
        # re-quoting needed, so arguments pass through untouched.
        exec script -q /dev/null dstask note "$@" </dev/null
      '';

  meta = with lib; {
    description = "TTY-wrapped `dstask note` that works from non-interactive shells";
    longDescription = ''
      dstask note silently does nothing when run without a controlling TTY.
      This wrapper runs it under a pty so notes can be written from scripts and
      agent sessions, papering over the BSD/util-linux script(1) syntax split.
    '';
    platforms = platforms.unix;
    mainProgram = "dstask-note";
  };
}
