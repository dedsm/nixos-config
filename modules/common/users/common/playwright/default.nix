{ lib, homeManagerConfig, pkgs, ... }:
let
  cfg = homeManagerConfig.playwright or {};
  enable = cfg.enable or false;
  isLinux = pkgs.stdenv.isLinux;

  # Playwright MCP support - dynamically resolve chromium path (Linux only, works natively on Darwin)
  pw = pkgs.playwright-driver;
  chromiumRevision = pw.browsersJSON.chromium.revision;
  playwrightChromiumPath = "${pw.browsers}/chromium-${chromiumRevision}/chrome-linux64/chrome";
  playwrightMcpCacheDir = "$HOME/.cache/playwright-mcp/profiles";

  mkdir = "${pkgs.coreutils}/bin/mkdir";
in
lib.mkIf (enable && isLinux) {
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pw.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_MCP_USER_DATA_DIR = "${playwrightMcpCacheDir}";
    PLAYWRIGHT_MCP_EXECUTABLE_PATH = playwrightChromiumPath;
  };

  home.activation.ensurePlaywrightCacheDir = {
    after = ["writeBoundary"];
    before = [];
    data = ''
      $DRY_RUN_CMD ${mkdir} -p "${playwrightMcpCacheDir}"
    '';
  };
}
