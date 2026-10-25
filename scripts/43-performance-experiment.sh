#!/usr/bin/env bash
# Script 43: experiment for the performance feature. It reads from your real Ollama which speed figures a test run reports, how the processor split looks, and what the machine reports about itself. It changes no settings and saves no file.
# Usage: scripts/43-performance-experiment.sh [MODEL] ; optional: EMBED_MODEL=name to also try an embedding model.
# CAUTION: it makes the model write a few short answers, so it LOADS the model. Run it only when Ollama is idle.
# Do not stop at errors: a failing step is itself a result we want to see.
set -uo pipefail
# The address of Ollama (the same default the monitor uses); OLLAMA_URL can override it.
BASE="${OLLAMA_URL:-http://127.0.0.1:11434}"
# The chat model to test; the first argument overrides the default.
MODEL="${1:-medgemma:latest}"
# An embedding model to try as well; empty means skip that step.
EMBED="${EMBED_MODEL:-}"
# A temporary folder for the helper program.
WORK="$(mktemp -d)"
# Becomes 1 only when this script loaded the model, so the cleanup unloads nothing else.
LOADED_BY_US=0
# Remove the temporary folder, and unload the model if this script loaded it; it runs however the script ends.
cleanup() {
  # Only when this script loaded the model.
  if [ "$LOADED_BY_US" = 1 ]; then
    # Ask Ollama to unload it now (keep_alive 0 with no prompt) and show the answer code.
    curl -s -m 60 -o /dev/null -w "cleanup: unload $MODEL -> HTTP %{http_code}\n" -X POST "$BASE/api/generate" -d "{\"model\":\"$MODEL\",\"keep_alive\":0}"
  fi
  # Remove the temporary folder.
  rm -rf "$WORK"
}
# Run the cleanup when the script ends, is interrupted, or fails.
trap cleanup EXIT

# The helper program: one small Python file with a few commands (env, ps, tags, gen, stream, embed).
cat > "$WORK/probe.py" <<'PY'
# json reads and writes Ollama's messages; os, sys, time, shutil and subprocess read the machine; urllib talks to Ollama; http.client reads a streamed reply.
import json, os, sys, time, shutil, subprocess, urllib.request, http.client, urllib.parse
# The address of Ollama and the command to run.
base, cmd = sys.argv[1], sys.argv[2]

# post sends one JSON request and returns the decoded reply and the seconds it took.
def post(path, body, timeout=300):
    # Build the request.
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    # Remember the start time.
    t0 = time.time()
    # Send it and decode the reply.
    with urllib.request.urlopen(req, timeout=timeout) as r:
        # The reply.
        data = json.load(r)
    # Hand back the reply and the wall-clock time.
    return data, time.time() - t0

# rate turns a count and a duration in nanoseconds into a speed per second, or None when it cannot be worked out.
def rate(count, ns):
    # A speed needs both numbers and a duration above zero.
    return round(count / (ns / 1e9), 2) if count and ns else None

# show prints the figures of one finished generate or embed reply (never the answer text itself).
def show(label, d, wall):
    # The keys the reply carries, without the text of the answer.
    print("  %s: reply keys = %s" % (label, sorted(k for k in d.keys() if k not in ("response", "embeddings", "context"))))
    # The raw figures, as Ollama reports them (durations are in nanoseconds).
    for k in ("total_duration", "load_duration", "prompt_eval_count", "prompt_eval_duration", "eval_count", "eval_duration", "done_reason"):
        # Print each, or say it is missing.
        print("    %-22s %s" % (k, d.get(k, "(missing)")))
    # The speeds worked out from them.
    print("    answer speed          %s tokens/s" % rate(d.get("eval_count"), d.get("eval_duration")))
    # Prompt reading speed.
    print("    prompt reading speed  %s tokens/s" % rate(d.get("prompt_eval_count"), d.get("prompt_eval_duration")))
    # Load time in seconds.
    print("    load time             %s s" % (round(d.get("load_duration", 0) / 1e9, 3) if "load_duration" in d else "(missing)"))
    # Total time in seconds, next to the time we measured ourselves.
    print("    total time            %s s (measured by this script: %.3f s)" % (round(d.get("total_duration", 0) / 1e9, 3) if "total_duration" in d else "(missing)", wall))
    # The estimate of the time to the first word.
    print("    first word estimate   %s s (load time + prompt reading time)" % round((d.get("load_duration", 0) + d.get("prompt_eval_duration", 0)) / 1e9, 3))

# The fixed short prompt of the test, and the options that keep the answer short and repeatable.
PROMPT = "Explain in two sentences why the sky is blue."
OPTIONS = {"num_predict": 64, "temperature": 0, "seed": 1}

# The command "env": what this machine says about itself.
if cmd == "env":
    # Logical processor count.
    print("  logical CPU cores     %s" % os.cpu_count())
    # The processor name, when Linux lists one.
    name = "(no model name in /proc/cpuinfo)"
    # Read the file.
    try:
        # Look for the first model name line.
        for line in open("/proc/cpuinfo"):
            # Found.
            if line.lower().startswith("model name"):
                # Keep the text after the colon.
                name = line.split(":", 1)[1].strip(); break
    except OSError as e:
        # Say why it could not be read.
        name = "(cannot read /proc/cpuinfo: %s)" % e
    # Print it.
    print("  processor             %s" % name)
    # The load average: how many programs wanted a processor in the last 1, 5 and 15 minutes.
    try:
        # Read the first three numbers.
        print("  load average 1/5/15m  %s" % " ".join(open("/proc/loadavg").read().split()[:3]))
    except OSError as e:
        # Say why it could not be read.
        print("  load average          (cannot read: %s)" % e)
    # Memory figures, in kilobytes in the file.
    try:
        # Read them into a table.
        mem = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
        # Print the four that matter, in gigabytes.
        for k in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
            # One line each.
            print("  %-21s %.1f GB" % (k, mem.get(k, 0) / 1048576))
    except OSError as e:
        # Say why it could not be read.
        print("  memory                (cannot read: %s)" % e)
    # The graphics card, only when its own tool is already on this machine.
    exe = shutil.which("nvidia-smi")
    # The tool is missing.
    if not exe:
        # Say so.
        print("  GPU                   nvidia-smi is not installed here")
    # The tool is there.
    else:
        # Ask it for four values.
        try:
            # Run with a time limit.
            out = subprocess.run([exe, "--query-gpu=name,memory.used,memory.total,utilization.gpu", "--format=csv,noheader"], capture_output=True, text=True, timeout=10)
            # Print what it said, or its error.
            print("  GPU                   %s" % (out.stdout.strip() or out.stderr.strip() or "(no output)"))
        except Exception as e:
            # Say why it failed.
            print("  GPU                   nvidia-smi failed: %s" % e)

# The command "ps": what Ollama says is loaded, with the processor split worked out.
elif cmd == "ps":
    # Read the loaded list.
    data = json.load(urllib.request.urlopen(base + "/api/ps", timeout=30))
    # Nothing loaded.
    if not data.get("models"):
        # Say so.
        print("  (nothing is loaded)")
    # One block per loaded model.
    for m in data.get("models", []):
        # The sizes.
        size, vram = m.get("size", 0), m.get("size_vram", 0)
        # Print the model's figures.
        print("  %s: size=%s size_vram=%s context_length=%s expires_at=%s" % (m.get("name"), size, vram, m.get("context_length"), m.get("expires_at")))
        # The split: the share in graphics memory and the rest.
        if size:
            # Print the percentages.
            print("    processor split: %.0f%% GPU memory, %.0f%% CPU/other" % (100 * vram / size, 100 * (size - vram) / size))

# The command "tags": the installed models and what each can do.
elif cmd == "tags":
    # Read the installed list.
    for m in json.load(urllib.request.urlopen(base + "/api/tags", timeout=30)).get("models", []):
        # One line each.
        print("  %-45s %s" % (m.get("name"), m.get("capabilities", "(no capabilities field)")))

# The command "gen": one answer in a single reply (the model name is argv[3]).
elif cmd == "gen":
    # Send the fixed prompt.
    d, wall = post("/api/generate", {"model": sys.argv[3], "prompt": PROMPT, "stream": False, "keep_alive": "2m", "options": OPTIONS})
    # Print the figures.
    show("run", d, wall)

# The command "stream": one answer read as a stream, to measure the real time to the first word.
elif cmd == "stream":
    # Split the address.
    u = urllib.parse.urlparse(base)
    # Open the connection.
    conn = http.client.HTTPConnection(u.hostname, u.port, timeout=300)
    # Remember the start time.
    t0 = time.time()
    # Send the request.
    conn.request("POST", "/api/generate", json.dumps({"model": sys.argv[3], "prompt": PROMPT, "stream": True, "keep_alive": "2m", "options": OPTIONS}), {"Content-Type": "application/json"})
    # The reply.
    r = conn.getresponse()
    # Times and the last piece.
    first, last, pieces = None, {}, 0
    # Read piece by piece.
    for raw in r:
        # Skip empty lines.
        if not raw.strip():
            continue
        # Decode one piece.
        piece = json.loads(raw)
        # Count it.
        pieces += 1
        # The first piece with text is the first word.
        if first is None and piece.get("response"):
            first = time.time() - t0
        # The last piece carries the figures.
        last = piece
    # Print the findings.
    print("  stream: %d pieces, first word after %s s (measured by this script)" % (pieces, round(first, 3) if first else "n/a"))
    # Compare with the estimate from the final figures.
    show("stream final piece", last, time.time() - t0)

# The command "embed": one embedding request (the model name is argv[3]).
elif cmd == "embed":
    # Send a short text.
    d, wall = post("/api/embed", {"model": sys.argv[3], "input": "The sky is blue.", "keep_alive": "5s"})
    # How many vectors and how long the first one is.
    print("  vectors: %d, length of the first: %d" % (len(d.get("embeddings", [])), len((d.get("embeddings") or [[]])[0])))
    # Print the figures.
    show("embed", d, wall)
PY

# --- STEP 0: checks before anything is loaded ---
echo "STEP 0  preflight"
# Both tools are needed.
for t in curl python3; do
  # Stop with a clear message when one is missing.
  command -v "$t" > /dev/null || { echo "FAIL  $t is not installed"; exit 1; }
done
# The installed models and what each can do.
echo "  installed models:"
python3 "$WORK/probe.py" "$BASE" tags
# What is loaded right now: the test must not disturb a model that is in use.
echo "  loaded right now:"
python3 "$WORK/probe.py" "$BASE" ps
# Stop when the chosen model is already loaded, so nothing in use is disturbed.
if curl -s -m 30 "$BASE/api/ps" | python3 -c 'import json,sys; sys.exit(0 if any(m.get("name")==sys.argv[1] for m in json.load(sys.stdin).get("models",[])) else 1)' "$MODEL"; then
  # Say why and stop.
  echo "STOP  $MODEL is already loaded and may be in use; unload it first or choose another model"; exit 1
fi
# From here on, the cleanup unloads the model again.
LOADED_BY_US=1

# --- STEP 1: the machine before the test ---
echo "STEP 1  machine before the test"
# Print the snapshot.
python3 "$WORK/probe.py" "$BASE" env

# --- STEP 2: three answers in a row; the first one has to load the model ---
for N in 1 2 3; do
  # Say which run this is.
  echo "STEP 2.$N  run $N for $MODEL$([ "$N" = 1 ] && echo " (this run loads the model, so its load time is long)")"
  # Run it.
  python3 "$WORK/probe.py" "$BASE" gen "$MODEL"
  # Show what is loaded after run 1 only (the processor split).
  if [ "$N" = 1 ]; then
    # Say what follows.
    echo "  loaded after run 1:"
    # Print it.
    python3 "$WORK/probe.py" "$BASE" ps
  fi
done

# --- STEP 3: one streamed answer, to measure the true time to the first word ---
echo "STEP 3  streamed run for $MODEL"
# Run it.
python3 "$WORK/probe.py" "$BASE" stream "$MODEL"

# --- STEP 4: the machine after the test ---
echo "STEP 4  machine after the test"
# Print the snapshot.
python3 "$WORK/probe.py" "$BASE" env

# --- STEP 5: an embedding model, if one was named ---
if [ -n "$EMBED" ]; then
  # Say what follows.
  echo "STEP 5  embedding model $EMBED"
  # Run it twice: the first run loads the model.
  for N in 1 2; do
    # Say which run this is.
    echo "  embed run $N"
    # Run it.
    python3 "$WORK/probe.py" "$BASE" embed "$EMBED"
  done
  # The embedding model unloads itself 5 seconds after its last request (keep_alive 5s).
  echo "  (the embedding model unloads itself 5 seconds after the last request)"
else
  # Say it was skipped.
  echo "STEP 5  skipped (to try an embedding model, run: EMBED_MODEL=name scripts/43-performance-experiment.sh)"
fi

# --- STEP 6: the model is unloaded by the cleanup that runs now ---
echo "STEP 6  cleanup runs now: $MODEL is unloaded again"
# End of the experiment; the trap unloads the model.
echo "Experiment finished. Paste everything above this line back to Claude."
