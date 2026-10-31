#!/usr/bin/env bash
# Script 69j: new command -check-links opens every reference address of the comparison page once and prints which answer (exit 0 = all answered, 1 = at least one did not). It is the only part of the program that contacts the internet, and only when you type that flag. Version 0.15.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/check-links" ] || { echo "FAIL  not on feature/check-links"; exit 1; }
# Script 69i (key twistie) must be applied already (merged into main).
[ -e key_test.go ] || { echo "FAIL  script 69i was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e checklinks.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index b2c82a8..12df87e 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.14.0"
+const appVersion = "0.15.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/checklinks.go b/checklinks.go
new file mode 100644
index 0000000..e55f64b
--- /dev/null
+++ b/checklinks.go
@@ -0,0 +1,174 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context carries the time limit of each request.
+	"context"
+	// errors tells a time-out from other failures.
+	"errors"
+	// fmt prints the report.
+	"fmt"
+	// io is the writer type the report goes to.
+	"io"
+	// net/http makes the requests.
+	"net/http"
+	// net/url holds the error type that wraps the network reason.
+	"net/url"
+	// strings builds the report lines.
+	"strings"
+	// time sets the limit of each request.
+	"time"
+) // end of imports
+
+// linkTimeout is how long one address may take to answer before it counts as a failure.
+const linkTimeout = 20 * time.Second
+
+// linkResult is what happened when one reference address was opened.
+type linkResult struct {
+	// N is the number of the reference, as the comparison page shows it.
+	N int
+	// URL is the address that was asked for.
+	URL string
+	// Status is the HTTP status code of the final answer, or 0 when there was none.
+	Status int
+	// Final is the address the answer came from, which differs from URL after a redirect.
+	Final string
+	// Problem is the plain reason when there was no answer at all (empty when there was one).
+	Problem string
+} // end of linkResult
+
+// ok says whether the address answered with a success code (200 to 299).
+func (r linkResult) ok() bool {
+	// Only a real answer in the success range counts.
+	return r.Status >= 200 && r.Status <= 299
+} // end of ok
+
+// newLinkClient makes the client of this command: a time limit per request and at most 5 redirects.
+func newLinkClient() *http.Client {
+	// The client; the program talks to the internet only here, and only when the person typed -check-links.
+	return &http.Client{
+		// The time limit of one request, redirects included.
+		Timeout: linkTimeout,
+		// Stop after 5 redirects so a loop cannot run on.
+		CheckRedirect: func(req *http.Request, via []*http.Request) error {
+			// Too many redirects.
+			if len(via) >= 5 {
+				// Give up with a plain reason.
+				return errors.New("more than 5 redirects")
+			} // end of the limit check
+			// Keep following.
+			return nil
+		}, // end of CheckRedirect
+	} // end of the client
+} // end of newLinkClient
+
+// checkOneLink opens one address with a plain GET (many sites refuse HEAD) and reports what came back; the page body is never read.
+func checkOneLink(ctx context.Context, client *http.Client, ref reference) linkResult {
+	// The result so far.
+	res := linkResult{N: ref.N, URL: ref.URL}
+	// Build the request with the time limit of the context.
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ref.URL, nil)
+	// A bad address is reported, not run.
+	if err != nil {
+		// Say why.
+		res.Problem = "not a valid address"
+		// Hand it back.
+		return res
+	} // end of the request check
+	// Say honestly who is asking; no data of the person is sent.
+	req.Header.Set("User-Agent", "OllamaControlCenter-check-links")
+	// Send it.
+	resp, err := client.Do(req)
+	// No answer at all.
+	if err != nil {
+		// A short plain reason: the time limit, or the error text of the network layer.
+		if errors.Is(err, context.DeadlineExceeded) || strings.Contains(err.Error(), "Client.Timeout") {
+			// The site was too slow.
+			res.Problem = fmt.Sprintf("no answer within %d seconds", int(linkTimeout/time.Second))
+		} else {
+			// Anything else, such as no network or an unknown name; the wrapper repeats the address, so only the reason inside is kept.
+			res.Problem = err.Error()
+			// Unwrap the reason.
+			var ue *url.Error
+			// Use it when it is there.
+			if errors.As(err, &ue) {
+				// The plain reason.
+				res.Problem = ue.Err.Error()
+			} // end of the unwrap
+		} // end of the reason choice
+		// Hand it back.
+		return res
+	} // end of the error check
+	// The body is not needed; close it so the connection is released.
+	defer resp.Body.Close()
+	// Remember the code and where the answer came from.
+	res.Status, res.Final = resp.StatusCode, resp.Request.URL.String()
+	// Hand it back.
+	return res
+} // end of checkOneLink
+
+// formatLinkResults writes one line per address and a closing summary, and says what to do about a failure.
+func formatLinkResults(results []linkResult, readOn string) string {
+	// The text being built.
+	var b strings.Builder
+	// How many answered with a success code.
+	good := 0
+	// Go through the results in order.
+	for _, r := range results {
+		// The start of the line: the number as the page shows it.
+		fmt.Fprintf(&b, "[%d] ", r.N)
+		// Choose the wording.
+		switch {
+		// A success code.
+		case r.ok():
+			// Count it and print it.
+			good++
+			fmt.Fprintf(&b, "OK    %d  %s\n", r.Status, r.URL)
+			// A redirect is not a failure, but the address should be updated.
+			if r.Final != r.URL {
+				// Say where it went.
+				fmt.Fprintf(&b, "      moved to %s (update the address in references.go)\n", r.Final)
+			} // end of the redirect note
+		// An answer that is not a success.
+		case r.Status != 0:
+			// Print the code.
+			fmt.Fprintf(&b, "FAIL  %d  %s\n", r.Status, r.URL)
+		// No answer at all.
+		default:
+			// Print the reason.
+			fmt.Fprintf(&b, "FAIL  --  %s (%s)\n", r.URL, r.Problem)
+		} // end of the wording choice
+	} // end of the loop
+	// The summary line.
+	fmt.Fprintf(&b, "%d of %d addresses answered with a success code. The list was last read by hand on %s.\n", good, len(results), readOn)
+	// Advice only when something failed.
+	if good != len(results) {
+		// What to do, and the honest caveat about sites that refuse programs.
+		b.WriteString("For each FAIL: open the address in a browser. A 403 or 429 can mean the site refuses programs, not that the page is gone.\nIf the page is really gone or has moved, fix or remove the reference in references.go and update the date; nothing was changed by this command.\n")
+	} // end of the advice
+	// Hand back the text.
+	return b.String()
+} // end of formatLinkResults
+
+// runCheckLinks opens every reference address one after another, prints the report, and returns the exit code (0 = all answered with a success code, 1 = at least one did not).
+func runCheckLinks(refs []reference, client *http.Client, readOn string, out io.Writer) int {
+	// The results in order.
+	results := make([]linkResult, 0, len(refs))
+	// Go through the references.
+	for _, ref := range refs {
+		// Ask for one address.
+		results = append(results, checkOneLink(context.Background(), client, ref))
+	} // end of the loop
+	// Print the report.
+	fmt.Fprint(out, formatLinkResults(results, readOn))
+	// The exit code follows the results.
+	for _, r := range results {
+		// One failure is enough.
+		if !r.ok() {
+			// Failure code.
+			return 1
+		} // end of the failure check
+	} // end of the loop
+	// All good.
+	return 0
+} // end of runCheckLinks
diff --git a/checklinks_test.go b/checklinks_test.go
new file mode 100644
index 0000000..c52ac07
--- /dev/null
+++ b/checklinks_test.go
@@ -0,0 +1,162 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes catches the printed report.
+	"bytes"
+	// net/http makes the fake sites.
+	"net/http"
+	// httptest runs the fake sites.
+	"net/http/httptest"
+	// strings searches the report.
+	"strings"
+	// sync/atomic counts requests safely.
+	"sync/atomic"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// fakeSites starts one fake site with a path for each case: ok, gone, moved (to ok), loop and refusal.
+func fakeSites(t *testing.T, hits *atomic.Int32, agents *[]string) *httptest.Server {
+	// Mark this as a helper.
+	t.Helper()
+	// The routes.
+	mux := http.NewServeMux()
+	// A page that answers.
+	mux.HandleFunc("/ok", func(w http.ResponseWriter, r *http.Request) {
+		// Count the request and note who asked and how.
+		hits.Add(1)
+		// Remember the agent and the method.
+		*agents = append(*agents, r.Method+" "+r.Header.Get("User-Agent"))
+		// Answer.
+		w.Write([]byte("hello"))
+	}) // end of ok
+	// A page that is gone.
+	mux.HandleFunc("/gone", func(w http.ResponseWriter, r *http.Request) {
+		// 404.
+		http.NotFound(w, r)
+	}) // end of gone
+	// A page that moved to /ok.
+	mux.HandleFunc("/moved", func(w http.ResponseWriter, r *http.Request) {
+		// Permanent redirect.
+		http.Redirect(w, r, "/ok", http.StatusMovedPermanently)
+	}) // end of moved
+	// A page that redirects to itself for ever.
+	mux.HandleFunc("/loop", func(w http.ResponseWriter, r *http.Request) {
+		// Redirect to itself.
+		http.Redirect(w, r, "/loop", http.StatusFound)
+	}) // end of loop
+	// A site that refuses programs.
+	mux.HandleFunc("/refuse", func(w http.ResponseWriter, r *http.Request) {
+		// 403.
+		w.WriteHeader(http.StatusForbidden)
+	}) // end of refuse
+	// Start the server and stop it at the end.
+	srv := httptest.NewServer(mux)
+	// Cleanup.
+	t.Cleanup(srv.Close)
+	// Hand it back.
+	return srv
+} // end of fakeSites
+
+// TestCheckLinksReportsEachCase checks success, a missing page, a redirect, a redirect loop, a refusal and a dead address.
+func TestCheckLinksReportsEachCase(t *testing.T) {
+	// Counters.
+	var hits atomic.Int32
+	// Who asked.
+	var agents []string
+	// The fake site.
+	srv := fakeSites(t, &hits, &agents)
+	// A closed port for the "no answer" case.
+	dead := httptest.NewServer(http.NotFoundHandler())
+	// Close it at once, so nothing listens there.
+	deadURL := dead.URL
+	// Close.
+	dead.Close()
+	// The references.
+	refs := []reference{{N: 1, URL: srv.URL + "/ok"}, {N: 2, URL: srv.URL + "/gone"}, {N: 3, URL: srv.URL + "/moved"}, {N: 4, URL: srv.URL + "/loop"}, {N: 5, URL: srv.URL + "/refuse"}, {N: 6, URL: deadURL + "/x"}}
+	// Run it.
+	var out bytes.Buffer
+	// The exit code.
+	code := runCheckLinks(refs, newLinkClient(), "1 January 2026", &out)
+	// The report.
+	text := out.String()
+	// At least one failed, so the code is 1.
+	if code != 1 {
+		// Report the problem.
+		t.Errorf("exit code %d, want 1\n%s", code, text)
+	} // end of the code check
+	// What each line must say.
+	for _, want := range []string{"[1] OK    200  " + srv.URL + "/ok", "[2] FAIL  404  ", "[3] OK    200  ", "moved to " + srv.URL + "/ok", "[4] FAIL  --  ", "more than 5 redirects", "[5] FAIL  403  ", "[6] FAIL  --  ", "2 of 6 addresses answered with a success code", "last read by hand on 1 January 2026", "A 403 or 429 can mean the site refuses programs", "nothing was changed by this command"} {
+		// Look for it.
+		if !strings.Contains(text, want) {
+			// Report the gap.
+			t.Errorf("report lacks %q\n%s", want, text)
+		} // end of the check
+	} // end of the loop
+	// Every request was a plain GET with our own name, nothing else.
+	for _, a := range agents {
+		// Check it.
+		if a != "GET OllamaControlCenter-check-links" {
+			// Report it.
+			t.Errorf("unexpected request %q", a)
+		} // end of the check
+	} // end of the loop
+} // end of TestCheckLinksReportsEachCase
+
+// TestCheckLinksAllGood checks the exit code 0 and that no advice is printed when everything answers.
+func TestCheckLinksAllGood(t *testing.T) {
+	// Counters.
+	var hits atomic.Int32
+	// Who asked.
+	var agents []string
+	// The fake site.
+	srv := fakeSites(t, &hits, &agents)
+	// Two good references.
+	refs := []reference{{N: 1, URL: srv.URL + "/ok"}, {N: 2, URL: srv.URL + "/ok"}}
+	// Run it.
+	var out bytes.Buffer
+	// The exit code.
+	code := runCheckLinks(refs, newLinkClient(), "x", &out)
+	// Success.
+	if code != 0 {
+		// Report the problem.
+		t.Errorf("exit code %d, want 0", code)
+	} // end of the code check
+	// No advice.
+	if strings.Contains(out.String(), "For each FAIL") || !strings.Contains(out.String(), "2 of 2 addresses") {
+		// Report the problem.
+		t.Errorf("unexpected report: %s", out.String())
+	} // end of the text check
+	// Two requests, no more.
+	if hits.Load() != 2 {
+		// Report the problem.
+		t.Errorf("%d requests, want 2", hits.Load())
+	} // end of the count check
+} // end of TestCheckLinksAllGood
+
+// TestRealReferencesAreWellFormed checks the six real addresses are https, unique and numbered 1 to n, without opening them (the tests never touch the internet).
+func TestRealReferencesAreWellFormed(t *testing.T) {
+	// Seen addresses.
+	seen := map[string]bool{}
+	// Go through the list.
+	for i, r := range compareReferences {
+		// Numbered without gaps.
+		if r.N != i+1 {
+			// Report it.
+			t.Errorf("reference %d has number %d", i+1, r.N)
+		} // end of the number check
+		// Secure address only.
+		if !strings.HasPrefix(r.URL, "https://") {
+			// Report it.
+			t.Errorf("reference %d is not https: %s", r.N, r.URL)
+		} // end of the scheme check
+		// No duplicates.
+		if seen[r.URL] {
+			// Report it.
+			t.Errorf("duplicate address %s", r.URL)
+		} // end of the duplicate check
+		// Remember it.
+		seen[r.URL] = true
+	} // end of the loop
+} // end of TestRealReferencesAreWellFormed
diff --git a/main.go b/main.go
index b264f0b..140e849 100644
--- a/main.go
+++ b/main.go
@@ -72,15 +72,33 @@ func main() {
 	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
 	// Define a -models switch: false unless given on the command line.
 	modelsFlag := flag.Bool("models", false, "print the installed and loaded models as tables, and exit (0 = printed, 1 = Ollama not reachable)")
+	// Define a -check-links switch: opens every reference address of the comparison page once, prints the result, and exits (the only time the program contacts the internet).
+	linksFlag := flag.Bool("check-links", false, "open every reference address of the comparison page once, print which answer, and exit (0 = all answered, 1 = at least one did not)")
 	// Read the command line now, so the variables above receive their values.
 	flag.Parse()
 
-	// The two one-shot modes cannot be combined; ask the person to choose one.
-	if *checkFlag && *modelsFlag {
+	// The one-shot modes cannot be combined; ask the person to choose one.
+	modes := 0
+	// Count the modes that were given.
+	for _, on := range []bool{*checkFlag, *modelsFlag, *linksFlag} {
+		// One more mode.
+		if on {
+			// Count it.
+			modes++
+		} // end of the mode check
+	} // end of the loop
+	// More than one is not allowed.
+	if modes > 1 {
 		// log.Fatal prints the message and exits with code 1.
-		log.Fatal("use either -check or -models, not both")
+		log.Fatal("use only one of -check, -models and -check-links")
 	} // end of the combination check
 
+	// In -check-links mode, no Ollama is needed: open the reference addresses, print the result and leave.
+	if *linksFlag {
+		// Run it and leave with its exit code.
+		os.Exit(runCheckLinks(compareReferences, newLinkClient(), referencesChecked, os.Stdout))
+	} // end of the links mode
+
 	// Choose the Ollama address by precedence: option, then environment variable, then default.
 	addr, err := resolve(*ollamaFlag, os.Getenv(envOllamaURL))
 	// If the address is unusable, stop with a clear message and a failure exit code.
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
94e5eb2c41816634c9e4f16c1baf6f1e8b38ed4b278137a3f3d4e7c617a393a3  about.go
e5f71c05316503a2ebf998d4387c21a654a168bf99a01a039cac0f240edb9a63  main.go
c142f2bf02dbb5382ee773938149e22de351b750ddfc6ac25e1fb3669c35c5ee  checklinks.go
2eeae0103739dad55c53247d59947846f12585323e2a659b4fff63d27bcccd01  checklinks_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person how to use the new command.
echo "NEXT  run: ./bin/OllamaControlCenter -check-links"
# List the changed files; nothing is committed yet.
git status --short
