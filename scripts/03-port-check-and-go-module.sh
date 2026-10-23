#!/usr/bin/env bash
# Step 2b: verifies the monitor's port is unclaimed on this machine, then creates the Go module file (go.mod).
# Safe to run more than once: go.mod is only created if it does not exist yet.

# Stop at the first error, treat unset variables as errors, and fail if any command in a pipe fails
set -euo pipefail

# Port the monitor page will use; can be overridden by exporting PORT before running
PORT="${PORT:-8765}"
# Project folder; can be overridden by exporting PROJECT_DIR before running
PROJECT_DIR="${PROJECT_DIR:-$HOME/OllamaControlCenter}"
# Folder holding docker-compose files to search; can be overridden by exporting COMPOSE_DIR
COMPOSE_DIR="${COMPOSE_DIR:-$HOME/AI-Stack}"
# Go module path: the project's unique name, conventionally the repository address
MODULE_PATH="${MODULE_PATH:-github.com/kodatishrini-beep/OllamaControlCenter}"

# ---------- Check 1: is anything on this machine listening on the port right now? ----------
# Announce the check
echo "== Check 1: host listeners on port $PORT =="
# Ask the kernel for listening TCP sockets on that port (-H hides the header, so any output means in use)
if [ -n "$(ss -ltnH "sport = :$PORT")" ]; then
  # Report the conflict on the error stream
  echo "IN USE: something is listening on port $PORT" >&2
  # Stop, because the monitor cannot start on a busy port
  exit 1
# End of the host listener check
fi
# Report success
echo "OK: nothing is listening on port $PORT"

# ---------- Check 2: does any Docker container, running or stopped, claim the port? ----------
# Announce the check
echo "== Check 2: Docker containers (running and stopped) =="
# Only check Docker if the command exists and the daemon answers (other machines may have no Docker)
if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
  # Collect IDs of all containers that publish the port on the host
  PUBLISHED="$(docker ps -aq --filter "publish=$PORT")"
  # Collect IDs of all containers that declare the port as exposed
  EXPOSED="$(docker ps -aq --filter "expose=$PORT")"
  # Any ID in either list means a container claims the port
  if [ -n "$PUBLISHED$EXPOSED" ]; then
    # Report the conflict on the error stream
    echo "IN USE: a Docker container claims port $PORT" >&2
    # Stop, because starting that container later would clash with the monitor
    exit 1
  # End of the container conflict check
  fi
  # Report success
  echo "OK: no container publishes or exposes port $PORT"
else
  # Tell the user the check was skipped, not failed
  echo "SKIP: Docker is not available on this machine"
# End of the Docker availability check
fi

# ---------- Check 3: do compose or environment files mention the port? ----------
# Announce the check
echo "== Check 3: compose and env files in $COMPOSE_DIR =="
# Only search if the folder exists (other machines may not have it)
if [ -d "$COMPOSE_DIR" ]; then
  # Search yml, yaml and .env files for the whole number (-w avoids matches inside longer numbers)
  if grep -rnw "$PORT" "$COMPOSE_DIR" --include='*.yml' --include='*.yaml' --include='.env*' 2> /dev/null; then
    # Report the conflict; the matching lines were printed above
    echo "IN USE: files above mention port $PORT, review them" >&2
    # Stop, because a stack may claim this port when it starts
    exit 1
  # End of the file search
  fi
  # Report success
  echo "OK: no compose or env file under $COMPOSE_DIR mentions port $PORT"
else
  # Tell the user the check was skipped, not failed
  echo "SKIP: folder $COMPOSE_DIR not found"
# End of the folder check
fi

# ---------- Go module ----------
# Announce the step
echo "== Go module =="
# Create the project folder if it does not exist yet
mkdir -p "$PROJECT_DIR"
# Work inside the project folder from here on
cd "$PROJECT_DIR"
# Only create go.mod if it does not exist, so re-running never overwrites it
if [ -f go.mod ]; then
  # Tell the user nothing needed doing
  echo "SKIP: go.mod already exists"
else
  # Create the module file with the project's unique name
  go mod init "$MODULE_PATH"
  # Confirm the file was created
  echo "CREATED: go.mod"
# End of the go.mod check
fi
# Show the module file so you can read what was written (read-only)
cat go.mod
# Show what git sees as new or changed (read-only)
git status --short
# Announce that the script finished
echo "== Done =="
