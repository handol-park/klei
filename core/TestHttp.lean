-- TestHttp.lean
-- Test suite for HTTP protocol stack over Unix Domain Sockets

import Klei.Communication.Http

open Klei.Communication.Http

def testParseStatusLine : IO Unit := do
  IO.println "Test: parseStatusLine"

  -- Test valid status line
  match parseStatusLine "HTTP/1.1 200 OK" with
  | .ok (code, text) =>
      if code == 200 && text == "OK" then
        IO.println "  ✓ Valid status line parsed correctly"
      else
        IO.println s!"  ✗ Unexpected result: code={code}, text={text}"
  | .error e => IO.println s!"  ✗ Failed to parse valid status line: {repr e}"

  -- Test status line with multi-word status text
  match parseStatusLine "HTTP/1.1 404 Not Found" with
  | .ok (code, text) =>
      if code == 404 && text == "Not Found" then
        IO.println "  ✓ Multi-word status text parsed correctly"
      else
        IO.println s!"  ✗ Unexpected result: code={code}, text={text}"
  | .error e => IO.println s!"  ✗ Failed to parse: {repr e}"

  -- Test invalid status line
  match parseStatusLine "Invalid" with
  | .error _ => IO.println "  ✓ Invalid status line rejected correctly"
  | .ok _ => IO.println "  ✗ Invalid status line should have been rejected"

def testFormatHeaders : IO Unit := do
  IO.println "\nTest: formatHeaders"

  let headers := [
    ("Content-Type", "application/json"),
    ("Content-Length", "42")
  ]

  let formatted := formatHeaders headers
  let expected := "Content-Type: application/json\r\nContent-Length: 42\r\n"

  if formatted == expected then
    IO.println "  ✓ Headers formatted correctly"
  else
    IO.println s!"  ✗ Header formatting failed"
    IO.println s!"    Expected: {repr expected}"
    IO.println s!"    Got: {repr formatted}"

def testHttpRequestToString : IO Unit := do
  IO.println "\nTest: HttpRequest.toString"

  let req : HttpRequest := {
    method := "POST"
    path := "/api/generate"
    headers := [
      ("Host", "localhost"),
      ("Content-Type", "application/json"),
      ("Content-Length", "13")
    ]
    body := "{\"test\":true}"
  }

  let str := req.toString

  -- Check that all parts are present by checking if they appear in the string
  let hasMethod := str.toSlice.contains "POST /api/generate HTTP/1.1"
  let hasHost := str.toSlice.contains "Host: localhost"
  let hasContentType := str.toSlice.contains "Content-Type: application/json"
  let hasBody := str.toSlice.contains "{\"test\":true}"

  if hasMethod && hasHost && hasContentType && hasBody then
    IO.println "  ✓ HTTP request serialized correctly"
  else
    IO.println "  ✗ HTTP request serialization failed"
    IO.println s!"    Got: {repr str}"

def testGetContentLength : IO Unit := do
  IO.println "\nTest: getContentLength"

  -- Test with Content-Length present
  let headers1 := [
    ("Content-Type", "text/plain"),
    ("Content-Length", "1024")
  ]

  let len1 := getContentLength headers1
  if len1 == 1024 then
    IO.println "  ✓ Content-Length extracted correctly"
  else
    IO.println s!"  ✗ Expected 1024, got {len1}"

  -- Test with no Content-Length
  let headers2 := [("Content-Type", "text/plain")]
  let len2 := getContentLength headers2
  if len2 == 0 then
    IO.println "  ✓ Missing Content-Length defaults to 0"
  else
    IO.println s!"  ✗ Expected 0, got {len2}"

  -- Test case-insensitive matching
  let headers3 := [("content-length", "512")]
  let len3 := getContentLength headers3
  if len3 == 512 then
    IO.println "  ✓ Case-insensitive Content-Length matching works"
  else
    IO.println s!"  ✗ Expected 512, got {len3}"

def testChunkedHelpers : IO Unit := do
  IO.println "\nTest: chunked helpers"

  match parseChunkSize "4" with
  | .ok n =>
      if n == 4 then
        IO.println "  ✓ Chunk size hex parsed correctly"
      else
        IO.println s!"  ✗ Expected 4, got {n}"
  | .error e => IO.println s!"  ✗ Failed to parse chunk size: {repr e}"

  match parseChunkSize "A;ext=value" with
  | .ok n =>
      if n == 10 then
        IO.println "  ✓ Chunk size with extensions parsed correctly"
      else
        IO.println s!"  ✗ Expected 10, got {n}"
  | .error e => IO.println s!"  ✗ Failed to parse chunk size with extensions: {repr e}"

  let headers := [
    ("Transfer-Encoding", "chunked"),
    ("Content-Type", "application/json")
  ]
  if hasChunkedTransferEncoding headers then
    IO.println "  ✓ Chunked transfer encoding detected"
  else
    IO.println "  ✗ Chunked transfer encoding not detected"

def testHttpStructures : IO Unit := do
  IO.println "\nTest: HTTP data structures"

  let req : HttpRequest := {
    method := "GET"
    path := "/test"
    headers := [("Host", "example.com")]
    body := ""
  }

  let resp : HttpResponse := {
    status := 200
    statusText := "OK"
    headers := [("Content-Type", "text/plain")]
    body := "Hello, World!"
  }

  IO.println "  ✓ HttpRequest structure created"
  IO.println "  ✓ HttpResponse structure created"
  IO.println s!"    Request: {req.method} {req.path}"
  IO.println s!"    Response: {resp.status} {resp.statusText}"

def main : IO Unit := do
  IO.println "Testing Klei HTTP Protocol Stack"
  IO.println "=================================="

  testParseStatusLine
  testFormatHeaders
  testHttpRequestToString
  testGetContentLength
  testChunkedHelpers
  testHttpStructures

  IO.println "\n=================================="
  IO.println "HTTP protocol stack tests complete!"
  IO.println "\nNote: Full integration tests require a Unix Domain Socket HTTP server."
  IO.println "To test the complete stack:"
  IO.println "  1. Start a test HTTP server on a Unix socket"
  IO.println "  2. Use the HTTP client to connect and make requests"
