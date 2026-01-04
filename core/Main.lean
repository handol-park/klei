import Klei

partial def repl (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) : IO Unit := do
  stdout.putStr "> "
  stdout.flush
  let input <- stdin.getLine
  let input := input.trim

  if input == "/exit" then
    stdout.putStrLn "Goodbye."
  else if input == "" then
    repl stdin stdout
  else
    try
      let response <- Klei.Ollama.generate input
      stdout.putStrLn response
    catch e =>
      stdout.putStrLn s!"Error: {e}"
    repl stdin stdout

def main : IO Unit := do
  let stdin <- IO.getStdin
  let stdout <- IO.getStdout

  stdout.putStrLn "--- Klei Chat (MVP) ---"
  stdout.putStrLn "Type '/exit' to quit."

  repl stdin stdout
