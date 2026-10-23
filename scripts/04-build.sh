#!/usr/bin/env bash
# Step 2e: checks formatting, runs Go's checker, then builds the monitor into bin/ for this machine.
# Safe to run more than once: the build simply overwrites the previous executable.

# Stop at the first error, treat unset variables as errors, and fail if any command in a pipe fails
set -euo pipefail

# Project folder; can be overridden by exporting PROJECT_DIR before running
PROJECT_DIR="${PROJECT_DIR:-$HOME/OllamaControlCenter}"
# Name of the executable to produce; can be overridden by exporting OUT_NAME
OUT_NAME="${OUT_NAME:-OllamaControlCenter}"

# Work inside the project folder, where go.mod lives
cd "$PROJECT_DIR"

# ---------- Format check ----------
# Announce the step
echo "== Format check =="
# List files whose layout differs from Go's official style (no output means all files are fine)
UNFORMATTED="$(gofmt -l .)"
# Any file name in the list means a formatting problem
if [ -n "$UNFORMATTED" ]; then
  # Explain the problem on the error stream
  echo "NOT FORMATTED: run 'gofmt -w' on these files:" >&2
  # Show which files need fixing
  echo "$UNFORMATTED" >&2
  # Stop before building
  exit 1
# End of the format check
fi
# Report success
echo "OK: all files follow Go's formatting style"

# ---------- Vet check ----------
# Announce the step
echo "== Vet check =="
# Compile everything and report suspicious code; any problem stops the script because of set -e
go vet ./...
# Report success
echo "OK: go vet found no problems"

# ---------- Build ----------
# Announce the step
echo "== Build =="
# Create the output folder if it does not exist (-p: no error if present)
mkdir -p bin
# Build a pure-Go executable (CGO_ENABLED=0) without local folder names inside it (-trimpath)
CGO_ENABLED=0 go build -trimpath -o "bin/$OUT_NAME" .
# Show the file's size, permissions and date (read-only)
ls -l "bin/$OUT_NAME"
# Show what kind of file it is: operating system, CPU type, and whether it is self-contained (read-only)
file "bin/$OUT_NAME"
# Show what git sees as new; bin/ should NOT appear because .gitignore excludes it (read-only)
git status --short
# Announce that the script finished
echo "== Done =="
