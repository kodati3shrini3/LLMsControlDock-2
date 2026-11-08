#!/usr/bin/env bash
# Script 90 (read-only helper, no change to the project): saves the official public Ollama library pages (the main list page, and the model page and tags page of a list of models) into one folder and one .tar.gz file, so the live "Find LLM" reader and its dated fallback copy are built only from what the official pages really say.
# It writes nothing inside the project folder. It only needs curl and tar. Run it on any computer with internet access: bash 90-collect-ollama-library-pages.sh
# Optional: add more model names after the script name, for example: bash 90-collect-ollama-library-pages.sh gemma3 phi4

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The official public library address (a variable so the script can be tested against a local fake server).
BASE="${LIBRARY_BASE:-https://ollama.com}"
# The pause in seconds between two requests, so the website is not hit hard.
PAUSE="${LIBRARY_PAUSE:-2}"
# The model names to collect: the two helper models first, then popular ones. A name the library does not have is reported, not guessed.
MODELS=(granite4 qwen3 llama3.2 llama3.1 gemma3 gemma3n mistral phi4 deepseek-r1 qwen2.5 qwen2.5-coder qwen3-vl llava smollm2 gpt-oss codellama starcoder2 nomic-embed-text mxbai-embed-large all-minilm bge-m3)
# Names given on the command line are added at the end.
MODELS+=("$@")

# Today's date, only for the folder name.
STAMP="$(date +%Y%m%d-%H%M%S)"
# The output folder, inside the home folder; the script never writes anywhere else.
OUT="$HOME/findllm-collect-$STAMP"
# Refuse to reuse a folder.
[ ! -e "$OUT" ] || { echo "FAIL  $OUT already exists"; exit 1; }
# curl is needed.
command -v curl >/dev/null || { echo "FAIL  curl is not installed"; exit 1; }
# tar is needed.
command -v tar >/dev/null || { echo "FAIL  tar is not installed"; exit 1; }
# Make the folder.
mkdir -p "$OUT"

# The report file: one line per page.
REPORT="$OUT/REPORT.tsv"
# The header line of the report.
printf 'model\tpage\tstatus\tbytes\tsha256\turl\n' > "$REPORT"
# The time of the collection, with its timezone, as the first fact in a separate file.
date '+%Y-%m-%d %H:%M:%S %Z (UTC%z)' > "$OUT/COLLECTED-AT.txt"

# Count of pages saved.
OK=0
# Count of pages that could not be saved.
BAD=0

# fetch_page saves one page: arguments are the model name, the page kind (model or tags) and the address.
fetch_page() {
  # The model name.
  local name="$1"
  # The page kind.
  local kind="$2"
  # The address.
  local url="$3"
  # The file the page is saved in.
  local file="$OUT/${name//\//_}.$kind.html"
  # Ask for the page; -f makes an HTTP error count as failure, -sS is quiet but shows errors, -L follows redirects; the client name says only what this is.
  if curl -fsSL --max-time 30 -A "LLMsControlDock-catalogue-check" -o "$file" "$url" 2>/dev/null; then
    # The size and fingerprint of what was saved.
    local bytes sum
    # Size in bytes.
    bytes="$(wc -c < "$file" | tr -d ' ')"
    # Fingerprint.
    sum="$(sha256sum "$file" | cut -d' ' -f1)"
    # One report line.
    printf '%s\t%s\tOK\t%s\t%s\t%s\n' "$name" "$kind" "$bytes" "$sum" "$url" >> "$REPORT"
    # Count it.
    OK=$((OK + 1))
    # Show it.
    echo "OK    $name ($kind) $bytes bytes"
  else
    # Remove a half-written file.
    rm -f "$file"
    # One report line for the failure.
    printf '%s\t%s\tNOT-SAVED\t0\t-\t%s\n' "$name" "$kind" "$url" >> "$REPORT"
    # Count it.
    BAD=$((BAD + 1))
    # Show it.
    echo "MISS  $name ($kind) could not be fetched: $url"
  fi
  # A pause before the next request.
  sleep "$PAUSE"
# End of fetch_page.
}

# First the main list page of the library: the page the live "Find LLM" search will read; it is saved under the name _listing.
fetch_page "_listing" model "$BASE/library"
# Go through every model.
for M in "${MODELS[@]}"; do
  # Only plain names are allowed (letters, digits, dot, dash, underscore, colon-free), so nothing odd goes into an address.
  [[ "$M" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "SKIP  $M (not a plain model name)"; continue; }
  # The model page: description, capabilities, licence, sizes.
  fetch_page "$M" model "$BASE/library/$M"
  # The tags page: every size and quantization with its download size.
  fetch_page "$M" tags "$BASE/library/$M/tags"
# End of the loop.
done

# Pack everything into one file next to the folder.
tar -czf "$OUT.tar.gz" -C "$HOME" "$(basename "$OUT")"
# Fingerprint of the packed file, to be sure it arrived unchanged.
PACK_SUM="$(sha256sum "$OUT.tar.gz" | cut -d' ' -f1)"
# Summary.
echo "----"
# Counts.
echo "Saved $OK pages, $BAD not saved."
# Where the file is.
echo "Send this file to Claude: $OUT.tar.gz"
# Its fingerprint.
echo "sha256 of the file: $PACK_SUM"
# Say clearly that nothing in the project was touched.
echo "Nothing in the project folder was changed."
