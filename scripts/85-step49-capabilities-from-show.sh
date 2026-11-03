#!/usr/bin/env bash
# Script 85 (Windows fix, version 0.30.1): when Ollama's model list leaves out the capabilities or the context length (seen with Ollama 0.21.2 on Windows), the program now asks Ollama's documented /api/show for them, once per model, so the model categories, the Max context length column and the speed test messages work. Also: the dedication ends with "develop this program." Added: capfallback.go, capfallback_test.go; changed: about.go, about_test.go, gear.go, models.go.
# Run it from the project folder, on the fix branch (never on main): cd ~/OllamaControlCenter && bash scripts/85-step49-capabilities-from-show.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the four files BEFORE the change (as on main after PR 36), and of all six files AFTER it.
declare -A BEFORE AFTER
BEFORE["about.go"]="1f17ff5ac6a4053eeafd6f5701d77c7adb8d8f56fbcf106187b78b4185c9fbaa"
BEFORE["about_test.go"]="107965d01a1834b3b75b095b7ea24a5921665d46a5e0d098ec85412fd5cbd0f2"
BEFORE["gear.go"]="d4d6344a7d07b835edaa34047ad88fd23fb0df7abe99995205f40c15e1ec0776"
BEFORE["models.go"]="178488aca2dfcd83cd715a8dd4ca187b8be4b94cc99149304f9f8b46b9416d10"
AFTER["about.go"]="46a7258b156e7a891f0867ab288faaf35a9d4f7365f695d278a669fc1d035599"
AFTER["about_test.go"]="7f0cffa902b36160539e61c574ebbd14505936cfbb49961a1aa21e62557a2a37"
AFTER["gear.go"]="d97e590e82c7c6265d8d8ccefe56517cfb6a4aad011247ac75665f1793b20661"
AFTER["models.go"]="8abadf7efa6e33df27deaca4c242fa647bea232dd171023fe0a59775204550f2"
AFTER["capfallback.go"]="84440f9181550040a5c353bcf291d20c95f55ca5571154b6b13077b43fceabae"
AFTER["capfallback_test.go"]="f11724f03e13b0aa15bbaf0bfd6cb3ce3e2a2f78a7eb48322974418d5fd6181c"

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
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on the fix branch (fix/capabilities-from-show)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Scripts 84, 84b and 84c must be in this branch: their new files exist.
[ -e environment.go ] || fail "environment.go is missing: run script 84 first"
# Report it.
pass "script 84 was applied (environment.go exists)"

# Refuse to run twice: the new wording is already there when the change was applied before.
[ -e problems.go ] || fail "problems.go is missing: script 84c (merged as PR 36) must be in this branch"
pass "script 84c is in this branch (problems.go exists)"

if [ -e capfallback.go ]; then fail "capfallback.go exists: this script was already applied"; fi
pass "the fallback is not there yet (script not applied before)"

for F in "${!BEFORE[@]}"; do
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
done
pass "the four files to change are the expected versions before the change"

PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_85_END'
diff --git a/about.go b/about.go
index de7b257..9f814d7 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.30.0"
+const appVersion = "0.30.1"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
@@ -38,7 +38,7 @@ const appDeveloperProfile = "https://www.linkedin.com/in/shrinikodati/"
 const appAssistant = "Claude (Sonnet 5.5), Anthropic"
 
 // appDedication is the dedication shown on the About page.
-const appDedication = "Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this."
+const appDedication = "Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this program."
 
 // appCopyright is the copyright line shown on the About page.
 const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
diff --git a/about_test.go b/about_test.go
index 0ec0157..f76305a 100644
--- a/about_test.go
+++ b/about_test.go
@@ -57,7 +57,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The assistant with its version.
 		"Claude (Sonnet 5.5), Anthropic",
 		// The dedication, exactly as the developer wrote it.
-		"Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this.",
+		"Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this program.",
 		// The version.
 		appVersion,
 		// The short revision, twelve characters.
diff --git a/capfallback.go b/capfallback.go
new file mode 100644
index 0000000..cb36cdc
--- /dev/null
+++ b/capfallback.go
@@ -0,0 +1,145 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// context lets the work stop when the request is cancelled.
+	"context"
+	// net/http provides the status codes.
+	"net/http"
+	// net/url holds the parsed address type.
+	"net/url"
+	// sync makes the memory safe for several requests at once.
+	"sync"
+	// time provides the clock and durations.
+	"time"
+) // end of imports
+
+// Why this file exists: the Ollama API documentation lists neither "capabilities" nor "context_length" for /api/tags, only for /api/show (capabilities since version 0.6.4; the context length is in model_info). Some Ollama versions (for example 0.21.2 on Windows) leave them out of /api/tags, so the model categories, the Max context length column and the speed test messages were empty. This file asks /api/show for exactly the models whose list entry lacks them, once per model.
+
+// maxShowPerFetch is the most /api/show questions one list fetch may ask, so a page never waits long; the rest are asked on the next fetch.
+const maxShowPerFetch = 20
+
+// factsRetry is how long a failed /api/show question is left alone before it is asked again.
+const factsRetry = time.Minute
+
+// modelFacts is what /api/show told about one model, remembered so the question is asked only once.
+type modelFacts struct {
+	// Caps are the capabilities (empty when Ollama gave none).
+	Caps []string
+	// Ctx is the largest context in tokens, or 0 when it could not be read.
+	Ctx int64
+	// Failed is true when the question did not get a good answer; it is asked again after factsRetry.
+	Failed bool
+	// At is when the question was asked.
+	At time.Time
+} // end of modelFacts
+
+// factsMemory holds the remembered answers; the key is the Ollama address plus the model's digest (its name when it has none), so a changed model is asked again.
+var factsMemory = struct {
+	// Lock protects the map.
+	sync.Mutex
+	// byKey holds the answers.
+	byKey map[string]modelFacts
+}{byKey: map[string]modelFacts{}}
+
+// factsNow is the clock; a test replaces it.
+var factsNow = time.Now
+
+// factsKey builds the memory key of one model.
+func factsKey(base *url.URL, m installedModel) string {
+	// The digest identifies the content; the name is the fallback.
+	id := m.Digest
+	// No digest reported.
+	if id == "" {
+		// Use the name.
+		id = m.Name
+	} // end of the digest check
+	// Address, a separator that cannot be in either, and the identity.
+	return base.Redacted() + "\n" + id
+} // end of factsKey
+
+// resetFacts forgets everything; used by tests.
+func resetFacts() {
+	// One at a time.
+	factsMemory.Lock()
+	// Release at the end.
+	defer factsMemory.Unlock()
+	// A fresh map.
+	factsMemory.byKey = map[string]modelFacts{}
+} // end of resetFacts
+
+// fillFromShow completes the list in place: for each model whose capabilities or context length are missing it uses what /api/show says. It never fails the list: a model that cannot be asked stays as /api/tags gave it.
+func fillFromShow(ctx context.Context, base *url.URL, timeout time.Duration, models []installedModel) {
+	// How many questions this fetch has asked.
+	asked := 0
+	// Go through the models.
+	for i := range models {
+		// What is missing.
+		m := &models[i]
+		// Nothing missing: nothing to ask.
+		if len(m.Capabilities) > 0 && m.Details.ContextLength > 0 {
+			// Next model.
+			continue
+		} // end of the nothing-missing check
+		// The request may have been cancelled.
+		if ctx.Err() != nil {
+			// Stop asking.
+			return
+		} // end of the cancel check
+		// The memory key.
+		key := factsKey(base, *m)
+		// Look it up.
+		factsMemory.Lock()
+		f, known := factsMemory.byKey[key]
+		factsMemory.Unlock()
+		// A failed answer is left alone for a while.
+		if known && f.Failed && factsNow().Sub(f.At) >= factsRetry {
+			// Ask again.
+			known = false
+		} // end of the retry check
+		// Not remembered: ask Ollama, within the limit.
+		if !known {
+			// Too many questions for one fetch: the rest wait for the next one.
+			if asked >= maxShowPerFetch {
+				// Next model.
+				continue
+			} // end of the limit check
+			// One more question.
+			asked++
+			// Ask.
+			reply, status, err := fetchShow(ctx, base, m.Name, timeout)
+			// Build the answer.
+			f = modelFacts{At: factsNow()}
+			// A good answer.
+			if err == nil && status == http.StatusOK {
+				// What Ollama said.
+				f.Caps = reply.Capabilities
+				// The context length, from the model's own facts.
+				if n, ok := modelMaxContext(reply.ModelInfo); ok {
+					// Keep it.
+					f.Ctx = n
+				} // end of the context check
+			} else {
+				// Ask again later.
+				f.Failed = true
+			} // end of the answer check
+			// Remember it, unless the request was cancelled (then the answer may be a cancel error, which says nothing about the model).
+			if ctx.Err() == nil {
+				// One at a time.
+				factsMemory.Lock()
+				factsMemory.byKey[key] = f
+				factsMemory.Unlock()
+			} // end of the remember check
+		} // end of the ask
+		// Fill only what /api/tags left out; what it gave stays.
+		if len(m.Capabilities) == 0 && len(f.Caps) > 0 {
+			// Copy, so the memory is never changed by a caller.
+			m.Capabilities = append([]string(nil), f.Caps...)
+		} // end of the capabilities fill
+		// The context length.
+		if m.Details.ContextLength == 0 && f.Ctx > 0 {
+			// Fill it.
+			m.Details.ContextLength = f.Ctx
+		} // end of the context fill
+	} // end of the model loop
+} // end of fillFromShow
diff --git a/capfallback_test.go b/capfallback_test.go
new file mode 100644
index 0000000..6f0e08c
--- /dev/null
+++ b/capfallback_test.go
@@ -0,0 +1,302 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// context is passed to the fetch.
+	"context"
+	// encoding/json reads the request body of the fake Ollama.
+	"encoding/json"
+	// fmt builds model names.
+	"fmt"
+	// net/http gives the fake server its types.
+	"net/http"
+	// net/http/httptest runs the fake Ollama.
+	"net/http/httptest"
+	// strings checks the capability text.
+	"strings"
+	// sync/atomic counts requests from the server goroutine.
+	"sync/atomic"
+	// testing is Go's test framework.
+	"testing"
+	// time gives the timeout and the fake clock.
+	"time"
+) // end of imports
+
+// oldOllama is a fake Ollama like version 0.21.2 seems to be: the list has no capabilities and no context length, but /api/show has them. showStatus is the status /api/show answers with; shows counts the questions; names has the models.
+type oldOllama struct {
+	// srv is the fake server.
+	srv *httptest.Server
+	// shows counts the /api/show questions.
+	shows atomic.Int32
+	// showStatus is what /api/show answers (200 by default).
+	showStatus atomic.Int32
+} // end of oldOllama
+
+// newOldOllama starts the fake with the given list body; the show answer depends on the model name.
+func newOldOllama(t *testing.T, tags string) *oldOllama {
+	// Mark this as a helper.
+	t.Helper()
+	// The fake.
+	o := &oldOllama{}
+	// Healthy by default.
+	o.showStatus.Store(http.StatusOK)
+	// The server.
+	o.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		// The list.
+		if r.URL.Path == "/api/tags" {
+			// Send it.
+			w.Write([]byte(tags))
+			// Done.
+			return
+		} // end of the list case
+		// The details of one model.
+		if r.URL.Path == "/api/show" && r.Method == http.MethodPost {
+			// Count the question.
+			o.shows.Add(1)
+			// Which model.
+			var in struct{ Model string }
+			// Read it.
+			json.NewDecoder(r.Body).Decode(&in)
+			// A failing server.
+			if st := int(o.showStatus.Load()); st != http.StatusOK {
+				// Fail.
+				http.Error(w, "boom", st)
+				// Done.
+				return
+			} // end of the failure case
+			// An embedding model has the embedding capability and a context length under its own architecture.
+			if strings.HasPrefix(in.Model, "embed") {
+				// The reply.
+				w.Write([]byte(`{"capabilities":["embedding"],"model_info":{"general.architecture":"bert","bert.context_length":512}}`))
+				// Done.
+				return
+			} // end of the embedding case
+			// A model that tells nothing (older than 0.6.4).
+			if strings.HasPrefix(in.Model, "mute") {
+				// The reply.
+				w.Write([]byte(`{"model_info":{}}`))
+				// Done.
+				return
+			} // end of the mute case
+			// A chat model.
+			w.Write([]byte(`{"capabilities":["completion","tools"],"model_info":{"general.architecture":"llama","llama.context_length":131072}}`))
+			// Done.
+			return
+		} // end of the show case
+		// Anything else is a mistake.
+		http.NotFound(w, r)
+	}))
+	// Stop it at the end.
+	t.Cleanup(o.srv.Close)
+	// Hand it back.
+	return o
+} // end of newOldOllama
+
+// TestFallbackFillsCapabilitiesAndContext checks the Windows case: the list lacks both, /api/show has them.
+func TestFallbackFillsCapabilitiesAndContext(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// A list of a chat model and an embedding model, with no capabilities and no context length.
+	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","details":{}},{"name":"embed:1","digest":"d2","details":{}}]}`)
+	// Fetch.
+	got, err := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// No error.
+	if err != nil || len(got) != 2 {
+		// Stop.
+		t.Fatalf("err=%v len=%d", err, len(got))
+	} // end of the check
+	// The chat model.
+	if c := categorize(got[0].Capabilities); c == categoryUnclassified || got[0].Details.ContextLength != 131072 {
+		// Report it.
+		t.Errorf("chat: caps=%v ctx=%d", got[0].Capabilities, got[0].Details.ContextLength)
+	} // end of the chat check
+	// The embedding model.
+	if got[1].Details.ContextLength != 512 || len(got[1].Capabilities) != 1 || got[1].Capabilities[0] != "embedding" {
+		// Report it.
+		t.Errorf("embed: caps=%v ctx=%d", got[1].Capabilities, got[1].Details.ContextLength)
+	} // end of the embedding check
+	// A second fetch uses the memory: no new questions.
+	before := o.shows.Load()
+	// Fetch again.
+	got2, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// Same answers, no questions.
+	if o.shows.Load() != before || got2[0].Details.ContextLength != 131072 {
+		// Report it.
+		t.Errorf("second fetch asked %d more questions", o.shows.Load()-before)
+	} // end of the memory check
+} // end of TestFallbackFillsCapabilitiesAndContext
+
+// TestFallbackLeavesCompleteListsAlone checks that a list that already has both costs no /api/show question and is not changed.
+func TestFallbackLeavesCompleteListsAlone(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// A complete entry.
+	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","capabilities":["completion"],"details":{"context_length":4096}}]}`)
+	// Fetch.
+	got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// Nothing asked, nothing changed.
+	if o.shows.Load() != 0 || got[0].Details.ContextLength != 4096 || len(got[0].Capabilities) != 1 {
+		// Report it.
+		t.Errorf("asked %d, got %+v", o.shows.Load(), got[0])
+	} // end of the check
+} // end of TestFallbackLeavesCompleteListsAlone
+
+// TestFallbackKeepsWhatTheListGave checks that only the missing part is filled: a list with capabilities but no context length keeps its capabilities.
+func TestFallbackKeepsWhatTheListGave(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// Capabilities present, context length missing.
+	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","capabilities":["vision"],"details":{}}]}`)
+	// Fetch.
+	got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// The list's own capabilities stay; the context length is filled.
+	if len(got[0].Capabilities) != 1 || got[0].Capabilities[0] != "vision" || got[0].Details.ContextLength != 131072 {
+		// Report it.
+		t.Errorf("got %+v", got[0])
+	} // end of the check
+} // end of TestFallbackKeepsWhatTheListGave
+
+// TestFallbackFailureIsSilentAndRetried checks that a failing /api/show never fails the list, is not asked again at once, and is asked again after the wait.
+func TestFallbackFailureIsSilentAndRetried(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// A fake clock.
+	now := time.Now()
+	// Replace the clock; put it back at the end.
+	old := factsNow
+	// Restore.
+	t.Cleanup(func() { factsNow = old })
+	// The clock reads this variable.
+	factsNow = func() time.Time { return now }
+	// A server whose /api/show fails.
+	o := newOldOllama(t, `{"models":[{"name":"chat:1","digest":"d1","details":{}}]}`)
+	// Fail.
+	o.showStatus.Store(http.StatusInternalServerError)
+	// Fetch.
+	got, err := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// The list still works, unchanged.
+	if err != nil || len(got) != 1 || len(got[0].Capabilities) != 0 || got[0].Details.ContextLength != 0 {
+		// Stop.
+		t.Fatalf("err=%v got=%+v", err, got)
+	} // end of the check
+	// One question so far.
+	if o.shows.Load() != 1 {
+		// Report it.
+		t.Fatalf("asked %d", o.shows.Load())
+	} // end of the count check
+	// Fetch again at once: not asked again.
+	fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// Still one.
+	if o.shows.Load() != 1 {
+		// Report it.
+		t.Errorf("asked again too soon: %d", o.shows.Load())
+	} // end of the quiet check
+	// The server heals and the wait passes.
+	o.showStatus.Store(http.StatusOK)
+	// Time passes.
+	now = now.Add(factsRetry + time.Second)
+	// Fetch.
+	got, _ = fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// Now it is filled.
+	if o.shows.Load() != 2 || got[0].Details.ContextLength != 131072 {
+		// Report it.
+		t.Errorf("asked %d, got %+v", o.shows.Load(), got[0])
+	} // end of the retry check
+} // end of TestFallbackFailureIsSilentAndRetried
+
+// TestFallbackRemembersMuteModels checks that a model that tells nothing (an old Ollama) is asked only once, and stays unclassified.
+func TestFallbackRemembersMuteModels(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// A mute model.
+	o := newOldOllama(t, `{"models":[{"name":"mute:1","digest":"d1","details":{}}]}`)
+	// Fetch twice.
+	for i := 0; i < 2; i++ {
+		// Fetch.
+		got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+		// Still unclassified.
+		if categorize(got[0].Capabilities) != categoryUnclassified {
+			// Report it.
+			t.Errorf("round %d: caps=%v", i, got[0].Capabilities)
+		} // end of the check
+	} // end of the loop
+	// Asked once.
+	if o.shows.Load() != 1 {
+		// Report it.
+		t.Errorf("asked %d times", o.shows.Load())
+	} // end of the count check
+} // end of TestFallbackRemembersMuteModels
+
+// TestFallbackAsksAgainWhenTheModelChanges checks that a new digest is a new question.
+func TestFallbackAsksAgainWhenTheModelChanges(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// The list the server sends can be switched.
+	var tags atomic.Value
+	// First list.
+	tags.Store(`{"models":[{"name":"chat:1","digest":"d1","details":{}}]}`)
+	// A server that serves the current list and the usual show answer.
+	o := newOldOllama(t, "")
+	// Replace the list handling: a second server in front would be heavier, so ask through a wrapper.
+	front := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		// The list comes from the switch.
+		if r.URL.Path == "/api/tags" {
+			// Send it.
+			w.Write([]byte(tags.Load().(string)))
+			// Done.
+			return
+		} // end of the list case
+		// Everything else goes to the fake.
+		o.srv.Config.Handler.ServeHTTP(w, r)
+	}))
+	// Stop it at the end.
+	t.Cleanup(front.Close)
+	// Fetch.
+	fetchInstalled(context.Background(), mustParse(t, front.URL), time.Second)
+	// The same name, a new digest.
+	tags.Store(`{"models":[{"name":"chat:1","digest":"d2","details":{}}]}`)
+	// Fetch again.
+	fetchInstalled(context.Background(), mustParse(t, front.URL), time.Second)
+	// Two questions.
+	if o.shows.Load() != 2 {
+		// Report it.
+		t.Errorf("asked %d times, want 2", o.shows.Load())
+	} // end of the count check
+} // end of TestFallbackAsksAgainWhenTheModelChanges
+
+// TestFallbackLimitsQuestionsPerFetch checks that one fetch asks at most maxShowPerFetch questions and the next fetch asks the rest.
+func TestFallbackLimitsQuestionsPerFetch(t *testing.T) {
+	// Start clean.
+	resetFacts()
+	// Thirty models.
+	var rows []string
+	// Build them.
+	for i := 0; i < 30; i++ {
+		// One row.
+		rows = append(rows, fmt.Sprintf(`{"name":"chat:%d","digest":"d%d","details":{}}`, i, i))
+	} // end of the loop
+	// The server.
+	o := newOldOllama(t, `{"models":[`+strings.Join(rows, ",")+`]}`)
+	// First fetch.
+	fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// At most the limit.
+	if n := o.shows.Load(); n != maxShowPerFetch {
+		// Report it.
+		t.Fatalf("first fetch asked %d, want %d", n, maxShowPerFetch)
+	} // end of the limit check
+	// Second fetch asks the rest only.
+	got, _ := fetchInstalled(context.Background(), mustParse(t, o.srv.URL), time.Second)
+	// Thirty in all.
+	if n := o.shows.Load(); n != 30 {
+		// Report it.
+		t.Errorf("after two fetches asked %d, want 30", n)
+	} // end of the total check
+	// Everyone is filled now.
+	for _, m := range got {
+		// Check one.
+		if m.Details.ContextLength != 131072 {
+			// Report it.
+			t.Errorf("%s not filled", m.Name)
+		} // end of the check
+	} // end of the loop
+} // end of TestFallbackLimitsQuestionsPerFetch
diff --git a/gear.go b/gear.go
index 7882d7f..7028378 100644
--- a/gear.go
+++ b/gear.go
@@ -63,6 +63,8 @@ type showReply struct {
 	Modelfile string `json:"modelfile"`
 	// ModelInfo holds the model's own facts; each value stays raw text until it is needed, so a long list inside it costs nothing.
 	ModelInfo map[string]json.RawMessage `json:"model_info"`
+	// Capabilities lists what the model can do (for example completion, vision, embedding); the Ollama API documentation lists it for /api/show since version 0.6.4.
+	Capabilities []string `json:"capabilities"`
 } // end of showReply
 
 // paramLine is one saved parameter, such as num_ctx with 8192.
diff --git a/models.go b/models.go
index 872b68b..1193c79 100644
--- a/models.go
+++ b/models.go
@@ -104,6 +104,8 @@ func fetchInstalled(ctx context.Context, base *url.URL, timeout time.Duration) (
 		// Pass the safe error on, with no models.
 		return nil, err
 	} // end of the fetch check
+	// Some Ollama versions do not put the capabilities or the context length into the list; ask /api/show for those models (see capfallback.go).
+	fillFromShow(ctx, base, timeout, reply.Models)
 	// Return the list (it may be empty on a machine with no models).
 	return reply.Models, nil
 } // end of fetchInstalled
OCC_PATCH_85_END

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
pass "the four changed files and the two new files have the expected sha256"

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
echo "NEXT  start the monitor and look at the main page, the System check and the About page (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
