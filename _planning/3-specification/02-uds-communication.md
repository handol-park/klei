# Specification: Unix Domain Socket Communication Layer

## Overview

This document specifies the Unix Domain Socket (UDS) communication layer between the Lean orchestrator and the vLLM inference engine, replacing the HTTP/curl approach from v0.1.0.

## Motivation

### Why UDS Instead of HTTP/TCP?

| Concern | HTTP/TCP (v0.1.0) | Unix Domain Sockets (v0.2.0) |
|---------|-------------------|------------------------------|
| **Security** | Port exposed on loopback (0.0.0.0) | Filesystem permissions only |
| **Attack Surface** | Network stack, HTTP parser | Minimal (direct socket R/W) |
| **Latency** | ~100-200μs (TCP overhead) | ~10-50μs (no network stack) |
| **Throughput** | Limited by TCP buffer | Higher bandwidth |
| **Setup Complexity** | Port management, firewall rules | Simple file path |
| **Dependencies** | curl subprocess | Direct socket I/O |
| **Streaming** | Complex (chunked encoding) | Natural (byte stream) |

### Performance Targets

- **Latency**: < 50μs round-trip for UDS communication
- **Throughput**: > 1 GB/s for large payloads
- **Overhead**: < 5% CPU usage for socket I/O
- **Memory**: < 1 MB for socket buffers

## Architecture

### Component Stack

```
┌─────────────────────────────────────┐
│   Lean Orchestrator (core/)         │
│                                      │
│   ┌──────────────────────────────┐  │
│   │ Klei.Communication.Protocol  │  │ ← High-level API
│   └────────────┬─────────────────┘  │
│                │                     │
│   ┌────────────▼─────────────────┐  │
│   │ Klei.Communication.Socket    │  │ ← Lean FFI bindings
│   └────────────┬─────────────────┘  │
│                │                     │
│   ┌────────────▼─────────────────┐  │
│   │ FFI/socket.c (C shim)        │  │ ← C wrapper
│   └────────────┬─────────────────┘  │
└────────────────┼─────────────────────┘
                 │
                 │ AF_UNIX socket
                 │ /tmp/vllm.sock
                 │
┌────────────────▼─────────────────────┐
│   vLLM Inference Engine               │
│                                      │
│   ┌──────────────────────────────┐  │
│   │ Unix Socket Listener         │  │
│   └────────────┬─────────────────┘  │
│                │                     │
│   ┌────────────▼─────────────────┐  │
│   │ JSON-RPC Handler             │  │
│   └────────────┬─────────────────┘  │
│                │                     │
│   ┌────────────▼─────────────────┐  │
│   │ Model Inference Engine       │  │
│   └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Implementation Layers

### Layer 1: C Shim (`core/FFI/socket.c`)

**Purpose**: Minimal C wrapper around POSIX socket API for Lean FFI.

**API Functions:**

```c
// socket.h
#ifndef KLEI_SOCKET_H
#define KLEI_SOCKET_H

#include <stddef.h>
#include <stdint.h>

// Opaque socket handle
typedef struct klei_socket_t klei_socket_t;

// Error codes
typedef enum {
    KLEI_OK = 0,
    KLEI_ERR_CONNECT = -1,
    KLEI_ERR_SEND = -2,
    KLEI_ERR_RECV = -3,
    KLEI_ERR_TIMEOUT = -4,
    KLEI_ERR_CLOSED = -5,
    KLEI_ERR_INVALID = -6
} klei_error_t;

// Connect to Unix Domain Socket
// Returns: socket handle on success, NULL on failure
klei_socket_t* klei_socket_connect(const char* path);

// Send data to socket
// Returns: number of bytes sent, or error code < 0
int64_t klei_socket_send(
    klei_socket_t* sock,
    const uint8_t* data,
    size_t len
);

// Receive data from socket
// Returns: number of bytes received, or error code < 0
// Blocks until data available or timeout
int64_t klei_socket_recv(
    klei_socket_t* sock,
    uint8_t* buffer,
    size_t bufsize,
    uint32_t timeout_ms  // 0 = no timeout
);

// Close socket and free resources
void klei_socket_close(klei_socket_t* sock);

// Get last error message
const char* klei_socket_error(klei_socket_t* sock);

#endif // KLEI_SOCKET_H
```

**Implementation Notes:**

```c
// socket.c
#include "socket.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

struct klei_socket_t {
    int fd;
    char last_error[256];
};

klei_socket_t* klei_socket_connect(const char* path) {
    // Allocate handle
    klei_socket_t* sock = malloc(sizeof(klei_socket_t));
    if (!sock) return NULL;

    // Create socket
    sock->fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock->fd < 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "socket() failed: %s", strerror(errno));
        free(sock);
        return NULL;
    }

    // Set up address
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    // Connect
    if (connect(sock->fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "connect() failed: %s", strerror(errno));
        close(sock->fd);
        free(sock);
        return NULL;
    }

    return sock;
}

int64_t klei_socket_send(klei_socket_t* sock, const uint8_t* data, size_t len) {
    if (!sock || sock->fd < 0) return KLEI_ERR_INVALID;

    ssize_t sent = send(sock->fd, data, len, MSG_NOSIGNAL);
    if (sent < 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "send() failed: %s", strerror(errno));
        return KLEI_ERR_SEND;
    }

    return sent;
}

int64_t klei_socket_recv(
    klei_socket_t* sock,
    uint8_t* buffer,
    size_t bufsize,
    uint32_t timeout_ms
) {
    if (!sock || sock->fd < 0) return KLEI_ERR_INVALID;

    // Set timeout if requested
    if (timeout_ms > 0) {
        struct timeval tv;
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        setsockopt(sock->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    }

    ssize_t received = recv(sock->fd, buffer, bufsize, 0);
    if (received < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return KLEI_ERR_TIMEOUT;
        }
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "recv() failed: %s", strerror(errno));
        return KLEI_ERR_RECV;
    } else if (received == 0) {
        return KLEI_ERR_CLOSED;
    }

    return received;
}

void klei_socket_close(klei_socket_t* sock) {
    if (!sock) return;
    if (sock->fd >= 0) {
        close(sock->fd);
    }
    free(sock);
}

const char* klei_socket_error(klei_socket_t* sock) {
    return sock ? sock->last_error : "Invalid socket";
}
```

**Build Integration:**

```toml
# lakefile.toml
[[lean_lib]]
name = "Klei"

[[lean_exe]]
name = "core"
root = "Main"

[lean_exe.linkFlags]
args = ["-L./FFI", "-lklei_socket"]

# Compile C shim before building Lean code
[lean_exe.preCompile]
cmd = "gcc"
args = ["-shared", "-fPIC", "-o", "FFI/libklei_socket.so", "FFI/socket.c"]
```

### Layer 2: Lean FFI Bindings (`core/Klei/Communication/Socket.lean`)

**Purpose**: Type-safe Lean interface to C socket operations.

```lean
import Lean

namespace Klei.Communication.Socket

-- Opaque type for socket handle
opaque SocketHandle : Type := Unit

-- Error type
inductive SocketError where
  | connectFailed : String → SocketError
  | sendFailed : String → SocketError
  | recvFailed : String → SocketError
  | timeout : SocketError
  | closed : SocketError
  | invalid : String → SocketError
deriving Repr, BEq

-- FFI declarations
@[extern "klei_socket_connect"]
opaque socket_connect_ffi (path : @& String) : IO (Option SocketHandle)

@[extern "klei_socket_send"]
opaque socket_send_ffi (sock : @& SocketHandle) (data : @& ByteArray) : IO Int64

@[extern "klei_socket_recv"]
opaque socket_recv_ffi (sock : @& SocketHandle) (bufsize : @& UInt32) (timeout : @& UInt32) : IO ByteArray

@[extern "klei_socket_close"]
opaque socket_close_ffi (sock : @& SocketHandle) : IO Unit

@[extern "klei_socket_error"]
opaque socket_error_ffi (sock : @& SocketHandle) : IO String

-- High-level API
def connect (path : String) : IO (Except SocketError SocketHandle) := do
  match ← socket_connect_ffi path with
  | some sock => pure (.ok sock)
  | none => pure (.error (.connectFailed s!"Failed to connect to {path}"))

def send (sock : SocketHandle) (data : ByteArray) : IO (Except SocketError Unit) := do
  let result ← socket_send_ffi sock data
  if result < 0 then
    let err ← socket_error_ffi sock
    pure (.error (.sendFailed err))
  else if result.toNat != data.size then
    pure (.error (.sendFailed "Incomplete send"))
  else
    pure (.ok ())

def recv (sock : SocketHandle) (maxBytes : Nat := 65536) (timeout : Nat := 30000) :
    IO (Except SocketError ByteArray) := do
  let result ← socket_recv_ffi sock maxBytes.toUInt32 timeout.toUInt32
  if result.size == 0 then
    pure (.error .closed)
  else
    pure (.ok result)

def close (sock : SocketHandle) : IO Unit :=
  socket_close_ffi sock

-- Resource management helper
def withSocket {α : Type} (path : String) (f : SocketHandle → IO (Except SocketError α)) :
    IO (Except SocketError α) := do
  match ← connect path with
  | .error e => pure (.error e)
  | .ok sock =>
      try
        f sock
      finally
        close sock

end Klei.Communication.Socket
```

### Layer 3: Protocol Layer (`core/Klei/Communication/Protocol.lean`)

**Purpose**: JSON-RPC protocol over UDS with request/response handling.

```lean
import Klei.Communication.Socket
import Lean.Data.Json

namespace Klei.Communication.Protocol

-- JSON-RPC request
structure Request where
  jsonrpc : String := "2.0"
  method : String
  params : Json
  id : Nat
deriving ToJson, FromJson

-- JSON-RPC response
structure Response where
  jsonrpc : String := "2.0"
  result : Option Json
  error : Option Json
  id : Nat
deriving ToJson, FromJson

-- Protocol errors
inductive ProtocolError where
  | socketError : Socket.SocketError → ProtocolError
  | parseError : String → ProtocolError
  | rpcError : Json → ProtocolError
deriving Repr

-- Send request and await response
def call (sock : Socket.SocketHandle) (method : String) (params : Json) (id : Nat) :
    IO (Except ProtocolError Response) := do
  -- Construct request
  let req : Request := { method, params, id }
  let reqJson := toJson req
  let reqStr := reqJson.compress ++ "\n"  -- Newline-delimited JSON

  -- Send request
  match ← Socket.send sock reqStr.toUTF8 with
  | .error e => pure (.error (.socketError e))
  | .ok () =>
      -- Receive response
      match ← Socket.recv sock with
      | .error e => pure (.error (.socketError e))
      | .ok respBytes =>
          let respStr := String.fromUTF8Unchecked respBytes
          match Json.parse respStr with
          | .error e => pure (.error (.parseError e))
          | .ok json =>
              match fromJson? json with
              | .error e => pure (.error (.parseError e))
              | .ok (resp : Response) =>
                  if resp.error.isSome then
                    pure (.error (.rpcError resp.error.get!))
                  else
                    pure (.ok resp)

-- High-level vLLM API
structure GenerateParams where
  prompt : String
  max_tokens : Nat := 2048
  temperature : Float := 0.7
  stream : Bool := false
deriving ToJson

def generate (sock : Socket.SocketHandle) (params : GenerateParams) :
    IO (Except ProtocolError String) := do
  let paramsJson := toJson params
  match ← call sock "generate" paramsJson 1 with
  | .error e => pure (.error e)
  | .ok resp =>
      match resp.result with
      | none => pure (.error (.parseError "Missing result field"))
      | some json =>
          match json.getObjValAs? String "text" with
          | .error e => pure (.error (.parseError e))
          | .ok text => pure (.ok text)

end Klei.Communication.Protocol
```

## vLLM Configuration

### Server Startup

```bash
# Start vLLM with Unix Domain Socket
vllm serve HuggingFaceH4/gpt-oss-20b-AWQ \
  --quantization awq \
  --dtype half \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.90 \
  --kv-cache-dtype auto \
  --enable-prefix-caching \
  --uvicorn-unix-socket /tmp/vllm.sock \
  --uvicorn-unix-socket-perms 0600
```

**Configuration Rationale:**
- `--quantization awq`: 4-bit quantization for memory efficiency
- `--max-model-len 32768`: Support long contexts
- `--gpu-memory-utilization 0.90`: Leave headroom for KV cache
- `--enable-prefix-caching`: Cache system prompts
- `--uvicorn-unix-socket`: Listen on UDS instead of TCP
- `--uvicorn-unix-socket-perms 0600`: Owner-only permissions

### Socket Permissions

```bash
# Set restrictive permissions
chmod 600 /tmp/vllm.sock
chown $USER:$USER /tmp/vllm.sock

# Verify
ls -l /tmp/vllm.sock
# Expected: srw------- 1 user user 0 Jan 4 12:00 /tmp/vllm.sock
```

## Usage Example

```lean
import Klei.Communication.Socket
import Klei.Communication.Protocol

def main : IO Unit := do
  let socketPath := "/tmp/vllm.sock"

  -- Connect and make request
  match ← Socket.withSocket socketPath (fun sock => do
    let params : Protocol.GenerateParams := {
      prompt := "What is the capital of France?",
      max_tokens := 100,
      temperature := 0.7
    }
    Protocol.generate sock params
  ) with
  | .error e => IO.eprintln s!"Error: {repr e}"
  | .ok text => IO.println s!"Response: {text}"
```

## Error Handling

### Connection Errors

- **Socket not found**: vLLM not running → retry with backoff
- **Permission denied**: Check file permissions → escalate to user
- **Connection refused**: vLLM crashed → restart vLLM

### Communication Errors

- **Send failed**: Connection lost → reconnect
- **Recv timeout**: Request taking too long → cancel and retry
- **Parse error**: Malformed JSON → log and return error to user

### Recovery Strategy

```lean
partial def retryWithBackoff {α : Type}
    (action : IO (Except SocketError α))
    (maxRetries : Nat := 3)
    (backoffMs : Nat := 1000) :
    IO (Except SocketError α) := do
  let rec loop (attempt : Nat) : IO (Except SocketError α) := do
    match ← action with
    | .ok result => pure (.ok result)
    | .error e =>
        if attempt >= maxRetries then
          pure (.error e)
        else
          IO.sleep (backoffMs * (2 ^ attempt)).toUInt32
          loop (attempt + 1)
  loop 0
```

## Performance Considerations

### Buffering

- Use 64 KB buffers for send/recv
- Batch small messages to reduce syscalls
- Consider writev/readv for scatter-gather

### Connection Pooling

- Keep socket open across requests (persistent connection)
- Implement connection pool if multi-threaded
- Close idle connections after timeout

### Monitoring

```lean
structure SocketMetrics where
  bytesSent : Nat
  bytesRecv : Nat
  requestCount : Nat
  errorCount : Nat
  avgLatency : Float

def updateMetrics (metrics : SocketMetrics) (latency : Nat) (bytes : Nat) :
    SocketMetrics :=
  { metrics with
    bytesSent := metrics.bytesSent + bytes,
    requestCount := metrics.requestCount + 1,
    avgLatency := (metrics.avgLatency * metrics.requestCount.toFloat + latency.toFloat) /
                   (metrics.requestCount + 1).toFloat
  }
```

## Security

### Threat Model

**Assumptions:**
- Attacker has local user access
- vLLM and Klei run as same user
- Filesystem permissions are enforced by OS

**Attacks Mitigated:**
- Network-based attacks (socket not on network)
- Cross-user access (filesystem permissions)
- Port scanning (no open ports)

**Attacks NOT Mitigated:**
- Root privilege escalation
- Same-user process injection
- Physical access

### Best Practices

1. **Minimal Permissions**: Socket file is 0600 (owner-only)
2. **No World Access**: Never use 0666 or 0777
3. **Validate Path**: Ensure socket path is not symlink to sensitive file
4. **Audit Logging**: Log all connections and requests
5. **Rate Limiting**: Prevent DoS via too many requests

## Testing

### Unit Tests

```lean
-- Test connection
def test_connect : IO Unit := do
  match ← Socket.connect "/tmp/vllm.sock" with
  | .error e => throw (IO.userError s!"Connect failed: {repr e}")
  | .ok sock =>
      Socket.close sock
      IO.println "✓ Connect test passed"

-- Test send/recv
def test_echo : IO Unit := do
  Socket.withSocket "/tmp/vllm.sock" (fun sock => do
    let message := "Hello, vLLM!"
    let _ ← Socket.send sock message.toUTF8
    let resp ← Socket.recv sock
    if resp.isOk then
      IO.println "✓ Echo test passed"
      pure (.ok ())
    else
      throw (IO.userError "Echo test failed")
  )
```

### Benchmark

```bash
# Measure UDS latency
hyperfine --warmup 3 \
  'echo "test" | nc -U /tmp/vllm.sock'

# Compare to TCP
hyperfine --warmup 3 \
  'echo "test" | nc localhost 8000'
```

## Migration from v0.1.0

1. Keep `Klei/Ollama.lean` as fallback
2. Add `Klei/vLLM.lean` with UDS support
3. Feature flag: `KLEI_USE_VLLM=1`
4. Benchmark both backends
5. Switch default to vLLM
6. Remove Ollama in v0.3.0
