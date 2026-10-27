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

// postJSON sends one JSON body with the POST method; it is the short form of sendJSON that every earlier feature uses.
func postJSON(ctx context.Context, base *url.URL, path string, timeout time.Duration, payload any) (int, error) {
	// Hand over to the general function with the POST method.
	return sendJSON(ctx, http.MethodPost, base, path, timeout, payload)
} // end of postJSON

// sendJSON sends one JSON body to base+path with the given method (POST, or DELETE for removing a model) and returns only the status number; every error text is fixed and never contains the address.
func sendJSON(ctx context.Context, method string, base *url.URL, path string, timeout time.Duration, payload any) (int, error) {
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
	req, err := http.NewRequestWithContext(ctx, method, target, bytes.NewReader(body))
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
} // end of sendJSON

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
	// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.
	Seconds int
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
		// A page with a ticking timer may run the monitor's own script, and nothing else.
		if data.Seconds > 0 {
			// Replace the strict policy by the one that allows the script file.
			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
		} // end of the script policy
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
		show(w, r, http.StatusOK, unloadPage{Kind: "confirm", Model: name, Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK)})
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
