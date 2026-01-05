# Repository Guidelines

## Project Structure & Module Organization

- `core/` holds the primary Lean 4 application, including `Klei/` modules and the `FFI/` C shim for socket work.
- `proofs/` is a separate Lean project for verification models.
- `api/` is a legacy Node.js gateway (standby/unused in current architecture).
- `agents/` is a legacy Python runner (standby/unused in current architecture).
- `_planning/` contains architecture and requirements notes.

## Build, Test, and Development Commands

- `nix develop`: enter the reproducible dev shell.
- `start-ollama`: helper defined by the Nix shell to start Ollama and pull `llama3.2`.
- `cd core && lake build`: build the Lean core.
- `cd core && lake exe core`: run the REPL chat interface.
- `cd core && lake exe test-socket`: run the socket test executable.
- `cd core && lake exe test-http`: run the HTTP stack tests.
- `cd proofs && lake build`: build the proof project.
- Legacy: `cd api && npm install && npm run build && npm start`, `cd agents && uv sync && uv run main.py`.

## Coding Style & Naming Conventions

- Lean modules use `PascalCase` filenames and are grouped under `core/Klei/`.
- C sources in `core/FFI/` use `snake_case` filenames.
- Match existing formatting in each language; no repo-wide formatter is enforced.

## Testing Guidelines

- Prefer running `lake exe test-socket` and `lake exe test-http` for core changes.
- There is no stated coverage requirement; include focused tests when adding protocol logic.

## Commit & Pull Request Guidelines

- Commit messages follow imperative, sentence-case summaries (e.g., “Add HTTP client implementation”).
- PRs should include a short summary, test commands run, and links to related issues or planning docs.
- Note when changes touch legacy components (`api/`, `agents/`) or FFI code (`core/FFI/`).

## Configuration Notes

- Primary runtime uses Ollama over HTTP; set `OLLAMA_HOST` if not using the default `127.0.0.1:11434`.
- Use `OLLAMA_MODELS` as configured by the Nix shell for local model storage.
