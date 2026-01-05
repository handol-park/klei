-- Socket.lean
-- Lean FFI bindings for Unix Domain Socket operations
-- Wraps the C shim (libklei_socket.so) with type-safe Lean interface

import Lean

namespace Klei.Communication.Socket

-- Opaque socket handle type (corresponds to klei_socket_t* in C)
axiom SocketHandle : Type
axiom socketHandleInhabited : Nonempty SocketHandle
instance : Nonempty SocketHandle := socketHandleInhabited

-- Socket error type
inductive SocketError where
  | connect : String → SocketError
  | send : String → SocketError
  | recv : String → SocketError
  | timeout : String → SocketError
  | closed : String → SocketError
  | invalid : String → SocketError
deriving Repr

instance : ToString SocketError where
  toString
    | .connect msg => s!"Connection error: {msg}"
    | .send msg => s!"Send error: {msg}"
    | .recv msg => s!"Receive error: {msg}"
    | .timeout msg => s!"Timeout error: {msg}"
    | .closed msg => s!"Socket closed: {msg}"
    | .invalid msg => s!"Invalid operation: {msg}"

-- Error codes from C (must match socket.h)
def KLEI_OK : Int := 0
def KLEI_ERR_CONNECT : Int := -1
def KLEI_ERR_SEND : Int := -2
def KLEI_ERR_RECV : Int := -3
def KLEI_ERR_TIMEOUT : Int := -4
def KLEI_ERR_CLOSED : Int := -5
def KLEI_ERR_INVALID : Int := -6

-- FFI declarations for C functions

@[extern "klei_socket_connect"]
opaque connectFFI (path : @& String) : IO SocketHandle

@[extern "klei_socket_send"]
opaque sendFFI (sock : @& SocketHandle) (data : @& ByteArray) (len : USize) : IO Int

@[extern "klei_socket_recv"]
opaque recvFFI (sock : @& SocketHandle) (buffer : ByteArray) (bufsize : USize) (timeout_ms : UInt32) : IO Int

@[extern "klei_socket_close"]
opaque closeFFI (sock : @& SocketHandle) : IO Unit

@[extern "klei_socket_error"]
opaque errorFFI (sock : @& SocketHandle) : IO String

-- Helper to check if socket handle is null
@[extern "klei_socket_is_null"]
opaque isNullFFI (sock : @& SocketHandle) : IO UInt8

-- Helper to convert Int64 to Nat
def intToNat (i : Int) : Nat :=
  if i < 0 then 0 else i.toNat

-- High-level API

/-- Connect to a Unix Domain Socket at the given path -/
def connect (path : String) : IO (Except SocketError SocketHandle) := do
  let sock ← connectFFI path
  let isNull ← isNullFFI sock
  if isNull != 0 then
    return Except.error $ .connect s!"Failed to connect to {path}"
  else
    return Except.ok sock

/-- Send data to the socket -/
def send (sock : SocketHandle) (data : ByteArray) : IO (Except SocketError USize) := do
  let result ← sendFFI sock data data.size.toUSize
  if result < 0 then
    let errMsg ← errorFFI sock
    let err := if result == KLEI_ERR_SEND then
        SocketError.send errMsg
      else if result == KLEI_ERR_CLOSED then
        SocketError.closed errMsg
      else if result == KLEI_ERR_INVALID then
        SocketError.invalid errMsg
      else
        SocketError.send errMsg
    return Except.error err
  else
    return Except.ok (intToNat result).toUSize

/-- Receive data from the socket with timeout -/
def recv (sock : SocketHandle) (bufsize : USize) (timeout_ms : UInt32 := 30000) : IO (Except SocketError ByteArray) := do
  let buffer := ByteArray.emptyWithCapacity bufsize.toNat
  let result ← recvFFI sock buffer bufsize timeout_ms
  if result < 0 then
    let errMsg ← errorFFI sock
    let err := if result == KLEI_ERR_RECV then
        SocketError.recv errMsg
      else if result == KLEI_ERR_TIMEOUT then
        SocketError.timeout errMsg
      else if result == KLEI_ERR_CLOSED then
        SocketError.closed errMsg
      else if result == KLEI_ERR_INVALID then
        SocketError.invalid errMsg
      else
        SocketError.recv errMsg
    return Except.error err
  else
    -- Extract only the received bytes
    return Except.ok $ buffer.extract 0 (intToNat result)

/-- Close the socket -/
def close (sock : SocketHandle) : IO Unit := do
  closeFFI sock

/-- Resource-safe socket operations using withSocket -/
def withSocket (path : String) (f : SocketHandle → IO α) : IO (Except SocketError α) := do
  match ← connect path with
  | Except.error e => return Except.error e
  | Except.ok sock =>
    try
      let result ← f sock
      close sock
      return Except.ok result
    catch e =>
      close sock
      throw e

end Klei.Communication.Socket
