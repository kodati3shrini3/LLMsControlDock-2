#!/usr/bin/env bash
# Script 07: Step 3a, adds the Ollama address setting (option, environment variable, default) and tests it.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Spare port for the test runs, so a real copy on 8765 is never disturbed.
TEST_PORT="${TEST_PORT:-18766}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write config.go; the quoted EOF_CONFIG marker saves every character exactly as typed.
cat > config.go << 'EOF_CONFIG'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds formatted error messages.
	"fmt"
	// net/url parses and checks web addresses (URL, Uniform Resource Locator).
	"net/url"
	// strings trims spaces and compares text.
	"strings"
)

// defaultOllamaURL is used when neither the option nor the environment variable is given: this machine only (requirement S1).
const defaultOllamaURL = "http://127.0.0.1:11434"

// envOllamaURL is the environment variable that can supply the address (OCC = OllamaControlCenter).
const envOllamaURL = "OCC_OLLAMA_URL"

// These three texts name the layer that supplied the address, so the program can print where it came from.
const (
	// sourceFlag means the address came from the -ollama-url command-line option.
	sourceFlag = "command-line option"
	// sourceEnv means the address came from the OCC_OLLAMA_URL environment variable.
	sourceEnv = "environment variable"
	// sourceDefault means nobody set an address, so the built-in default is used.
	sourceDefault = "default"
) // end of the source names

// ollamaAddress holds the chosen address and the layer that supplied it.
type ollamaAddress struct {
	// URL is the parsed, validated address.
	URL *url.URL
	// Source says which layer supplied it (one of the source names above).
	Source string
} // end of ollamaAddress

// resolve picks the address by precedence: option, then environment variable, then default; an empty text counts as "not set".
func resolve(flagValue, envValue string) (ollamaAddress, error) {
	// Start from the default layer.
	raw := defaultOllamaURL
	// Remember that the default supplied it, until a stronger layer overrides.
	source := sourceDefault
	// If the environment variable has real content, it beats the default.
	if strings.TrimSpace(envValue) != "" {
		// Use the environment variable's text.
		raw = strings.TrimSpace(envValue)
		// Record the layer.
		source = sourceEnv
	} // end of the environment check
	// If the command-line option has real content, it beats everything else.
	if strings.TrimSpace(flagValue) != "" {
		// Use the option's text.
		raw = strings.TrimSpace(flagValue)
		// Record the layer.
		source = sourceFlag
	} // end of the option check
	// Check the chosen text and turn it into a parsed address.
	parsed, err := parseOllamaURL(raw)
	// If the text is not a usable address, report which layer supplied the bad value.
	if err != nil {
		// The message never repeats the bad text, because it might contain a password.
		return ollamaAddress{}, fmt.Errorf("the Ollama address from the %s is not usable: %w", source, err)
	} // end of the error check
	// Everything is fine: return the address and where it came from.
	return ollamaAddress{URL: parsed, Source: source}, nil
} // end of resolve

// parseOllamaURL checks that text is an http or https address with a host, and returns it parsed.
func parseOllamaURL(raw string) (*url.URL, error) {
	// Parse the text; the error from url.Parse is dropped on purpose, because it would echo the text (and any password).
	parsed, err := url.Parse(raw)
	// If parsing failed outright, say so without echoing the text.
	if err != nil {
		// Return a fixed, safe message.
		return nil, fmt.Errorf("it is not a valid web address; expected a form like http://host:11434")
	} // end of the parse check
	// Only http and https are supported (HTTPS = HTTP Secure); "localhost:11434" parses with scheme "localhost" and fails here.
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		// Explain what is expected.
		return nil, fmt.Errorf("it must start with http:// or https://, for example http://127.0.0.1:11434")
	} // end of the scheme check
	// A host name or IP (Internet Protocol) address is required.
	if parsed.Host == "" {
		// Explain what is missing.
		return nil, fmt.Errorf("it has no host name, for example http://127.0.0.1:11434")
	} // end of the host check
	// A trailing slash is harmless but would make later joins messy, so remove a lone "/".
	if parsed.Path == "/" {
		// Clear the path.
		parsed.Path = ""
	} // end of the path tidy
	// Return the validated address.
	return parsed, nil
} // end of parseOllamaURL
EOF_CONFIG

# Write main.go; every line here follows the comment rule, including closing braces.
cat > main.go << 'EOF_MAIN'
// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text, here into the web reply.
	"fmt"
	// log prints timestamped messages to the terminal.
	"log"
	// net/http is Go's built-in web server (standard library only, requirement T1).
	"net/http"
	// os reads environment variables.
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

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
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
# Ask Go to look for suspicious constructs; any finding stops the script.
go vet ./...
# Make sure the output folder exists.
mkdir -p bin
# Build one static executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .

# Counters for passed and failed checks.
pass=0; fail=0

# check LABEL ENV_VALUE EXPECTED_TEXT [options...]: runs the program briefly and looks for EXPECTED_TEXT in its output.
check() {
  # Name the three fixed arguments.
  local label="$1" envval="$2" expected="$3"
  # Drop them so only the program's options remain.
  shift 3
  # Run for at most 2 seconds; "|| true" because timeout (code 124) or a deliberate failure exit is expected.
  out="$(OCC_OLLAMA_URL="$envval" timeout 2 ./bin/OllamaControlCenter -listen "127.0.0.1:${TEST_PORT}" "$@" 2>&1 || true)"
  # Look for the expected text as a fixed string, not a pattern.
  if printf '%s' "$out" | grep -qF -- "$expected"; then
    # Report success and count it.
    echo "PASS  $label"; pass=$((pass+1))
  else
    # Report failure, show the output, and count it.
    echo "FAIL  $label -> got: $out"; fail=$((fail+1))
  fi # end of the match check
} # end of check

# Case 1: nothing set, so the default applies.
check "default" "" "http://127.0.0.1:11434 (from default)"
# Case 2: only the environment variable is set.
check "environment variable" "http://10.0.0.5:11434" "http://10.0.0.5:11434 (from environment variable)"
# Case 3: both set, so the option must win.
check "option beats environment variable" "http://10.0.0.5:11434" "http://10.0.0.6:11434 (from command-line option)" -ollama-url http://10.0.0.6:11434
# Case 4: an address without http:// is rejected with a clear message.
check "missing scheme rejected" "" "must start with http:// or https://" -ollama-url localhost:11434
# Case 5: a password in the address is hidden in the printed line.
check "password redacted" "" "xxxxx@" -ollama-url https://me:secret@host.example:11434
# Case 6: the real password text must never appear anywhere in the output.
out="$(timeout 2 ./bin/OllamaControlCenter -listen "127.0.0.1:${TEST_PORT}" -ollama-url https://me:secret@host.example:11434 2>&1 || true)"
# Look for the secret as a fixed string; finding it is a failure.
if printf '%s' "$out" | grep -qF "secret"; then
  # Report failure.
  echo "FAIL  password leaked"; fail=$((fail+1))
else
  # Report success.
  echo "PASS  password not leaked"; pass=$((pass+1))
fi # end of the leak check

# Case 7: the option appears in the help text.
if ./bin/OllamaControlCenter -h 2>&1 | grep -qF -- "-ollama-url"; then
  # Report success.
  echo "PASS  -h lists -ollama-url"; pass=$((pass+1))
else
  # Report failure.
  echo "FAIL  -h lacks -ollama-url"; fail=$((fail+1))
fi # end of the help check

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
