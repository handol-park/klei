# Klei: Distributed Agent Backend

## Components
- **api/**: Node.js API Gateway
- **agents/**: Python Agent Runner (with Ollama)
- **coordinator/**: Haskell State Coordinator
- **proofs/**: Lean Verification Models

## Setup
1. Enter environment: `nix develop`
2. Start Ollama: `ollama serve` (in a separate terminal)
3. Build components: see component dirs.
