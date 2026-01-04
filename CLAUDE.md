# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Klei is a distributed agent backend system that provides a CLI-based conversation interface powered by local LLMs via Ollama. The architecture has evolved to use **Lean as the primary core** for logic, state management, and LLM communication, with legacy Python/TypeScript components present but not actively used.

**Current Version: 0.1.0** - Simple Conversation Partner (MVP complete)

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

## Version History & Roadmap

### v0.1.0 - Simple Conversation Partner (Current)
**Status: Complete**

Features:
- CLI-based REPL interface for chatting with local LLMs
- Lean 4 core that communicates directly with Ollama via curl/HTTP
- Simple JSON request/response handling
- Support for llama3.2 model (3B parameters)
- Environment-based Ollama host configuration

### v0.2.0 - vLLM Communication Channel (Planned)

**Focus:** Replace HTTP/curl with high-performance Unix Domain Sockets

**Scope:**
- **Inference Engine:** Replace Ollama with **vLLM**
  - PagedAttention for efficient memory management
  - OpenAI-compatible API
  - Support for larger models (20B parameters)
  - 32k+ context window support

- **Communication Layer:** Unix Domain Sockets (UDS) implementation
  - C shim for POSIX socket operations (`socket.h` wrapper)
  - Lean 4 FFI bindings for type-safe socket API
  - JSON-RPC protocol layer over UDS
  - Security: POSIX filesystem permissions, no network exposure
  - Performance: < 50μs latency vs ~100-200μs for HTTP

- **Environment Setup:** vLLM integration in Nix development shell
  - Automated vLLM setup similar to current `start-ollama`
  - CUDA acceleration support
  - VRAM-optimized configuration

**Target Environment:** 16 GB VRAM
- Model: ~11-13 GB (Q4 quantization)
- KV Cache: ~3-5 GB (supporting 32k+ tokens)

**Out of Scope:** Tool calling, MCP, formal verification (deferred to later versions)

### v0.3.0 - Tool Calling System (Future)

**Focus:** Type-safe tool execution framework

Planned features:
- Formal verification of tool schemas using dependent types
- Verified state machine for agent orchestration
- Tool registry with compile-time validation
- JSON parser with schema conformance proofs
- Kleisli category for composable tool actions

### v0.4.0 - Model Context Protocol (Future)

**Focus:** MCP integration for standardized tool interfaces

Planned features:
- MCP server/client implementation
- Native vLLM MCP support
- Standard tool protocols
- Multi-tool orchestration

### v0.5.0 - Web Search Integration (Future)

**Focus:** External information retrieval

Planned features:
- Web search tool implementation
- Search result parsing and ranking
- Integration with agent reasoning loop
