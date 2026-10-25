#!/usr/bin/env bash
# Script 13: loads ONE model into memory for a short time (no prompt text is sent) and prints the real /api/ps entry.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Ollama address (default: this machine); override with TARGET_URL.
export TARGET_URL="${TARGET_URL:-http://127.0.0.1:11434}"
# The model to load; the smallest chat model is the default; override with MODEL.
export MODEL="${MODEL:-medgemma:latest}"
# How long it stays loaded after this request; Ollama then unloads it by itself; override with KEEP_ALIVE.
export KEEP_ALIVE="${KEEP_ALIVE:-5m}"

# Run a short Python 3 program (standard library only).
python3 - << 'EOF_PY'
# json encodes and decodes, os reads settings, sys exits, time waits, urllib talks to Ollama.
import json, os, sys, time, urllib.request
# Read the three settings from the environment.
base, model, keep = os.environ["TARGET_URL"], os.environ["MODEL"], os.environ["KEEP_ALIVE"]
# Helper: send one request and return the decoded JSON reply.
def call(path, body=None, timeout=10):
    # With a body this is a POST (a change request); without one it is a plain GET (read-only).
    data = json.dumps(body).encode() if body is not None else None
    # Build the request, telling Ollama that a body is JSON.
    req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
    # Send it and decode the reply.
    with urllib.request.urlopen(req, timeout=timeout) as r:
        # Return the decoded data.
        return json.load(r)
# Step 1: make sure the model is installed, so we never ask Ollama to fetch anything.
installed = [m["name"] for m in call("/api/tags").get("models", [])]
# Stop with a clear message if it is missing.
if model not in installed:
    # Say what is wrong and what exists.
    sys.exit("STOP: " + model + " is not installed. Installed: " + ", ".join(installed))
# Step 2: show what is loaded before we start.
before = [m["name"] for m in call("/api/ps").get("models", [])]
# Print it so the before-and-after is clear.
print("loaded before:", before or "(none)")
# Step 3: ask Ollama to load the model; an empty prompt loads it without generating any text.
print("loading", model, "with keep_alive", keep, "(this can take a little while) ...")
# Send the load request; allow up to 3 minutes because large models take time.
call("/api/generate", {"model": model, "keep_alive": keep}, timeout=180)
# Step 4: wait up to 60 seconds for the model to appear in the loaded list.
for _ in range(30):
    # Read the loaded list.
    loaded = call("/api/ps").get("models", [])
    # Look for our model by name.
    mine = [m for m in loaded if m.get("name") == model]
    # If it is there, show the whole entry exactly as Ollama sent it, then finish.
    if mine:
        # Print the real entry with indentation for reading.
        print(json.dumps(mine[0], indent=2))
        # Remind that Ollama will unload it by itself.
        print("Ollama will unload it by itself after about", keep, "of no use.")
        # Leave successfully.
        sys.exit(0)
    # Wait 2 seconds before looking again.
    time.sleep(2)
# If we get here the model never appeared.
sys.exit("STOP: " + model + " did not appear in /api/ps within 60 seconds")
EOF_PY
