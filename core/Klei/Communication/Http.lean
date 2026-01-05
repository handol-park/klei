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

partial def readLine (sock : SocketHandle) (acc : String := "") : IO (Except HttpError String) :=
  do
    let res ← Socket.recv sock 1
    match res with
    | .error e => pure (.error (.socketError e))
    | .ok bytes =>
        if bytes.size == 0 then
          pure (.error (.socketError (.closed "Remote closed connection")))
        else
          match String.fromUTF8? bytes with
          | some char =>
              if char == "\n" then
                let final := if acc.endsWith "\r" then acc.dropRight 1 else acc
                pure (.ok final)
              else
                readLine sock (acc ++ char)
          | none => pure (.error (.parseError "Invalid UTF-8 byte in header"))

partial def readHeaders (sock : SocketHandle) (acc : List (String × String) := []) :
    IO (Except HttpError (List (String × String))) :=
  do
    let res ← readLine sock
    match res with
    | .error e => pure (.error e)
    | .ok line =>
        if line.isEmpty then
          pure (.ok acc.reverse)
        else
          match line.splitOn ":" with
          | key :: valParts =>
              let val := (String.intercalate ":" valParts).trim
              readHeaders sock ((key.trim, val) :: acc)
          | [] => pure (.error (.headerError s!"Invalid header: {line}"))

def getContentLength (headers : List (String × String)) : Nat :=
  headers.find? (fun (k, _) => k.toLower == "content-length")
    |>.bind (fun (_, v) => v.toNat?)
    |>.getD 0

partial def readExact (sock : SocketHandle) (remaining : Nat) (acc : ByteArray := ByteArray.empty) :
    IO (Except HttpError ByteArray) := do
  if remaining == 0 then
    return .ok acc
  let chunkSize := min remaining 4096
  match ← Socket.recv sock (USize.ofNat chunkSize) with
  | .error e => return .error (.socketError e)
  | .ok bytes =>
      if bytes.size == 0 then
        return .error (.socketError (.closed "Remote closed connection"))
      else
        readExact sock (remaining - bytes.size) (acc ++ bytes)

def readBody (sock : SocketHandle) (contentLength : Nat) : IO (Except HttpError String) := do
  if contentLength == 0 then
    return .ok ""
  if contentLength > USize.size then
    return .error (.parseError "Content-Length exceeds platform limits")
  match ← readExact sock contentLength with
  | .error e => return .error e
  | .ok bytes =>
      match String.fromUTF8? bytes with
      | some body => return .ok body
      | none => return .error (.parseError "Invalid UTF-8 body")

partial def readChunkedBody (sock : SocketHandle) (acc : ByteArray := ByteArray.empty) :
    IO (Except HttpError String) := do
  let line ← match ← readLine sock with
    | .error e => return .error e
    | .ok l => pure l
  let size ← match parseChunkSize line with
    | .error e => return .error e
    | .ok n => pure n
  if size == 0 then
    match ← readHeaders sock with
    | .error e => return .error e
    | .ok _ =>
        match String.fromUTF8? acc with
        | some body => return .ok body
        | none => return .error (.parseError "Invalid UTF-8 body")
  else
    let bytes ← match ← readExact sock size with
      | .error e => return .error e
      | .ok b => pure b
    let lineAfter ← match ← readLine sock with
      | .error e => return .error e
      | .ok l => pure l
    if lineAfter != "" then
      return .error (.parseError s!"Expected CRLF after chunk, got: {lineAfter}")
    readChunkedBody sock (acc ++ bytes)

def sendRequest (sock : SocketHandle) (req : HttpRequest) : IO (Except HttpError HttpResponse) := do
  -- Send the request
  match ← Socket.send sock req.toString.toUTF8 with
  | .error e => return .error (.socketError e)
  | .ok _ => pure ()

  -- Read and parse status line
  let line ← match ← readLine sock with
    | .error e => return .error e
    | .ok l => pure l

  let (code, text) ← match parseStatusLine line with
    | .error e => return .error e
    | .ok result => pure result

  -- Read headers
  let headers ← match ← readHeaders sock with
    | .error e => return .error e
    | .ok h => pure h

  -- Read body
  let body ← match hasChunkedTransferEncoding headers with
    | true =>
        match ← readChunkedBody sock with
        | .error e => return .error e
        | .ok b => pure b
    | false =>
        match ← readBody sock (getContentLength headers) with
        | .error e => return .error e
        | .ok b => pure b

  return .ok { status := code, statusText := text, headers, body }

end Klei.Communication.Http
