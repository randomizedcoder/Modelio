{
  description = "Modelio – open-source UML/BPMN modeling tool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    # Pinned Modelio source for maven dependency fetching.
    # This ensures the maven deps FOD only changes when you explicitly
    # run: nix flake update modelio-src
    modelio-src = {
      url = "github:randomizedcoder/Modelio/53eb60381eac57b313ea862208b3d38652bf59b9";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      modelio-src,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        modelio = pkgs.callPackage ./nix/package.nix { inherit modelio-src; };
      in
      {
        packages = {
          default = modelio;
          inherit modelio;
          container = pkgs.callPackage ./nix/container.nix { inherit modelio; };
        };

        devShells.default = pkgs.callPackage ./nix/shell.nix { };

        checks.default = pkgs.callPackage ./nix/test.nix { inherit modelio; };

        formatter = pkgs.nixfmt;
      }
    );
}
