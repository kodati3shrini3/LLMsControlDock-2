#!/usr/bin/env bash
# Script 08: read-only watcher; polls Ollama's /api/ps and prints a line only when the set of loaded models changes.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Ollama address (default: this machine); override with TARGET_URL.
TARGET_URL="${TARGET_URL:-http://127.0.0.1:11434}"
# Seconds between polls; override with INTERVAL.
INTERVAL="${INTERVAL:-3}"
# Stop after this many polls; 0 means run until Ctrl+C (a small number is handy for testing).
MAX_POLLS="${MAX_POLLS:-0}"

# On Ctrl+C (the INT signal) print a friendly line and leave cleanly.
trap 'echo; echo "Stopped."; exit 0' INT

# The last set seen; a marker value that no real reply can equal, so the first poll always prints.
last="<start>"
# Count of polls done so far.
polls=0

# Announce what is being watched.
echo "Watching ${TARGET_URL}/api/ps every ${INTERVAL}s; prints only on change; Ctrl+C to stop."

# Repeat forever (or until MAX_POLLS is reached).
while true; do
  # Ask Ollama which models are loaded; -s hides progress, --max-time 3 gives up after 3 seconds, failure becomes empty text.
  reply="$(curl -s --max-time 3 "${TARGET_URL}/api/ps" || true)"
  # Turn the reply into one sorted, comma-separated line of model names, or a marker when unreachable or malformed.
  now="$(printf '%s' "$reply" | python3 -c '
# json decodes the reply; sys reads standard input.
import json, sys
# Try to decode the reply; any failure means "unreachable or not Ollama".
try:
    # Parse the JSON text from standard input.
    data = json.load(sys.stdin)
    # Collect the model names, sorted so the order never causes false changes.
    names = sorted(m.get("name", "?") for m in data.get("models", []))
    # Print "(none loaded)" for an empty list, otherwise the names joined by commas.
    print(", ".join(names) if names else "(none loaded)")
# Catch every failure to decode.
except Exception:
    # Print the marker for unreachable or unexpected replies.
    print("(unreachable or unexpected reply)")
')"
  # Only print when the set differs from the last one seen.
  if [ "$now" != "$last" ]; then
    # Print a timestamp and the new set.
    echo "$(date '+%H:%M:%S')  loaded: $now"
    # Remember it for the next comparison.
    last="$now"
  fi # end of the change check
  # Count this poll.
  polls=$((polls+1))
  # Leave the loop if a limit was set and reached.
  if [ "$MAX_POLLS" -gt 0 ] && [ "$polls" -ge "$MAX_POLLS" ]; then
    # Stop polling.
    break
  fi # end of the limit check
  # Wait before the next poll.
  sleep "$INTERVAL"
done # end of the polling loop
