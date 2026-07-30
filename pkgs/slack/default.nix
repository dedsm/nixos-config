{ slack }:

slack.overrideAttrs (oldAttrs: {
  # This is a wrapper around the nixpkgs package, so its version tracks the
  # `unstable` flake input and `nix flake update` is the updater. Drop the
  # inherited `updateScript`, which belongs to a nixpkgs checkout and would
  # otherwise be picked up by scripts/update-packages.sh.
  passthru = builtins.removeAttrs (oldAttrs.passthru or { }) [ "updateScript" ];

  # postFixup runs after the default installPhase, allowing us to patch the
  # final wrapper script that nixpkgs generates.
  postFixup = (oldAttrs.postFixup or "") + ''
    # We are replacing the unreliable 'auto' hint with an explicit command
    # to use the Wayland Ozone platform. This is more robust than adding a
    # new layer of wrapping.
    sed -i 's/--ozone-platform-hint=auto/--ozone-platform=wayland/' $out/bin/slack
  '';
})
