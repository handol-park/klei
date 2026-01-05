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

def readBody (sock : SocketHandle) (contentLength : Nat) : IO (Except HttpError String) := do
  if contentLength == 0 then
    return .ok ""

  if contentLength > USize.size then
    return .error (.parseError "Content-Length exceeds platform limits")

  match ← Socket.recv sock (USize.ofNat contentLength) with
  | .error e => return .error (.socketError e)
  | .ok bytes =>
      match String.fromUTF8? bytes with
      | some body => return .ok body
      | none => return .error (.parseError "Invalid UTF-8 body")

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
  let body ← match ← readBody sock (getContentLength headers) with
    | .error e => return .error e
    | .ok b => pure b

  return .ok { status := code, statusText := text, headers, body }

end Klei.Communication.Http