#!/usr/bin/env bash
# Script 29: copy only the files needed to continue the project into one folder (export2chat), keep the sub-folders, skip secrets and build leftovers, and make a few combined text files for the 20-files-per-chat limit.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# The project folder; the PROJECT_DIR variable can override it.
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# The export folder, placed NEXT TO the project (not inside it) so that git never sees it; the EXPORT_DIR variable can override it.
EXPORT_DIR="${EXPORT_DIR:-$(dirname "$PROJECT_DIR")/export2chat}"
# The numbers of the scripts worth keeping: 21 loads a model, 23 is the pending busy test, 27 and 28 show the newest style (older scripts only produced code that already exists in the files).
KEEP_SCRIPTS="${KEEP_SCRIPTS:-21 23 27 28}"

# The project folder must exist.
[ -d "$PROJECT_DIR" ] || { echo "NOT FOUND: $PROJECT_DIR" >&2; exit 1; }
# Never overwrite or mix with an earlier export: stop if the export folder already exists.
[ ! -e "$EXPORT_DIR" ] || { echo "ALREADY EXISTS: $EXPORT_DIR (rename or delete it first)" >&2; exit 1; }
# Work inside the project folder so all paths are relative to it.
cd "$PROJECT_DIR"

# Names that look like secrets; any file matching one of these is never copied (find -iname patterns).
SECRET_NAMES=( '.env' '.env.*' '*.pem' '*.key' '*.p12' '*.pfx' 'id_rsa*' 'id_ed25519*' '*secret*' '*password*' '*credential*' '*.token' '.netrc' )
# Build the find arguments that match those names (a list like: -iname A -o -iname B ...).
SECRET_ARGS=()
# Go through the secret names.
for n in "${SECRET_NAMES[@]}"; do
  # Add an "or" between the names, but not before the first.
  [ ${#SECRET_ARGS[@]} -eq 0 ] || SECRET_ARGS+=( -o )
  # Add one name test.
  SECRET_ARGS+=( -iname "$n" )
done # end of the loop

# Collect the secret-looking files outside git and build folders; they are listed at the end and never copied.
mapfile -t SECRETS < <(find . \( -path ./.git -o -path ./bin -o -path ./export2chat \) -prune -o -type f \( "${SECRET_ARGS[@]}" \) -print | sort)

# Collect the files to copy, one path per line (the allow-list): Go source and tests, module files, requirements, git ignore list, labels file, and the web folder.
mapfile -t WANTED < <( { \
  find . -maxdepth 1 -type f \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' -o -name '.gitignore' -o -name 'OllamaControlCenter.txt' -o -name 'README*' -o -name 'project-labels.json' \) -print; \
  find ./web -type f -print 2> /dev/null; \
  for num in $KEEP_SCRIPTS; do find ./scripts -maxdepth 1 -type f -name "${num}-*.sh" -print 2> /dev/null; done; \
} | sed 's|^\./||' | sort -u)

# Remove any secret-looking file from the wanted list (a file is copied only if its name is not in the secrets list).
COPY=()
# Go through the wanted files.
for f in "${WANTED[@]}"; do
  # Assume it is safe until a match is found.
  skip=0
  # Compare with every secret-looking file.
  for s in "${SECRETS[@]:-}"; do
    # A match means skip the file.
    [ "./$f" = "$s" ] && skip=1
  done # end of the secret comparison
  # Keep the file when it is safe.
  [ "$skip" -eq 1 ] || COPY+=( "$f" )
done # end of the loop

# Refuse to continue if nothing was found (probably the wrong folder).
[ ${#COPY[@]} -gt 0 ] || { echo "NO FILES FOUND in $PROJECT_DIR" >&2; exit 1; }
# Look inside the files to be copied for private-key blocks (a last safety net for secrets pasted into code).
if grep -l 'BEGIN [A-Z ]*PRIVATE KEY' "${COPY[@]}" 2> /dev/null; then
  # Say why the export stops.
  echo "STOPPED: a private key block was found in the file(s) above" >&2; exit 1
fi # end of the key scan

# Create the export folder.
mkdir -p "$EXPORT_DIR"
# Copy every wanted file with its sub-folders (--parents keeps the folder structure).
cp --parents "${COPY[@]}" "$EXPORT_DIR/"

# Make the combined text files in a sub-folder; each starts every file with a header line, so the original paths stay visible.
mkdir -p "$EXPORT_DIR/_upload"
# bundle OUTPUT FILES...: writes the files one after another, each under a "FILE:" header.
bundle() {
  # The first argument is the output file; the rest are input files.
  local out="$1"; shift
  # Start with an empty output file.
  : > "$EXPORT_DIR/_upload/$out"
  # Go through the input files.
  for f in "$@"; do
    # Write the header with the original path.
    printf '\n===== FILE: %s =====\n' "$f" >> "$EXPORT_DIR/_upload/$out"
    # Write the file content.
    cat "$f" >> "$EXPORT_DIR/_upload/$out"
  done # end of the loop
} # end of bundle
# Group 1: Go source (not tests).
bundle 01-go-source.txt $(printf '%s\n' "${COPY[@]}" | grep -E '^[^/]+\.go$' | grep -v '_test\.go$' || true)
# Group 2: Go tests.
bundle 02-go-tests.txt $(printf '%s\n' "${COPY[@]}" | grep -E '^[^/]+_test\.go$' || true)
# Group 3: the web folder (page templates, stylesheet, scripts).
bundle 03-web.txt $(printf '%s\n' "${COPY[@]}" | grep -E '^web/' || true)
# Group 4: requirements, module and ignore files, labels file.
bundle 04-docs-config.txt $(printf '%s\n' "${COPY[@]}" | grep -vE '\.go$|^web/|^scripts/' || true)
# Group 5: the kept scripts.
bundle 05-scripts.txt $(printf '%s\n' "${COPY[@]}" | grep -E '^scripts/' || true)

# Write the manifest: every copied file with its size, line count and checksum, so the copy can be verified.
{
  # A title.
  echo "MANIFEST of export2chat (made $(date '+%Y-%m-%d %H:%M'))"
  # The source folder.
  echo "Source: $PROJECT_DIR"
  # A blank line.
  echo
  # One line per copied file: checksum, lines, bytes, path.
  for f in "${COPY[@]}"; do printf '%s  %6s lines  %8s bytes  %s\n' "$(sha256sum "$f" | cut -c1-12)" "$(wc -l < "$f")" "$(wc -c < "$f")" "$f"; done
} > "$EXPORT_DIR/MANIFEST.txt"

# Show the result: the copied files (with sizes), the combined files, and the secret-looking files that were NOT copied.
echo "---- COPIED FILES (${#COPY[@]}) ----"
# Print the copied files with their sizes.
( cd "$EXPORT_DIR" && find . -path ./_upload -prune -o -type f ! -name MANIFEST.txt -printf '%8s bytes  %p\n' | sort -k3 )
# Print the combined files.
echo "---- COMBINED FILES FOR UPLOAD (in _upload) ----"
# List them with sizes.
( cd "$EXPORT_DIR/_upload" && find . -type f -printf '%8s bytes  %p\n' | sort -k3 )
# Print the total size and a rough token estimate (about 4 characters per token).
TOTAL=$(cat "$EXPORT_DIR"/_upload/*.txt | wc -c)
# Show it.
echo "Total of combined files: $TOTAL bytes, roughly $((TOTAL / 4)) tokens"
# Print the secret-looking files that were skipped.
echo "---- NOT COPIED (secret-looking names) ----"
# Say "none" or list them.
if [ ${#SECRETS[@]} -eq 0 ]; then echo "none found"; else printf '%s\n' "${SECRETS[@]}"; fi
# Say where everything is.
echo "Export folder: $EXPORT_DIR"
