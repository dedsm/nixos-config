{ config, pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
lib.mkIf isDarwin {
  home.activation.installCLINotify = {
    after = ["writeBoundary"];
    before = [];
    data = ''
      APP_SRC="${pkgs.local.cli-notify}/Applications/CLINotify.app"
      APP_DEST="$HOME/Applications/CLINotify.app"
      STAMP="$HOME/Applications/.cli-notify.nix-store-path"

      $DRY_RUN_CMD mkdir -p "$HOME/Applications"

      if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$APP_SRC" ]; then
        $DRY_RUN_CMD rm -rf "$APP_DEST"
        $DRY_RUN_CMD cp -R "$APP_SRC" "$APP_DEST"
        $DRY_RUN_CMD chmod -R u+w "$APP_DEST"
        # Re-sign with host codesign so Info.plist is bound into the signature.
        # Nix's sigtool only signs Mach-O files, not the bundle — without this,
        # TCC refuses notification authorization.
        $DRY_RUN_CMD /usr/bin/codesign --force --deep --sign - "$APP_DEST"
        $DRY_RUN_CMD sh -c "echo '$APP_SRC' > '$STAMP'"
      fi
    '';
  };
}
