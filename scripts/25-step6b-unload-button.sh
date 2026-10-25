#!/usr/bin/env bash
# Script 25: Step 6b, the Unload button: a red outlined button next to "Loaded", a warning page with Yes and Cancel, and an unload that is checked afterwards.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with scripts 05, 19, 20, 22 and 24.
TEST_PORT="${TEST_PORT:-18771}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write unload.go (the two unload steps and the call to Ollama); the quoted EOF_UNLOAD marker saves every character exactly as typed.
cat > unload.go << 'EOF_UNLOAD'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes holds the JSON that is sent to Ollama and the finished page.
	"bytes"
	// context lets a request be cancelled or given a deadline.
	"context"
	// embed lets the unload page template be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// encoding/json writes the request body, so a model name can never break the JSON.
	"encoding/json"
	// errors builds fixed error messages.
	"errors"
	// fmt builds formatted text.
	"fmt"
	// html/template builds HTML and escapes every inserted value.
	"html/template"
	// io drains reply bodies.
	"io"
	// log prints messages to the terminal.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// time provides durations and pauses.
	"time"
) // end of imports

// unloadTemplateText is the unload page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/unload.html
var unloadTemplateText string

// unloadTimeout is how long the unload request may take; a busy model can keep Ollama from answering for a while, so this is longer than a normal check.
const unloadTimeout = 30 * time.Second

// unloadVerifyWait is how long the monitor keeps asking whether the model is really gone (a variable so tests can make it short).
var unloadVerifyWait = 4 * time.Second

// unloadVerifyStep is the pause between those questions.
const unloadVerifyStep = 300 * time.Millisecond

// maxModelNameLen is the longest model name the forms accept.
const maxModelNameLen = 300

// postJSON sends one JSON body to base+path and returns only the status number; every error text is fixed and never contains the address.
func postJSON(ctx context.Context, base *url.URL, path string, timeout time.Duration, payload any) (int, error) {
	// Turn the payload into JSON text.
	body, err := json.Marshal(payload)
	// A failure here is a bug in the program, not in Ollama.
	if err != nil {
		// Return a fixed message.
		return 0, errors.New("the request could not be built")
	} // end of the marshal check
	// Build the full address by adding the path safely.
	target := base.JoinPath(path).String()
	// Create the request; the context allows cancelling it from outside.
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, target, bytes.NewReader(body))
	// A failure here means the address could not form a request.
	if err != nil {
		// Return a fixed message.
		return 0, errors.New("the address could not be used to build a request")
	} // end of the request check
	// Tell Ollama the body is JSON.
	req.Header.Set("Content-Type", "application/json")
	// Create a client that gives up after the timeout.
	client := &http.Client{Timeout: timeout}
	// Send the request and wait for the reply.
	resp, err := client.Do(req)
	// A failure here means no reply arrived at all.
	if err != nil {
		// Turn the technical error into a plain reason (reused from check.go).
		return 0, errors.New(explainError(err))
	} // end of the send check
	// Always close the reply body when this function ends.
	defer resp.Body.Close()
	// Read and drop a little of the body so the connection can be reused; the content is not needed.
	io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
	// Hand back the status number.
	return resp.StatusCode, nil
} // end of postJSON

// unloadModel asks Ollama to unload one model now by setting its keep-alive time to 0; it returns which request worked.
func unloadModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) (string, error) {
	// Chat and text models are unloaded through /api/generate with no prompt and keep_alive 0 (the documented way).
	status, err := postJSON(ctx, base, "api/generate", timeout, map[string]any{"model": name, "keep_alive": 0})
	// No answer at all.
	if err != nil {
		// Pass the safe error on.
		return "", err
	} // end of the send check
	// Status 200 means Ollama accepted the request.
	if status == http.StatusOK {
		// Report which request worked.
		return "generate", nil
	} // end of the success case
	// Status 400 is what a model that cannot generate text (an embedding model, for example) answers; try the embedding request instead.
	if status == http.StatusBadRequest {
		// Embedding models are asked through /api/embed; the one-word input is only there because the request needs some input.
		status2, err2 := postJSON(ctx, base, "api/embed", timeout, map[string]any{"model": name, "input": "unload", "keep_alive": 0})
		// No answer at all.
		if err2 != nil {
			// Pass the safe error on.
			return "", err2
		} // end of the second send check
		// Status 200 means Ollama accepted the request.
		if status2 == http.StatusOK {
			// Report which request worked.
			return "embed", nil
		} // end of the second success case
		// Both requests were refused; report both numbers.
		return "", fmt.Errorf("Ollama refused both unload requests (status %d and status %d)", status, status2)
	} // end of the 400 case
	// Any other status.
	return "", fmt.Errorf("Ollama answered the unload request with status %d", status)
} // end of unloadModel

// findLoaded returns the loaded model with the given name; the second result is false when it is not loaded.
func findLoaded(list []loadedModel, name string) (loadedModel, bool) {
	// Look at every loaded model.
	for _, m := range list {
		// A match by exact name.
		if m.Name == name {
			// Found it.
			return m, true
		} // end of the name check
	} // end of the loop
	// Not in the list.
	return loadedModel{}, false
} // end of findLoaded

// waitUntilGone asks Ollama every fraction of a second whether the model has left the loaded list, for a limited time.
func waitUntilGone(ctx context.Context, base *url.URL, name string, timeout time.Duration) (bool, error) {
	// The moment to stop asking.
	deadline := time.Now().Add(unloadVerifyWait)
	// Ask until the deadline.
	for {
		// Read the loaded list.
		list, err := fetchLoaded(ctx, base, timeout)
		// A failure to read means we cannot say.
		if err != nil {
			// Pass the safe error on.
			return false, err
		} // end of the read check
		// The model is gone from the list.
		if _, ok := findLoaded(list, name); !ok {
			// Done: it is unloaded.
			return true, nil
		} // end of the gone check
		// Out of time: still loaded.
		if time.Now().After(deadline) {
			// Report that it is still there.
			return false, nil
		} // end of the deadline check
		// Wait a little, or stop at once if the browser went away.
		select {
		// The browser closed the request.
		case <-ctx.Done():
			// Give up.
			return false, ctx.Err()
		// The pause is over.
		case <-time.After(unloadVerifyStep):
		} // end of the wait
	} // end of the loop
} // end of waitUntilGone

// remainingText words the time left before Ollama unloads the model by itself; a model set to stay loaded forever reports a date centuries away, which is shown in words instead of a huge number of hours.
func remainingText(now, expires time.Time, ok bool) string {
	// More than 30 days away means "kept loaded" rather than a countdown.
	if ok && expires.Sub(now) > 30*24*time.Hour {
		// Say so in words.
		return "never on its own (it is set to stay loaded)"
	} // end of the far-future case
	// Otherwise use the normal wording from loaded.go.
	return formatRemaining(now, expires, ok)
} // end of remainingText

// unloadPage is everything the unload page template can show.
type unloadPage struct {
	// Kind says which version of the page to draw: confirm, notloaded, done, stillloaded or error.
	Kind string
	// Model is the model name.
	Model string
	// Remaining is the time left before Ollama unloads the model by itself (confirm page).
	Remaining string
	// Detail is the plain reason shown on the error page.
	Detail string
	// Theme is the saved theme choice, as on the main page.
	Theme string
	// Token is the page token for the forms on this page.
	Token string
} // end of unloadPage

// unloadHandlers builds the two handlers: the first asks "are you sure?" (it changes nothing), the second does the unload.
func unloadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc) {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("unload").Parse(unloadTemplateText))
	// readForm runs the checks that both handlers share and returns the model name; ok is false when a refusal was already sent.
	readForm := func(w http.ResponseWriter, r *http.Request) (string, bool) {
		// Never read more than 2 KB of form data; the real form is tiny.
		r.Body = http.MaxBytesReader(w, r.Body, 2048)
		// Only a form on this very page may send this request (requirement S2).
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return "", false
		} // end of the origin check
		// Read the form fields.
		if err := r.ParseForm(); err != nil {
			// A broken or too large form.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return "", false
		} // end of the form check
		// The token proves the form came from a page this monitor made.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return "", false
		} // end of the token check
		// The model name must be present and not absurdly long.
		name := r.PostFormValue("model")
		// Check the name.
		if name == "" || len(name) > maxModelNameLen {
			// Refuse.
			http.Error(w, "bad model name", http.StatusBadRequest)
			// Stop here.
			return "", false
		} // end of the name check
		// All checks passed.
		return name, true
	} // end of readForm
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data unloadPage) {
		// Add what every version of the page needs.
		data.Theme, data.Token = themeFromRequest(r), token
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("unload page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(status)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// ask is the first step: it re-checks Ollama and shows the warning with a Yes and a Cancel button; it never unloads anything.
	ask := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Ask Ollama what is loaded right now, not what the page showed earlier.
		list, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, unloadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the read check
		// Look for the model.
		m, found := findLoaded(list, name)
		// It is not loaded (any more): say so, with no unload button (requirement S3).
		if !found {
			// Show that page.
			show(w, r, http.StatusOK, unloadPage{Kind: "notloaded", Model: name})
			// Stop here.
			return
		} // end of the not-loaded case
		// Work out the time left before Ollama unloads it by itself.
		exp, expOK := m.expiresTime()
		// Show the warning page.
		show(w, r, http.StatusOK, unloadPage{Kind: "confirm", Model: name, Remaining: remainingText(time.Now(), exp, expOK)})
	} // end of ask
	// confirm is the second step: it checks again, unloads, and then checks that the model is really gone.
	confirm := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared checks.
		name, ok := readForm(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Look again: the model may have been unloaded since the warning page was shown.
		list, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, unloadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the read check
		// Only a model that is loaded now may be unloaded (requirement S3).
		if _, found := findLoaded(list, name); !found {
			// Show that page.
			show(w, r, http.StatusOK, unloadPage{Kind: "notloaded", Model: name})
			// Stop here.
			return
		} // end of the not-loaded case
		// Ask Ollama to unload it.
		if _, err := unloadModel(r.Context(), addr.URL, name, unloadTimeout); err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, unloadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the unload check
		// Do not trust the 200 alone: ask until the model has left the loaded list.
		gone, err := waitUntilGone(r.Context(), addr.URL, name, defaultCheckTimeout)
		// The list could not be read afterwards.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, unloadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the verify check
		// The model is still loaded: say so honestly.
		if !gone {
			// Show that page.
			show(w, r, http.StatusOK, unloadPage{Kind: "stillloaded", Model: name})
			// Stop here.
			return
		} // end of the still-loaded case
		// The model is gone.
		show(w, r, http.StatusOK, unloadPage{Kind: "done", Model: name})
	} // end of confirm
	// Hand both back.
	return ask, confirm
} // end of unloadHandlers
EOF_UNLOAD

# Write web/unload.html (the warning page); the quoted EOF_UHTML marker saves every character exactly as typed.
cat > web/unload.html << 'EOF_UHTML'
{{/* Unload page template: one page with five versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
<!DOCTYPE html>
{{/* lang tells screen readers which language the page is written in. */}}
<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
<head>{{/* start of the head. */}}
{{/* Text encoding. */}}
<meta charset="utf-8">
{{/* Fit the page to the width of the screen on phones. */}}
<meta name="viewport" content="width=device-width, initial-scale=1">
{{/* The title shown on the browser tab. */}}
<title>Unload a model - OllamaControlCenter</title>
{{/* Our one stylesheet. */}}
<link rel="stylesheet" href="/app.css">
</head>{{/* end of the head. */}}
<body>{{/* start of the visible page. */}}
{{/* The page content. */}}
<main>
{{/* A panel that holds the message. */}}
<section class="panel">
{{/* The heading names the model, so there is no doubt which one is meant. */}}
<h1>Unload <code>{{.Model}}</code></h1>
{{/* Version 1: the model is loaded and the person must confirm. */}}
{{if eq .Kind "confirm"}}
{{/* The warning about work in progress, in plain words. */}}
<p><strong>Before you continue:</strong> This monitor cannot see whether a model is working on a request right now. If an application is using this model at this moment, unloading it can interrupt that work or leave the application in an unexpected state.</p>
{{/* What happens if the person does nothing. */}}
<p class="muted">If you do nothing, Ollama unloads this model by itself in: {{.Remaining}}.</p>
{{/* The advice. */}}
<p>Only continue if you know that nothing is using this model.</p>
{{/* The two choices side by side. */}}
<div class="choices">
{{/* The Yes form sends the model name and the page token to the second step. */}}
<form method="post" action="/unload/confirm">
{{/* The page token proves the form comes from this monitor. */}}
<input type="hidden" name="token" value="{{.Token}}">
{{/* The model name. */}}
<input type="hidden" name="model" value="{{.Model}}">
{{/* The Yes button. */}}
<button type="submit" class="btn-solid">Yes, unload it now</button>
{{/* End of the Yes form. */}}
</form>
{{/* The Cancel link simply goes back; nothing was changed. */}}
<a class="btn-plain" href="/">Cancel, keep it loaded</a>
{{/* End of the choices. */}}
</div>
{{/* Version 2: the model is not loaded (any more). */}}
{{else if eq .Kind "notloaded"}}
{{/* Say so; there is nothing to unload. */}}
<p>This model is not loaded right now, so there is nothing to unload.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 3: the unload worked. */}}
{{else if eq .Kind "done"}}
{{/* Say so; it was checked afterwards. */}}
<p><strong>Done.</strong> Ollama no longer lists this model as loaded.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 4: Ollama accepted the request but the model is still listed. */}}
{{else if eq .Kind "stillloaded"}}
{{/* Say exactly what is known and what is not. */}}
<p><strong>Not unloaded yet.</strong> Ollama accepted the request, but the model is still listed as loaded. It may be busy with a request. Reload the monitor page in a moment to check.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 5: something went wrong. */}}
{{else}}
{{/* Say what went wrong, in the plain words the program already uses. */}}
<p><strong>Could not do this.</strong> {{.Detail}}</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* End of the five versions. */}}
{{end}}
{{/* End of the panel. */}}
</section>
{{/* End of the content. */}}
</main>
</body>{{/* end of the visible page. */}}
</html>{{/* end of the page. */}}
EOF_UHTML

# Write unload_test.go; the quoted EOF_UTEST marker saves every character exactly as typed.
cat > unload_test.go << 'EOF_UTEST'
// Package main tells Go that this test file belongs to the same program as unload.go.
package main

import ( // import lists the packages this test file uses.
	// io reads request bodies in the fake Ollama.
	"io"
	// net/http provides requests and status codes.
	"net/http"
	// net/http/httptest records replies and runs the fake Ollama.
	"net/http/httptest"
	// net/url builds form data.
	"net/url"
	// regexp finds the token in the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records, because the server runs in its own goroutine.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
	// time shortens the waiting time in the tests.
	"time"
) // end of imports

// unloadFake is a fake Ollama that remembers what it was asked and can pretend to unload models.
type unloadFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// loaded is the list of names that /api/ps reports.
	loaded []string
	// calls records "path body" for every POST.
	calls []string
	// generateStatus is the status that /api/generate answers (200 unless a test changes it).
	generateStatus int
	// ignore makes the fake accept unload requests without actually unloading (a busy model).
	ignore bool
} // end of unloadFake

// start runs the fake as a server and returns it.
func (f *unloadFake) start(t *testing.T) *httptest.Server {
	// Mark this as a helper.
	t.Helper()
	// Default to a working generate.
	if f.generateStatus == 0 {
		// Status 200.
		f.generateStatus = http.StatusOK
	} // end of the default
	// Start the server.
	return fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// One request at a time.
		f.mu.Lock()
		// Release when this request is done.
		defer f.mu.Unlock()
		// Pick the reply by path.
		switch r.URL.Path {
		// The version check.
		case "/api/version":
			// A valid version.
			w.Write([]byte(`{"version":"0.34.4"}`))
		// The installed list: two models.
		case "/api/tags":
			// Two models, one of them an embedding model.
			w.Write([]byte(`{"models":[{"name":"alpha:1b","size":1000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"embed:1b","size":2000,"details":{"family":"bert"},"capabilities":["embedding"]}]}`))
		// The loaded list.
		case "/api/ps":
			// Build the list from the fake's state.
			parts := []string{}
			// Every loaded name.
			for _, n := range f.loaded {
				// One entry with an expiry far in the future.
				parts = append(parts, `{"name":"`+n+`","size":5,"expires_at":"2099-01-01T00:00:00Z"}`)
			} // end of the loop
			// Send the list.
			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
		// The two unload requests.
		case "/api/generate", "/api/embed":
			// Read the body.
			b, _ := io.ReadAll(r.Body)
			// Record the call.
			f.calls = append(f.calls, r.URL.Path+" "+string(b))
			// A refusal from generate (an embedding model) is what a real Ollama gives.
			if r.URL.Path == "/api/generate" && f.generateStatus != http.StatusOK {
				// Send the chosen status.
				w.WriteHeader(f.generateStatus)
				// Stop here.
				return
			} // end of the refusal
			// A working fake really unloads.
			if !f.ignore {
				// Empty the loaded list.
				f.loaded = nil
			} // end of the unload
			// Accept.
			w.Write([]byte(`{}`))
		// Anything else.
		default:
			// Not found.
			http.NotFound(w, r)
		} // end of the switch
	}) // end of the server
} // end of start

// callCount says how many unload requests the fake has received.
func (f *unloadFake) callCount() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return len(f.calls)
} // end of callCount

// unloadRig builds a handler on top of the fake and finds the page token.
func unloadRig(t *testing.T, f *unloadFake) themeRig {
	// Mark this as a helper.
	t.Helper()
	// Short waiting, so the tests stay quick.
	old := unloadVerifyWait
	// Restore it afterwards.
	t.Cleanup(func() { unloadVerifyWait = old })
	// Half a second is plenty for a fake.
	unloadVerifyWait = 500 * time.Millisecond
	// Start the fake.
	srv := f.start(t)
	// Build the handler once, because the token belongs to one handler.
	h := handlerFor(t, srv.URL)
	// Fetch the page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the first hidden token field.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
	// The page must carry a token.
	if m == nil {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// Hand back the pair.
	return themeRig{h: h, token: m[1]}
} // end of unloadRig

// bodyOf reads a recorded reply.
func bodyOf(res *http.Response) string {
	// Read it all.
	b, _ := io.ReadAll(res.Body)
	// As text.
	return string(b)
} // end of bodyOf

// TestUnloadButtonOnlyOnLoadedRows checks the button appears for the loaded model and nowhere else.
func TestUnloadButtonOnlyOnLoadedRows(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig and fetch the page.
	rig := unloadRig(t, f)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// Exactly one unload form.
	if n := strings.Count(body, `action="/unload"`); n != 1 {
		// Report the difference.
		t.Errorf("unload forms = %d, want 1", n)
	} // end of the count
	// It names the loaded model.
	if !strings.Contains(body, `name="model" value="alpha:1b"`) {
		// Report the problem.
		t.Errorf("the unload form does not name alpha:1b")
	} // end of the name check
	// The button has a name for screen readers that includes the model.
	if !strings.Contains(body, `aria-label="Unload alpha:1b"`) {
		// Report the problem.
		t.Errorf("the unload button has no accessible name")
	} // end of the label check
	// The embedding model is not loaded, so it has no button.
	if strings.Contains(body, `value="embed:1b"`) {
		// Report the problem.
		t.Errorf("a not-loaded model has an unload form")
	} // end of the other check
} // end of TestUnloadButtonOnlyOnLoadedRows

// TestUnloadAskChangesNothing checks the first step shows the warning and sends no unload request.
func TestUnloadAskChangesNothing(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// Ask to unload it.
	res := post(t, rig.h, "/unload", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// Read the page.
	body := bodyOf(res)
	// The warning must be there, saying that Ollama does not report busy.
	for _, want := range []string{"cannot see whether a model is working", "Only continue if you know that nothing is using this model", `action="/unload/confirm"`, "Cancel, keep it loaded"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("confirm page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("the first step sent %d unload requests, want 0", n)
	} // end of the call check
	// The model must still be loaded.
	if len(f.loaded) != 1 {
		// Report the problem.
		t.Errorf("the model was unloaded by the first step")
	} // end of the state check
} // end of TestUnloadAskChangesNothing

// TestUnloadConfirmUnloads checks the second step sends exactly one correct request and reports success.
func TestUnloadConfirmUnloads(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// Confirm.
	res := post(t, rig.h, "/unload/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// The page must say it worked.
	if body := bodyOf(res); !strings.Contains(body, "no longer lists this model as loaded") {
		// Report the problem.
		t.Errorf("success message missing: %s", body)
	} // end of the message check
	// Exactly one request, to /api/generate, with keep_alive 0 and the right model.
	if len(f.calls) != 1 || f.calls[0] != `/api/generate {"keep_alive":0,"model":"alpha:1b"}` {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestUnloadConfirmUnloads

// TestUnloadEmbeddingFallback checks a model that cannot generate is unloaded through /api/embed.
func TestUnloadEmbeddingFallback(t *testing.T) {
	// A fake whose generate answers 400, with an embedding model loaded.
	f := &unloadFake{loaded: []string{"embed:1b"}, generateStatus: http.StatusBadRequest}
	// Build the rig.
	rig := unloadRig(t, f)
	// Confirm.
	res := post(t, rig.h, "/unload/confirm", url.Values{"token": {rig.token}, "model": {"embed:1b"}}, fromThisPage)
	// It must answer 200 with the success message.
	if body := bodyOf(res); res.StatusCode != http.StatusOK || !strings.Contains(body, "no longer lists this model as loaded") {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, body)
	} // end of the check
	// Two requests: generate, then embed with keep_alive 0.
	if len(f.calls) != 2 || !strings.HasPrefix(f.calls[1], "/api/embed ") || !strings.Contains(f.calls[1], `"keep_alive":0`) {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestUnloadEmbeddingFallback

// TestUnloadStillLoaded checks the page does not claim success when Ollama accepted the request but the model stays loaded.
func TestUnloadStillLoaded(t *testing.T) {
	// A fake that accepts and ignores unload requests.
	f := &unloadFake{loaded: []string{"alpha:1b"}, ignore: true}
	// Build the rig.
	rig := unloadRig(t, f)
	// Confirm.
	res := post(t, rig.h, "/unload/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// It must say the model is still loaded and must not claim success.
	if !strings.Contains(body, "still listed as loaded") || strings.Contains(body, "no longer lists") {
		// Report the problem.
		t.Errorf("wrong message: %s", body)
	} // end of the message check
} // end of TestUnloadStillLoaded

// TestUnloadNotLoaded checks a model that is not loaded is never sent an unload request (requirement S3).
func TestUnloadNotLoaded(t *testing.T) {
	// A fake with nothing loaded.
	f := &unloadFake{}
	// Build the rig.
	rig := unloadRig(t, f)
	// Both steps must refuse politely.
	for _, path := range []string{"/unload", "/unload/confirm"} {
		// Send it.
		res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
		// Read the page.
		body := bodyOf(res)
		// The page says there is nothing to unload and offers no unload form.
		if res.StatusCode != http.StatusOK || !strings.Contains(body, "nothing to unload") || strings.Contains(body, "/unload/confirm") {
			// Report the problem.
			t.Errorf("%s: status %d, body %s", path, res.StatusCode, body)
		} // end of the check
	} // end of the loop
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("%d unload requests were sent for a model that is not loaded", n)
	} // end of the call check
} // end of TestUnloadNotLoaded

// TestUnloadEscapesModelName checks a hostile model name can never become markup.
func TestUnloadEscapesModelName(t *testing.T) {
	// A fake with nothing loaded.
	f := &unloadFake{}
	// Build the rig.
	rig := unloadRig(t, f)
	// Send a name that contains a script tag.
	res := post(t, rig.h, "/unload", url.Values{"token": {rig.token}, "model": {"<script>alert(1)</script>"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// The tag must be escaped.
	if strings.Contains(body, "<script>") {
		// Report the problem.
		t.Errorf("the model name reached the page unescaped")
	} // end of the escape check
} // end of TestUnloadEscapesModelName

// TestUnloadRefusals checks every way a post can be refused on both routes, and that a refusal never reaches Ollama.
func TestUnloadRefusals(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// A table of cases.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// form is the posted form.
		form url.Values
		// headers are the request headers.
		headers map[string]string
		// want is the expected status.
		want int
	}{ // the cases follow
		// A page on another site posts the form.
		{"cross-site", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// A script without any browser headers.
		{"no origin headers", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{}, http.StatusForbidden},
		// The right origin but no token.
		{"missing token", url.Values{"model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
		// The right origin but a wrong token.
		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
		// No model name.
		{"no model", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
		// A model name that is far too long.
		{"model too long", url.Values{"token": {rig.token}, "model": {strings.Repeat("a", 400)}}, fromThisPage, http.StatusBadRequest},
		// A body larger than the 2 KB limit.
		{"too large", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Both routes must refuse in the same way.
		for _, path := range []string{"/unload", "/unload/confirm"} {
			// Run each case as a named subtest.
			t.Run(tc.name+" "+path, func(t *testing.T) {
				// Send it.
				res := post(t, rig.h, path, tc.form, tc.headers)
				// Compare the status.
				if res.StatusCode != tc.want {
					// Report the difference.
					t.Errorf("status %d, want %d", res.StatusCode, tc.want)
				} // end of the status check
			}) // end of the subtest
		} // end of the route loop
	} // end of the table loop
	// No refusal may have reached Ollama, and the model must still be loaded.
	if n := f.callCount(); n != 0 || len(f.loaded) != 1 {
		// Report the problem.
		t.Errorf("a refused request had an effect: %d calls, %d loaded", n, len(f.loaded))
	} // end of the effect check
} // end of TestUnloadRefusals

// TestUnloadRoutesNeedPost checks the unload addresses accept only POST, so a link or an image tag can never trigger them.
func TestUnloadRoutesNeedPost(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// Both addresses.
	for _, path := range []string{"/unload", "/unload/confirm"} {
		// A GET must be refused with 405.
		if status, _, _ := get(t, rig.h, http.MethodGet, path+"?model=alpha:1b"); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the check
	} // end of the loop
} // end of TestUnloadRoutesNeedPost

// TestUnloadOllamaDown checks a clear error page when Ollama cannot be read.
func TestUnloadOllamaDown(t *testing.T) {
	// A fake that works for the first page and is then closed.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Start it by hand so it can be closed.
	srv := f.start(t)
	// Build the handler and read the token.
	h := handlerFor(t, srv.URL)
	// Fetch the page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the token.
	token := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)[1]
	// Close the fake: Ollama is now unreachable.
	srv.Close()
	// Ask to unload.
	res := post(t, h, "/unload", url.Values{"token": {token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must be a 502 with a message and without the address.
	if b := bodyOf(res); res.StatusCode != http.StatusBadGateway || !strings.Contains(b, "Could not do this") || strings.Contains(b, srv.URL) {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, b)
	} // end of the check
} // end of TestUnloadOllamaDown

// TestUnloadStyles checks the stylesheet has the button rules in both themes.
func TestUnloadStyles(t *testing.T) {
	// The stylesheet text.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// The outlined button.
		"unload button": ".unload {",
		// It fills on hover.
		"unload hover": ".unload:hover",
		// Light colour.
		"light button colour": "--btn: #b3261e",
		// Dark colour.
		"dark button colour": "--btn: #ff8a80",
		// A visible keyboard focus.
		"focus ring": ".unload:focus-visible",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestUnloadStyles

// TestRemainingText checks the three kinds of "time left" wording.
func TestRemainingText(t *testing.T) {
	// A fixed "now" keeps the test steady.
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	// A table of cases.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// expires is the reported unload time.
		expires time.Time
		// ok says whether a time was reported.
		ok bool
		// want is the expected text.
		want string
	}{ // the cases follow
		// A normal countdown.
		{"soon", now.Add(4*time.Minute + 30*time.Second), true, "4 min 30 s"},
		// A model set to stay loaded forever reports a date centuries away.
		{"forever", time.Date(2318, 1, 1, 0, 0, 0, 0, time.UTC), true, "never on its own (it is set to stay loaded)"},
		// No time reported.
		{"unknown", time.Time{}, false, "not reported"},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Compare.
			if got := remainingText(now, tc.expires, tc.ok); got != tc.want {
				// Report the difference.
				t.Errorf("got %q, want %q", got, tc.want)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestRemainingText
EOF_UTEST

# Edit the existing files with a small Python program; the quoted EOF_PY25 marker saves every character exactly as typed.
python3 - << 'EOF_PY25'
# pathlib reads and writes the files.
import pathlib

# replace_once(file, old, new): swap text that must appear exactly once; stop with a message if it does not.
def replace_once(name, old, new):
    # Load the file.
    path = pathlib.Path(name)
    # Read its text.
    text = path.read_text()
    # Already changed earlier: the new text is in the file, so there is nothing to do (this keeps the script safe to run twice).
    if new in text:
        # Say so and leave the file alone.
        print("already done: " + name)
        # Stop this edit.
        return
    # The old text must be there exactly once, otherwise the file is not the one this script was made for.
    if text.count(old) != 1:
        # Stop with a clear message.
        raise SystemExit("cannot edit " + name + ": expected text found " + str(text.count(old)) + " times")
    # Write the changed text back.
    path.write_text(text.replace(old, new))
    # Say what happened.
    print("edited: " + name)

# The two unload routes are added to the router (web.go).
replace_once("web.go",
    "\tmux.HandleFunc(\"POST /theme\", themeHandler(token))\n",
    "\tmux.HandleFunc(\"POST /theme\", themeHandler(token))\n\t// Make the two unload handlers: the first asks \"are you sure?\", the second unloads (the checks are in unload.go).\n\tunloadAsk, unloadConfirm := unloadHandlers(addr, token)\n\t// Route: a POST request for \"/unload\" shows the warning page and changes nothing.\n\tmux.HandleFunc(\"POST /unload\", unloadAsk)\n\t// Route: a POST request for \"/unload/confirm\" unloads the model.\n\tmux.HandleFunc(\"POST /unload/confirm\", unloadConfirm)\n")
# The state cell of a loaded row gets the Unload button (web/index.html).
replace_once("web/index.html",
    "<td><span class=\"dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}\" aria-hidden=\"true\"></span> {{.StateWord}}</td>",
    "<td><span class=\"dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}\" aria-hidden=\"true\"></span> {{.StateWord}}\n{{- /* Only a loaded model gets the Unload button; it opens a warning page first, so one click never unloads anything. */ -}}\n{{if .Loaded}}\n{{/* A small form that sends the model name and the page token to the warning page. */}}\n<form class=\"unloadform\" method=\"post\" action=\"/unload\">\n{{/* The page token proves the form comes from this monitor. */}}\n<input type=\"hidden\" name=\"token\" value=\"{{$.Token}}\">\n{{/* The model name. */}}\n<input type=\"hidden\" name=\"model\" value=\"{{.Name}}\">\n{{/* The button: the symbol is hidden from screen readers, which read the label instead. */}}\n<button type=\"submit\" class=\"unload\" aria-label=\"Unload {{.Name}}\"><span aria-hidden=\"true\">⏏</span> Unload</button>\n{{/* End of the form. */}}\n</form>\n{{/* End of the loaded check. */}}\n{{end -}}\n</td>")
# The existing table test counted whole cells; the cell now also holds the button, so it counts the start of the cell (webtable_test.go).
replace_once("webtable_test.go",
    "`<td><span class=\"dot dot-on\" aria-hidden=\"true\"></span> Loaded</td>`",
    "`<td><span class=\"dot dot-on\" aria-hidden=\"true\"></span> Loaded\n`")

# The button styles go at the end of app.css, once (recognised by the ".unload {" rule).
path = pathlib.Path("web/app.css")
# Read the file.
text = path.read_text()
# Only add the rules when they are not there yet.
if "\n.unload {" not in text:
    # Append the rules.
    text += """
/* Button colours: a red that works on each theme (contrast 6.6:1 on white in light, 7.9:1 on the dark panel in dark). */
:root {
  /* Outline and text colour of the Unload button. */
  --btn: #b3261e;
  /* Text colour on the filled button. */
  --btn-text: #ffffff;
} /* end of rule */

/* The same two colours for a chosen dark theme. */
:root[data-theme="dark"] {
  /* Lighter red for dark backgrounds. */
  --btn: #ff8a80;
  /* Dark text on the light red fill. */
  --btn-text: #121417;
} /* end of rule */

/* The same two colours for the computer's own dark setting when no theme was chosen. */
@media (prefers-color-scheme: dark) {
  /* No theme chosen. */
  :root:not([data-theme="light"]):not([data-theme="dark"]) {
    /* Lighter red for dark backgrounds. */
    --btn: #ff8a80;
    /* Dark text on the light red fill. */
    --btn-text: #121417;
  } /* end of rule */
} /* end of rule */

/* The Unload form sits right after the state words, on the same line. */
.unloadform {
  /* Inline, so it follows the words. */
  display: inline;
  /* Room between the words and the button. */
  margin-left: 0.6rem;
} /* end of rule */

/* The Unload button: a red outlined pill that fills when pointed at. */
.unload {
  /* Use the page font. */
  font: inherit;
  /* A little smaller than the table text. */
  font-size: 0.8rem;
  /* Room inside the pill. */
  padding: 0.1rem 0.7rem;
  /* A solid outline in the button colour: visible without relying on fill. */
  border: 2px solid var(--btn);
  /* Pill shape. */
  border-radius: 999px;
  /* Empty inside until hovered. */
  background: transparent;
  /* Text in the button colour. */
  color: var(--btn);
  /* A hand cursor. */
  cursor: pointer;
} /* end of rule */

/* Pointed at or keyboard-focused: fill the pill. */
.unload:hover, .unload:focus-visible {
  /* Fill with the button colour. */
  background: var(--btn);
  /* Text switches to the contrast colour. */
  color: var(--btn-text);
} /* end of rule */

/* A clear ring for keyboard users. */
.unload:focus-visible, .btn-solid:focus-visible, .btn-plain:focus-visible {
  /* A ring outside the button. */
  outline: 3px solid var(--text);
  /* A gap between button and ring. */
  outline-offset: 2px;
} /* end of rule */

/* The two choices on the warning page, side by side. */
.choices {
  /* In a row. */
  display: flex;
  /* Wrap on narrow screens. */
  flex-wrap: wrap;
  /* Centre the items vertically. */
  align-items: center;
  /* Space between them. */
  gap: 1rem;
} /* end of rule */

/* The confirming button: filled with the button colour. */
.btn-solid {
  /* Use the page font. */
  font: inherit;
  /* Room inside. */
  padding: 0.4rem 1rem;
  /* Outline in the button colour. */
  border: 2px solid var(--btn);
  /* Pill shape. */
  border-radius: 999px;
  /* Filled. */
  background: var(--btn);
  /* Contrast text. */
  color: var(--btn-text);
  /* A hand cursor. */
  cursor: pointer;
} /* end of rule */

/* The safe choice: a plain outlined link that looks like a button. */
.btn-plain {
  /* Room inside. */
  padding: 0.4rem 1rem;
  /* Outline in the text colour. */
  border: 2px solid var(--border);
  /* Pill shape. */
  border-radius: 999px;
  /* Text colour. */
  color: var(--text);
  /* No underline. */
  text-decoration: none;
} /* end of rule */
"""
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: web/app.css (added the unload button rules)")
EOF_PY25

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run every test quietly; a failure stops the script and shows Go's own message (-count=1 forces a fresh run).
go test -count=1 ./... 2>&1 | grep -v 'TLS handshake'
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build and tests worked.
echo "PASS  tests and build"

# Refuse to run if something on this machine already listens on the page-check port (-H hides the header, so any output means in use).
if [ -n "$(ss -ltnH "sport = :$TEST_PORT")" ]; then
  # Explain the problem and stop.
  echo "IN USE: something is already listening on port $TEST_PORT; set TEST_PORT to another port" >&2; exit 1
fi # end of the host port check
# Read the ports published by Docker containers, running and stopped (|| true: carry on if Docker is not available to this user).
DOCKER_PORTS="$(docker ps -a --format '{{.Ports}}' 2> /dev/null || true)"
# Look for the test port in that list (a here-string, not a pipe, so there is no early-exit problem).
if grep -q ":$TEST_PORT->" <<< "$DOCKER_PORTS"; then
  # Explain the problem and stop.
  echo "IN USE: a Docker container publishes port $TEST_PORT; set TEST_PORT to another port" >&2; exit 1
fi # end of the Docker port check
# Start the monitor in the background on the spare port, watching the chosen Ollama; its messages are discarded.
OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -listen "127.0.0.1:$TEST_PORT" -ollama-url "$OLLAMA_TEST_URL" > /dev/null 2>&1 &
# Remember the background process so it can be stopped.
PID=$!
# Stop the monitor when the script ends for any reason.
trap 'kill "$PID" 2> /dev/null || true' EXIT
# Wait up to 5 seconds for the page to answer.
for _ in $(seq 1 50); do
  # Any answer at all means it is up.
  if curl -s -o /dev/null "http://127.0.0.1:$TEST_PORT/"; then break; fi # end of the answer check
  # Wait a moment before asking again.
  sleep 0.1
done # end of the waiting loop

# The page address used by every check below.
BASE="http://127.0.0.1:$TEST_PORT"
# Fetch the page once (-s hides the progress bar).
PAGE="$(curl -s "$BASE/")"
# Read the page token (grep -o prints only the match, sed keeps only the 32 characters; || true so a missing token is reported by the checks, not by stopping here).
TOKEN="$(grep -o 'name="token" value="[0-9a-f]*"' <<< "$PAGE" | head -n 1 | sed 's/.*value="//; s/"//' || true)"
# Ask Ollama itself which models are loaded (|| true: an unreachable Ollama is reported by the checks).
PS="$(curl -s "$OLLAMA_TEST_URL/api/ps" || true)"
# The name of the first loaded model, or nothing when none is loaded.
LOADED_NAME="$(grep -o '"name":"[^"]*"' <<< "$PS" | head -n 1 | sed 's/"name":"//; s/"//' || true)"
# How many models are loaded (counting name fields in the /api/ps answer).
LOADED_COUNT="$(grep -o '"name":"' <<< "$PS" | wc -l || true)"
# How many Unload buttons the page shows.
BUTTONS="$(grep -o 'class="unload"' <<< "$PAGE" | wc -l || true)"

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL RESULT: prints PASS when the result is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check
# status ARGS...: prints only the HTTP status number of a request made with the given curl arguments.
status() {
  # -s hides the progress bar, -o drops the body, -w prints the status number.
  curl -s -o /dev/null -w '%{http_code}' "$@"
} # end of status

# Say what the real Ollama has loaded, so the checks can be read in context.
echo "info  loaded models seen by Ollama: $LOADED_COUNT; Unload buttons on the page: $BUTTONS"
# Check 1: there is exactly one Unload button per loaded model.
check "one Unload button per loaded model" "$([ "$BUTTONS" = "$LOADED_COUNT" ] && echo yes || echo no)"
# Check 2: a post without browser headers (a script or curl) cannot even open the warning page.
check "warning page refuses a post without browser headers (403)" "$([ "$(status -d "model=x&token=$TOKEN" "$BASE/unload")" = "403" ] && echo yes || echo no)"
# Check 3: the unload step refuses a post without browser headers.
check "unload step refuses a post without browser headers (403)" "$([ "$(status -d "model=x&token=$TOKEN" "$BASE/unload/confirm")" = "403" ] && echo yes || echo no)"
# Check 4: a post from another site is refused.
check "unload step refuses a post from another site (403)" "$([ "$(status -H 'Sec-Fetch-Site: cross-site' -d "model=x&token=$TOKEN" "$BASE/unload/confirm")" = "403" ] && echo yes || echo no)"
# Check 5: a post from this page with a wrong token is refused.
check "unload step refuses a wrong token (403)" "$([ "$(status -H 'Sec-Fetch-Site: same-origin' -d 'model=x&token=00000000000000000000000000000000' "$BASE/unload/confirm")" = "403" ] && echo yes || echo no)"
# Check 6: the two addresses accept only POST.
check "GET to /unload and /unload/confirm is refused (405)" "$([ "$(status "$BASE/unload")" = "405" ] && [ "$(status "$BASE/unload/confirm")" = "405" ] && echo yes || echo no)"
# Check 7: a model that is not loaded gets the "nothing to unload" page and no Yes button (requirement S3).
NOTLOADED="$(curl -s -H 'Sec-Fetch-Site: same-origin' --data-urlencode "token=$TOKEN" --data-urlencode "model=no-such-model:0" "$BASE/unload")"
# Both words must be there and the confirm form must not.
check "a model that is not loaded gets 'nothing to unload' and no Yes button" "$(grep -q 'nothing to unload' <<< "$NOTLOADED" && ! grep -q '/unload/confirm' <<< "$NOTLOADED" && echo yes || echo no)"
# Check 8: for a loaded model (if there is one) the warning page appears AND the model is still loaded afterwards.
if [ -n "$LOADED_NAME" ]; then
  # Open the warning page for the first loaded model.
  ASK="$(curl -s -H 'Sec-Fetch-Site: same-origin' --data-urlencode "token=$TOKEN" --data-urlencode "model=$LOADED_NAME" "$BASE/unload")"
  # Ask Ollama again.
  PS_AFTER="$(curl -s "$OLLAMA_TEST_URL/api/ps" || true)"
  # The warning and the Yes form must be there, and the model must still be loaded.
  check "warning page for $LOADED_NAME shows the warning, and the model stays loaded" "$(grep -q 'Before you continue' <<< "$ASK" && grep -q '/unload/confirm' <<< "$ASK" && grep -q "\"name\":\"$LOADED_NAME\"" <<< "$PS_AFTER" && echo yes || echo no)"
else
  # Nothing is loaded, so this check cannot run; say so instead of pretending.
  echo "skip  warning page check: no model is loaded (load one with scripts/21-load-model.sh to include it)"
fi # end of the loaded check
# Ask for the safety headers of the page (-D - prints the headers; -o /dev/null drops the body).
HEADERS="$(curl -s -D - -o /dev/null "$BASE/")"
# Check 9: still no script rule in the policy, and the page has no script or inline style.
check "policy has no script-src and the page has no script or inline style" "$(! grep -qi 'script-src' <<< "$HEADERS" && ! grep -qiE '<script|<style| style=' <<< "$PAGE" && echo yes || echo no)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
