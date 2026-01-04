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

            # Lean ecosystem
            elan

            # C/C++ toolchain for FFI
            gcc
            gnumake

            # Utilities
            git

            # Ollama for local AI model hosting
            (ollama.override { acceleration = "cuda"; })
          ];

          shellHook = ''
            echo "--- Klei: Distributed Agent Backend Dev Environment ---"
            echo "Node: $(node --version)"
            echo "TypeScript: $(tsc --version)"
            echo "UV: $(uv --version)"
            echo "Lean: $(lean --version)"

            # Ollama Configuration
            export OLLAMA_MODELS="$PWD/.ollama/models"
            export OLLAMA_HOST="127.0.0.1:11434"

            # Ensure Ollama can find its libraries on WSL
            export LD_LIBRARY_PATH="/usr/lib/wsl/lib:$LD_LIBRARY_PATH"

            # Helper function to start Ollama and pull models
            start-ollama() {
              echo "Setting up Ollama..."
              mkdir -p "$OLLAMA_MODELS"
              
              if ! pgrep -x "ollama" > /dev/null; then
                echo "Starting Ollama server..."
                ollama serve > .ollama/server.log 2>&1 &
                OLLAMA_PID=$!
                echo "Ollama server started with PID $OLLAMA_PID"
              else
                echo "Ollama server is already running."
              fi

              echo "Waiting for Ollama to be ready..."
              while ! curl -s http://$OLLAMA_HOST/api/tags > /dev/null; do
                sleep 1
              done
              echo "Ollama is ready!"

              if ! ollama list | grep -q "llama3.2"; then
                echo "Pulling llama3.2 model..."
                ollama pull llama3.2
              else
                echo "Model llama3.2 is already available."
              fi
              
              echo "Ollama setup complete. Server running at http://$OLLAMA_HOST"
            }

            echo ""
            echo "Run 'start-ollama' to initialize the AI backend."
          '';
        };
      }
    );
}
