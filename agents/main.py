import ollama
import sys

def main():
    print("--- Klei Agent Runner ---")
    try:
        models = ollama.list()
        print("Connected to Ollama.")
        print("Available models:", [m['name'] for m in models['models']])
    except Exception as e:
        print(f"Error connecting to Ollama: {e}", file=sys.stderr)
        print("Ensure 'ollama serve' is running.", file=sys.stderr)

if __name__ == "__main__":
    main()
