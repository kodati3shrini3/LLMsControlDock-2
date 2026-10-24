#!/usr/bin/env bash
# Step 3 research: asks a running Ollama read-only questions and prints what it reports. It changes nothing and loads no model.

# Stop at the first error, treat unset variables as errors, and fail if any command in a pipe fails
set -euo pipefail

# Address of the Ollama to ask; can be overridden by exporting TARGET_URL before running
TARGET_URL="${TARGET_URL:-http://127.0.0.1:11434}"

# Announce question 1
echo "== 1. Root address =="
# Ask the root address; -i prints the status line and headers, -sS hides progress but shows errors, --max-time gives up after 5 seconds
curl -sS -i --max-time 5 "$TARGET_URL/"
# Print an empty line to separate the answers
echo

# Announce question 2
echo "== 2. Version =="
# Ask the version endpoint; -w adds the status code and the time the call took
curl -sS -w '\nHTTP %{http_code} in %{time_total}s\n' --max-time 5 "$TARGET_URL/api/version"
# Print an empty line to separate the answers
echo

# Announce question 3
echo "== 3. Loaded models (in memory right now) =="
# Ask which models are loaded, then indent the answer so it is easy to read
curl -sS --max-time 5 "$TARGET_URL/api/ps" | python3 -m json.tool
# Print an empty line to separate the answers
echo

# Announce question 4
echo "== 4. Installed models, raw answer =="
# Ask which models are installed, then indent the answer; this also shows whether a capabilities field is already present here
curl -sS --max-time 5 "$TARGET_URL/api/tags" | python3 -m json.tool
# Print an empty line to separate the answers
echo

# Announce question 5
echo "== 5. What each installed model reports about itself =="
# Run a short Python program read from the lines below; the quoted marker EOF_PY keeps the shell from changing any character
python3 - "$TARGET_URL" << 'EOF_PY'
# Read-only probe: lists the installed models and what each one reports about itself.
# Import the json module, which reads and writes text in the JSON (JavaScript Object Notation) format.
import json
# Import sys to read the command-line argument and to stop with an error code.
import sys
# Import urllib.request to make web calls using only the standard library.
import urllib.request

# Take the Ollama address from the first command-line argument.
base = sys.argv[1]


# Define a helper that sends one request and returns the answer already decoded.
def call(path, payload=None):
    # Build the full address from the base address and the path.
    url = base + path
    # Choose the kind of request: without a payload it is a plain read.
    if payload is None:
        # Create a GET request, which only reads.
        req = urllib.request.Request(url)
    # With a payload, ask a question about one named model.
    else:
        # Create a POST request that carries the payload as JSON text and says so in its headers.
        req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}, method="POST")
    # Send the request, wait at most 15 seconds, and close the connection afterwards.
    with urllib.request.urlopen(req, timeout=15) as resp:
        # Read the answer and convert it from JSON text into Python data.
        return json.loads(resp.read())


# Try to fetch the list of installed models.
try:
    # Ask Ollama for the installed models.
    tags = call("/api/tags")
# Catch network problems and answers that are not valid JSON.
except (OSError, ValueError) as err:
    # Explain the problem on the error stream.
    print("Could not read /api/tags:", err, file=sys.stderr)
    # Stop with an error code.
    sys.exit(1)

# Take the list of model entries, or an empty list if the key is missing.
models = tags.get("models", [])
# Tell the user how many installed models were found.
print("Installed models found:", len(models))
# Go through every installed model.
for m in models:
    # Read the name that apps use to address this model.
    name = m.get("name", "?")
    # Print a header line for this model.
    print("---", name)
    # Try to ask for this model's details.
    try:
        # Ask for the details of this one model; the verbose option is deliberately not used.
        info = call("/api/show", {"model": name})
    # Catch problems for this one model so the loop can continue with the next one.
    except (OSError, ValueError) as err:
        # Report the problem for this model.
        print("  could not read details:", err)
        # Skip to the next model.
        continue
    # Take the details block, or an empty one if it is missing.
    details = info.get("details", {})
    # Print the capabilities list, or a note if Ollama reports none.
    print("  capabilities:", info.get("capabilities", "NOT REPORTED"))
    # Print the model family.
    print("  family:", details.get("family"))
    # Print the parameter size label.
    print("  parameter_size:", details.get("parameter_size"))
    # Print the quantization level label.
    print("  quantization_level:", details.get("quantization_level"))
    # Show whether the installed-models entry itself already carried a capabilities field.
    print("  capabilities also present in the /api/tags entry:", "capabilities" in m)
# End of the Python probe.
EOF_PY
# Print an empty line to separate the answers
echo

# Announce question 6
echo "== 6. Loaded models again (must match question 3: the probe loaded nothing) =="
# Ask again which models are loaded, then indent the answer
curl -sS --max-time 5 "$TARGET_URL/api/ps" | python3 -m json.tool
# Announce that the script finished
echo "== Done =="
# End of the probe script.
