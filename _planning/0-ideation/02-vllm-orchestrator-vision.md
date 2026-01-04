# Ideation: High-Performance vLLM Orchestrator

## Discussion Summary

This conversation focused on architecting a high-performance, secure, and formally verified local LLM orchestrator using **Lean 4**, targeting a **16 GB VRAM** environment.

---

## Key Decisions & Architecture

### The Model
We identified **GPT-OSS 20B (Q4 quantization)** or **Qwen3 14B** as the ideal candidates. These provide advanced reasoning and tool-calling capabilities while leaving enough VRAM (~3–5 GB) for a substantial KV cache (supporting up to 32k+ context).

**VRAM Budget (16 GB total):**
- Model weights: ~11-13 GB (Q4 quantization)
- KV Cache: ~3-5 GB (supporting 32k+ tokens)
- Overhead: ~1-2 GB

### Inference Engine
**vLLM** was selected as the primary recommendation due to its:
- Efficient memory management (PagedAttention)
- Critical for long-context windows in constrained VRAM
- OpenAI-compatible API
- Unix Domain Socket support
- Note: Original discussion mentioned 2026-era native **MCP (Model Context Protocol)** support, though this is planned for v0.4.0

### The Orchestrator
Building in **Lean 4** to leverage its strong typing and formal verification capabilities. The original vision discussed modeling the agent's decision-making as a **Verified State Machine** or **Kleisli Category**, ensuring that tool calls are type-safe and logically sound before execution.

---

## Security & Communication

### Transport Layer
We moved away from standard HTTP/TCP in favor of **Unix Domain Sockets (UDS)**.

### Benefits of UDS
- **Security:** Limits access via POSIX filesystem permissions (no network exposure)
- **Performance:** Lower latency and higher throughput compared to the local networking stack
  - UDS: ~10-50μs latency
  - TCP/HTTP: ~100-200μs latency

### Implementation
We established a technical path using **Lean 4's FFI** to link a C-based shim, allowing the orchestrator to communicate directly with vLLM via the socket.

---

## Technical Components Identified

### 1. C Shim
A boilerplate for `socket.h` to handle the `AF_UNIX` connection and data transmission.

Key functions:
- `klei_socket_connect(path)`: Establish UDS connection
- `klei_socket_send(sock, data, len)`: Send data
- `klei_socket_recv(sock, buffer, size, timeout)`: Receive data
- `klei_socket_close(sock)`: Clean up resources
- `klei_socket_error(sock)`: Get error messages

### 2. Lean 4 Bindings
An `extern` interface to bridge the C socket logic into a Lean monad.

Implementation approach:
- Opaque `SocketHandle` type
- FFI declarations with `@[extern]` attribute
- IO monad for effectful operations
- Type-safe wrappers with error handling

### 3. VRAM Strategy
Specific `vllm serve` configurations to optimize the 16 GB footprint using 4-bit quantization and specific memory utilization flags.

Example configuration:
```bash
vllm serve MODEL_NAME \
  --quantization awq \
  --dtype half \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.90 \
  --kv-cache-dtype auto \
  --enable-prefix-caching \
  --uvicorn-unix-socket /tmp/vllm.sock \
  --uvicorn-unix-socket-perms 0600
```

### 4. Formal Verification (Future)
Lean 4 logic for:
- JSON parser that maps LLM tool-call outputs into formal inductive types
- Verified state machine for agent orchestration
- Type-safe tool schemas using dependent types
- Kleisli category for composable tool actions

---

## Phased Implementation

Based on this discussion, the vision has been broken down into multiple releases:

### v0.2.0 - Communication Foundation
**Focus:** vLLM integration with Unix Domain Sockets

Implements:
- C shim for socket operations
- Lean FFI bindings
- JSON-RPC protocol over UDS
- vLLM client with OpenAI-compatible API
- Backend abstraction (Ollama vs vLLM)

Out of scope:
- Tool calling
- Formal verification
- MCP integration

### v0.3.0 - Tool Calling System
**Focus:** Type-safe tool execution

Plans to implement:
- Verified state machine for agent orchestration
- Tool registry with compile-time validation
- JSON parser with schema conformance proofs
- Dependent types for tool schemas
- Kleisli category for composable tool actions

### v0.4.0 - MCP Integration
**Focus:** Model Context Protocol

Plans to implement:
- MCP server/client implementation
- Native vLLM MCP support
- Standard tool protocols
- Multi-tool orchestration

### v0.5.0 - Web Search
**Focus:** External information retrieval

Plans to implement:
- Web search tool
- Search result parsing and ranking
- Integration with agent reasoning loop

---

## Design Principles

### 1. Performance First
- Target < 50μs latency for UDS communication
- Efficient VRAM utilization (90% max)
- PagedAttention for KV cache management
- Prefix caching for common prompts

### 2. Security by Design
- Unix Domain Sockets (no network exposure)
- POSIX filesystem permissions (0600 on socket)
- Input validation at boundaries
- Minimal attack surface

### 3. Correctness Through Types
- Lean's dependent type system for verification
- Impossible to construct invalid states
- Compile-time guarantees for critical paths
- Runtime safety through formal proofs

### 4. Gradual Enhancement
- Each version builds on the previous
- Backwards compatibility maintained
- Feature flags for experimental features
- Clear migration paths

---

## Success Criteria (Full Vision)

The complete vision is realized when:

1. ✓ vLLM runs 20B Q4 model in 16 GB VRAM
2. ✓ Communication via UDS with < 50μs latency
3. ✓ 32k+ context window supported
4. ✓ Tool calls are type-safe and formally verified
5. ✓ Agent state machine is proven correct
6. ✓ JSON parser maps LLM outputs to verified Lean types
7. ✓ MCP integration for standardized tools
8. ✓ Web search and external data retrieval
9. ✓ End-to-end formal verification of orchestrator
10. ✓ Production-ready personal AI backend

---

## Open Questions (For Future Versions)

1. **State Machine Design:** Kleisli Category vs Inductive State Machine?
2. **Context Management:** Optimal pruning strategy at 32k limit?
3. **Tool Execution:** Synchronous vs asynchronous?
4. **Streaming:** How to handle streaming responses from vLLM?
5. **Recovery:** Fallback strategy if vLLM crashes?
6. **Concurrency:** Multi-threaded tool execution?
7. **Persistence:** Long-term conversation storage?
8. **Multi-Model:** Orchestrate multiple models for different tasks?

---

## References

- vLLM Documentation: https://docs.vllm.ai/
- Lean 4 Manual: https://lean-lang.org/lean4/doc/
- Unix Domain Sockets: POSIX specification
- PagedAttention: vLLM's memory-efficient attention mechanism
- MCP: Model Context Protocol (Anthropic)
