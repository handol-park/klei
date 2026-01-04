# Project Vision: Klei

"Klei" is designed to be the **ultimate personal agentic AI**.
It serves as a **personal knowledge maintainer** and **productivity assistant**.

## Core Philosophy

### 1. Gradual Growth
Start small ("lean") and grow iteratively. Each version builds incrementally on the previous foundation:
- v0.1.0: Simple conversation partner (MVP) ✓ **COMPLETE**
- v0.2.0: High-performance communication channel
- v0.3.0: Type-safe tool calling system
- v0.4.0: Model Context Protocol integration
- v0.5.0: Web search and external data retrieval

### 2. Primary Language: Lean 4
The project is written primarily in **Lean 4**, utilizing its unique strengths:
- **Dependent Types**: For compile-time correctness guarantees
- **Formal Verification**: Prove agent behavior is correct before execution
- **Functional Programming**: Pure, composable, and maintainable code
- **FFI Capability**: Interface with C for performance-critical operations

Other languages (C for socket operations, shell for tooling) are used only when necessary.

### 3. Initial Domain
Software development and learning assistant, with potential to expand into:
- Personal knowledge management
- Task automation
- Research assistance
- Creative workflows

## Evolution of the Vision

### Phase 1: Foundation (v0.1.0) ✓ COMPLETE
**Goal**: Prove the Lean-only approach works

**Architecture:**
```
User (CLI) <--> Lean Core <--> Ollama LLM (HTTP)
```

**Achievements:**
- CLI-based REPL for chatting with local LLMs
- Lean 4 core communicates directly with Ollama via curl/HTTP
- Simple JSON request/response handling
- Support for llama3.2 model (3B parameters)
- Environment-based configuration

**Key Insight:** Lean 4 is viable for building complete applications, not just proofs.

### Phase 2: Performance (v0.2.0) ← CURRENT
**Goal**: Build a high-performance communication foundation

**Architecture:**
```
User (CLI) <--> Lean Core <--> [Unix Domain Socket] <--> vLLM (20B model)
```

**Objectives:**
- Replace HTTP/curl with Unix Domain Sockets (< 50μs latency)
- Migrate from Ollama to vLLM for better performance and larger models
- Support 20B parameter models in 16 GB VRAM
- 32k+ context window
- C FFI for socket operations

**Key Innovation:** Direct socket communication eliminates network stack overhead and subprocess spawning.

### Phase 3: Intelligence (v0.3.0) - FUTURE
**Goal**: Add type-safe tool calling with formal verification

**Architecture:**
```
User <--> Lean Core <--> vLLM
              ↓
        Verified State Machine
              ↓
        Type-Safe Tools
```

**Planned Features:**
- Formal verification of agent state transitions
- Tool schemas as dependent types
- JSON parser with schema conformance proofs
- Kleisli category for composable tool actions
- Compile-time guarantee that tool calls are valid

**Key Innovation:** Impossible to execute invalid tool calls—proven at compile time.

### Phase 4: Ecosystem (v0.4.0+) - FUTURE
**Goal**: Integrate with broader AI ecosystem

**Planned Features:**
- Model Context Protocol (MCP) server/client
- Web search integration
- Multi-tool orchestration
- External data sources
- Persistent knowledge base

## Current Architecture (v0.1.0)

**Core Logic**: Lean 4
- Application entry point
- REPL loop
- Conversation state management
- LLM API client

**Interface**: CLI (Lean Executable)
- Interactive terminal-based chat
- Commands: `/exit` to quit

**External Dependencies**:
- Ollama: Local LLM inference (HTTP API)
- curl: HTTP communication (subprocess)
- Nix: Development environment

**Legacy Components** (not actively used):
- `api/`: Node.js API gateway (standby)
- `agents/`: Python agent runner (legacy)

## Target Architecture (v0.2.0+)

**Core Logic**: Lean 4
- Application entry point
- REPL loop
- State machine orchestration
- vLLM client (UDS)
- Tool execution engine (v0.3.0+)

**Communication Layer**:
- C shim: POSIX socket operations
- Lean FFI: Type-safe bindings
- JSON-RPC: Protocol over UDS

**Inference Engine**: vLLM
- PagedAttention for memory efficiency
- OpenAI-compatible API
- Unix Domain Socket listener
- Support for 20B models in 16 GB VRAM

**Future Extensions**:
- Tool registry (v0.3.0)
- MCP integration (v0.4.0)
- Web search (v0.5.0)

## Success Criteria

### MVP (v0.1.0) ✓ COMPLETE
- [x] User can chat with local LLM via CLI
- [x] Lean core manages conversation state
- [x] HTTP communication works reliably
- [x] Simple and functional

### High-Performance Communication (v0.2.0)
- [ ] UDS communication < 50μs latency
- [ ] vLLM serving 20B model in 16 GB VRAM
- [ ] 32k context window supported
- [ ] REPL experience identical to v0.1.0
- [ ] Backend abstraction (Ollama/vLLM switchable)

### Type-Safe Tools (v0.3.0)
- [ ] Tool calls formally verified
- [ ] State machine proven correct
- [ ] JSON parser with schema proofs
- [ ] Impossible to construct invalid tool calls

### Ecosystem Integration (v0.4.0+)
- [ ] MCP server/client operational
- [ ] Web search functional
- [ ] Multi-tool orchestration
- [ ] Production-ready for daily use

## Design Principles

### 1. Correctness First
Use Lean's type system to prove correctness at compile time. Runtime errors are bugs in our proofs.

### 2. Performance Matters
Target sub-millisecond overhead for orchestration. The LLM is slow; everything else should be fast.

### 3. Security by Design
- No network exposure (Unix Domain Sockets only)
- POSIX permissions for access control
- Input validation at all boundaries
- Minimal attack surface

### 4. Developer Experience
- Single command to start (`nix develop`)
- Clear error messages
- Fast iteration cycles
- Comprehensive documentation

### 5. Incremental Delivery
Each version is usable and valuable on its own. No "big bang" releases.

## Long-Term Vision

Klei aims to be:

1. **Your Second Brain**: Maintain context across all your work
2. **Your Research Assistant**: Search, synthesize, and reason over information
3. **Your Automation Engine**: Execute complex workflows with verified correctness
4. **Your Learning Partner**: Explain, teach, and grow with you
5. **100% Under Your Control**: Local-first, privacy-preserving, transparent

Built on a foundation of:
- **Formal Verification**: Mathematical proofs of correctness
- **High Performance**: Optimized for low latency and memory efficiency
- **Local-First**: Your data stays on your machine
- **Open Architecture**: Extensible, hackable, understandable

## References

For detailed technical planning, see:
- `02-vllm-orchestrator-vision.md`: Original discussion summary and technical vision
- `../1-requirements/`: Detailed requirements for each version
- `../2-architecture/`: System design documents
- `../3-specification/`: Technical specifications
- `../4-implementation/`: Implementation plans

