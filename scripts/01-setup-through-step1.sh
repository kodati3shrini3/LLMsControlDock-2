#!/usr/bin/env bash
# Reproduces Step 0 (environment check) and Step 1 (git identity, repository, .gitignore).
# Safe to run more than once: it only creates things that do not exist yet.

# Stop at the first error, treat unset variables as errors, and fail if any command in a pipe fails
set -euo pipefail

# Project folder; can be overridden by exporting PROJECT_DIR before running
PROJECT_DIR="${PROJECT_DIR:-$HOME/OllamaControlCenter}"
# Name stamped on commits; can be overridden by exporting GIT_NAME before running
GIT_NAME="${GIT_NAME:-Kodati}"

# ---------- Step 0: environment check (read-only) ----------
# Announce the start of Step 0
echo "== Step 0: environment check =="
# Loop over every tool this project needs
for tool in go git gh docker; do
  # Check that the tool is on the PATH, hiding the normal output
  if command -v "$tool" > /dev/null 2>&1; then
    # Report that the tool was found
    echo "OK: $tool found"
  else
    # Report the missing tool on the error stream
    echo "MISSING: $tool (install it first, see https://go.dev/dl/ and https://cli.github.com/)" >&2
    # Stop, because later steps cannot work without it
    exit 1
  fi
# End of the loop
done
# Show the Go version (expect linux/arm64 on the DGX Spark)
go version
# Show the git version
git --version
# Show the GitHub CLI version
gh --version
# Show the Docker version
docker --version
# List running containers to find the Ollama container and its published port
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
# Show the CPU architecture (aarch64 on the Spark)
uname -m

# ---------- Step 1: git and GitHub ----------
# Announce the start of Step 1
echo "== Step 1: git and GitHub =="
# Stop with a clear message if gh is not logged in (output hidden, only the exit code matters)
gh auth status > /dev/null 2>&1 || { echo "gh is not logged in: run 'gh auth login' first" >&2; exit 1; }
# Ask GitHub for the numeric account ID (needed to build the no-reply email)
GH_ID="$(gh api user --jq '.id')"
# Ask GitHub for the login name of the logged-in account
GH_LOGIN="$(gh api user --jq '.login')"
# Show which account is being used so you can double-check it
echo "GitHub account: $GH_LOGIN (id $GH_ID)"
# Set the commit name for every repository of this Linux user
git config --global user.name "$GIT_NAME"
# Set the GitHub no-reply email so the real address stays out of commit history
git config --global user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"
# New repositories start on a branch called main, matching GitHub
git config --global init.defaultBranch main
# Read the settings back to confirm they were saved
git config --global --get-regexp '^(user\.|init\.)'

# Create the project folder if it does not exist yet (-p: no error if present)
mkdir -p "$PROJECT_DIR"
# Work inside the project folder from here on
cd "$PROJECT_DIR"

# Only initialise git if this folder is not a repository yet
if [ -d .git ]; then
  # Tell the user nothing needed doing
  echo "SKIP: git repository already exists"
else
  # Turn the folder into a git repository
  git init
# End of the repository check
fi

# Only create .gitignore if it does not exist, so later edits are never overwritten
if [ -f .gitignore ]; then
  # Tell the user nothing needed doing
  echo "SKIP: .gitignore already exists"
else
  # Write the approved .gitignore; everything up to the closing EOF line is saved exactly as typed
  cat > .gitignore << 'EOF'
# Build output folder: compiled programs for each OS/CPU live here and can be rebuilt from source
dist/
bin/

# Compiled binaries on any OS (Linux has no extension, Windows uses .exe)
*.exe
*.test
*.out

# Go test coverage reports: generated files, not source code
coverage.txt
*.coverprofile

# Saved monitoring history (F10): must never reach GitHub, supports requirement S4
history/
*.history.json

# Local user settings written by the app: personal to each machine
settings.json

# Environment files that might hold secrets such as tokens
.env

# Editor and OS clutter
.vscode/
.idea/
.DS_Store
EOF
  # Confirm the file was created
  echo "CREATED: .gitignore"
# End of the .gitignore check
fi

# Show the final repository state (read-only)
git status --short
# Announce that the script finished
echo "== Done =="
