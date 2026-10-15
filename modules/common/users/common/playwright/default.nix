{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  cfg = homeManagerConfig.playwright or { };
  enable = cfg.enable or false;
  isLinux = pkgs.stdenv.isLinux;

  # Playwright MCP support - dynamically resolve chromium path (Linux only, works natively on Darwin)
  pw = pkgs.playwright-driver;
  chromiumRevision = pw.browsersJSON.chromium.revision;
  playwrightChromiumPath = "${pw.browsers}/chromium-${chromiumRevision}/chrome-linux64/chrome";

  # Claude Code's wrapper (pkgs.unstable) prefixes LD_LIBRARY_PATH with
  # unstable's alsa-lib, which needs a newer glibc than this nixpkgs' Chromium
  # links; every MCP server it spawns inherits it and Chromium dies with
  # "GLIBC_2.43 not found". The browser finds its own libraries without it.
  playwrightChromium = pkgs.writeShellScript "playwright-mcp-chromium" ''
    unset LD_LIBRARY_PATH
    exec ${playwrightChromiumPath} "$@"
  '';
  playwrightMcpCacheDir = "$HOME/.cache/playwright-mcp/profiles";

  mkdir = "${pkgs.coreutils}/bin/mkdir";
in
lib.mkIf (enable && isLinux) {
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pw.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_MCP_USER_DATA_DIR = "${playwrightMcpCacheDir}";
    PLAYWRIGHT_MCP_EXECUTABLE_PATH = "${playwrightChromium}";
  };

  home.activation.ensurePlaywrightCacheDir = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      $DRY_RUN_CMD ${mkdir} -p "${playwrightMcpCacheDir}"
    '';
  };
}
