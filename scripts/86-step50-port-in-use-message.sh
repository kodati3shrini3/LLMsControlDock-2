#!/usr/bin/env bash
# Script 86 (clear message when the port is busy, version 0.30.2): when the monitor cannot take its port because it is already used, it now says so in plain words: either that OllamaControlCenter is already running (with its address and how to stop it), or that another program uses the port, and it suggests another port with -listen. Before, it printed a raw network error after already announcing it was listening. The port is now taken before that announcement. Added: portbusy.go, portbusy_test.go; changed: main.go, about.go.
# Run it from the project folder, on the fix branch (never on main): cd ~/OllamaControlCenter && bash scripts/86-step50-port-in-use-message.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files BEFORE the change (as on main after PR 37), and of all four files AFTER it.
declare -A BEFORE AFTER
BEFORE["main.go"]="6d8e3a2c376ad4b724f4a5a0f098ec1d88d87423e0ff1665152e6ba4d9d9059f"
BEFORE["about.go"]="46a7258b156e7a891f0867ab288faaf35a9d4f7365f695d278a669fc1d035599"
AFTER["main.go"]="4f72e27c12ae1b85d92de6be899d43aa546277b278b450f3c0522faaa22c6a03"
AFTER["about.go"]="48a7029ec4bf2b0d59e7b41d233a4368468d694bb3ba68d3c4a5592a8a51a49a"
AFTER["portbusy.go"]="4887cfc85ffaac892802bef4ed9684536276a1eabf3e0b026ee66f9e23692f8d"
AFTER["portbusy_test.go"]="fa9fc24578b5a31dcc37af5d7b466038bb985b714de90fffb337259aefc12e12"

PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be OllamaControlCenter: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the OllamaControlCenter folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on the fix branch (fix/port-in-use-message)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Scripts 84 to 85 must be in this branch: their new files exist.
[ -e environment.go ] || fail "environment.go is missing: run script 84 first"
# Report it.
pass "script 84 was applied (environment.go exists)"

# Refuse to run twice: the new wording is already there when the change was applied before.
[ -e capfallback.go ] || fail "capfallback.go is missing: script 85 (merged as PR 37) must be in this branch"
pass "script 85 is in this branch (capfallback.go exists)"

if [ -e portbusy.go ]; then fail "portbusy.go exists: this script was already applied"; fi
pass "the port message is not there yet (script not applied before)"

for F in "${!BEFORE[@]}"; do
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
done
pass "the two files to change are the expected versions before the change"

PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_86_END'
diff --git a/about.go b/about.go
index 9f814d7..bcc8d3b 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.30.1"
+const appVersion = "0.30.2"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/main.go b/main.go
index 9219a8e..f2a6d4f 100644
--- a/main.go
+++ b/main.go
@@ -12,6 +12,8 @@ import ( // import lists the standard-library packages this file uses.
 	"fmt"
 	// log prints timestamped messages to the terminal.
 	"log"
+	// net takes the port before the server starts, so a busy port gets a clear message.
+	"net"
 	// net/http is Go's built-in web server (standard library only, requirement T1).
 	"net/http"
 	// os reads environment variables and ends the program with an exit code.
@@ -218,6 +220,15 @@ func main() {
 	// The server, with the monitor built into the web interface.
 	server := &http.Server{Addr: listenAddr, Handler: hostGuard(newWebHandlerWith(addr, defaultCheckTimeout, mon), listenAddr), ReadHeaderTimeout: 5 * time.Second}
 
+	// Take the port first, so a busy port gets a clear message and not a half-started program.
+	ln, listenErr := net.Listen("tcp", listenAddr)
+	// The port could not be taken.
+	if listenErr != nil {
+		// Say why in plain words, and what to do.
+		log.Print(listenFailureMessage(listenAddr, listenErr))
+		// Leave with the error code.
+		os.Exit(1)
+	} // end of the listen check
 	// Tell the person which address we are about to serve on.
 	log.Printf("OllamaControlCenter listening on http://%s (from %s; press Ctrl+C to stop)", listenAddr, listenSource)
 	// Closed when the shutdown that the Stop button started has finished.
@@ -246,8 +257,8 @@ func main() {
 	}) // end of stopRequest
 	// From here on Ctrl+C and a termination request (SIGTERM) stop the program as cleanly as the Stop button does; the first one asks politely, a second one quits at once.
 	startStopSignals()
-	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
-	err = server.ListenAndServe()
+	// Start serving on the port we hold; this call blocks (waits) until the server stops or fails.
+	err = server.Serve(ln)
 	// A shutdown asked for by the Stop button is a normal end, not an error.
 	if errors.Is(err, http.ErrServerClosed) {
 		// Wait until the shutdown has finished.
diff --git a/portbusy.go b/portbusy.go
new file mode 100644
index 0000000..176593c
--- /dev/null
+++ b/portbusy.go
@@ -0,0 +1,107 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// errors recognises the "port already in use" error inside a longer error.
+	"errors"
+	// fmt builds the message texts.
+	"fmt"
+	// io reads a limited part of an answer.
+	"io"
+	// net splits the listen address and holds the port.
+	"net"
+	// net/http asks the program on the port who it is.
+	"net/http"
+	// strconv turns the port into a number and back.
+	"strconv"
+	// strings looks for the program's name in an answer.
+	"strings"
+	// syscall holds the operating system's error numbers.
+	"syscall"
+	// time limits the question.
+	"time"
+) // end of imports
+
+// isAddrInUse says whether an error means "another program already uses this port". Linux and macOS give EADDRINUSE; Windows gives its own number 10048 (WSAEADDRINUSE), which Go does not map to EADDRINUSE.
+func isAddrInUse(err error) bool {
+	// Either number counts; the Windows number means nothing on the other systems, so it never matches there by mistake.
+	return errors.Is(err, syscall.EADDRINUSE) || errors.Is(err, syscall.Errno(10048))
+} // end of isAddrInUse
+
+// probeIsOurs asks whatever answers at the address whether it is an OllamaControlCenter monitor: its read-only About page always answers and names the program. A test replaces it.
+var probeIsOurs = func(url string) bool {
+	// A short time limit: this runs while the program is leaving anyway.
+	c := &http.Client{Timeout: 2 * time.Second}
+	// Ask for the About page.
+	res, err := c.Get(url + "about")
+	// No answer, so it is not a web page of ours.
+	if err != nil {
+		// Not ours, as far as we can tell.
+		return false
+	} // end of the error check
+	// Close the body at the end.
+	defer res.Body.Close()
+	// Only a normal page can be ours.
+	if res.StatusCode != http.StatusOK {
+		// Not ours.
+		return false
+	} // end of the status check
+	// Read the first 64 KB; the name is in the page title.
+	body, _ := io.ReadAll(io.LimitReader(res.Body, 64*1024))
+	// Ours when the page names the program.
+	return strings.Contains(string(body), "OllamaControlCenter")
+} // end of probeIsOurs
+
+// nextPortAddress suggests the same address with the next port number, or the empty text when the address cannot be read.
+func nextPortAddress(listen string) string {
+	// Split host and port.
+	host, port, err := net.SplitHostPort(listen)
+	// An unreadable address.
+	if err != nil {
+		// No suggestion.
+		return ""
+	} // end of the split check
+	// The port as a number.
+	n, err := strconv.Atoi(port)
+	// Not a number, or the last port.
+	if err != nil || n < 1 || n >= 65535 {
+		// No suggestion.
+		return ""
+	} // end of the number check
+	// A listen address of ":8765" (all addresses) would give ":8766"; keep the same host part.
+	return net.JoinHostPort(host, strconv.Itoa(n+1))
+} // end of nextPortAddress
+
+// listenFailureMessage explains in plain words why the program could not take its port and what to do; it never contains a password or anything private, only the listen address.
+func listenFailureMessage(listen string, err error) string {
+	// Another reason than a busy port: say it as it is.
+	if !isAddrInUse(err) {
+		// The real reason follows.
+		return fmt.Sprintf("OllamaControlCenter cannot listen on %s: %v", listen, err)
+	} // end of the other-reason case
+	// The address a browser on this computer opens.
+	url := launchURL(listen)
+	// The next free-looking port, when one can be named.
+	next := nextPortAddress(listen)
+	// The hint for a second copy.
+	hint := ""
+	// Name the option when we can.
+	if next != "" {
+		// The option to use.
+		hint = fmt.Sprintf(" To run a second copy on purpose, start it on another port, for example: -listen %s", next)
+	} // end of the hint
+	// Is the program on that port one of ours?
+	if probeIsOurs(url) {
+		// Say so, and say what to do.
+		return fmt.Sprintf("OllamaControlCenter is already running and answers at %s. Open that address in your browser. To stop it, use its Stop button, or press Ctrl+C in the window where it runs.%s", url, hint)
+	} // end of the ours case
+	// The option for another port, when one can be named.
+	other := ""
+	// Name the option when we can.
+	if next != "" {
+		// The option to use.
+		other = fmt.Sprintf(" For example: -listen %s", next)
+	} // end of the option
+	// Something else uses the port.
+	return fmt.Sprintf("Port %s is already used by another program, which is not OllamaControlCenter. Stop that program, or start this one on another port.%s", listen[strings.LastIndex(listen, ":")+1:], other)
+} // end of listenFailureMessage
diff --git a/portbusy_test.go b/portbusy_test.go
new file mode 100644
index 0000000..fa027ba
--- /dev/null
+++ b/portbusy_test.go
@@ -0,0 +1,174 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// errors builds a plain error.
+	"errors"
+	// net opens a real port twice.
+	"net"
+	// net/http runs fake programs on a port.
+	"net/http"
+	// net/http/httptest runs them.
+	"net/http/httptest"
+	// strings checks the messages.
+	"strings"
+	// syscall gives the Windows error number.
+	"syscall"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestRealSecondListenIsAddrInUse checks the recognition on the real operating system: taking a port twice must be recognised.
+func TestRealSecondListenIsAddrInUse(t *testing.T) {
+	// Take a free port.
+	first, err := net.Listen("tcp", "127.0.0.1:0")
+	// It must work.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the check
+	// Release it at the end.
+	defer first.Close()
+	// Take the same one again.
+	_, err = net.Listen("tcp", first.Addr().String())
+	// It must fail, and be recognised.
+	if err == nil || !isAddrInUse(err) {
+		// Report it.
+		t.Fatalf("err = %v, want address in use", err)
+	} // end of the check
+} // end of TestRealSecondListenIsAddrInUse
+
+// TestAddrInUseRecognition checks the cases that a real port cannot give on this system, including the Windows number.
+func TestAddrInUseRecognition(t *testing.T) {
+	// Cases.
+	for name, tc := range map[string]struct {
+		err  error
+		want bool
+	}{
+		"linux number":      {syscall.EADDRINUSE, true},
+		"windows number":    {syscall.Errno(10048), true},
+		"wrapped":           {&net.OpError{Op: "listen", Err: syscall.EADDRINUSE}, true},
+		"permission denied": {syscall.EACCES, false},
+		"plain":             {errors.New("boom"), false},
+		"nil":               {nil, false},
+	} {
+		// One sub-test per case.
+		t.Run(name, func(t *testing.T) {
+			// Check.
+			if got := isAddrInUse(tc.err); got != tc.want {
+				// Report it.
+				t.Errorf("isAddrInUse = %v, want %v", got, tc.want)
+			} // end of the check
+		})
+	} // end of the loop
+} // end of TestAddrInUseRecognition
+
+// TestNextPortAddress checks the suggested other port.
+func TestNextPortAddress(t *testing.T) {
+	// Cases.
+	for in, want := range map[string]string{
+		"127.0.0.1:8765":  "127.0.0.1:8766",
+		"0.0.0.0:8765":    "0.0.0.0:8766",
+		":8765":           ":8766",
+		"[::1]:8765":      "[::1]:8766",
+		"127.0.0.1:65535": "",
+		"nonsense":        "",
+		"127.0.0.1:abc":   "",
+	} {
+		// Check.
+		if got := nextPortAddress(in); got != want {
+			// Report it.
+			t.Errorf("nextPortAddress(%q) = %q, want %q", in, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestNextPortAddress
+
+// TestFailureMessages checks the three messages: our own monitor on the port, another program, and another reason.
+func TestFailureMessages(t *testing.T) {
+	// Put the probe back at the end.
+	old := probeIsOurs
+	// Restore.
+	t.Cleanup(func() { probeIsOurs = old })
+	// Our own monitor is there.
+	probeIsOurs = func(string) bool { return true }
+	// The message.
+	m := listenFailureMessage("127.0.0.1:8765", syscall.EADDRINUSE)
+	// It names the address, says how to stop it, and offers another port.
+	for _, want := range []string{"already running", "http://127.0.0.1:8765/", "Stop button", "Ctrl+C", "-listen 127.0.0.1:8766"} {
+		// Check each.
+		if !strings.Contains(m, want) {
+			// Report it.
+			t.Errorf("own-monitor message lacks %q: %s", want, m)
+		} // end of the check
+	} // end of the loop
+	// Another program is there.
+	probeIsOurs = func(string) bool { return false }
+	// The message.
+	m = listenFailureMessage("127.0.0.1:8765", syscall.EADDRINUSE)
+	// It says another program, with the port, and offers another port.
+	for _, want := range []string{"Port 8765", "another program", "not OllamaControlCenter", "For example: -listen 127.0.0.1:8766"} {
+		// Check each.
+		if !strings.Contains(m, want) {
+			// Report it.
+			t.Errorf("other-program message lacks %q: %s", want, m)
+		} // end of the check
+	} // end of the loop
+	// The other-program message does not talk about a second copy.
+	if strings.Contains(m, "second copy") {
+		// Report it.
+		t.Errorf("other-program message mentions a second copy: %s", m)
+	} // end of the wording check
+	// Another reason: no claim about a busy port, and the real reason is kept.
+	m = listenFailureMessage("127.0.0.1:80", syscall.EACCES)
+	// The text.
+	if strings.Contains(m, "already") || !strings.Contains(m, "cannot listen on 127.0.0.1:80") || !strings.Contains(m, syscall.EACCES.Error()) {
+		// Report it.
+		t.Errorf("other-reason message: %s", m)
+	} // end of the check
+} // end of TestFailureMessages
+
+// TestProbeIsOurs checks the real probe against fake programs: a page that names OllamaControlCenter, a page that does not, an error page, and nothing at all.
+func TestProbeIsOurs(t *testing.T) {
+	// A program that looks like ours.
+	ours := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		// Only the About page.
+		if r.URL.Path != "/about" {
+			// Anything else is not found.
+			http.NotFound(w, r)
+			// Done.
+			return
+		} // end of the path check
+		// The title names the program.
+		w.Write([]byte("<title>About - OllamaControlCenter</title>"))
+	}))
+	// Stop it at the end.
+	defer ours.Close()
+	// Another web program.
+	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("<title>Something else</title>")) }))
+	// Stop it at the end.
+	defer other.Close()
+	// A program that always fails.
+	broken := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "OllamaControlCenter", 500) }))
+	// Stop it at the end.
+	defer broken.Close()
+	// The cases.
+	if !probeIsOurs(ours.URL + "/") {
+		// Report it.
+		t.Error("our page was not recognised")
+	} // end of the ours check
+	// Not ours.
+	if probeIsOurs(other.URL + "/") {
+		// Report it.
+		t.Error("another page was taken for ours")
+	} // end of the other check
+	// An error page is not ours even if it names the program.
+	if probeIsOurs(broken.URL + "/") {
+		// Report it.
+		t.Error("an error page was taken for ours")
+	} // end of the broken check
+	// Nothing answering.
+	if probeIsOurs("http://127.0.0.1:1/") {
+		// Report it.
+		t.Error("nothing was taken for ours")
+	} // end of the nothing check
+} // end of TestProbeIsOurs
OCC_PATCH_86_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
done
pass "the two changed files and the two new files have the expected sha256"

UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter . || fail "go build failed"
# Report it.
pass "build for this computer: bin/OllamaControlCenter"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start the monitor twice to see the message (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
