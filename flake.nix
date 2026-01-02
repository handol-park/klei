{
  description = "Klei: Distributed Agent Backend Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Node ecosystem
            nodejs_20
            nodePackages.typescript
            nodePackages.typescript-language-server

            # Python ecosystem
            uv

            # Functional Programming
            ghc
            cabal-install
            haskell-language-server

            # Lean 4
            lean4

            # Utilities
            git
            ollama
          ];

          shellHook = ''
            echo "--- Klei: Distributed Agent Backend Dev Environment ---"
            echo "Node: $(node --version)"
            echo "TypeScript: $(tsc --version)"
            echo "UV: $(uv --version)"
            echo "GHC: $(ghc --version)"
            echo "Lean: $(lean4 --version)"
          '';
        };
      }
    );
}
