{
  description = "Modelio – open-source UML/BPMN modeling tool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        modelio = pkgs.callPackage ./nix/package.nix { };
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
