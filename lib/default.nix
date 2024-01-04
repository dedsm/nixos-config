attrs@{ system, ... }: rec {
  host = import ./host.nix attrs;
}
