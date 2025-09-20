{ slack }:

slack.overrideAttrs (oldAttrs: {
  # postFixup runs after the default installPhase, allowing us to patch the
  # final wrapper script that nixpkgs generates.
  postFixup = (oldAttrs.postFixup or "") + ''
    # We are replacing the unreliable 'auto' hint with an explicit command
    # to use the Wayland Ozone platform. This is more robust than adding a
    # new layer of wrapping.
    sed -i 's/--ozone-platform-hint=auto/--ozone-platform=wayland/' $out/bin/slack
  '';
})
