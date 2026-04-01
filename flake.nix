{
  description = "worktigre - Git worktree manager with fzf integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          worktigre = pkgs.callPackage ./default.nix {};
          default = self.packages.${system}.worktigre;
        };
      }
    ) // {
      overlays.default = final: prev: {
        worktigre = final.callPackage ./default.nix {};
      };
    };
}
