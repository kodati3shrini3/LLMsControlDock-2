#!/usr/bin/env bash
# Script 11: Step 3d, adds the -check option to main.go, then proves it works against real and missing servers.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the "online" case; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write main.go; the quoted EOF_MAIN marker saves every character exactly as typed.
cat > main.go << 'EOF_MAIN'
// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// context supplies the (empty) context the check function needs.
	"context"
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text, here into the web reply and the check line.
	"fmt"
	// log prints timestamped messages to the terminal.
	"log"
	// net/http is Go's built-in web server (standard library only, requirement T1).
	"net/http"
	// os reads environment variables and ends the program with an exit code.
	"os"
	// time provides durations such as the request-header timeout.
	"time"
) // end of imports

// defaultListen is where the page is served unless the user chooses otherwise: this machine only (requirement S1).
const defaultListen = "127.0.0.1:8765"

// helloHandler answers one kind of request; w is where we write the reply and r describes the incoming request.
func helloHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser the reply is plain text, not a web page.
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	// Write the one-line reply; Fprintln adds a newline at the end.
	fmt.Fprintln(w, "OllamaControlCenter is running")
} // end of helloHandler

// formatCheck turns one check result into the single status line the -check option prints.
func formatCheck(res checkResult) string {
	// A successful check says ONLINE, the version and the time taken.
	if res.Online {
		// Build the online line; %s is text and %d is a whole number.
		return fmt.Sprintf("ONLINE  version %s  %d ms", res.Version, res.Elapsed.Milliseconds())
	} // end of the online case
	// A failed check says OFFLINE, the reason and the time taken.
	return fmt.Sprintf("OFFLINE  %s  %d ms", res.Reason, res.Elapsed.Milliseconds())
} // end of formatCheck

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
	// Define a -check switch: false unless given on the command line.
	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
	// Read the command line now, so the variables above receive their values.
	flag.Parse()

	// Choose the Ollama address by precedence: option, then environment variable, then default.
	addr, err := resolve(*ollamaFlag, os.Getenv(envOllamaURL))
	// If the address is unusable, stop with a clear message and a failure exit code.
	if err != nil {
		// log.Fatalf prints the message and exits with code 1.
		log.Fatalf("%v", err)
	} // end of the address check
	// Print the address (any password shown as xxxxx) and which layer supplied it.
	log.Printf("Ollama address: %s (from %s)", addr.URL.Redacted(), addr.Source)

	// In -check mode, knock once, print the result, and leave without starting the web page.
	if *checkFlag {
		// Ask Ollama once, waiting at most the default timeout.
		res := checkOllama(context.Background(), addr.URL, defaultCheckTimeout)
		// Print the single status line.
		fmt.Println(formatCheck(res))
		// Exit with 0 when online, so scripts can tell it worked.
		if res.Online {
			// Leave with the success code.
			os.Exit(0)
		} // end of the online exit
		// Leave with the failure code.
		os.Exit(1)
	} // end of the check mode

	// Create a router, which decides which function answers which URL.
	mux := http.NewServeMux()
	// Route: a GET request for exactly "/" is answered by helloHandler; any other path gets a 404.
	mux.HandleFunc("GET /{$}", helloHandler)

	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the router,
	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second}

	// Tell the person which address we are about to serve on.
	log.Printf("OllamaControlCenter listening on http://%s (press Ctrl+C to stop)", *listen)
	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
	err = server.ListenAndServe()
	// If we get here the server has stopped; log.Fatal prints the reason and exits with an error code.
	log.Fatal(err)
} // end of main
EOF_MAIN

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build worked.
echo "PASS  build"

# Counters for passed and failed checks.
pass=1; fail=0

# run_case LABEL EXPECTED_EXIT_CODE EXPECTED_TEXT [options...]: runs the program and checks its exit code and output.
run_case() {
  # Name the three fixed arguments.
  local label="$1" want_rc="$2" want_text="$3"
  # Drop them so only the program's options remain.
  shift 3
  # Run it, capture all output, and record the exit code (the || keeps set -e from stopping the script).
  rc=0; out="$(OCC_OLLAMA_URL="" ./bin/OllamaControlCenter "$@" 2>&1)" || rc=$?
  # Both the exit code and the text must match.
  if [ "$rc" -eq "$want_rc" ] && printf '%s' "$out" | grep -qF -- "$want_text"; then
    # Report success and count it.
    echo "PASS  $label (exit $rc)"; pass=$((pass+1))
  else
    # Report failure, show what happened, and count it.
    echo "FAIL  $label -> exit $rc, output: $out"; fail=$((fail+1))
  fi # end of the match check
} # end of run_case

# Case 1: the real (or chosen) Ollama is online, so the exit code is 0.
run_case "online" 0 "ONLINE  version" -check -ollama-url "$OLLAMA_TEST_URL"
# Case 2: port 1 has nothing listening, so the check is refused and the exit code is 1.
run_case "offline (refused)" 1 "OFFLINE  connection refused" -check -ollama-url http://127.0.0.1:1
# Case 3: an address without http:// is rejected before any check, with exit code 1.
run_case "bad address" 1 "must start with http:// or https://" -check -ollama-url localhost:11434
# Case 4: the new option appears in the help text (-h exits with code 0 in Go's flag package).
run_case "-h lists -check" 0 "-check" -h

# Run the unit tests from Step 3c to prove nothing broke.
go test -count=1 ./... && { echo "PASS  unit tests"; pass=$((pass+1)); } || { echo "FAIL  unit tests"; fail=$((fail+1)); }
# Run the smoke test from script 05 if it exists, to prove the web page still works.
if [ -x scripts/05-smoke-test.sh ]; then
  # Run it; its own output is hidden, only the verdict is shown.
  if ./scripts/05-smoke-test.sh > /dev/null 2>&1; then
    # Report success.
    echo "PASS  smoke test (script 05)"; pass=$((pass+1))
  else
    # Report failure.
    echo "FAIL  smoke test (script 05)"; fail=$((fail+1))
  fi # end of the smoke-test verdict
else
  # The script is missing; say so instead of silently skipping.
  echo "SKIP  smoke test: scripts/05-smoke-test.sh not found"
fi # end of the smoke-test check

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
