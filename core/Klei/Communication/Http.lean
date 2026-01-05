import Klei.Communication.Socket

namespace Klei.Communication.Http

open Klei.Communication.Socket

structure HttpRequest where
  method : String := "POST"
  path : String
  headers : List (String × String)
  body : String
deriving Repr, BEq

structure HttpResponse where
  status : UInt16
  statusText : String
  headers : List (String × String)
  body : String
deriving Repr, BEq

inductive HttpError where
  | socketError : SocketError → HttpError
  | parseError : String → HttpError
  | headerError : String → HttpError
  | timeout : HttpError
deriving Repr

def formatHeaders (headers : List (String × String)) : String :=
  headers.foldl (fun acc (k, v) => acc ++ s!"{k}: {v}\r\n") ""

def HttpRequest.toString (req : HttpRequest) : String :=
  let headerStr := formatHeaders req.headers
  s!"{req.method} {req.path} HTTP/1.1\r\n{headerStr}\r\n{req.body}"

def parseStatusLine (line : String) : Except HttpError (UInt16 × String) :=
  let parts := line.splitOn " "
  if parts.length < 3 then
    .error (.parseError s!"Invalid status line: {line}")
  else
    match parts[1]?.bind String.toNat? with
    | some code => .ok (code.toUInt16, parts.drop 2 |> String.intercalate " ")
    | none => .error (.parseError "Invalid status code")

def getHeaderValue (headers : List (String × String)) (name : String) : Option String :=
  headers.find? (fun (k, _) => k.toLower == name.toLower) |>.map (fun (_, v) => v)

def hasChunkedTransferEncoding (headers : List (String × String)) : Bool :=
  match getHeaderValue headers "transfer-encoding" with
  | none => false
  | some value =>
      value.splitOn "," |>.any (fun part => part.trim.toLower == "chunked")

def hexDigitValue (c : Char) : Option Nat :=
  if c >= '0' && c <= '9' then
    some (c.toNat - '0'.toNat)
  else if c >= 'a' && c <= 'f' then
    some (10 + (c.toNat - 'a'.toNat))
  else if c >= 'A' && c <= 'F' then
    some (10 + (c.toNat - 'A'.toNat))
  else
    none

def parseChunkSize (line : String) : Except HttpError Nat :=
  let sizePart := match line.trim.splitOn ";" with
    | size :: _ => size.trim
    | [] => ""
  if sizePart.isEmpty then
    .error (.parseError s!"Invalid chunk size line: {line}")
  else
    let result :=
      sizePart.toList.foldl (fun acc c =>
        match acc with
        | none => none
        | some n =>
            match hexDigitValue c with
            | some v => some (n * 16 + v)
            | none => none) (some 0)
    match result with
    | some n => .ok n
    | none => .error (.parseError s!"Invalid chunk size: {line}")

structure HttpReader where
  sock : SocketHandle
  buffer : ByteArray
  pos : Nat

def HttpReader.new (sock : SocketHandle) : HttpReader :=
  { sock, buffer := ByteArray.empty, pos := 0 }

partial def readByte (reader : HttpReader) : IO (Except HttpError (UInt8 × HttpReader)) := do
  if reader.pos < reader.buffer.size then
    let b := reader.buffer.get! reader.pos
    let next := { reader with pos := reader.pos + 1 }
    return .ok (b, next)
  match ← Socket.recv reader.sock 4096 with
  | .error e => return .error (.socketError e)
  | .ok bytes =>
      if bytes.size == 0 then
        return .error (.socketError (.closed "Remote closed connection"))
      readByte { reader with buffer := bytes, pos := 0 }

partial def readLine (reader : HttpReader) (acc : ByteArray := ByteArray.empty) :
    IO (Except HttpError (String × HttpReader)) := do
  let res ← readByte reader
  match res with
  | .error e => return .error e
  | .ok (b, next) =>
      if b == 10 then
        let finalBytes :=
          if acc.size > 0 && acc.get! (acc.size - 1) == 13 then
            acc.extract 0 (acc.size - 1)
          else
            acc
        match String.fromUTF8? finalBytes with
        | some line => return .ok (line, next)
        | none => return .error (.parseError "Invalid UTF-8 byte in header")
      else
        readLine next (acc.push b)

partial def readHeaders (reader : HttpReader) (acc : List (String × String) := []) :
    IO (Except HttpError (List (String × String) × HttpReader)) := do
  let res ← readLine reader
  match res with
  | .error e => return .error e
  | .ok (line, next) =>
      if line.isEmpty then
        return .ok (acc.reverse, next)
      else
        match line.splitOn ":" with
        | key :: valParts =>
            let val := (String.intercalate ":" valParts).trim
            readHeaders next ((key.trim, val) :: acc)
        | [] => return .error (.headerError s!"Invalid header: {line}")

def getContentLength (headers : List (String × String)) : Nat :=
  headers.find? (fun (k, _) => k.toLower == "content-length")
    |>.bind (fun (_, v) => v.toNat?)
    |>.getD 0

partial def readExact (reader : HttpReader) (remaining : Nat) (acc : ByteArray := ByteArray.empty) :
    IO (Except HttpError (ByteArray × HttpReader)) := do
  if remaining == 0 then
    return .ok (acc, reader)
  if reader.pos < reader.buffer.size then
    let available := reader.buffer.size - reader.pos
    let take := min remaining available
    let chunk := reader.buffer.extract reader.pos (reader.pos + take)
    let next := { reader with pos := reader.pos + take }
    readExact next (remaining - take) (acc ++ chunk)
  else
    let chunkSize := min remaining 4096
    match ← Socket.recv reader.sock (USize.ofNat chunkSize) with
    | .error e => return .error (.socketError e)
    | .ok bytes =>
        if bytes.size == 0 then
          return .error (.socketError (.closed "Remote closed connection"))
        let take := min remaining bytes.size
        let chunk := bytes.extract 0 take
        let next := { reader with buffer := bytes, pos := take }
        readExact next (remaining - take) (acc ++ chunk)

def readBody (reader : HttpReader) (contentLength : Nat) :
    IO (Except HttpError (String × HttpReader)) := do
  if contentLength == 0 then
    return .ok ("", reader)
  if contentLength > USize.size then
    return .error (.parseError "Content-Length exceeds platform limits")
  match ← readExact reader contentLength with
  | .error e => return .error e
  | .ok (bytes, next) =>
      match String.fromUTF8? bytes with
      | some body => return .ok (body, next)
      | none => return .error (.parseError "Invalid UTF-8 body")

partial def sendAll (sock : SocketHandle) (data : ByteArray) (offset : Nat := 0) :
    IO (Except HttpError Unit) := do
  if offset >= data.size then
    return .ok ()
  let remaining := data.extract offset data.size
  match ← Socket.send sock remaining with
  | .error e => return .error (.socketError e)
  | .ok sent =>
      if sent.toNat == 0 then
        return .error (.socketError (.send "Socket returned 0 bytes sent"))
      sendAll sock data (offset + sent.toNat)

partial def readChunkedBody (reader : HttpReader) (acc : ByteArray := ByteArray.empty) :
    IO (Except HttpError (String × HttpReader)) := do
  let res ← readLine reader
  match res with
  | .error e => return .error e
  | .ok (line, next) =>
      let size ← match parseChunkSize line with
        | .error e => return .error e
        | .ok n => pure n
      if size == 0 then
        match ← readHeaders next with
        | .error e => return .error e
        | .ok (_, after) =>
            match String.fromUTF8? acc with
            | some body => return .ok (body, after)
            | none => return .error (.parseError "Invalid UTF-8 body")
      else
        let bytesAndReader ← match ← readExact next size with
          | .error e => return .error e
          | .ok result => pure result
        let bytes := bytesAndReader.fst
        let afterBytes := bytesAndReader.snd
        let lineAfterRes ← readLine afterBytes
        match lineAfterRes with
        | .error e => return .error e
        | .ok (lineAfter, afterLine) =>
            if lineAfter != "" then
              return .error (.parseError s!"Expected CRLF after chunk, got: {lineAfter}")
            readChunkedBody afterLine (acc ++ bytes)

def sendRequest (sock : SocketHandle) (req : HttpRequest) : IO (Except HttpError HttpResponse) := do
  -- Send the request
  match ← sendAll sock req.toString.toUTF8 with
  | .error e => return .error e
  | .ok _ => pure ()

  -- Read and parse status line
  let reader := HttpReader.new sock
  let lineAndReader ← match ← readLine reader with
    | .error e => return .error e
    | .ok result => pure result
  let line := lineAndReader.fst
  let reader := lineAndReader.snd

  let (code, text) ← match parseStatusLine line with
    | .error e => return .error e
    | .ok result => pure result

  -- Read headers
  let headersAndReader ← match ← readHeaders reader with
    | .error e => return .error e
    | .ok result => pure result
  let headers := headersAndReader.fst
  let reader := headersAndReader.snd

  -- Read body
  let bodyAndReader ← match hasChunkedTransferEncoding headers with
    | true =>
        match ← readChunkedBody reader with
        | .error e => return .error e
        | .ok result => pure result
    | false =>
        match ← readBody reader (getContentLength headers) with
        | .error e => return .error e
        | .ok result => pure result
  let body := bodyAndReader.fst

  return .ok { status := code, statusText := text, headers, body }

end Klei.Communication.Http
