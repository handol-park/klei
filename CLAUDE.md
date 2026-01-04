# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Klei is a distributed agent backend system that provides a CLI-based conversation interface powered by local LLMs via Ollama. The architecture has evolved to use **Lean as the primary core** for logic, state management, and LLM communication, with legacy Python/TypeScript components present but not actively used.

### Current Architecture

The system follows a **Lean-only approach** where the Lean core directly communicates with Ollama's REST API:

```
User (CLI) <--> Lean Core <--> Ollama LLM (HTTP/JSON)
```

- **core/**: Lean 4 application - handles REPL, state, and HTTP communication with Ollama
- **proofs/**: Lean verification models (separate Lake project)
- **agents/**: Legacy Python agent runner (not actively used in current architecture)
- **api/**: Legacy Node.js API gateway (standby/unused)

## Development Environment Setup

This project uses Nix flakes for reproducible development environments.

### Initial Setup

```bash
# Enter the Nix development shell
nix develop

# Start Ollama server (in a separate terminal or use the helper function)
start-ollama
```

The `start-ollama` helper function:
- Starts the Ollama server if not running
- Pulls the `llama3.2` model if not available
- Configures Ollama to use `.ollama/models` for model storage
- Sets `OLLAMA_HOST=127.0.0.1:11434`

## Building and Running

### Lean Core (Primary Component)

```bash
cd core

# Build the Lean executable
lake build

# Run the REPL chat interface
lake exe core
```

The core application provides a REPL interface:
- Type messages to chat with the LLM
- Type `/exit` to quit
- Uses `llama3.2` model by default

### Proofs

```bash
cd proofs

# Build Lean proofs
lake build
```

### Legacy Components (Not Currently Used)

**API (Node.js - standby):**
```bash
cd api
npm install
npm run build
npm start
```

**Agents (Python - legacy):**
```bash
cd agents
uv sync          # Install dependencies
uv run main.py   # Run agent runner
```

## Code Architecture

### Lean Core Structure

The Lean codebase is organized as follows:

- **Main.lean** (core/Main.lean:1): Entry point containing the REPL loop
  - Handles user input/output
  - Manages the read-eval-print cycle
  - Calls Ollama API for text generation

- **Klei/Ollama.lean** (core/Klei/Ollama.lean:1): Ollama API integration
  - `Request` and `Response` data structures with JSON serialization
  - `generate` function (core/Klei/Ollama.lean:19): Makes HTTP POST requests to Ollama using `curl`
  - Respects `OLLAMA_HOST` environment variable
  - Default model: `llama3.2`

- **Klei.lean** (core/Klei.lean:1): Library root - imports all library modules

### Lean Build Configuration

- **lakefile.toml** (core/lakefile.toml:1): Lake build configuration
  - Defines `Klei` library and `core` executable
  - Package name: "core", version: "0.1.0"

- **lean-toolchain** (core/lean-toolchain:1): Specifies Lean version
  - Current: `leanprover/lean4:4.25.0`

### Communication Model

The current implementation uses **curl subprocess calls** for HTTP communication:
- Lean's `IO.Process.run` executes curl commands
- JSON serialization/deserialization via Lean's built-in JSON support
- Ollama API endpoint: `http://${OLLAMA_HOST}/api/generate`

## Key Technologies

- **Lean 4**: Functional programming language with dependent types
- **Lake**: Lean's build system and package manager
- **Ollama**: Local LLM inference server
- **Nix**: Reproducible development environment management

## Environment Variables

- `OLLAMA_HOST`: Ollama server address (default: `127.0.0.1:11434`)
- `OLLAMA_MODELS`: Model storage location (set to `.ollama/models` in dev shell)
- `LD_LIBRARY_PATH`: Required for WSL GPU support

## Project Planning Documents

The `_planning/` directory contains architecture decisions and requirements:
- **_planning/2-architecture/01-system-design.md**: Explains the decision to use Lean-only architecture
- **_planning/1-requirements/01-mvp-conversation.md**: MVP requirements for CLI conversation interface
- **_planning/0-ideation/01-project-vision.md**: Original project vision
