# plugin -> the harnesses it can be installed into. A harness name is the key
# of that harness's own module in the user config (`claude-code.enable`, ...).
# Pure data, kept apart from lib.nix so ./default.nix can declare one option
# per pair without forcing anything that depends on pkgs or config.
{
  rtk = [
    "claude-code"
    "antigravity"
  ];
  # Claude Code doesn't need it: its Bash tool inherits the environment of
  # the shell it was started from, which direnv has already loaded for the
  # project. Antigravity's commands don't, hence the export prefix.
  direnv = [ "antigravity" ];
  # rtk's `rtk:posthook` pipeline: compresses tool output after the tool ran
  # (PostToolUse). Upstream applies pipeline hook rules to Claude Code only.
  # It extends rtk's PreToolUse rewrite, so it is inert where `rtk` is off.
  rtk-posthook = [ "claude-code" ];
  # The personal `brain` skill and its SessionStart health line. The store
  # machinery it relies on (the CLI on PATH, the ~/brain bootstrap and
  # commit hooks, the weekly health timer) comes with it in either harness.
  brain = [
    "claude-code"
    "antigravity"
  ];
}
