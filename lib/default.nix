attrs@{ mkPkgs, ... }:
{
  nixosHost = import ./nixos-host.nix attrs;
  darwinHost = import ./darwin-host.nix attrs;
}
