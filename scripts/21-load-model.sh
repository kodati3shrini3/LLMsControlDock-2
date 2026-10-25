#!/usr/bin/env bash
# Script 21: loads one model into Ollama's memory and keeps it there for a chosen time (default 2 minutes), then shows what Ollama reports as loaded.
# Usage: scripts/21-load-model.sh embed MODEL   (for embedding models)   or   scripts/21-load-model.sh chat MODEL   (for chat models)
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Address of Ollama; override it to use another server.
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
# How long the model stays loaded after this request; Ollama accepts values such as 2m or 30s.
KEEP_ALIVE="${KEEP_ALIVE:-2m}"

# Both arguments are needed: the kind and the model name.
if [ "$#" -ne 2 ]; then
  # Explain the usage and stop.
  echo "usage: $0 embed|chat MODEL" >&2; exit 2
fi # end of the argument check
# The first argument says which kind of model it is.
KIND="$1"
# The second argument is the model name exactly as Ollama lists it.
MODEL="$2"

# Choose the request by kind.
case "$KIND" in
  # Embedding models are loaded by asking for the embedding of one short word.
  embed)
    # The address of the embedding endpoint.
    ENDPOINT="/api/embed"
    # The request body: the model, one short word as input, and the keep-alive time.
    BODY="$(printf '{"model":"%s","input":"hello","keep_alive":"%s"}' "$MODEL" "$KEEP_ALIVE")"
    ;;
  # Chat models are loaded with a request that has no prompt (Ollama's documented way to preload a model).
  chat)
    # The address of the generate endpoint.
    ENDPOINT="/api/generate"
    # The request body: the model and the keep-alive time, no prompt.
    BODY="$(printf '{"model":"%s","keep_alive":"%s"}' "$MODEL" "$KEEP_ALIVE")"
    ;;
  # Anything else is a typing mistake.
  *)
    # Explain and stop.
    echo "first argument must be embed or chat, not '$KIND'" >&2; exit 2
    ;;
esac # end of the kind choice

# Say what is about to happen.
echo "Loading $MODEL ($KIND) with keep_alive $KEEP_ALIVE ..."
# Send the request; -s hides the progress bar, -o discards the body, -w prints only the HTTP status number, and --max-time stops after 10 minutes (a big model can take a while to load).
STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 600 -H 'Content-Type: application/json' -d "$BODY" "$OLLAMA_URL$ENDPOINT")"
# Anything other than 200 means Ollama refused or failed.
if [ "$STATUS" != "200" ]; then
  # Say so and stop.
  echo "FAIL  Ollama answered HTTP status $STATUS" >&2; exit 1
fi # end of the status check
# Say it worked.
echo "PASS  Ollama answered HTTP status 200"
# Ask Ollama what is loaded now and print one line per loaded model: name and the time it will be unloaded.
curl -s "$OLLAMA_URL/api/ps" | python3 -c '
# json reads the reply; sys reads standard input.
import json, sys
# Decode the reply.
data = json.load(sys.stdin)
# Print a header.
print("Loaded now (name, unload time):")
# One line per loaded model.
for m in data.get("models", []):
    # Name and expiry as Ollama reports them.
    print("  ", m.get("name"), m.get("expires_at"))
# Say so when nothing is loaded.
if not data.get("models"):
    # A plain note.
    print("   (nothing loaded)")
'
