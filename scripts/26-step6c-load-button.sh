#!/usr/bin/env bash
# Script 26: Step 6c, the Load button for models that are not loaded, with a memory warning, and a live countdown on the Unload and Load message pages.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with scripts 05, 19, 20, 22, 24 and 25.
TEST_PORT="${TEST_PORT:-18772}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write memory.go (free memory reading); the quoted marker saves every character exactly as typed.
cat > memory.go << 'EOF_MEM'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// errors builds fixed error messages.
	"errors"
	// net/url holds the parsed address type.
	"net/url"
	// os reads files.
	"os"
	// strconv turns the number text into a number.
	"strconv"
	// strings splits the file into lines.
	"strings"
) // end of imports

// meminfoPath is the Linux file that lists the computer's memory.
const meminfoPath = "/proc/meminfo"

// availableMemoryFunc reads the free memory; it is a variable so tests can replace it.
var availableMemoryFunc = availableMemory

// parseMemAvailable finds the MemAvailable line in the text of /proc/meminfo and returns its value in bytes; the second result is false when the line is missing or unreadable.
func parseMemAvailable(text string) (int64, bool) {
	// Look at every line.
	for _, line := range strings.Split(text, "\n") {
		// The line looks like "MemAvailable:   12345678 kB".
		if !strings.HasPrefix(line, "MemAvailable:") {
			// Not the line we want.
			continue
		} // end of the prefix check
		// Split it into words: the name, the number and the unit.
		f := strings.Fields(line)
		// There must be a number and the unit kB.
		if len(f) != 3 || f[2] != "kB" {
			// An unknown layout: say "unknown" instead of guessing.
			return 0, false
		} // end of the layout check
		// Read the number.
		kb, err := strconv.ParseInt(f[1], 10, 64)
		// A bad number or a negative one.
		if err != nil || kb < 0 {
			// Unknown.
			return 0, false
		} // end of the number check
		// The file counts in kibibytes (1024 bytes).
		return kb * 1024, true
	} // end of the line loop
	// The line was not found.
	return 0, false
} // end of parseMemAvailable

// availableMemory returns how much memory programs can still use on this computer, in bytes (Linux only; other systems report an error).
func availableMemory() (int64, error) {
	// Read the file; on systems without it this fails, which is reported as unknown.
	data, err := os.ReadFile(meminfoPath)
	// No file.
	if err != nil {
		// A fixed message.
		return 0, errors.New("this system does not report its free memory")
	} // end of the read check
	// Find the value.
	n, ok := parseMemAvailable(string(data))
	// Not found.
	if !ok {
		// A fixed message.
		return 0, errors.New("the free memory could not be read")
	} // end of the parse check
	// Hand it back.
	return n, nil
} // end of availableMemory

// ollamaIsLocal says whether the monitored Ollama runs on this same computer, so that this computer's free memory is the right number to show.
func ollamaIsLocal(u *url.URL) bool {
	// The host name without the port.
	switch u.Hostname() {
	// The three names a computer uses for itself.
	case "127.0.0.1", "localhost", "::1":
		// Same computer.
		return true
	} // end of the switch
	// Anything else may be another computer.
	return false
} // end of ollamaIsLocal
EOF_MEM

# Write countdown.go (the script route, the policy for pages with a timer, the seconds helper).
cat > countdown.go << 'EOF_CD'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// net/http provides requests and status codes.
	"net/http"
	// time provides durations.
	"time"
) // end of imports

// countdownJS is the small script that makes the timers tick, stored inside the executable at build time (requirement T3).
//
//go:embed web/countdown.js
var countdownJS []byte

// contentSecurityPolicyWithScript is the policy for the message pages that show a ticking timer: the same as the main page plus scripts from this same address only (no inline scripts, no other sites).
const contentSecurityPolicyWithScript = "default-src 'none'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

// countdownHandler sends the script file.
func countdownHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser this is JavaScript.
	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	// Send it.
	w.Write(countdownJS)
} // end of countdownHandler

// remainingSeconds is the time left in whole seconds for the ticking timer; 0 means "no countdown" (no time reported, already past, or a model set to stay loaded).
func remainingSeconds(now, expires time.Time, ok bool) int {
	// No usable time.
	if !ok {
		// No countdown.
		return 0
	} // end of the no-time case
	// How long is left.
	left := expires.Sub(now)
	// Past, or so far away that the model is set to stay loaded.
	if left <= 0 || left > 30*24*time.Hour {
		// No countdown.
		return 0
	} // end of the range check
	// Round to whole seconds.
	return int(left.Round(time.Second).Seconds())
} // end of remainingSeconds
EOF_CD

# Write web/countdown.js (the small script that makes the timers tick).
cat > web/countdown.js << 'EOF_JS'
// Countdown: makes every element marked class="countdown" and data-seconds="N" count down once a second, starting from the number the monitor wrote into the page.
(function () {
  // Remember when this page was opened, using the browser's steady clock (it ignores clock changes and any clock difference with Ollama).
  var start = performance.now();
  // Find every timer on the page.
  var items = document.querySelectorAll('.countdown[data-seconds]');
  // Nothing to do when there is no timer.
  if (items.length === 0) {
    // Stop here.
    return;
  }
  // Turn a number of seconds into the same wording the monitor uses: "4 min 30 s", "1 h 5 min" or "20 s".
  function words(total) {
    // Whole hours.
    var h = Math.floor(total / 3600);
    // Whole minutes left over.
    var m = Math.floor((total % 3600) / 60);
    // Seconds left over.
    var s = total % 60;
    // With hours, show hours and minutes.
    if (h > 0) {
      // Hours and minutes.
      return h + ' h ' + m + ' min';
    }
    // With minutes, show minutes and seconds.
    if (m > 0) {
      // Minutes and seconds.
      return m + ' min ' + s + ' s';
    }
    // Otherwise only seconds.
    return s + ' s';
  }
  // Update every timer once.
  function tick() {
    // Seconds since the page opened.
    var elapsed = (performance.now() - start) / 1000;
    // Go through the timers.
    items.forEach(function (el) {
      // Seconds left: the number the monitor wrote minus the time passed, rounded up so 0 appears only at the end.
      var left = Math.ceil(Number(el.getAttribute('data-seconds')) - elapsed);
      // Show the time, or say the unload time has arrived.
      el.textContent = left > 0 ? words(left) : 'unloading now';
    });
  }
  // Show the first value at once, then every second.
  tick();
  // Repeat once a second.
  setInterval(tick, 1000);
})();
EOF_JS

# Write load.go (the two load steps and the memory figures).
cat > load.go << 'EOF_LOAD'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes holds the finished page.
	"bytes"
	// context lets a request be cancelled or given a deadline.
	"context"
	// embed lets the load page template be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// fmt builds formatted text.
	"fmt"
	// html/template builds HTML and escapes every inserted value.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// time provides durations and pauses.
	"time"
) // end of imports

// loadTemplateText is the load page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/load.html
var loadTemplateText string

// loadTimeout is how long the load request may take; loading a large model from disk can take minutes.
const loadTimeout = 5 * time.Minute

// loadVerifyWait is how long the monitor keeps asking whether the model is listed after the load request returned (a variable so tests can make it short).
var loadVerifyWait = 10 * time.Second

// defaultKeepText is Ollama's built-in time to keep a model loaded after its last use (from Ollama's FAQ); a server can be set to another value, which only the real countdown after loading shows.
const defaultKeepText = "5 minutes"

// tightFactor decides when free memory counts as "close": less than this many times the model's size.
const tightFactor = 1.25

// loadModel asks Ollama to load one model now, without a prompt and without a keep-alive setting, so Ollama's own default time applies; it returns which request worked.
func loadModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) (string, error) {
	// Chat and text models are loaded through /api/generate with no prompt (the documented way to preload).
	status, err := postJSON(ctx, base, "api/generate", timeout, map[string]any{"model": name})
	// No answer at all.
	if err != nil {
		// Pass the safe error on.
		return "", err
	} // end of the send check
	// Status 200 means the model is loaded.
	if status == http.StatusOK {
		// Report which request worked.
		return "generate", nil
	} // end of the success case
	// Status 400 is what a model that cannot generate text (an embedding model, for example) answers; try the embedding request instead.
	if status == http.StatusBadRequest {
		// The one-word input is only there because an embedding request needs some input.
		status2, err2 := postJSON(ctx, base, "api/embed", timeout, map[string]any{"model": name, "input": "load"})
		// No answer at all.
		if err2 != nil {
			// Pass the safe error on.
			return "", err2
		} // end of the second send check
		// Status 200 means the model is loaded.
		if status2 == http.StatusOK {
			// Report which request worked.
			return "embed", nil
		} // end of the second success case
		// Both requests were refused; report both numbers.
		return "", fmt.Errorf("Ollama refused both load requests (status %d and status %d)", status, status2)
	} // end of the 400 case
	// Any other status.
	return "", fmt.Errorf("Ollama answered the load request with status %d", status)
} // end of loadModel

// waitUntilLoaded asks Ollama until the model appears in the loaded list, for a limited time, and returns its entry.
func waitUntilLoaded(ctx context.Context, base *url.URL, name string, timeout time.Duration) (loadedModel, bool, error) {
	// The moment to stop asking.
	deadline := time.Now().Add(loadVerifyWait)
	// Ask until the deadline.
	for {
		// Read the loaded list.
		list, err := fetchLoaded(ctx, base, timeout)
		// A failure to read means we cannot say.
		if err != nil {
			// Pass the safe error on.
			return loadedModel{}, false, err
		} // end of the read check
		// The model is in the list.
		if m, ok := findLoaded(list, name); ok {
			// Done: it is loaded.
			return m, true, nil
		} // end of the found check
		// Out of time: not listed.
		if time.Now().After(deadline) {
			// Report that it is not there.
			return loadedModel{}, false, nil
		} // end of the deadline check
		// Wait a little, or stop at once if the browser went away.
		select {
		// The browser closed the request.
		case <-ctx.Done():
			// Give up.
			return loadedModel{}, false, ctx.Err()
		// The pause is over.
		case <-time.After(unloadVerifyStep):
		} // end of the wait
	} // end of the loop
} // end of waitUntilLoaded

// findInstalled returns the installed model with the given name; the second result is false when it is not installed.
func findInstalled(list []installedModel, name string) (installedModel, bool) {
	// Look at every installed model.
	for _, m := range list {
		// A match by exact name.
		if m.Name == name {
			// Found it.
			return m, true
		} // end of the name check
	} // end of the loop
	// Not installed.
	return installedModel{}, false
} // end of findInstalled

// loadPage is everything the load page template can show.
type loadPage struct {
	// Kind says which version of the page to draw: confirm, alreadyloaded, notinstalled, done, stillnotloaded or error.
	Kind string
	// Model is the model name.
	Model string
	// NeedText is the memory the model needs at least, such as 3.3 GB.
	NeedText string
	// AvailText is the free memory now, such as 12.4 GB; empty when it is unknown.
	AvailText string
	// MemNote explains why the free memory is unknown.
	MemNote string
	// Level is "short" when free memory is below the model's size, "tight" when it is close, and empty otherwise.
	Level string
	// DefaultText is the default time the model stays loaded.
	DefaultText string
	// Remaining is the time left before Ollama unloads the model by itself (done page).
	Remaining string
	// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.
	Seconds int
	// Detail is the plain reason shown on the error page.
	Detail string
	// Theme is the saved theme choice, as on the main page.
	Theme string
	// Token is the page token for the forms on this page.
	Token string
} // end of loadPage

// memoryLevel compares free memory with the model's size and returns "short", "tight" or "".
func memoryLevel(avail, need int64) string {
	// Less free memory than the model's size.
	if avail < need {
		// Not enough.
		return "short"
	} // end of the short case
	// Free memory is below the model's size times the factor.
	if float64(avail) < float64(need)*tightFactor {
		// Close.
		return "tight"
	} // end of the tight case
	// Plenty.
	return ""
} // end of memoryLevel

// memoryFacts works out what the load page says about free memory: the free memory text, the reason when it is unknown, and the warning level.
func memoryFacts(u *url.URL, need int64) (avail, note, level string) {
	// Free memory is only meaningful when Ollama runs on this same computer.
	if !ollamaIsLocal(u) {
		// Say why it is not shown.
		return "", "Ollama runs on another computer, and this monitor can read only the memory of the computer it runs on", ""
	} // end of the remote case
	// Read this computer's free memory.
	n, err := availableMemoryFunc()
	// It could not be read.
	if err != nil {
		// Say why it is not shown.
		return "", err.Error(), ""
	} // end of the failure case
	// Show it and compare.
	return formatSize(n), "", memoryLevel(n, need)
} // end of memoryFacts

// loadHandlers builds the two handlers: the first shows the memory warning (it changes nothing), the second does the load.
func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc) {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("load").Parse(loadTemplateText))
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data loadPage) {
		// Add what every version of the page needs.
		data.Theme, data.Token, data.DefaultText = themeFromRequest(r), token, defaultKeepText
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("load page error: %v", err)
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
	// check runs the checks both steps share: the model must be installed and not loaded yet; it returns the installed model, or false after the page was already shown.
	check := func(w http.ResponseWriter, r *http.Request, name string) (installedModel, bool) {
		// Read the installed models now, not what the page showed earlier.
		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return installedModel{}, false
		} // end of the installed read check
		// The model must exist.
		m, found := findInstalled(installed, name)
		// Not installed.
		if !found {
			// Say so.
			show(w, r, http.StatusOK, loadPage{Kind: "notinstalled", Model: name})
			// Stop here.
			return installedModel{}, false
		} // end of the installed check
		// Read the loaded models.
		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return installedModel{}, false
		} // end of the loaded read check
		// Already loaded: nothing to do.
		if _, ok := findLoaded(loaded, name); ok {
			// Say so.
			show(w, r, http.StatusOK, loadPage{Kind: "alreadyloaded", Model: name})
			// Stop here.
			return installedModel{}, false
		} // end of the loaded check
		// All good.
		return m, true
	} // end of check
	// ask is the first step: it shows the memory figures and the default time with a Yes and a Cancel button; it never loads anything.
	ask := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Run the model checks.
		m, ok := check(w, r, name)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the model checks
		// Start the page data with the memory the model needs at least: its size on disk (the real use is higher once the context memory is added).
		data := loadPage{Kind: "confirm", Model: name, NeedText: formatSize(m.Size)}
		// Fill in the memory figures.
		data.AvailText, data.MemNote, data.Level = memoryFacts(addr.URL, m.Size)
		// Show the page.
		show(w, r, http.StatusOK, data)
	} // end of ask
	// confirm is the second step: it checks again, loads, and then reads the real unload time from Ollama.
	confirm := func(w http.ResponseWriter, r *http.Request) {
		// Run the shared form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Run the model checks again: things may have changed since the warning page.
		if _, ok := check(w, r, name); !ok {
			// A page was already shown.
			return
		} // end of the model checks
		// Ask Ollama to load it; this call returns when loading is finished, which can take a while.
		if _, err := loadModel(r.Context(), addr.URL, name, loadTimeout); err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the load check
		// Do not trust the 200 alone: ask until the model is in the loaded list.
		m, found, err := waitUntilLoaded(r.Context(), addr.URL, name, defaultCheckTimeout)
		// The list could not be read afterwards.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, loadPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the verify check
		// Not listed: say so honestly.
		if !found {
			// Show that page.
			show(w, r, http.StatusOK, loadPage{Kind: "stillnotloaded", Model: name})
			// Stop here.
			return
		} // end of the not-listed case
		// Read the real unload time that Ollama reports for the loaded model.
		exp, expOK := m.expiresTime()
		// Show the result with the live timer.
		show(w, r, http.StatusOK, loadPage{Kind: "done", Model: name, Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK)})
	} // end of confirm
	// Hand both back.
	return ask, confirm
} // end of loadHandlers

// readModelForm runs the checks the load forms share (same rules as the unload forms): origin, form, token and model name; ok is false when a refusal was already sent.
func readModelForm(w http.ResponseWriter, r *http.Request, token string) (string, bool) {
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
} // end of readModelForm
EOF_LOAD

# Write web/load.html (the load message page).
cat > web/load.html << 'EOF_LHTML'
{{/* Load page template: one page with six versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
<!DOCTYPE html>
{{/* lang tells screen readers which language the page is written in. */}}
<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
<head>{{/* start of the head. */}}
{{/* Text encoding. */}}
<meta charset="utf-8">
{{/* Fit the page to the width of the screen on phones. */}}
<meta name="viewport" content="width=device-width, initial-scale=1">
{{/* The title shown on the browser tab. */}}
<title>Load a model - OllamaControlCenter</title>
{{/* Our one stylesheet. */}}
<link rel="stylesheet" href="/app.css">
</head>{{/* end of the head. */}}
<body>{{/* start of the visible page. */}}
{{/* The page content. */}}
<main>
{{/* A panel that holds the message. */}}
<section class="panel">
{{/* The heading names the model, so there is no doubt which one is meant. */}}
<h1>Load <code>{{.Model}}</code></h1>
{{/* Version 1: the model can be loaded and the person must confirm. */}}
{{if eq .Kind "confirm"}}
{{/* A warning first, when free memory is short or close. */}}
{{if eq .Level "short"}}
{{/* The warning has a symbol and a bold lead, so colour is never the only signal. */}}
<p class="warn"><strong>⚠ Not enough free memory.</strong> The free memory is less than this model needs. Loading it can slow down or disturb the applications that are running now.</p>
{{/* The milder warning. */}}
{{else if eq .Level "tight"}}
{{/* The same kind of marking. */}}
<p class="warn"><strong>⚠ Free memory is close to what this model needs.</strong> The real use is higher than the figure below, so other running applications may slow down.</p>
{{/* End of the warnings. */}}
{{end}}
{{/* The facts in a small table. */}}
<table class="facts">
{{/* Row 1: free memory. */}}
<tr><th scope="row">Free memory now</th><td>{{if .AvailText}}{{.AvailText}}{{else}}not known{{if .MemNote}} ({{.MemNote}}){{end}}{{end}}</td></tr>
{{/* Row 2: memory needed. */}}
<tr><th scope="row">This model needs at least</th><td>{{.NeedText}} (its size on disk; the real use is higher once the memory for the conversation context is added)</td></tr>
{{/* Row 3: the default time. */}}
<tr><th scope="row">Stays loaded after loading</th><td>Ollama's default is {{.DefaultText}} after the last use, then it unloads the model by itself. Your Ollama may be set to another time; the real countdown appears as soon as the model is loaded.</td></tr>
{{/* End of the facts. */}}
</table>
{{/* A hint about the waiting time. */}}
<p class="muted">Loading a large model can take a minute or more. This page waits until Ollama is done.</p>
{{/* The advice. */}}
<p>Only continue if you are happy to use this memory now.</p>
{{/* The two choices side by side. */}}
<div class="choices">
{{/* The Yes form sends the model name and the page token to the second step. */}}
<form method="post" action="/load/confirm">
{{/* The page token proves the form comes from this monitor. */}}
<input type="hidden" name="token" value="{{.Token}}">
{{/* The model name. */}}
<input type="hidden" name="model" value="{{.Model}}">
{{/* The Yes button. */}}
<button type="submit" class="btn-load">Yes, load it now</button>
{{/* End of the Yes form. */}}
</form>
{{/* The Cancel link simply goes back; nothing was changed. */}}
<a class="btn-plain" href="/">Cancel, do not load</a>
{{/* End of the choices. */}}
</div>
{{/* Version 2: the model is loaded already. */}}
{{else if eq .Kind "alreadyloaded"}}
{{/* Say so. */}}
<p>This model is already loaded, so there is nothing to load.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 3: the model is not installed. */}}
{{else if eq .Kind "notinstalled"}}
{{/* Say so. */}}
<p>This model is not installed, so it cannot be loaded.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 4: the load worked. */}}
{{else if eq .Kind "done"}}
{{/* Say so; it was checked afterwards. */}}
<p><strong>Done.</strong> Ollama lists this model as loaded.</p>
{{/* The live timer: it ticks down once a second, and shows the plain text when the script cannot run. */}}
<p class="muted">Ollama unloads it by itself in: <span class="countdown"{{if .Seconds}} data-seconds="{{.Seconds}}"{{end}}>{{.Remaining}}</span>.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 5: Ollama accepted the request but the model is not listed. */}}
{{else if eq .Kind "stillnotloaded"}}
{{/* Say exactly what is known and what is not. */}}
<p><strong>Not listed yet.</strong> Ollama accepted the request, but the model is not in its loaded list. Reload the monitor page in a moment to check.</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* Version 6: something went wrong. */}}
{{else}}
{{/* Say what went wrong, in the plain words the program already uses. */}}
<p><strong>Could not do this.</strong> {{.Detail}}</p>
{{/* A link back. */}}
<p><a class="btn-plain" href="/">Back to the monitor</a></p>
{{/* End of the six versions. */}}
{{end}}
{{/* End of the panel. */}}
</section>
{{/* End of the content. */}}
</main>
{{/* The ticking timer needs the monitor's own script; it is included only when there is a timer to tick. */}}
{{if .Seconds}}<script src="/countdown.js" defer></script>{{end}}
</body>{{/* end of the visible page. */}}
</html>{{/* end of the page. */}}
EOF_LHTML

# Write load_test.go.
cat > load_test.go << 'EOF_LTEST'
// Package main tells Go that this test file belongs to the same program as load.go, memory.go and countdown.go.
package main

import ( // import lists the packages this test file uses.
	// errors builds a fake memory failure.
	"errors"
	// io reads request bodies in the fake Ollama.
	"io"
	// net/http provides requests and status codes.
	"net/http"
	// net/http/httptest records replies and runs the fake Ollama.
	"net/http/httptest"
	// net/url builds form data and parsed addresses.
	"net/url"
	// regexp finds the token in the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records, because the server runs in its own goroutine.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
	// time shortens the waiting time in the tests and builds times.
	"time"
) // end of imports

// loadFake is a fake Ollama that remembers what it was asked and can pretend to load and unload models.
type loadFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// loaded is the list of names that /api/ps reports.
	loaded []string
	// calls records "path body" for every POST.
	calls []string
	// generateStatus is the status that /api/generate answers (200 unless a test changes it).
	generateStatus int
	// ignore makes the fake accept load requests without actually loading.
	ignore bool
} // end of loadFake

// start runs the fake as a server and returns it.
func (f *loadFake) start(t *testing.T) *httptest.Server {
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
		// The installed list: a 3.3 GB chat model and a 2 GB embedding model.
		case "/api/tags":
			// Two models.
			w.Write([]byte(`{"models":[{"name":"alpha:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]}]}`))
		// The loaded list.
		case "/api/ps":
			// Build the list from the fake's state.
			parts := []string{}
			// Five minutes from now, the way a default load reports it.
			exp := time.Now().Add(5 * time.Minute).UTC().Format(time.RFC3339)
			// Every loaded name.
			for _, n := range f.loaded {
				// One entry.
				parts = append(parts, `{"name":"`+n+`","size":5,"expires_at":"`+exp+`"}`)
			} // end of the loop
			// Send the list.
			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
		// The load and unload requests.
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
			// A request without keep_alive loads; the model name is between the quotes after "model":.
			if !f.ignore && !strings.Contains(string(b), "keep_alive") {
				// Take the name out of the body.
				name := regexp.MustCompile(`"model":"([^"]*)"`).FindStringSubmatch(string(b))[1]
				// Add it to the loaded list.
				f.loaded = append(f.loaded, name)
			} // end of the load
			// Accept.
			w.Write([]byte(`{}`))
		// Anything else.
		default:
			// Not found.
			http.NotFound(w, r)
		} // end of the switch
	}) // end of the server
} // end of start

// callCount says how many load or unload requests the fake has received.
func (f *loadFake) callCount() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return len(f.calls)
} // end of callCount

// loadRig builds a handler on top of the fake, fixes the free memory to the given value (a negative value means "cannot be read") and finds the page token.
func loadRig(t *testing.T, f *loadFake, avail int64) themeRig {
	// Mark this as a helper.
	t.Helper()
	// Keep the old settings and restore them afterwards.
	oldWait, oldMem := loadVerifyWait, availableMemoryFunc
	// Restore at the end.
	t.Cleanup(func() { loadVerifyWait, availableMemoryFunc = oldWait, oldMem })
	// Short waiting, so the tests stay quick.
	loadVerifyWait = 500 * time.Millisecond
	// The pretend memory reading.
	availableMemoryFunc = func() (int64, error) {
		// A negative value means the memory cannot be read.
		if avail < 0 {
			// A fixed message.
			return 0, errors.New("this system does not report its free memory")
		} // end of the failure case
		// The pretend value.
		return avail, nil
	} // end of the pretend reading
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
} // end of loadRig

// TestLoadButtonOnlyOnNotLoadedRows checks the Load button appears for the not-loaded model and not for the loaded one.
func TestLoadButtonOnlyOnNotLoadedRows(t *testing.T) {
	// One model loaded, one not.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// Exactly one load form, for the embedding model.
	if n := strings.Count(body, `action="/load"`); n != 1 {
		// Report the difference.
		t.Errorf("load forms = %d, want 1", n)
	} // end of the count
	// It names the right model and has an accessible name.
	for _, want := range []string{`name="model" value="embed:1b"`, `aria-label="Load embed:1b"`, `class="load"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The loaded model has an Unload button and no Load button.
	if strings.Contains(body, `aria-label="Load alpha:1b"`) {
		// Report the problem.
		t.Errorf("a loaded model has a Load button")
	} // end of the other check
	// The main page itself must stay free of scripts and keep the strict policy.
	if strings.Contains(body, "<script") {
		// Report the problem.
		t.Errorf("the main page contains a script")
	} // end of the script check
} // end of TestLoadButtonOnlyOnNotLoadedRows

// TestLoadAskShowsMemoryAndChangesNothing checks the first step shows the figures and sends no load request.
func TestLoadAskShowsMemoryAndChangesNothing(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Plenty of memory: 16 GB free.
	rig := loadRig(t, f, 16e9)
	// Ask to load the 3.3 GB model.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// Read the page.
	body := bodyOf(res)
	// The figures and the default time must be there.
	for _, want := range []string{"16.0 GB", "3.3 GB", "Ollama's default is 5 minutes", `action="/load/confirm"`, "Cancel, do not load"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("confirm page lacks %q", want)
		} // end of the check
	} // end of the loop
	// With plenty of memory there is no warning.
	if strings.Contains(body, "⚠") {
		// Report the problem.
		t.Errorf("a warning was shown although memory is plentiful")
	} // end of the warning check
	// This page has no timer to tick, so no script and the strict policy.
	if strings.Contains(body, "<script") || strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src") {
		// Report the problem.
		t.Errorf("the load warning page allows or contains a script")
	} // end of the script check
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 || len(f.loaded) != 0 {
		// Report the problem.
		t.Errorf("the first step had an effect: %d calls, %d loaded", n, len(f.loaded))
	} // end of the effect check
} // end of TestLoadAskShowsMemoryAndChangesNothing

// TestLoadMemoryWarnings checks the three memory situations and the unknown case.
func TestLoadMemoryWarnings(t *testing.T) {
	// A table of free memory, expected words that must appear and words that must not.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// avail is the pretend free memory in bytes; negative means unreadable.
		avail int64
		// want is text that must appear.
		want string
		// not is text that must not appear.
		not string
	}{ // the cases follow
		// Less free memory than the model's size.
		{"short", 1e9, "Not enough free memory", "close to what"},
		// Between the model's size and 1.25 times that.
		{"tight", 3.5e9, "Free memory is close to what this model needs", "Not enough free memory"},
		// Plenty.
		{"plenty", 20e9, "20.0 GB", "⚠"},
		// Unreadable memory is said plainly and not guessed.
		{"unknown", -1, "not known (this system does not report its free memory)", "⚠"},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Nothing loaded.
			f := &loadFake{}
			// Build the rig with the pretend memory.
			rig := loadRig(t, f, tc.avail)
			// Ask.
			res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
			// Read the page.
			body := bodyOf(res)
			// The wanted text.
			if !strings.Contains(body, tc.want) {
				// Report the problem.
				t.Errorf("page lacks %q", tc.want)
			} // end of the want check
			// The unwanted text.
			if strings.Contains(body, tc.not) {
				// Report the problem.
				t.Errorf("page contains %q", tc.not)
			} // end of the not check
			// The Yes button is always offered: the person decides.
			if !strings.Contains(body, "Yes, load it now") {
				// Report the problem.
				t.Errorf("the Yes button is missing")
			} // end of the button check
		}) // end of the subtest
	} // end of the loop
} // end of TestLoadMemoryWarnings

// TestLoadConfirmLoads checks the second step sends exactly one load request without a keep-alive and shows the live timer.
func TestLoadConfirmLoads(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm.
	res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// Read the page.
	body := bodyOf(res)
	// The page says it worked, has a ticking timer and the script.
	for _, want := range []string{"Ollama lists this model as loaded", `class="countdown" data-seconds="`, `<script src="/countdown.js" defer></script>`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("done page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The policy allows the script from this address only, and no inline scripts.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report the problem.
		t.Errorf("unexpected policy: %s", csp)
	} // end of the policy check
	// Exactly one request: generate with only the model (no keep_alive, so Ollama's default applies).
	if len(f.calls) != 1 || f.calls[0] != `/api/generate {"model":"alpha:1b"}` {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestLoadConfirmLoads

// TestLoadEmbeddingFallback checks a model that cannot generate is loaded through /api/embed, again without a keep-alive.
func TestLoadEmbeddingFallback(t *testing.T) {
	// A fake whose generate answers 400.
	f := &loadFake{generateStatus: http.StatusBadRequest}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm.
	res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"embed:1b"}}, fromThisPage)
	// It must say it worked.
	if body := bodyOf(res); res.StatusCode != http.StatusOK || !strings.Contains(body, "Ollama lists this model as loaded") {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, body)
	} // end of the check
	// Two requests: generate, then embed, and neither carries keep_alive.
	if len(f.calls) != 2 || !strings.HasPrefix(f.calls[1], "/api/embed ") || strings.Contains(f.calls[0]+f.calls[1], "keep_alive") {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestLoadEmbeddingFallback

// TestLoadStillNotLoaded checks the page does not claim success when the model never appears.
func TestLoadStillNotLoaded(t *testing.T) {
	// A fake that accepts and ignores load requests.
	f := &loadFake{ignore: true}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm.
	res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// It must say the model is not listed and must not claim success.
	if !strings.Contains(body, "Not listed yet") || strings.Contains(body, "Ollama lists this model as loaded") {
		// Report the problem.
		t.Errorf("wrong message: %s", body)
	} // end of the message check
} // end of TestLoadStillNotLoaded

// TestLoadRefusesWrongModels checks a loaded model and an unknown model are never sent a load request.
func TestLoadRefusesWrongModels(t *testing.T) {
	// One model loaded.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// A table of model, expected words.
	for _, tc := range []struct {
		// model is the posted name.
		model string
		// want is the text that must appear.
		want string
	}{ // the cases follow
		// Already loaded.
		{"alpha:1b", "already loaded"},
		// Not installed.
		{"ghost:1", "not installed"},
	} { // end of the table
		// Both steps must refuse politely.
		for _, path := range []string{"/load", "/load/confirm"} {
			// Send it.
			res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {tc.model}}, fromThisPage)
			// Read the page.
			body := bodyOf(res)
			// The page explains and offers no Yes form.
			if res.StatusCode != http.StatusOK || !strings.Contains(body, tc.want) || strings.Contains(body, "/load/confirm") {
				// Report the problem.
				t.Errorf("%s %s: status %d, body %s", path, tc.model, res.StatusCode, body)
			} // end of the check
		} // end of the path loop
	} // end of the table loop
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("%d requests were sent for models that must not be loaded", n)
	} // end of the call check
} // end of TestLoadRefusesWrongModels

// TestLoadEscapesModelName checks a hostile model name can never become markup.
func TestLoadEscapesModelName(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Send a name that contains a script tag.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"<script>alert(1)</script>"}}, fromThisPage)
	// The tag must be escaped.
	if strings.Contains(bodyOf(res), "<script>") {
		// Report the problem.
		t.Errorf("the model name reached the page unescaped")
	} // end of the escape check
} // end of TestLoadEscapesModelName

// TestLoadPostRefusals checks every way a post can be refused on both load routes, and that a refusal never reaches Ollama.
func TestLoadPostRefusals(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
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
		// A body larger than the 2 KB limit.
		{"too large", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Both routes must refuse in the same way.
		for _, path := range []string{"/load", "/load/confirm"} {
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
	// No refusal may have reached Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("a refused request reached Ollama: %d calls", n)
	} // end of the effect check
	// A GET must be refused on both routes.
	for _, path := range []string{"/load", "/load/confirm"} {
		// Check the method.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the check
	} // end of the method loop
} // end of TestLoadPostRefusals

// TestLoadOllamaDown checks a clear error page when Ollama cannot be read.
func TestLoadOllamaDown(t *testing.T) {
	// A fake that works for the first page and is then closed.
	f := &loadFake{}
	// Keep the old settings and restore them afterwards.
	oldMem := availableMemoryFunc
	// Restore at the end.
	t.Cleanup(func() { availableMemoryFunc = oldMem })
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
	// Ask to load.
	res := post(t, h, "/load", url.Values{"token": {token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must be a 502 with a message and without the address.
	if b := bodyOf(res); res.StatusCode != http.StatusBadGateway || !strings.Contains(b, "Could not do this") || strings.Contains(b, srv.URL) {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, b)
	} // end of the check
} // end of TestLoadOllamaDown

// TestUnloadWarningHasLiveTimer checks the unload warning page now carries the ticking timer, the script and the relaxed policy.
func TestUnloadWarningHasLiveTimer(t *testing.T) {
	// One model loaded, reported as unloading in five minutes.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Ask to unload.
	res := post(t, rig.h, "/unload", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// A ticking timer with its starting seconds, and the script.
	if m := regexp.MustCompile(`class="countdown" data-seconds="(\d+)"`).FindStringSubmatch(body); m == nil || !strings.Contains(body, `<script src="/countdown.js" defer></script>`) {
		// Report the problem.
		t.Errorf("no ticking timer or script in: %s", body)
	} // end of the timer check
	// The policy allows only the monitor's own script.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report the problem.
		t.Errorf("unexpected policy: %s", csp)
	} // end of the policy check
} // end of TestUnloadWarningHasLiveTimer

// TestMainPolicyStaysStrict checks the main page keeps the policy without scripts.
func TestMainPolicyStaysStrict(t *testing.T) {
	// A fake with nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page and its headers.
	_, header, _ := get(t, rig.h, http.MethodGet, "/")
	// No script rule at all.
	if csp := header.Get("Content-Security-Policy"); strings.Contains(csp, "script-src") {
		// Report the problem.
		t.Errorf("the main page policy allows scripts: %s", csp)
	} // end of the policy check
} // end of TestMainPolicyStaysStrict

// TestCountdownScriptIsServed checks the script file is sent as JavaScript.
func TestCountdownScriptIsServed(t *testing.T) {
	// A fake with nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/countdown.js")
	// It must be found, typed as JavaScript, and be the countdown.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "setInterval") {
		// Report the problem.
		t.Errorf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
} // end of TestCountdownScriptIsServed

// TestRemainingSeconds checks which times get a ticking timer.
func TestRemainingSeconds(t *testing.T) {
	// A fixed "now".
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	// A table of cases.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// expires is the reported unload time.
		expires time.Time
		// ok says whether a time was reported.
		ok bool
		// want is the expected number of seconds.
		want int
	}{ // the cases follow
		// Four and a half minutes left.
		{"soon", now.Add(270 * time.Second), true, 270},
		// Already past.
		{"past", now.Add(-time.Second), true, 0},
		// A model set to stay loaded reports a date centuries away.
		{"forever", time.Date(2318, 1, 1, 0, 0, 0, 0, time.UTC), true, 0},
		// No time reported.
		{"unknown", time.Time{}, false, 0},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Compare.
			if got := remainingSeconds(now, tc.expires, tc.ok); got != tc.want {
				// Report the difference.
				t.Errorf("got %d, want %d", got, tc.want)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestRemainingSeconds

// TestParseMemAvailable checks the reading of /proc/meminfo.
func TestParseMemAvailable(t *testing.T) {
	// A table of file texts and expected results.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// text is the file content.
		text string
		// want is the expected number of bytes.
		want int64
		// ok says whether a value is expected.
		ok bool
	}{ // the cases follow
		// A normal file: 1000 kB are 1,024,000 bytes.
		{"normal", "MemTotal:  2000 kB\nMemFree:   500 kB\nMemAvailable:   1000 kB\n", 1024000, true},
		// The line is missing.
		{"missing", "MemTotal: 2000 kB\n", 0, false},
		// A different unit.
		{"unit", "MemAvailable: 1000 MB\n", 0, false},
		// Not a number.
		{"garbage", "MemAvailable: lots kB\n", 0, false},
		// A negative number.
		{"negative", "MemAvailable: -5 kB\n", 0, false},
		// Empty.
		{"empty", "", 0, false},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Parse.
			got, ok := parseMemAvailable(tc.text)
			// Compare.
			if got != tc.want || ok != tc.ok {
				// Report the difference.
				t.Errorf("got %d, %v; want %d, %v", got, ok, tc.want, tc.ok)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestParseMemAvailable

// TestOllamaIsLocal checks which addresses count as this same computer.
func TestOllamaIsLocal(t *testing.T) {
	// A table of addresses and expected answers.
	for addr, want := range map[string]bool{
		// The usual local addresses.
		"http://127.0.0.1:11434": true, "http://localhost:11434": true, "http://[::1]:11434": true,
		// Other computers, by name and by number.
		"http://spark-5f81:11434": false, "http://192.168.1.20:11434": false, "https://ollama.example.com": false,
	} { // end of the table
		// Parse it.
		u, err := url.Parse(addr)
		// A bad test address.
		if err != nil {
			// Stop the test.
			t.Fatalf("bad address %q", addr)
		} // end of the parse check
		// Compare.
		if got := ollamaIsLocal(u); got != want {
			// Report the difference.
			t.Errorf("%s: got %v, want %v", addr, got, want)
		} // end of the compare
	} // end of the loop
} // end of TestOllamaIsLocal

// TestMemoryLevel checks the thresholds.
func TestMemoryLevel(t *testing.T) {
	// A table of free memory, model size and expected level.
	for _, tc := range []struct {
		// avail is the free memory.
		avail int64
		// need is the model size.
		need int64
		// want is the expected level.
		want string
	}{ // the cases follow
		// Less than the model.
		{99, 100, "short"},
		// Exactly the model: not short, but tight.
		{100, 100, "tight"},
		// Just below 1.25 times.
		{124, 100, "tight"},
		// Exactly 1.25 times and more.
		{125, 100, ""}, {1000, 100, ""},
	} { // end of the table
		// Compare.
		if got := memoryLevel(tc.avail, tc.need); got != tc.want {
			// Report the difference.
			t.Errorf("memoryLevel(%d, %d) = %q, want %q", tc.avail, tc.need, got, tc.want)
		} // end of the compare
	} // end of the loop
} // end of TestMemoryLevel

// TestLoadStyles checks the stylesheet has the Load button rules in both themes.
func TestLoadStyles(t *testing.T) {
	// The stylesheet text.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// The outlined button.
		"load button": ".load {",
		// It fills on hover.
		"load hover": ".load:hover",
		// Light colour.
		"light load colour": "--load: #0b57d0",
		// Dark colour.
		"dark load colour": "--load: #8ab4f8",
		// The memory warning has a marker that is not only colour.
		"warning box": ".warn {",
		// The facts table.
		"facts table": ".facts {",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestLoadStyles

// TestMemoryFacts checks the three ways the free memory can be reported, including Ollama on another computer.
func TestMemoryFacts(t *testing.T) {
	// Keep the old reading and restore it afterwards.
	old := availableMemoryFunc
	// Restore at the end.
	t.Cleanup(func() { availableMemoryFunc = old })
	// A reading that always says 10 GB.
	availableMemoryFunc = func() (int64, error) { return 10e9, nil }
	// Parse a local and a remote address.
	local, _ := url.Parse("http://127.0.0.1:11434")
	// The remote one.
	remote, _ := url.Parse("http://spark-5f81:11434")
	// Local: the figure is shown and compared with the need.
	if avail, note, level := memoryFacts(local, 3e9); avail != "10.0 GB" || note != "" || level != "" {
		// Report the problem.
		t.Errorf("local: %q %q %q", avail, note, level)
	} // end of the local check
	// Local and short.
	if _, _, level := memoryFacts(local, 20e9); level != "short" {
		// Report the problem.
		t.Errorf("local short: level %q", level)
	} // end of the short check
	// Remote: no figure, with the reason, and no warning level (the 10 GB must not be used).
	if avail, note, level := memoryFacts(remote, 3e9); avail != "" || !strings.Contains(note, "another computer") || level != "" {
		// Report the problem.
		t.Errorf("remote: %q %q %q", avail, note, level)
	} // end of the remote check
	// A reading that fails.
	availableMemoryFunc = func() (int64, error) { return 0, errors.New("no reading") }
	// Local but unreadable: the reason is passed on.
	if avail, note, _ := memoryFacts(local, 3e9); avail != "" || note != "no reading" {
		// Report the problem.
		t.Errorf("unreadable: %q %q", avail, note)
	} // end of the unreadable check
} // end of TestMemoryFacts
EOF_LTEST

# Edit the existing files with a small Python program; the quoted EOF_PY26 marker saves every character exactly as typed.
python3 - << 'EOF_PY26'
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

# The load routes and the script route are added to the router (web.go).
replace_once("web.go",
    "\tmux.HandleFunc(\"POST /unload/confirm\", unloadConfirm)\n",
    "\tmux.HandleFunc(\"POST /unload/confirm\", unloadConfirm)\n\t// Make the two load handlers: the first shows the memory warning, the second loads (the checks are in load.go).\n\tloadAsk, loadConfirm := loadHandlers(addr, token)\n\t// Route: a POST request for \"/load\" shows the memory warning and changes nothing.\n\tmux.HandleFunc(\"POST /load\", loadAsk)\n\t// Route: a POST request for \"/load/confirm\" loads the model.\n\tmux.HandleFunc(\"POST /load/confirm\", loadConfirm)\n\t// Route: a GET request for \"/countdown.js\" sends the small script that makes the timers tick (only the message pages use it).\n\tmux.HandleFunc(\"GET /countdown.js\", countdownHandler)\n")
# A row that is not loaded gets the Load button, in the same place as the Unload button (web/index.html).
replace_once("web/index.html",
    "</form>\n{{/* End of the loaded check. */}}\n{{end -}}\n</td>",
    "</form>\n{{else}}\n{{/* A model that is not loaded gets the Load button; it opens a warning page about memory first, so one click never loads anything. */}}\n<form class=\"unloadform\" method=\"post\" action=\"/load\">\n{{/* The page token proves the form comes from this monitor. */}}\n<input type=\"hidden\" name=\"token\" value=\"{{$.Token}}\">\n{{/* The model name. */}}\n<input type=\"hidden\" name=\"model\" value=\"{{.Name}}\">\n{{/* The button: the symbol is hidden from screen readers, which read the label instead. */}}\n<button type=\"submit\" class=\"load\" aria-label=\"Load {{.Name}}\"><span aria-hidden=\"true\">▶</span> Load</button>\n{{/* End of the form. */}}\n</form>\n{{/* End of the loaded check. */}}\n{{end -}}\n</td>")
# The existing table test counted whole cells; the not-loaded cell now also holds the Load button, so it counts the start of the cell (webtable_test.go).
replace_once("webtable_test.go",
    "`<td><span class=\"dot dot-off\" aria-hidden=\"true\"></span> Not loaded</td>`",
    "`<td><span class=\"dot dot-off\" aria-hidden=\"true\"></span> Not loaded\n`")
# The old unload test said a not-loaded model has no form at all; it now has a Load form, so the test checks that there is no Unload form for it (unload_test.go).
replace_once("unload_test.go",
    "\t// The embedding model is not loaded, so it has no button.\n\tif strings.Contains(body, `value=\"embed:1b\"`) {\n\t\t// Report the problem.\n\t\tt.Errorf(\"a not-loaded model has an unload form\")\n\t} // end of the other check\n",
    "\t// The embedding model is not loaded, so it has no Unload button (it has a Load button instead).\n\tif strings.Contains(body, `aria-label=\"Unload embed:1b\"`) {\n\t\t// Report the problem.\n\t\tt.Errorf(\"a not-loaded model has an unload button\")\n\t} // end of the other check\n")

# The Unload warning page gets the ticking timer (unload.go): a new field for the seconds.
replace_once("unload.go",
    "\t// Remaining is the time left before Ollama unloads the model by itself (confirm page).\n\tRemaining string\n",
    "\t// Remaining is the time left before Ollama unloads the model by itself (confirm page).\n\tRemaining string\n\t// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.\n\tSeconds int\n")
# The warning page is given the seconds (unload.go).
replace_once("unload.go",
    "Remaining: remainingText(time.Now(), exp, expOK)})",
    "Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK)})")
# A page with a ticking timer may run the monitor's own script, and nothing else (unload.go).
replace_once("unload.go",
    "\t\t// Tell the browser this is an HTML page.\n\t\tw.Header().Set(\"Content-Type\", \"text/html; charset=utf-8\")",
    "\t\t// A page with a ticking timer may run the monitor's own script, and nothing else.\n\t\tif data.Seconds > 0 {\n\t\t\t// Replace the strict policy by the one that allows the script file.\n\t\t\tw.Header().Set(\"Content-Security-Policy\", contentSecurityPolicyWithScript)\n\t\t} // end of the script policy\n\t\t// Tell the browser this is an HTML page.\n\t\tw.Header().Set(\"Content-Type\", \"text/html; charset=utf-8\")")
# The timer text in the unload template (web/unload.html).
replace_once("web/unload.html",
    "<p class=\"muted\">If you do nothing, Ollama unloads this model by itself in: {{.Remaining}}.</p>",
    "<p class=\"muted\">If you do nothing, Ollama unloads this model by itself in: <span class=\"countdown\"{{if .Seconds}} data-seconds=\"{{.Seconds}}\"{{end}}>{{.Remaining}}</span>.</p>")
# The script is included only when there is a timer to tick (web/unload.html).
replace_once("web/unload.html",
    "</main>\n</body>",
    "</main>\n{{/* The ticking timer needs the monitor's own script; it is included only when there is a timer to tick. */}}\n{{if .Seconds}}<script src=\"/countdown.js\" defer></script>{{end}}\n</body>")

# The Load button, the memory warning and the facts table get their styles at the end of app.css, once (recognised by the ".load {" rule).
path = pathlib.Path("web/app.css")
# Read the file.
text = path.read_text()
# Only add the rules when they are not there yet.
if "\n.load {" not in text:
    # Append the rules.
    text += """
/* Load button colours: a blue that works on each theme (contrast 6.9:1 on white in light, 8:1 on the dark panel in dark). */
:root {
  /* Outline and text colour of the Load button. */
  --load: #0b57d0;
  /* Text colour on the filled button. */
  --load-text: #ffffff;
} /* end of rule */

/* The same two colours for a chosen dark theme. */
:root[data-theme="dark"] {
  /* Lighter blue for dark backgrounds. */
  --load: #8ab4f8;
  /* Dark text on the light blue fill. */
  --load-text: #121417;
} /* end of rule */

/* The same two colours for the computer's own dark setting when no theme was chosen. */
@media (prefers-color-scheme: dark) {
  /* No theme chosen. */
  :root:not([data-theme="light"]):not([data-theme="dark"]) {
    /* Lighter blue for dark backgrounds. */
    --load: #8ab4f8;
    /* Dark text on the light blue fill. */
    --load-text: #121417;
  } /* end of rule */
} /* end of rule */

/* The Load button: a blue outlined pill that fills when pointed at (the same shape as the Unload button, in another colour). */
.load {
  /* Use the page font. */
  font: inherit;
  /* A little smaller than the table text. */
  font-size: 0.8rem;
  /* Room inside the pill. */
  padding: 0.1rem 0.7rem;
  /* A solid outline in the button colour: visible without relying on fill. */
  border: 2px solid var(--load);
  /* Pill shape. */
  border-radius: 999px;
  /* Empty inside until hovered. */
  background: transparent;
  /* Text in the button colour. */
  color: var(--load);
  /* A hand cursor. */
  cursor: pointer;
} /* end of rule */

/* Pointed at or keyboard-focused: fill the pill. */
.load:hover, .load:focus-visible {
  /* Fill with the button colour. */
  background: var(--load);
  /* Text switches to the contrast colour. */
  color: var(--load-text);
} /* end of rule */

/* A clear ring for keyboard users. */
.load:focus-visible, .btn-load:focus-visible {
  /* A ring outside the button. */
  outline: 3px solid var(--text);
  /* A gap between button and ring. */
  outline-offset: 2px;
} /* end of rule */

/* The confirming button of the load page: filled with the Load colour. */
.btn-load {
  /* Use the page font. */
  font: inherit;
  /* Room inside. */
  padding: 0.4rem 1rem;
  /* Outline in the button colour. */
  border: 2px solid var(--load);
  /* Pill shape. */
  border-radius: 999px;
  /* Filled. */
  background: var(--load);
  /* Contrast text. */
  color: var(--load-text);
  /* A hand cursor. */
  cursor: pointer;
} /* end of rule */

/* The memory warning: a thick bar on the left plus a warning sign in the text, so colour is never the only signal. */
.warn {
  /* A thick bar in the problem colour. */
  border-left: 6px solid var(--bad);
  /* Room between the bar and the text. */
  padding: 0.4rem 0.8rem;
  /* A light panel behind it. */
  background: var(--bg);
} /* end of rule */

/* The facts table of the load page. */
.facts {
  /* No double lines. */
  border-collapse: collapse;
  /* Room below. */
  margin: 0.5rem 0;
} /* end of rule */

/* Cells of the facts table. */
.facts th, .facts td {
  /* Text starts on the left. */
  text-align: left;
  /* Room around the text. */
  padding: 0.3rem 1rem 0.3rem 0;
  /* Align the top lines of long cells. */
  vertical-align: top;
} /* end of rule */
"""
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: web/app.css (added the load button rules)")
EOF_PY26

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
# Ask Ollama itself for its installed and loaded models (|| true: an unreachable Ollama is reported by the checks).
TAGS="$(curl -s "$OLLAMA_TEST_URL/api/tags" || true)"
# The loaded list.
PS="$(curl -s "$OLLAMA_TEST_URL/api/ps" || true)"
# All installed names, one per line.
INSTALLED_NAMES="$(grep -o '"name":"[^"]*"' <<< "$TAGS" | sed 's/"name":"//; s/"//' || true)"
# How many models are installed.
INSTALLED_COUNT="$(grep -c . <<< "$INSTALLED_NAMES" || true)"
# How many models are loaded (counting name fields in the /api/ps answer).
LOADED_COUNT="$(grep -o '"name":"' <<< "$PS" | wc -l || true)"
# The name of the first loaded model, or nothing when none is loaded.
LOADED_NAME="$(grep -o '"name":"[^"]*"' <<< "$PS" | head -n 1 | sed 's/"name":"//; s/"//' || true)"
# The name of the first installed model that is not loaded (the loop keeps the first one that is missing from the loaded list).
FREE_NAME=""
# Go through the installed names.
while IFS= read -r n; do
  # Skip empty lines.
  [ -n "$n" ] || continue
  # A name that is not in the loaded list.
  if ! grep -qF "\"name\":\"$n\"" <<< "$PS"; then FREE_NAME="$n"; break; fi # end of the check
done <<< "$INSTALLED_NAMES"
# How many Load buttons and Unload buttons the page shows.
LOAD_BUTTONS="$(grep -o 'class="load"' <<< "$PAGE" | wc -l || true)"
# The Unload buttons.
UNLOAD_BUTTONS="$(grep -o 'class="unload"' <<< "$PAGE" | wc -l || true)"

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

# Say what Ollama has, so the checks can be read in context.
echo "info  installed: $INSTALLED_COUNT, loaded: $LOADED_COUNT; buttons on the page: $LOAD_BUTTONS Load, $UNLOAD_BUTTONS Unload"
# Check 1: every not-loaded model has a Load button and every loaded model an Unload button.
check "one Load button per not-loaded model, one Unload button per loaded model" "$([ "$LOAD_BUTTONS" = "$((INSTALLED_COUNT - LOADED_COUNT))" ] && [ "$UNLOAD_BUTTONS" = "$LOADED_COUNT" ] && echo yes || echo no)"
# Check 2: a post without browser headers cannot open the load warning page.
check "load warning page refuses a post without browser headers (403)" "$([ "$(status -d "model=x&token=$TOKEN" "$BASE/load")" = "403" ] && echo yes || echo no)"
# Check 3: the load step refuses a post from another site.
check "load step refuses a post from another site (403)" "$([ "$(status -H 'Sec-Fetch-Site: cross-site' -d "model=x&token=$TOKEN" "$BASE/load/confirm")" = "403" ] && echo yes || echo no)"
# Check 4: the load step refuses a wrong token.
check "load step refuses a wrong token (403)" "$([ "$(status -H 'Sec-Fetch-Site: same-origin' -d 'model=x&token=00000000000000000000000000000000' "$BASE/load/confirm")" = "403" ] && echo yes || echo no)"
# Check 5: the two load addresses accept only POST.
check "GET to /load and /load/confirm is refused (405)" "$([ "$(status "$BASE/load")" = "405" ] && [ "$(status "$BASE/load/confirm")" = "405" ] && echo yes || echo no)"
# Check 6: the script file is served as JavaScript.
check "the countdown script is served as JavaScript" "$(curl -s -D - -o /dev/null "$BASE/countdown.js" | grep -qi '^content-type: text/javascript' && echo yes || echo no)"
# Ask for the safety headers of the main page (-D - prints the headers; -o /dev/null drops the body).
HEADERS="$(curl -s -D - -o /dev/null "$BASE/")"
# Check 7: the main page still has no script and no script rule in its policy.
check "main page has no script and its policy has no script-src" "$(! grep -qi 'script-src' <<< "$HEADERS" && ! grep -qiE '<script|<style| style=' <<< "$PAGE" && echo yes || echo no)"
# Check 8: the load warning page for a not-loaded model shows memory, need and default time, and changes nothing.
if [ -n "$FREE_NAME" ]; then
  # Open the warning page for the first model that is not loaded.
  ASK="$(curl -s -H 'Sec-Fetch-Site: same-origin' --data-urlencode "token=$TOKEN" --data-urlencode "model=$FREE_NAME" "$BASE/load")"
  # Ask Ollama again.
  PS_AFTER="$(curl -s "$OLLAMA_TEST_URL/api/ps" || true)"
  # The three facts and the Yes form must be there, and the model must still be not loaded.
  check "load warning for $FREE_NAME shows memory, need and default time, and loads nothing" "$(grep -q 'Free memory now' <<< "$ASK" && grep -q 'This model needs at least' <<< "$ASK" && grep -q 'default is 5 minutes' <<< "$ASK" && grep -q '/load/confirm' <<< "$ASK" && ! grep -qF "\"name\":\"$FREE_NAME\"" <<< "$PS_AFTER" && echo yes || echo no)"
  # Show the free-memory line, so you can compare it with the free command.
  echo "info  memory line: $(grep -o 'Free memory now</th><td>[^<]*' <<< "$ASK" | sed 's/.*<td>//')"
else
  # Everything is loaded, so this check cannot run; say so instead of pretending.
  echo "skip  load warning check: every installed model is already loaded"
fi # end of the not-loaded check
# Check 9: the unload warning page for a loaded model shows a ticking timer (or the stay-loaded wording).
if [ -n "$LOADED_NAME" ]; then
  # Open the unload warning page for the first loaded model, keeping its headers.
  UASK="$(curl -s -D - -H 'Sec-Fetch-Site: same-origin' --data-urlencode "token=$TOKEN" --data-urlencode "model=$LOADED_NAME" "$BASE/unload")"
  # Either a ticking timer with the script and the relaxed policy, or the wording for a model that stays loaded.
  check "unload warning for $LOADED_NAME has a ticking timer, or says it stays loaded" "$( { grep -q 'class="countdown" data-seconds="' <<< "$UASK" && grep -q 'countdown.js' <<< "$UASK" && grep -qi "script-src 'self'" <<< "$UASK"; } || grep -q 'never on its own' <<< "$UASK" && echo yes || echo no)"
else
  # Nothing is loaded, so this check cannot run; say so instead of pretending.
  echo "skip  unload timer check: no model is loaded (load one with scripts/21-load-model.sh to include it)"
fi # end of the loaded check

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
