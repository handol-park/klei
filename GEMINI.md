# Klei: Distributed Agent Backend

## Project Overview

Klei is a distributed agent backend system designed to provide a CLI-based conversation interface powered by local LLMs. The project has evolved to prioritize **Lean 4** as the primary core for logic, state management, and communication, replacing earlier Python and Node.js components.

**Current Version:** 0.1.0 (Simple Conversation Partner)

## Architecture

The system follows a **Lean-only approach** where the Lean core directly communicates with the LLM provider.

*   **Core (`core/`):** A Lean 4 application that handles the REPL, manages state, and communicates with the LLM.
*   **LLM Provider:** Currently uses **Ollama** via HTTP/JSON. Future versions target **vLLM** via Unix Domain Sockets.
*   **Verification (`proofs/`):** Separate Lean project for formal verification models.
*   **Legacy:** The `api/` (Node.js) and `agents/` (Python) directories are deprecated/standby components.

## Development Environment

This project uses **Nix** to manage a reproducible development environment.

### Initial Setup

1.  **Enter the environment:**
    ```bash
    nix develop
    ```

2.  **Initialize Ollama:**
    Run the helper function defined in `flake.nix` to start the server and pull the default model (`llama3.2`).
    ```bash
    start-ollama
    ```

## Building and Running

### Lean Core (Primary)

The core application provides a REPL interface for chatting with the LLM.

```bash
cd core

# Build the executable
lake build

# Run the REPL
lake exe core
```

### Proofs

```bash
cd proofs
lake build
```

## Key Files & Directories

*   **`core/Main.lean`**: Entry point for the Lean application. Contains the REPL loop.
*   **`core/Klei/Ollama.lean`**: Handles HTTP communication with the Ollama API (currently using `curl` subprocesses).
*   **`core/lakefile.lean`**: Lake build configuration for the core project (includes C FFI compilation).
*   **`core/FFI/`**: C implementation of the socket communication layer.
*   **`flake.nix`**: Defines the Nix development environment and the `start-ollama` helper script.
*   **`_planning/`**: Contains architectural decisions (`2-architecture/`) and requirements (`1-requirements/`).

## Development Conventions

*   **Language:** Lean 4 is the primary language for new development.
*   **Build System:** Use `lake` for building and running Lean code.
*   **Environment:** Always run commands inside the `nix develop` shell.
*   **LLM Configuration:**
    *   `OLLAMA_HOST` defaults to `127.0.0.1:11434`.
    *   `OLLAMA_MODELS` is set to `.ollama/models` within the project.
