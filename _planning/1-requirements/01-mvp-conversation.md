# Requirements: MVP - Simple Conversation Partner

## Goal
Establish a basic CLI-based conversation loop where the user can chat with the Klei system. This serves as the foundation for the "Personal Agentic AI Backend".

## Functional Requirements
1.  **CLI Interface**:
    *   User launches the application from the terminal.
    *   User inputs text prompts.
    *   System prints responses to the terminal.
    *   Support for a command to exit (e.g., `/exit` or `Ctrl+C`).

2.  **Core Logic (Lean)**:
    *   The main entry point should be a Lean program.
    *   It should handle the read-eval-print loop (REPL).
    *   It needs to invoke the AI agent to generate responses.

3.  **AI Integration (Python)**:
    *   Reuse/Refine the existing `agents/` Python code as a service or subprocess.
    *   Must connect to Ollama to generate text.
    *   Must accept input from the Lean Core and return the generated text.

## Non-Functional Requirements
*   **Modularity**: The Lean core should be decoupled from the specific LLM implementation (initially Python/Ollama).
*   **Performance**: Reasonable latency for local inference.

## Integration Flows
`User (CLI) -> Lean Core -> [Process/Socket] -> Python Agent -> Ollama -> [Return Path]`

## Open Questions
*   How will Lean communicate with Python?
    *   *Option A*: Lean calls Python script as a subprocess for every generation (simpler for MVP).
    *   *Option B*: Python runs as a daemon/server (HTTP/gRPC/Socket), Lean calls it (better for performance/context).
    *   *Decision for MVP*: Start with subprocess or simple HTTP request if Lean has easy HTTP support? Let's check Lean's capabilities or stick to subprocess for simplicity unless advised otherwise.
