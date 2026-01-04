import Lean
import Lean.Data.Json.FromToJson

open Lean Json

namespace Klei.Ollama

structure Request where
  model : String
  prompt : String
  stream : Bool
deriving ToJson

structure Response where
  response : String
  done : Bool
deriving FromJson

def generate (prompt : String) (model : String := "llama3.2") : IO String := do
  let req := { model := model, prompt := prompt, stream := false : Request }
  let json := toJson req
  let jsonStr := json.compress

  -- Get Ollama host from environment or default
  let host <- IO.getEnv "OLLAMA_HOST"
  let host := host.getD "127.0.0.1:11434"
  let url := s!"http://{host}/api/generate"

  -- Using curl to POST to Ollama
  let outStr <- IO.Process.run {
    cmd := "curl"
    args := #["-s", "-X", "POST", url, "-d", jsonStr]
  }

  match Json.parse outStr with
  | Except.error e => throw $ IO.userError s!"JSON parse error: {e}\nRaw output: {outStr}"
  | Except.ok j =>
    match fromJson? j with
    | Except.error e => throw $ IO.userError s!"JSON decode error: {e}"
    | Except.ok (res : Response) => return res.response

end Klei.Ollama
