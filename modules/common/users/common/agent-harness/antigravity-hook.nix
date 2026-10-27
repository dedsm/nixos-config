# Antigravity's run_command PreToolUse hook. It is the one place two plugins
# meet: rtk rewrites the command first (`git status` -> `rtk git status`), then
# the direnv prefix wraps the result so per-project devShells (e.g. a flake
# providing xelatex) are active for the agent's commands. They must be one
# hook rather than one per plugin, since the direnv wrap has to see rtk's
# rewrite. Either half drops out when its plugin is off.
{
  pkgs,
  rtkPkg,
  rtk,
  direnv,
}:
let
  pyStr = s: builtins.toJSON s;
in
pkgs.writeScript "antigravity-pre-tool-use" ''
  #!${pkgs.python3}/bin/python3
  import sys, json, subprocess

  RTK = ${if rtk then pyStr "${rtkPkg}/bin/rtk" else "None"}
  DIRENV = ${if direnv then pyStr "${pkgs.unstable.direnv}/bin/direnv" else "None"}

  raw = sys.stdin.read()
  if not raw.strip():
      print(json.dumps({"decision": "allow"}))
      sys.exit(0)

  try:
      payload = json.loads(raw)
  except Exception:
      print(json.dumps({"decision": "allow"}))
      sys.exit(0)

  cmd = payload.get("toolCall", {}).get("args", {}).get("CommandLine", "")
  if not cmd:
      print(json.dumps({"decision": "allow"}))
      sys.exit(0)

  res = {}
  if RTK:
      try:
          proc = subprocess.run(
              [RTK, "hook", "antigravity"],
              input=raw,
              text=True,
              capture_output=True,
              timeout=5
          )
          if proc.returncode == 0 and proc.stdout.strip():
              res = json.loads(proc.stdout)
      except Exception:
          pass

  rewritten = res.get("overwrite", {}).get("CommandLine") or cmd
  res.setdefault("decision", "allow")

  if DIRENV:
      prefix = f'eval "$({DIRENV} export bash)" && '
      if (
          not rewritten.startswith(prefix)
          and not rewritten.startswith('eval "$(direnv export bash)"')
          and not rewritten.startswith("direnv exec")
      ):
          res.setdefault("overwrite", {})["CommandLine"] = f"{prefix}{rewritten}"

  print(json.dumps(res))
''
