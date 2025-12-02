attrs@{ system, ... }: rec {
  nixosHost = import ./nixos-host.nix attrs;
  darwinHost = import ./darwin-host.nix attrs;
}
