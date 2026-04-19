{
  description = "Apollo is a Game stream host for Moonlight";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/9cf7092bdd603554bd8b63c216e8943cf9b12512"; # rev I happened to be using at the moment
  };
  outputs = {nixpkgs, ...}: let
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    overlay = final: prev: {
      apollo = final.callPackage ./default.nix {};
      apollo-cuda = final.callPackage ./default.nix {
        cudaSupport = true;
      };
    };

    overlays = [overlay];

    forEachSupportedSystem = overlays: f:
      nixpkgs.lib.genAttrs supportedSystems (
        system:
          f {
            pkgs = import nixpkgs {
              inherit system overlays;
              config = {allowUnfree = true;};
            };
            inherit system;
          }
      );

    perSystem = {
      pkgs,
      system,
    }: {
      packages = {
        default = pkgs.apollo;
        apollo = pkgs.apollo;
        apollo-cuda = pkgs.apollo-cuda;
      };

      apps = {
        default = {
          type = "app";
          program = "${pkgs.apollo}/bin/sunshine";
        };

        apollo = {
          type = "app";
          program = "${pkgs.apollo}/bin/sunshine";
        };

        apollo-cuda = {
          type = "app";
          program = "${pkgs.apollo-cuda}/bin/sunshine";
        };
      };

      devShells = {
        default = pkgs.mkShell {
          inputsFrom = [pkgs.apollo];
          packages = [
            pkgs.cmake
            pkgs.gdb
          ];
        };
      };
    };

    systems = forEachSupportedSystem overlays perSystem;
  in {
    packages = nixpkgs.lib.mapAttrs (_: v: v.packages) systems;
    apps = nixpkgs.lib.mapAttrs (_: v: v.apps) systems;
    devShells = nixpkgs.lib.mapAttrs (_: v: v.devShells) systems;

    overlays.default = overlay;
    nixosModules.default = ./apollo-module.nix;
  };
}
