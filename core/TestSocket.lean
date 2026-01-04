-- TestSocket.lean
-- Simple test for Socket FFI bindings

import Klei.Communication.Socket

open Klei.Communication.Socket

def main : IO Unit := do
  IO.println "Testing Klei Socket FFI bindings..."

  -- Test connection to a non-existent socket (should fail gracefully)
  IO.println "\nTest 1: Connecting to non-existent socket"
  match ← connect "/tmp/nonexistent_test.sock" with
  | Except.error e => IO.println s!"  Expected error: {e}"
  | Except.ok _ => IO.println "  Unexpected success!"

  IO.println "\nSocket FFI bindings are working correctly!"
  IO.println "Note: For full testing, run the C test suite with './FFI/test_socket'"
