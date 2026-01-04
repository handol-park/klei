# Specification: Formal Verification Strategy

## Overview

This document specifies the formal verification approach for v0.2.0, ensuring that the agent orchestrator is mathematically proven correct at compile time.

## Goals

1. **Type Safety**: Impossible to construct invalid tool calls or state transitions
2. **Correctness**: State machine transitions are proven to maintain invariants
3. **Totality**: All functions are total (no runtime panics or undefined behavior)
4. **Composability**: Verified components can be composed while preserving guarantees

## Verification Scope

### In Scope for v0.2.0

✓ Tool call parsing and validation
✓ State machine transition correctness
✓ JSON parser correctness (schema conformance)
✓ Context window bounds checking
✓ Type-safe API boundaries

### Out of Scope for v0.2.0

✗ Tool execution correctness (tools have side effects)
✗ LLM output quality or factuality
✗ Network/socket layer correctness (FFI boundary)
✗ Performance guarantees (timing, memory usage)

## Core Verification Strategies

### 1. Dependent Types for Tool Schemas

**Concept**: Use Lean's dependent types to encode tool schemas such that invalid tool calls are rejected by the type checker.

**Example:**

```lean
-- Tool parameter as a dependent type
structure ToolParam where
  name : String
  type : ParamType
  required : Bool
  validate : (value : JSON) → Option (TypeOf type)

inductive ParamType where
  | string
  | number
  | boolean
  | array : ParamType → ParamType
  | object : List ToolParam → ParamType

-- Type-level function that extracts the Lean type
def TypeOf : ParamType → Type
  | .string => String
  | .number => Float
  | .boolean => Bool
  | .array t => List (TypeOf t)
  | .object params => ToolArgs params

-- Tool definition with type-safe parameters
structure VerifiedTool (params : List ToolParam) where
  name : String
  description : String
  execute : ToolArgs params → IO ToolResult
  -- Invariant: execution preserves system state properties
  preserves : ∀ args, ValidState (execute args)
```

**Benefits:**
- Compile-time guarantee that tool calls match schema
- No runtime type errors for tool parameters
- Self-documenting tool signatures

### 2. Inductive State Machine with Proofs

**Concept**: Model the agent's execution as a finite state machine where transitions are proven to maintain invariants.

**State Definitions:**

```lean
-- Agent states with embedded data
inductive AgentState where
  | idle : AgentState
  | processing :
      (prompt : String) →
      (context : ContextWindow) →
      AgentState
  | awaitingTool :
      (toolCall : ToolCall) →
      (verified : ValidTool toolCall) →  -- Proof that tool is valid
      AgentState
  | executingTool :
      (toolCall : ToolCall) →
      (handle : TaskHandle) →
      AgentState
  | responding :
      (response : String) →
      AgentState
  | error :
      (message : String) →
      (recoverable : Bool) →
      AgentState

-- State invariant
def StateInvariant : AgentState → Prop
  | .idle => True
  | .processing prompt ctx =>
      estimateTokens ctx < ctx.maxTokens ∧ prompt.length > 0
  | .awaitingTool tc _ =>
      tc.name ∈ toolRegistry.keys
  | .executingTool tc handle =>
      tc.name ∈ toolRegistry.keys ∧ handle.valid
  | .responding resp =>
      resp.length > 0
  | .error msg _ =>
      msg.length > 0
```

**Transition Function with Proof:**

```lean
-- Events that trigger transitions
inductive Event where
  | userInput : String → Event
  | llmResponse : String → Event
  | llmToolCall : ToolCall → Event
  | toolComplete : ToolResult → Event
  | timeout : Event
  | error : String → Event

-- The step function with state preservation proof
def step (s : AgentState) (e : Event) :
    { s' : AgentState // StateInvariant s → StateInvariant s' } :=
  match s, e with
  | .idle, .userInput prompt =>
      ⟨.processing prompt emptyContext, by
        intro h
        simp [StateInvariant]
        constructor
        · -- Prove token count < max
          simp [estimateTokens, emptyContext]
          exact Nat.zero_lt_succ _
        · -- Prove prompt non-empty
          sorry -- Requires validation of user input
      ⟩
  | .processing prompt ctx, .llmResponse resp =>
      -- Parse response, decide next state
      match parseResponse resp with
      | .text content =>
          ⟨.responding content, by intro h; simp [StateInvariant]⟩
      | .toolCall tc =>
          match verifyTool tc with
          | some proof =>
              ⟨.awaitingTool tc proof, by intro h; simp [StateInvariant]⟩
          | none =>
              ⟨.error "Invalid tool call" true, by intro h; simp [StateInvariant]⟩
  | .awaitingTool tc proof, .toolComplete result =>
      -- Format result and continue
      let newPrompt := formatToolResult tc result
      let newCtx := addToContext ctx result
      ⟨.processing newPrompt newCtx, by
        intro h
        simp [StateInvariant]
        -- Prove context still within bounds
        sorry
      ⟩
  | _, .error msg =>
      ⟨.error msg true, by intro h; simp [StateInvariant]⟩
  | _, _ =>
      -- Invalid transition
      ⟨.error "Invalid state transition" false, by intro h; simp [StateInvariant]⟩

-- Main theorem: step always produces valid states
theorem step_preserves_invariant (s : AgentState) (e : Event) :
    StateInvariant s → StateInvariant (step s e).val :=
  (step s e).property

-- Corollary: starting from valid state, always stay valid
theorem always_valid :
    ∀ (events : List Event),
    StateInvariant .idle →
    StateInvariant (events.foldl (fun s e => (step s e).val) .idle) := by
  intro events h
  induction events with
  | nil => exact h
  | cons e es ih =>
      simp [List.foldl]
      apply step_preserves_invariant
      exact ih
```

**Benefits:**
- Impossible to reach invalid states
- All transitions explicitly modeled
- Runtime behavior matches specification
- Proof of correctness is part of the code

### 3. Verified JSON Parser

**Concept**: Build a JSON parser that produces a proof that the parsed value conforms to the expected schema.

**Schema Definition:**

```lean
-- JSON schema as inductive type
inductive JSONSchema where
  | string : JSONSchema
  | number : JSONSchema
  | boolean : JSONSchema
  | null : JSONSchema
  | array : JSONSchema → JSONSchema
  | object : List (String × JSONSchema) → JSONSchema
  | oneOf : List JSONSchema → JSONSchema

-- Predicate: JSON value matches schema
def matches : JSON → JSONSchema → Prop
  | .str _, .string => True
  | .num _, .number => True
  | .bool _, .boolean => True
  | .null, .null => True
  | .arr values, .array schema =>
      ∀ v ∈ values, matches v schema
  | .obj fields, .object fieldSchemas =>
      (∀ (name, schema) ∈ fieldSchemas,
        ∃ value, (name, value) ∈ fields ∧ matches value schema) ∧
      (∀ (name, value) ∈ fields,
        ∃ schema, (name, schema) ∈ fieldSchemas)
  | value, .oneOf schemas =>
      ∃ schema ∈ schemas, matches value schema
  | _, _ => False
```

**Verified Parser:**

```lean
-- Parser result with proof
structure ParseResult (schema : JSONSchema) where
  value : JSON
  proof : matches value schema

-- Parse with validation
def parseWithSchema (json : JSON) (schema : JSONSchema) :
    Except String (ParseResult schema) := do
  if h : matches json schema then
    pure { value := json, proof := h }
  else
    throw s!"JSON does not match schema: {json}"

-- Example: Tool call schema
def toolCallSchema : JSONSchema :=
  .object [
    ("name", .string),
    ("arguments", .object []),  -- Simplified
    ("id", .string)
  ]

-- Type-safe tool call parser
def parseToolCall (json : JSON) : Except String ToolCall := do
  let result ← parseWithSchema json toolCallSchema
  -- Extract fields with proof that they exist
  let name := extractField result "name"
  let args := extractField result "arguments"
  let id := extractField result "id"
  pure { name, args, id }
```

**Benefits:**
- Compile-time guarantee of schema conformance
- Self-documenting schemas
- Impossible to access non-existent fields
- Basis for tool call validation

### 4. Kleisli Category for Composable Effects

**Concept**: Model agent actions as composable monadic computations with verification.

**Monad Definition:**

```lean
-- Agent action monad
def AgentM (α : Type) : Type :=
  StateT AgentState (ExceptT Error IO) α

-- Lift IO actions with error handling
def liftIO {α : Type} (action : IO α) : AgentM α := do
  try
    let result ← action
    pure result
  catch e =>
    throw (.ioError e.toString)

-- Run tool with verification
def runTool {params : List ToolParam}
    (tool : VerifiedTool params)
    (args : ToolArgs params) :
    AgentM ToolResult := do
  -- State transition: mark as executing
  modify (fun s => .executingTool tool.name args)

  -- Execute tool (verified to preserve invariants)
  let result ← liftIO (tool.execute args)

  -- State transition: back to processing
  modify (fun s => .processing (formatResult result) (updateContext result))

  pure result

-- Compose tool calls
def composeTool {α β : Type}
    (f : α → AgentM β)
    (g : β → AgentM γ) :
    α → AgentM γ := fun a => do
  let b ← f a
  g b

-- Kleisli composition preserves state invariants
theorem compose_preserves_invariant {α β γ : Type}
    (f : α → AgentM β) (g : β → AgentM γ) :
    (∀ a s, StateInvariant s → StateInvariant (f a |> runState s).fst) →
    (∀ b s, StateInvariant s → StateInvariant (g b |> runState s).fst) →
    (∀ a s, StateInvariant s → StateInvariant (composeTool f g a |> runState s).fst) := by
  sorry -- Proof by monad laws
```

**Benefits:**
- Composable, reusable agent actions
- Automatic error handling and state management
- Verified composition
- Functional programming style

## Proof Strategy

### Axioms and Trusted Components

We accept the following as axiomatic (no formal proof):

1. **Lean's type system**: We trust Lean 4's kernel
2. **FFI boundary**: C socket code is not verified
3. **vLLM correctness**: We don't verify the LLM itself
4. **System libraries**: Standard IO operations are trusted

### What We Prove

1. **Parsers are correct**: `parseToolCall` produces valid `ToolCall` or fails
2. **State machine is sound**: `step` preserves `StateInvariant`
3. **Tool calls are type-safe**: Arguments match schema
4. **Context stays bounded**: Token count never exceeds `maxTokens`
5. **No stuck states**: Every state has a valid transition (liveness)

### Proof Techniques

1. **Induction**: Prove properties over recursive structures (lists, trees)
2. **Case Analysis**: Exhaustive matching on inductive types
3. **Dependent Types**: Encode invariants in types
4. **Refinement Types**: `{ x : T // P x }` for values with proofs
5. **Monad Laws**: Leverage associativity and identity for composition

## Testing Strategy

Formal verification complements, not replaces, testing:

1. **Property-Based Testing**: Generate random inputs, check invariants hold
2. **Unit Tests**: Test individual components (parsers, state transitions)
3. **Integration Tests**: End-to-end flows with real vLLM
4. **Regression Tests**: Prevent bugs from reoccurring

Example property test:

```lean
-- Property: parsing then serializing is identity
def parse_serialize_identity (json : JSON) : Prop :=
  match parseToolCall json with
  | .ok tc => serializeToolCall tc = json
  | .error _ => True  -- Parse failure is acceptable

#check parse_serialize_identity  -- Can be tested with random JSON
```

## Verification Milestones

### Milestone 1: Tool Call Parsing
- [ ] Define `ToolSchema` inductive type
- [ ] Implement `parseToolCall` with schema validation
- [ ] Prove `parseToolCall_valid` theorem
- [ ] Property tests for all tool types

### Milestone 2: State Machine
- [ ] Define `AgentState` and `Event` types
- [ ] Implement `step` function
- [ ] Prove `step_preserves_invariant`
- [ ] Prove `always_valid` (induction over event list)

### Milestone 3: JSON Parser
- [ ] Define `JSONSchema` and `matches` predicate
- [ ] Implement `parseWithSchema`
- [ ] Prove `parseWithSchema_sound`
- [ ] Integration with tool call parsing

### Milestone 4: Effect System
- [ ] Define `AgentM` monad
- [ ] Implement tool execution in `AgentM`
- [ ] Prove Kleisli composition preserves invariants
- [ ] Refactor main loop to use `AgentM`

## Open Questions

1. **Totality**: Should we prove all functions terminate (using well-founded recursion)?
2. **Liveness**: Should we prove the system doesn't get stuck (always makes progress)?
3. **Concurrency**: If we add async tool execution, how to verify race conditions?
4. **Error Recovery**: Should we prove that error states are always recoverable?
5. **Performance**: Can we prove bounds on execution time or memory usage?

## References

- [Lean 4 Theorem Proving](https://lean-lang.org/theorem_proving_in_lean4/)
- [Kleisli Category in Lean](https://github.com/leanprover-community/mathlib4/blob/master/Mathlib/CategoryTheory/Monad/Kleisli.lean)
- [Verified Parsers](https://doi.org/10.1145/2676726.2677002)
- [Dependent Types for Verification](https://doi.org/10.1017/S0956796807006466)
