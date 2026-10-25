#!/usr/bin/env bash
# Script 23: busy-detection experiment. Asks a chat model for a long answer and, while it is writing, reads Ollama's loaded-models list every 2 seconds, so we can see whether Ollama shows any sign that a model is busy.
# Usage: scripts/23-busy-experiment.sh [MODEL]   (default medgemma:latest; set TOKENS to change the answer length, default 1200)
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Address of Ollama; override it to use another server.
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
# The chat model to use; the first argument overrides the default.
MODEL="${1:-medgemma:latest}"
# The most word pieces (tokens) the answer may have; a long answer gives us time to look.
TOKENS="${TOKENS:-1200}"
# How long the model stays loaded after the answer is finished.
KEEP_ALIVE="${KEEP_ALIVE:-2m}"

# A temporary file that holds the HTTP status of the long request.
STATUS_FILE="$(mktemp)"
# Remove the temporary file when the script ends for any reason.
trap 'rm -f "$STATUS_FILE"' EXIT

# The request: the model, a story prompt, one single reply instead of a stream, the keep-alive time and the answer length limit.
BODY="$(printf '{"model":"%s","prompt":"Write a long story about a lighthouse keeper who finds a message in a bottle.","stream":false,"keep_alive":"%s","options":{"num_predict":%s}}' "$MODEL" "$KEEP_ALIVE" "$TOKENS")"

# sample LABEL: asks Ollama what is loaded and prints one line about our model (seconds since start, label, name, unload time, memory on the GPU, context length).
sample() {
  # Ask for the loaded-models list and let a short Python program pick out our model.
  curl -s "$OLLAMA_URL/api/ps" | python3 -c '
# json reads the reply; sys reads the input and the arguments; time gives the clock.
import json, sys, time
# The arguments: the label, the model name and the start time.
label, model, start = sys.argv[1], sys.argv[2], float(sys.argv[3])
# Decode the reply.
data = json.load(sys.stdin)
# Seconds since the experiment started.
secs = int(time.time() - start)
# Look for our model in the list.
mine = [m for m in data.get("models", []) if m.get("name") == model]
# Our model is not loaded.
if not mine:
    # Say so in the same column layout.
    print("%4ds  %-10s  (not loaded)" % (secs, label))
# Our model is loaded.
else:
    # The first match.
    m = mine[0]
    # Print the values Ollama reports.
    print("%4ds  %-10s  expires_at=%s  size_vram=%s  context_length=%s" % (secs, label, m.get("expires_at"), m.get("size_vram"), m.get("context_length")))
' "$1" "$MODEL" "$START"
} # end of sample

# Say what is about to happen.
echo "Experiment: $MODEL writes up to $TOKENS tokens; Ollama's loaded list is read every 2 seconds."
# Remember the start time in seconds (with decimals) for the sample lines.
START="$(python3 -c 'import time; print(time.time())')"
# Show the state before anything is requested.
sample "before"
# Start the long request in the background; -s hides the progress bar, -o discards the answer text, -w writes only the HTTP status to the temporary file, and --max-time stops after 5 minutes.
curl -s -o /dev/null -w '%{http_code}' --max-time 300 -H 'Content-Type: application/json' -d "$BODY" "$OLLAMA_URL/api/generate" > "$STATUS_FILE" &
# Remember the background request so we can tell when it ends.
GEN_PID=$!
# Keep sampling while the request is still running (kill -0 only tests that the process exists).
while kill -0 "$GEN_PID" 2> /dev/null; do
  # One sample, labelled as during the answer.
  sample "answering"
  # Wait 2 seconds.
  sleep 2
done # end of the answering loop
# Collect the background request; || true because a failed request is reported below, not by stopping here.
wait "$GEN_PID" || true
# Say how the request ended.
echo "The long request ended with HTTP status $(cat "$STATUS_FILE")."
# Five more samples after the answer is finished, to see what changes.
for _ in 1 2 3 4 5; do
  # One sample, labelled as after the answer.
  sample "finished"
  # Wait 2 seconds.
  sleep 2
done # end of the finished loop
