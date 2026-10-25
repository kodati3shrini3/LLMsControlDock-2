#!/usr/bin/env bash
# Script 35: experiment for the full settings table. It works ONLY on a throwaway copy of one model (never on the real model) and deletes the copy at the end.
# It answers: how does Ollama print each saved setting, does a new "stop" list replace or add to the old one, do special values (-1, -2, 0) survive, and what happens with wrong value types.
# Do not stop at errors: a failing step is itself a result we want to see.
set -uo pipefail
# The address of Ollama (the same default the monitor uses); OLLAMA_URL can override it.
BASE="${OLLAMA_URL:-http://127.0.0.1:11434}"
# The small real model that gets copied (the copy is what the experiment changes).
SRC="${SRC_MODEL:-medgemma:latest}"
# The name of the throwaway copy; nothing else is ever deleted by this script.
COPY="occ-experiment-copy"
# A temporary folder for the raw replies.
WORK="$(mktemp -d)"
# Becomes 1 only after Ollama confirmed the copy was made, so cleanup deletes nothing else.
CREATED=0

# cleanup deletes the throwaway copy (it was never loaded) and removes the temporary folder; it runs however the script ends.
cleanup() {
  # Only when this script made the copy.
  if [ "$CREATED" = 1 ]; then
    # Delete the copy and show the answer code.
    curl -s -m 60 -o /dev/null -w "cleanup: delete %{url_effective} -> HTTP %{http_code}\n" -X DELETE "$BASE/api/delete" -d "{\"model\":\"$COPY\"}"
  fi
  # Remove the temporary folder.
  rm -rf "$WORK"
}
# Run the cleanup when the script ends, is interrupted, or fails.
trap cleanup EXIT

# call METHOD PATH BODY OUTFILE: sends one request, saves the reply in OUTFILE and prints the HTTP status code.
call() {
  # -m 120 allows two minutes.
  curl -s -m 120 -o "$4" -w "%{http_code}" -X "$1" "$BASE$2" -H 'Content-Type: application/json' -d "$3"
}

# params: prints the saved parameters of the copy exactly as /api/show reports them, one line each.
params() {
  # Ask Ollama and print the parameters text with the invisible characters made visible.
  curl -s -m 60 -X POST "$BASE/api/show" -d "{\"model\":\"$COPY\"}" | python3 -c '
import json, sys
# Decode the reply.
d = json.load(sys.stdin)
# The parameters text, one "name value" pair per line.
text = d.get("parameters", "")
# Say so when nothing is saved.
if not text.strip():
    print("    (no saved parameters)")
# Print each line with repr so quotes and spaces are visible.
for line in text.split("\n"):
    print("    " + repr(line))
'
}

# create LABEL JSON: sends /api/create for the copy with the given parameters object and prints the status, Ollama's short reply, and the parameters afterwards.
create() {
  # Say what is tried.
  echo "  $1: parameters $2"
  # Send it; from = the copy itself, so no weights are fetched.
  CODE="$(call POST /api/create "{\"model\":\"$COPY\",\"from\":\"$COPY\",\"parameters\":$2,\"stream\":false}" "$WORK/c.json")"
  # Print the status and the start of the reply.
  echo "    -> HTTP $CODE  $(head -c 160 "$WORK/c.json" | tr '\n' ' ')"
  # Print what is saved now.
  params
}

# --- STEP 0: checks before touching anything ---
echo "STEP 0  preflight"
# Both tools are needed.
for t in curl python3; do
  # Stop with a clear message when one is missing.
  command -v "$t" > /dev/null || { echo "FAIL  $t is not installed"; exit 1; }
done
# The source model must be installed, and the copy name must be free.
python3 - "$BASE" "$SRC" "$COPY" <<'PY' || exit 1
import json, sys, urllib.request
# Read the installed list.
names = [m["name"] for m in json.load(urllib.request.urlopen(sys.argv[1] + "/api/tags"))["models"]]
# The source must exist.
if sys.argv[2] not in names:
    print("FAIL  %s is not installed" % sys.argv[2]); sys.exit(1)
# The copy name must not exist yet (the script never touches an existing model).
if sys.argv[3] in names or sys.argv[3] + ":latest" in names:
    print("FAIL  %s already exists; delete it yourself first" % sys.argv[3]); sys.exit(1)
print("  ok: %s is installed and %s is free" % (sys.argv[2], sys.argv[3]))
PY

# --- STEP 1: make the throwaway copy ---
echo "STEP 1  /api/copy $SRC -> $COPY"
# Copy the model (the weights are shared, so this is quick).
CODE="$(call POST /api/copy "{\"source\":\"$SRC\",\"destination\":\"$COPY\"}" "$WORK/copy.json")"
# Print the status.
echo "  HTTP $CODE"
# Only a 200 means the copy exists; otherwise stop, with nothing to clean up.
[ "$CODE" = "200" ] || { echo "FAIL  the copy was not made"; cat "$WORK/copy.json"; exit 1; }
# From here on, cleanup may delete the copy.
CREATED=1
# What the copy has saved before any change.
echo "  saved parameters of the fresh copy:"
# Print them.
params

# --- STEP 2: every number setting at once ---
echo "STEP 2  all number settings in one request"
# Ten typical values; the output shows how Ollama prints each one.
create "typical values" '{"num_ctx":8192,"temperature":0.2,"top_k":40,"top_p":0.9,"min_p":0.05,"repeat_penalty":1.1,"repeat_last_n":64,"seed":42,"num_predict":512}'

# --- STEP 3: does a request with ONE setting keep the others? ---
echo "STEP 3  one setting only (temperature 0.7); are the others kept?"
# Only temperature is sent.
create "only temperature" '{"temperature":0.7}'

# --- STEP 4: special values the Ollama documentation mentions ---
echo "STEP 4  special values: -1, -2, 0"
# Infinite answer length, repeat window = context size.
create "num_predict -1, repeat_last_n -1" '{"num_predict":-1,"repeat_last_n":-1}'
# Fill the context (a value of the documentation mirror, not of the official page).
create "num_predict -2" '{"num_predict":-2}'
# Repeat check off, seed 0, temperature 0.
create "repeat_last_n 0, seed 0, temperature 0" '{"repeat_last_n":0,"seed":0,"temperature":0}'
# Very small and very large numbers, as they would be typed.
create "temperature 1.0, top_p 1, min_p 0.0" '{"temperature":1.0,"top_p":1,"min_p":0.0}'

# --- STEP 5: the stop list ---
echo "STEP 5  stop: does a new list replace the old one or add to it?"
# First list of two.
create "stop A and B" '{"stop":["AAA","BBB"]}'
# A second request with one different entry.
create "stop CCC only" '{"stop":["CCC"]}'
# Text with a space, a quote and a backslash.
create "stop with space, quote, backslash" '{"stop":["a b","say \"hi\"","back\\slash"]}'
# An empty list.
create "stop empty list" '{"stop":[]}'

# --- STEP 6: wrong types (the monitor will check before sending; this shows what Ollama alone would do) ---
echo "STEP 6  wrong types"
# Text instead of a number.
create "temperature as text" '{"temperature":"abc"}'
# A decimal where a whole number is expected.
create "top_k 1.5" '{"top_k":1.5}'
# A negative number where one is meaningless.
create "top_p -1" '{"top_p":-1}'

# --- STEP 7: cleanup runs now; the source model is untouched ---
echo "STEP 7  cleanup runs now; the source model $SRC is untouched"
# End of the experiment; the trap deletes the copy.
echo "Experiment finished. Paste everything above this line back to Claude."
