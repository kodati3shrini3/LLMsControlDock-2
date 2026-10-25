#!/usr/bin/env bash
# Script 33: experiment for the gear feature. It works ONLY on a throwaway copy of one model (never on the real model) and deletes the copy at the end.
# It answers: does /api/create keep the weights and prompts, does a changed num_ctx show up in /api/ps, and what does Ollama do with odd values?
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

# cleanup unloads and deletes the throwaway copy, and removes the temporary folder; it runs however the script ends.
cleanup() {
  # Only when this script made the copy.
  if [ "$CREATED" = 1 ]; then
    # Ask Ollama to unload the copy first (keep_alive 0).
    curl -s -m 60 -o /dev/null -X POST "$BASE/api/generate" -d "{\"model\":\"$COPY\",\"keep_alive\":0}"
    # Give it a moment.
    sleep 2
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
  # -m 600 allows ten minutes, enough for loading a model.
  curl -s -m 600 -o "$4" -w "%{http_code}" -X "$1" "$BASE$2" -H 'Content-Type: application/json' -d "$3"
}

# summ FILE: prints the interesting parts of an /api/show reply.
summ() {
  # Read the file with a small Python program (Python is only used here, in the test script).
  python3 - "$1" <<'PY'
import json, sys
# Load the saved reply.
d = json.load(open(sys.argv[1]))
# The model_info section holds the model's own limits.
mi = d.get("model_info", {})
# Find every key that ends in context_length.
ctx = {k: v for k, v in mi.items() if k.endswith(".context_length")}
# Print the parts that matter for the gear page.
print("  parameters     :", repr(d.get("parameters", "")))
print("  template chars :", len(d.get("template", "")))
print("  system chars   :", len(d.get("system", "")))
print("  license chars  :", len(d.get("license", "")))
print("  capabilities   :", d.get("capabilities"))
print("  model max ctx  :", ctx)
print("  details        :", d.get("details"))
PY
}

# same FILE1 FILE2: says whether the template, system prompt, license, details and capabilities are equal in two /api/show replies.
same() {
  # Compare with a small Python program.
  python3 - "$1" "$2" <<'PY'
import json, sys
# Load both replies.
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
# Compare each part and print the verdict.
for k in ["template", "system", "license", "details", "capabilities"]:
    print("  %-13s: %s" % (k, "same" if a.get(k) == b.get(k) else "DIFFERENT"))
PY
}

# psum: prints what /api/ps says about the copy right now.
psum() {
  # Ask Ollama which models are loaded and pick out the copy.
  curl -s -m 30 "$BASE/api/ps" | python3 -c '
import json, sys
# Decode the reply.
d = json.load(sys.stdin)
# Keep only the copy.
m = [x for x in d.get("models", []) if x.get("name", "").startswith("occ-experiment-copy")]
# Say so when it is not loaded.
if not m:
    print("  (copy is not loaded)")
# Print the figures for the copy.
for x in m:
    print("  loaded:", x.get("name"), "context_length=", x.get("context_length"), "size=", x.get("size"), "size_vram=", x.get("size_vram"), "expires_at=", x.get("expires_at"))
'
}

# tagsum: prints size and digest (fingerprint) of the source model and the copy from /api/tags.
tagsum() {
  # Ask Ollama for the installed list and pick out the two names.
  curl -s -m 30 "$BASE/api/tags" | python3 -c '
import json, sys
# Decode the reply.
d = json.load(sys.stdin)
# Print one line for each of the two names.
for x in d.get("models", []):
    if x["name"] in (sys.argv[1], sys.argv[2]):
        print("  %-26s size=%s digest=%s" % (x["name"], x["size"], x["digest"][:12]))
' "$SRC" "$COPY"
}

# unload: asks Ollama to unload the copy and waits a moment.
unload() {
  # keep_alive 0 means unload now.
  curl -s -m 60 -o /dev/null -X POST "$BASE/api/generate" -d "{\"model\":\"$COPY\",\"keep_alive\":0}"
  # Give Ollama a moment to finish.
  sleep 2
}

# --- STEP 0: checks before touching anything ---
echo "STEP 0  preflight"
# Both tools are needed.
for t in curl python3; do
  # Stop with a clear message when one is missing.
  command -v "$t" > /dev/null || { echo "FAIL  $t is not installed"; exit 1; }
done
# Ollama must answer.
VER="$(curl -s -m 10 "$BASE/api/version")" || true
# Show the version text.
echo "  version reply: $VER"
# An empty reply means Ollama is not reachable.
[ -n "$VER" ] || { echo "FAIL  Ollama does not answer at $BASE"; exit 1; }
# The source model must be installed, and the copy name must be free.
python3 - "$BASE" "$SRC" "$COPY" <<'PY' || exit 1
import json, sys, urllib.request
# Read the installed list.
names = [m["name"] for m in json.load(urllib.request.urlopen(sys.argv[1] + "/api/tags"))["models"]]
# The source must exist.
if sys.argv[2] not in names:
    print("FAIL  %s is not installed" % sys.argv[2]); sys.exit(1)
# The copy name must not exist yet (the script never touches an existing model).
if sys.argv[3] in names:
    print("FAIL  %s already exists; delete it yourself first" % sys.argv[3]); sys.exit(1)
print("  ok: %s is installed and %s is free" % (sys.argv[2], sys.argv[3]))
PY

# --- STEP 1: what /api/show says about the real model ---
echo "STEP 1  /api/show of $SRC"
# Ask for the details and save them.
echo "  HTTP $(call POST /api/show "{\"model\":\"$SRC\"}" "$WORK/show_src.json")"
# Print the interesting parts.
summ "$WORK/show_src.json"

# --- STEP 2: make the throwaway copy ---
echo "STEP 2  /api/copy $SRC -> $COPY"
# Copy the model (the weights are shared, so this is quick).
CODE="$(call POST /api/copy "{\"source\":\"$SRC\",\"destination\":\"$COPY\"}" "$WORK/copy.json")"
# Print the status.
echo "  HTTP $CODE"
# Only a 200 means the copy exists; otherwise stop, with nothing to clean up.
[ "$CODE" = "200" ] || { echo "FAIL  the copy was not made"; cat "$WORK/copy.json"; exit 1; }
# From here on, cleanup may delete the copy.
CREATED=1
# Compare size and fingerprint of source and copy.
tagsum

# --- STEP 3: is the copy identical in everything that matters? ---
echo "STEP 3  /api/show of the copy compared with the source"
# Ask and save.
echo "  HTTP $(call POST /api/show "{\"model\":\"$COPY\"}" "$WORK/show_copy1.json")"
# Compare the two replies.
same "$WORK/show_src.json" "$WORK/show_copy1.json"

# --- STEP 4: baseline, load the copy with Ollama's own defaults ---
echo "STEP 4  load the copy with defaults (keep_alive 2m), then read /api/ps"
# An empty prompt loads the model without answering anything.
echo "  HTTP $(call POST /api/generate "{\"model\":\"$COPY\",\"keep_alive\":\"2m\"}" "$WORK/load1.json")"
# What Ollama reports now.
psum
# Unload again.
unload

# --- STEP 5: change num_ctx inside the copy with /api/create ---
echo "STEP 5  /api/create: same model, parameters num_ctx 8192"
# Rewrite the copy's configuration; from = the copy itself, so no weights are fetched.
echo "  HTTP $(call POST /api/create "{\"model\":\"$COPY\",\"from\":\"$COPY\",\"parameters\":{\"num_ctx\":8192},\"stream\":false}" "$WORK/create1.json")"
# The first 300 characters of the reply.
echo "  reply: $(head -c 300 "$WORK/create1.json")"

# --- STEP 6: what changed in the copy ---
echo "STEP 6  /api/show of the copy after the change"
# Ask and save.
echo "  HTTP $(call POST /api/show "{\"model\":\"$COPY\"}" "$WORK/show_copy2.json")"
# Print the parts.
summ "$WORK/show_copy2.json"
# Template, system prompt and the rest must be unchanged.
echo "  compared with the source:"
# Compare.
same "$WORK/show_src.json" "$WORK/show_copy2.json"
# Size must be unchanged (weights shared) and the fingerprint may differ.
echo "  size and fingerprint now:"
# Print.
tagsum

# --- STEP 7: does the loaded model use the new context size? ---
echo "STEP 7  load the copy again (keep_alive 2m), then read /api/ps"
# Load.
echo "  HTTP $(call POST /api/generate "{\"model\":\"$COPY\",\"keep_alive\":\"2m\"}" "$WORK/load2.json")"
# Compare context_length with step 4.
psum

# --- STEP 8: what happens when a request asks for another context size while the model is loaded? ---
echo "STEP 8  request with num_ctx 4096 while the copy is loaded"
# Same model, other option, no prompt.
echo "  HTTP $(call POST /api/generate "{\"model\":\"$COPY\",\"keep_alive\":\"2m\",\"options\":{\"num_ctx\":4096}}" "$WORK/load3.json")"
# See whether the loaded model changed.
psum
# Unload again.
unload

# --- STEP 9: which values does Ollama accept? (only the copy's configuration is written; nothing is loaded) ---
echo "STEP 9  limits: what /api/create accepts"
# Try three odd values and one unknown name.
for P in '{"num_ctx":1}' '{"num_ctx":100000000}' '{"temperature":5}' '{"bogus_setting":1}'; do
  # Send it.
  C="$(call POST /api/create "{\"model\":\"$COPY\",\"from\":\"$COPY\",\"parameters\":$P,\"stream\":false}" "$WORK/lim.json")"
  # Print the value, the status and the start of the reply.
  echo "  $P -> HTTP $C  $(head -c 160 "$WORK/lim.json" | tr '\n' ' ')"
done
# What the copy's parameters say after those attempts.
echo "  parameters now: $(call POST /api/show "{\"model\":\"$COPY\"}" "$WORK/show_copy3.json" > /dev/null; python3 -c 'import json,sys; print(repr(json.load(open(sys.argv[1])).get("parameters","")))' "$WORK/show_copy3.json")"
# An invalid keep_alive text on a generate request (nothing should load).
echo "  keep_alive \"abc\" -> HTTP $(call POST /api/generate "{\"model\":\"$COPY\",\"keep_alive\":\"abc\"}" "$WORK/ka.json")  $(head -c 160 "$WORK/ka.json" | tr '\n' ' ')"
# Make sure nothing is left loaded.
unload
# Check.
psum

# --- STEP 10: clean up (also done automatically when the script ends) ---
echo "STEP 10 cleanup runs now; the source model $SRC is untouched"
# End of the experiment; the trap deletes the copy.
echo "Experiment finished. Paste everything above this line back to Claude."
