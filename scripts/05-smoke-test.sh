#!/usr/bin/env bash
# Step 2h: automatic smoke test. Builds the monitor, starts it on a spare port, checks its replies, stops it, and reports PASS or FAIL.
# Exit code 0 means every check passed; exit code 1 means a problem (useful later for automation).

# Stop at the first unhandled error, treat unset variables as errors, and fail if any command in a pipe fails
set -euo pipefail

# Project folder; can be overridden by exporting PROJECT_DIR before running
PROJECT_DIR="${PROJECT_DIR:-$HOME/OllamaControlCenter}"
# Spare port for the test, so it never collides with a real monitor on 8765; can be overridden by exporting TEST_PORT
TEST_PORT="${TEST_PORT:-18765}"
# Address the test server listens on: this machine only, like the real default
TEST_ADDR="127.0.0.1:$TEST_PORT"
# Web address that curl uses to reach the test server
BASE_URL="http://$TEST_ADDR"
# Path of the executable that the build script produces
BIN="$PROJECT_DIR/bin/OllamaControlCenter"
# Temporary file that captures the server's messages during the test
LOG_FILE="$(mktemp)"
# Process ID of the background server; empty means no server is running
SERVER_PID=""
# Counter of failed checks
FAILURES=0

# stop_server: stops the background server if one is running
stop_server() {
  # Only act if we have a process ID
  if [ -n "$SERVER_PID" ]; then
    # Ask the server to stop; ignore errors if it already ended
    kill "$SERVER_PID" 2> /dev/null || true
    # Wait until it has really ended; ignore its exit status, which is non-zero after a kill
    wait "$SERVER_PID" 2> /dev/null || true
    # Forget the process ID so we never stop it twice
    SERVER_PID=""
  # End of the process ID check
  fi
# End of stop_server
}

# cleanup: runs automatically when the script ends for ANY reason; stops the server and deletes the log file
cleanup() {
  # Make sure the server is stopped
  stop_server
  # Delete the temporary log file (-f: no error if it is already gone)
  rm -f "$LOG_FILE"
# End of cleanup
}
# Register cleanup to run when the script exits, whether it passed, failed or was interrupted
trap cleanup EXIT

# record_result: prints PASS or FAIL for one check and counts failures; $1 is "ok" or "bad", $2 is the description
record_result() {
  # A good result is printed as PASS
  if [ "$1" = "ok" ]; then
    # Print the passing check
    echo "PASS: $2"
  else
    # Print the failing check
    echo "FAIL: $2"
    # Add one to the failure counter
    FAILURES=$((FAILURES + 1))
  # End of the result check
  fi
# End of record_result
}

# check_status: asks curl for a URL and compares the HTTP status code; $1 is the description, $2 the expected code, the rest are curl arguments
check_status() {
  # Name the first two arguments, then drop them so only curl arguments remain
  local desc="$1" expected="$2"
  # Remove the first two arguments from the list
  shift 2
  # Ask curl for the status code only (-s quiet, -o discard the body, -w print the code); on connection failure it prints 000
  local actual
  # Run curl; the || true keeps the script going if curl itself reports an error
  actual="$(curl -s -o /dev/null -w '%{http_code}' "$@" || true)"
  # Compare what we got with what we expected
  if [ "$actual" = "$expected" ]; then
    # Record a pass
    record_result ok "$desc (HTTP $actual)"
  else
    # Record a failure and show both codes
    record_result bad "$desc (expected $expected, got $actual)"
  # End of the comparison
  fi
# End of check_status
}

# ---------- Setup ----------
# Announce the section
echo "== Setup =="
# Work inside the project folder
cd "$PROJECT_DIR"
# Refuse to run if something already listens on the test port (-H hides the header, so any output means in use)
if [ -n "$(ss -ltnH "sport = :$TEST_PORT")" ]; then
  # Explain the problem on the error stream
  echo "IN USE: something is already listening on port $TEST_PORT; set TEST_PORT to another port" >&2
  # Stop before starting anything
  exit 1
# End of the port check
fi
# Report success
echo "OK: test port $TEST_PORT is free"
# Build the monitor; normal output is hidden, errors still show
"$PROJECT_DIR/scripts/04-build.sh" > /dev/null
# Report success
echo "OK: build finished"

# ---------- Start ----------
# Announce the section
echo "== Start =="
# Start the monitor in the background (&) on the spare port, sending its messages to the log file
"$BIN" -listen "$TEST_ADDR" > "$LOG_FILE" 2>&1 &
# Remember the process ID of the background server ($! is the last background process)
SERVER_PID=$!
# Flag that becomes 1 once the server answers
READY=0
# Poll up to 50 times, 0.1 seconds apart, which gives the server about 5 seconds to start
for _ in $(seq 1 50); do
  # Give up waiting if the server process has already died
  if ! kill -0 "$SERVER_PID" 2> /dev/null; then
    # Leave the loop
    break
  # End of the process check
  fi
  # Ask for the page; any answer at all means the server is up
  if curl -s -o /dev/null "$BASE_URL/"; then
    # Remember that the server is ready
    READY=1
    # Leave the loop
    break
  # End of the answer check
  fi
  # Wait a moment before asking again
  sleep 0.1
# End of the polling loop
done
# If the server never answered, show why and stop
if [ "$READY" -ne 1 ]; then
  # Explain the problem on the error stream
  echo "FAIL: server did not answer within 5 seconds; its messages were:" >&2
  # Show what the server printed
  cat "$LOG_FILE" >&2
  # Stop with an error code
  exit 1
# End of the readiness check
fi
# Report success
echo "OK: server is answering on $TEST_ADDR"

# ---------- Checks ----------
# Announce the section
echo "== Checks =="
# A normal visit must return 200
check_status "GET / returns 200" 200 "$BASE_URL/"
# Fetch the body of the normal visit; the shell drops the trailing newline for us
BODY="$(curl -s "$BASE_URL/")"
# The body must be exactly our message
if [ "$BODY" = "OllamaControlCenter is running" ]; then
  # Record a pass
  record_result ok "GET / body is the expected message"
else
  # Record a failure and show what came back
  record_result bad "GET / body is the expected message (got: $BODY)"
# End of the body check
fi
# An unknown path must return 404
check_status "GET /nothing-here returns 404" 404 "$BASE_URL/nothing-here"
# A POST to a GET-only route must return 405
check_status "POST / returns 405" 405 -X POST "$BASE_URL/"
# Read the local address the server is bound to (fourth column of the ss output)
LISTEN_ADDR="$(ss -ltnH "sport = :$TEST_PORT" | awk '{print $4}')"
# It must be exactly 127.0.0.1:PORT, meaning this machine only (requirement S1)
if [ "$LISTEN_ADDR" = "$TEST_ADDR" ]; then
  # Record a pass
  record_result ok "server listens on $TEST_ADDR only"
else
  # Record a failure and show the address that was found
  record_result bad "server listens on $TEST_ADDR only (found: $LISTEN_ADDR)"
# End of the bind check
fi

# ---------- Stop ----------
# Announce the section
echo "== Stop =="
# Stop the server now, so we can prove nothing keeps running (requirement F6)
stop_server
# The port must be empty again
if [ -z "$(ss -ltnH "sport = :$TEST_PORT")" ]; then
  # Record a pass
  record_result ok "port $TEST_PORT is closed after stopping"
else
  # Record a failure
  record_result bad "port $TEST_PORT is still open after stopping"
# End of the closed-port check
fi

# ---------- Result ----------
# Report the final verdict and set the exit code
if [ "$FAILURES" -eq 0 ]; then
  # Everything passed
  echo "== PASS =="
else
  # At least one check failed
  echo "== FAIL ($FAILURES failed) ==" >&2
  # Stop with an error code
  exit 1
# End of the verdict
fi
