{
  description = "emberglass: Apple silicon sensors in your panel (KDE Plasma widget, Waybar module, MangoHud line)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAll = f: nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: rec {
        emberglass = pkgs.callPackage ./nix/package.nix { };
        default = emberglass;
      });
      nixosModules.default = import ./nix/module.nix;
      nixosModules.emberglass = self.nixosModules.default;
    };
}
