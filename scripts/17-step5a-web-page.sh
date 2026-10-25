#!/usr/bin/env bash
# Script 17: Step 5a, adds the monitor web page (web/index.html, web/app.css, web.go, web_test.go, main.go), tests it, and checks it against the real Ollama.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with script 05 on 18765.
TEST_PORT="${TEST_PORT:-18766}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"
# Create the web folder that holds the page template and the stylesheet (-p: no error if it exists).
mkdir -p web

# Write index.html page template; the quoted EOF_HTML marker saves every character exactly as typed.
cat > web/index.html << 'EOF_HTML'
{{/* Page template: the comments in this file are template comments, so they never reach the browser. */}}
<!DOCTYPE html>
{{/* lang tells screen readers which language the page is written in. */}}
<html lang="en">
<head>
{{/* Use UTF-8 so the symbols in the status line display correctly. */}}
<meta charset="utf-8">
{{/* Make the page scale to the screen width on phones and small windows. */}}
<meta name="viewport" content="width=device-width, initial-scale=1">
{{/* Tell the browser the page supports both light and dark colours. */}}
<meta name="color-scheme" content="light dark">
{{/* The product name is the page title. */}}
<title>OllamaControlCenter</title>
{{/* Load our own stylesheet; the safety policy allows only styles from this same address. */}}
<link rel="stylesheet" href="/app.css">
</head>
<body>
{{/* The page header. */}}
<header>
{{/* The main heading. */}}
<h1>OllamaControlCenter</h1>
{{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
<p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
</header>
{{/* The main content area. */}}
<main>
{{/* The status panel; aria-live asks screen readers to announce changes. */}}
<section class="panel" aria-labelledby="status-title" aria-live="polite">
{{/* The panel heading. */}}
<h2 id="status-title">Ollama status</h2>
{{/* Online: a tick, the word Online, the version and the reply time. */}}
{{if .Online}}
{{/* The class ok colours the line, but the tick and the word carry the meaning. */}}
<p class="status ok"><span class="symbol" aria-hidden="true">✔</span> <strong>Online</strong> <span class="muted">version {{.Version}}, answered in {{.ElapsedMs}} ms</span></p>
{{/* Offline: a cross, the word Offline and the plain reason. */}}
{{else}}
{{/* The class bad colours the line, but the cross and the word carry the meaning. */}}
<p class="status bad"><span class="symbol" aria-hidden="true">✖</span> <strong>Offline</strong> <span class="muted">{{.Reason}} ({{.ElapsedMs}} ms)</span></p>
{{/* End of the online check. */}}
{{end}}
{{/* End of the status panel. */}}
</section>
{{/* End of the main content. */}}
</main>
</body>
</html>
EOF_HTML

# Write app.css stylesheet; the quoted EOF_CSS marker saves every character exactly as typed.
cat > web/app.css << 'EOF_CSS'
/* Colours are defined once as variables; the light set is the default. */
:root {
  /* Page background. */
  --bg: #ffffff;
  /* Panel background, slightly different from the page. */
  --panel: #f4f6f8;
  /* Main text colour (contrast 17:1 on the page background). */
  --text: #1a1a1a;
  /* Secondary text colour (contrast 8:1). */
  --muted: #4a4f57;
  /* Colour for the online line (contrast 6.6:1). */
  --ok: #0b6b2f;
  /* Colour for the offline line (contrast 7.7:1). */
  --bad: #a4161a;
  /* Border colour (contrast 3.2:1 against the page, enough for outlines). */
  --border: #8a9099;
  /* Tell the browser to draw its own controls in light colours. */
  color-scheme: light;
}

/* When the computer is set to a dark theme, replace the colours; the layout stays the same. */
@media (prefers-color-scheme: dark) {
  /* The dark set of colours. */
  :root {
    /* Page background. */
    --bg: #121417;
    /* Panel background. */
    --panel: #1b1f24;
    /* Main text colour (contrast 15.6:1). */
    --text: #ececec;
    /* Secondary text colour (contrast 9.8:1). */
    --muted: #b8bdc5;
    /* Colour for the online line (contrast 10.9:1). */
    --ok: #6fdc97;
    /* Colour for the offline line (contrast 9.1:1). */
    --bad: #ff9a9a;
    /* Border colour (contrast 3.8:1). */
    --border: #6b727c;
    /* Tell the browser to draw its own controls in dark colours. */
    color-scheme: dark;
  }
}

/* Page-wide basics: the system font, our colours, and comfortable line spacing. */
body {
  /* Use the font the operating system already has, so nothing is downloaded. */
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  /* Page background from the variables. */
  background: var(--bg);
  /* Text colour from the variables. */
  color: var(--text);
  /* Space lines out for readability. */
  line-height: 1.5;
  /* Keep the content away from the window edges. */
  margin: 0 auto;
  /* Limit the line length on very wide screens. */
  max-width: 80rem;
  /* Padding that also gives a 16px side gutter on phones. */
  padding: 1rem;
}

/* The main heading. */
h1 {
  /* A little smaller than the browser default. */
  font-size: 1.6rem;
  /* Tighten the space below. */
  margin: 0 0 0.25rem;
}

/* Section headings. */
h2 {
  /* Smaller than the page heading. */
  font-size: 1.15rem;
  /* Tighten the space above and below. */
  margin: 0 0 0.5rem;
}

/* Secondary text such as the address line. */
.muted {
  /* Use the secondary colour. */
  color: var(--muted);
}

/* A boxed area with a visible outline, so it is clear without colour. */
.panel {
  /* Panel background from the variables. */
  background: var(--panel);
  /* A solid outline, which keeps the box visible for people who cannot tell colours apart. */
  border: 2px solid var(--border);
  /* Slightly rounded corners. */
  border-radius: 0.5rem;
  /* Space inside the box. */
  padding: 0.75rem 1rem;
  /* Space between boxes. */
  margin: 1rem 0;
}

/* The status line. */
.status {
  /* Larger than normal text so it is the first thing seen. */
  font-size: 1.2rem;
  /* No extra space around the paragraph. */
  margin: 0;
}

/* The online line colour; the tick and the word say it too. */
.status.ok {
  /* Colour from the variables. */
  color: var(--ok);
}

/* The offline line colour; the cross and the word say it too. */
.status.bad {
  /* Colour from the variables. */
  color: var(--bad);
}

/* The status symbol. */
.symbol {
  /* Make the symbol bold so it stands out. */
  font-weight: 700;
}

/* The explanation text next to the status keeps the secondary colour and normal size. */
.status .muted {
  /* Back to normal size. */
  font-size: 1rem;
}

/* Show a clear outline on anything reached with the keyboard. */
:focus-visible {
  /* A thick outline in the text colour. */
  outline: 3px solid var(--text);
  /* Space between the element and its outline. */
  outline-offset: 2px;
}
EOF_CSS

# Write web.go; the quoted EOF_WEB marker saves every character exactly as typed.
cat > web.go << 'EOF_WEB'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes provides a buffer so the page is built completely before anything is sent.
	"bytes"
	// embed lets files be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// html/template builds HTML and escapes every inserted value, so untrusted text cannot become markup.
	"html/template"
	// log prints messages to the terminal.
	"log"
	// net/http is Go's built-in web server.
	"net/http"
	// time provides durations.
	"time"
) // end of imports

// indexTemplateText is the page template, stored inside the executable at build time (requirements T3 and T4).
//
//go:embed web/index.html
var indexTemplateText string

// appCSS is the stylesheet, stored inside the executable at build time.
//
//go:embed web/app.css
var appCSS []byte

// contentSecurityPolicy tells the browser what the page may load: only our own stylesheet, no scripts, no frames, no forms.
const contentSecurityPolicy = "default-src 'none'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

// pageData is everything the page template can show.
type pageData struct {
	// Address is the Ollama address with any password hidden.
	Address string
	// AddressSource names the layer that supplied the address.
	AddressSource string
	// Online is true when Ollama answered with a valid version.
	Online bool
	// Version is the Ollama version text.
	Version string
	// ElapsedMs is how long the check took, in milliseconds.
	ElapsedMs int64
	// Reason explains why Ollama is offline.
	Reason string
} // end of pageData

// secureHeaders wraps a handler so every reply, including errors, carries the same safety headers.
func secureHeaders(next http.Handler) http.Handler {
	// Return a handler that sets the headers and then calls the wrapped one.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Limit what the page may load.
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
		// Stop the browser from guessing a different content type.
		w.Header().Set("X-Content-Type-Options", "nosniff")
		// Forbid showing the page inside a frame (older browsers read this header).
		w.Header().Set("X-Frame-Options", "DENY")
		// Never send the page address to other sites.
		w.Header().Set("Referrer-Policy", "no-referrer")
		// A status page must never come from a cache.
		w.Header().Set("Cache-Control", "no-store")
		// Hand the request on.
		next.ServeHTTP(w, r)
	}) // end of the wrapper
} // end of secureHeaders

// newWebHandler builds the whole web interface: the page at "/" and the stylesheet at "/app.css".
func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
	page := template.Must(template.New("index").Parse(indexTemplateText))
	// Create a router for the two routes.
	mux := http.NewServeMux()
	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		// Ask Ollama once; the request's own context cancels the check if the browser goes away.
		res := checkOllama(r.Context(), addr.URL, timeout)
		// Fill in what the template shows.
		data := pageData{
			// The address with any password replaced by xxxxx.
			Address: addr.URL.Redacted(),
			// Which layer supplied it.
			AddressSource: addr.Source,
			// Online or offline.
			Online: res.Online,
			// The version, if online.
			Version: res.Version,
			// The time taken.
			ElapsedMs: res.Elapsed.Milliseconds(),
			// The reason, if offline.
			Reason: res.Reason,
		} // end of the data
		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	}) // end of the page route
	// Route: a GET request for "/app.css" sends the embedded stylesheet.
	mux.HandleFunc("GET /app.css", func(w http.ResponseWriter, r *http.Request) {
		// Tell the browser this is a stylesheet.
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		// Send it.
		w.Write(appCSS)
	}) // end of the stylesheet route
	// Wrap the router so every reply carries the safety headers.
	return secureHeaders(mux)
} // end of newWebHandler
EOF_WEB

# Write web_test.go; the quoted EOF_WT marker saves every character exactly as typed.
cat > web_test.go << 'EOF_WT'
// Package main tells Go that this test file belongs to the same program as web.go.
package main

import ( // import lists the packages this test file uses.
	// io reads a whole reply body.
	"io"
	// net opens and closes a port, to find one with nothing listening.
	"net"
	// net/http provides request methods and status codes.
	"net/http"
	// net/http/httptest records replies without starting a real server.
	"net/http/httptest"
	// strings searches the page text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the timeouts.
	"time"
) // end of imports

// get sends a request straight into the handler and returns the status, the headers and the body text.
func get(t *testing.T, h http.Handler, method, path string) (int, http.Header, string) {
	// Mark this as a helper.
	t.Helper()
	// Create a recorder that stands in for the browser connection.
	rec := httptest.NewRecorder()
	// Create the request.
	req := httptest.NewRequest(method, path, nil)
	// Run the handler.
	h.ServeHTTP(rec, req)
	// Read the finished reply.
	res := rec.Result()
	// Close the body when this function ends.
	defer res.Body.Close()
	// Read the whole body.
	body, err := io.ReadAll(res.Body)
	// A read failure means the test itself is broken.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot read the reply: %v", err)
	} // end of the read check
	// Hand back the three parts.
	return res.StatusCode, res.Header, string(body)
} // end of get

// handlerFor builds the web handler for the given Ollama address text.
func handlerFor(t *testing.T, raw string) http.Handler {
	// Mark this as a helper.
	t.Helper()
	// Parse and validate the address the same way the program does.
	addr, err := resolve(raw, "")
	// A bad address means the test itself is wrong.
	if err != nil {
		// Stop the test.
		t.Fatalf("bad test address: %v", err)
	} // end of the address check
	// Build the handler with a short timeout.
	return newWebHandler(addr, time.Second)
} // end of handlerFor

// closedAddress returns an address where nothing is listening.
func closedAddress(t *testing.T) string {
	// Mark this as a helper.
	t.Helper()
	// Open a port.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	// A failure means this machine cannot run the test.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot open a test port: %v", err)
	} // end of the listen check
	// Remember where it was.
	addr := l.Addr().String()
	// Close it, so connections are refused.
	l.Close()
	// Return the address.
	return addr
} // end of closedAddress

// TestPageOnline checks the page when Ollama answers.
func TestPageOnline(t *testing.T) {
	// Start a fake Ollama that answers /api/version.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Ask the page.
	status, hdr, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/")
	// The page must load.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status = %d, want 200", status)
	} // end of the status check
	// It must be HTML.
	if got := hdr.Get("Content-Type"); got != "text/html; charset=utf-8" {
		// Report the difference.
		t.Errorf("Content-Type = %q", got)
	} // end of the type check
	// Every expected piece of text must appear.
	for _, want := range []string{"<title>OllamaControlCenter</title>", "✔", "<strong>Online</strong>", "version 0.34.4", srv.URL, "(from command-line option)"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the difference.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// The offline wording must not appear.
	if strings.Contains(body, "Offline") || strings.Contains(body, "✖") {
		// Report the difference.
		t.Errorf("page shows offline wording while online")
	} // end of the offline check
} // end of TestPageOnline

// TestPageOffline checks the page when nothing answers, and that a password in the address never reaches the page.
func TestPageOffline(t *testing.T) {
	// An address with a password and a closed port.
	raw := "http://me:secret@" + closedAddress(t)
	// Ask the page.
	status, _, body := get(t, handlerFor(t, raw), http.MethodGet, "/")
	// The page itself still loads: the monitor is working even when Ollama is not.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status = %d, want 200", status)
	} // end of the status check
	// Every expected piece of text must appear.
	for _, want := range []string{"✖", "<strong>Offline</strong>", "connection refused", "me:xxxxx@"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the difference.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// The password must never appear.
	if strings.Contains(body, "secret") {
		// Report the leak.
		t.Errorf("the password leaked into the page")
	} // end of the leak check
	// The online wording must not appear.
	if strings.Contains(body, "Online") || strings.Contains(body, "✔") {
		// Report the difference.
		t.Errorf("page shows online wording while offline")
	} // end of the online check
} // end of TestPageOffline

// TestPageEscapesUntrustedText checks that markup coming from Ollama is shown as text and never runs.
func TestPageEscapesUntrustedText(t *testing.T) {
	// A fake Ollama that sends a hostile version text.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"<script>alert(1)</script>"}`))
	// Ask the page.
	_, _, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/")
	// A real script tag must not appear.
	if strings.Contains(body, "<script>") {
		// Report the problem.
		t.Errorf("an unescaped script tag reached the page")
	} // end of the script check
	// The escaped text must appear instead.
	if !strings.Contains(body, "&lt;script&gt;alert(1)&lt;/script&gt;") {
		// Report the problem.
		t.Errorf("the hostile text was not shown as escaped text")
	} // end of the escaped check
} // end of TestPageEscapesUntrustedText

// TestPageHasNoInlineCode checks the page works under the safety policy: no scripts, no style tags, no style attributes.
func TestPageHasNoInlineCode(t *testing.T) {
	// A fake Ollama that is online.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Ask the page.
	_, _, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/")
	// None of these may appear.
	for _, bad := range []string{"<script", "<style", " style=", " onclick=", " onload="} {
		// Look for it.
		if strings.Contains(body, bad) {
			// Report the problem.
			t.Errorf("page contains %q, which the safety policy would block", bad)
		} // end of the check
	} // end of the loop
	// Comments written in the template must not reach the browser.
	if strings.Contains(body, "template comments") || strings.Contains(body, "{{") {
		// Report the problem.
		t.Errorf("template text leaked into the page")
	} // end of the comment check
} // end of TestPageHasNoInlineCode

// TestSecurityHeaders checks the safety headers on the page, the stylesheet and an error reply.
func TestSecurityHeaders(t *testing.T) {
	// A fake Ollama that is online.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Build the handler once.
	h := handlerFor(t, srv.URL)
	// The headers every reply must carry.
	want := map[string]string{
		// Only our own stylesheet may load; nothing else.
		"Content-Security-Policy": contentSecurityPolicy,
		// No content-type guessing.
		"X-Content-Type-Options": "nosniff",
		// No framing.
		"X-Frame-Options": "DENY",
		// No referrer.
		"Referrer-Policy": "no-referrer",
		// No caching.
		"Cache-Control": "no-store",
	} // end of the header table
	// Check three different replies: the page, the stylesheet and a 404.
	for _, path := range []string{"/", "/app.css", "/nothing-here"} {
		// Ask for it.
		_, hdr, _ := get(t, h, http.MethodGet, path)
		// Check every header.
		for name, value := range want {
			// Compare.
			if got := hdr.Get(name); got != value {
				// Report the difference.
				t.Errorf("%s on %s = %q, want %q", name, path, got, value)
			} // end of the compare
		} // end of the header loop
	} // end of the path loop
	// The policy must forbid scripts: it starts from "nothing allowed" and never mentions script-src.
	if !strings.Contains(contentSecurityPolicy, "default-src 'none'") || strings.Contains(contentSecurityPolicy, "script-src") {
		// Report the difference.
		t.Errorf("unexpected policy: %s", contentSecurityPolicy)
	} // end of the policy check
} // end of TestSecurityHeaders

// TestStylesheet checks the stylesheet is served as CSS and contains both themes.
func TestStylesheet(t *testing.T) {
	// A fake Ollama (not used by this route, but the handler needs an address).
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Ask for the stylesheet.
	status, hdr, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/app.css")
	// It must load.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status = %d, want 200", status)
	} // end of the status check
	// It must be CSS.
	if got := hdr.Get("Content-Type"); got != "text/css; charset=utf-8" {
		// Report the difference.
		t.Errorf("Content-Type = %q", got)
	} // end of the type check
	// It must contain the dark theme rule and a light default.
	for _, want := range []string{"@media (prefers-color-scheme: dark)", "color-scheme: light", "color-scheme: dark", ":focus-visible"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the difference.
			t.Errorf("stylesheet does not contain %q", want)
		} // end of the check
	} // end of the loop
} // end of TestStylesheet

// TestRoutes checks the paths and methods the router refuses.
func TestRoutes(t *testing.T) {
	// A fake Ollama.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Build the handler once.
	h := handlerFor(t, srv.URL)
	// A table of requests and the expected status.
	cases := []struct {
		// name labels the case.
		name string
		// method is the request method.
		method string
		// path is the request path.
		path string
		// want is the expected status.
		want int
	}{
		// An unknown path.
		{"unknown path", http.MethodGet, "/nothing-here", http.StatusNotFound},
		// A change request to the page.
		{"POST to the page", http.MethodPost, "/", http.StatusMethodNotAllowed},
		// A change request to the stylesheet.
		{"POST to the stylesheet", http.MethodPost, "/app.css", http.StatusMethodNotAllowed},
		// A path that only looks like the page.
		{"page with extra path", http.MethodGet, "/index.html", http.StatusNotFound},
	} // end of the table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Ask.
			status, _, _ := get(t, h, tc.method, tc.path)
			// Compare.
			if status != tc.want {
				// Report the difference.
				t.Errorf("%s %s = %d, want %d", tc.method, tc.path, status, tc.want)
			} // end of the compare
		}) // end of the subtest
	} // end of the case loop
} // end of TestRoutes
EOF_WT

# Write main.go; the quoted EOF_MAIN marker saves every character exactly as typed.
cat > main.go << 'EOF_MAIN'
// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// context supplies the (empty) context the fetch functions need.
	"context"
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text to the terminal.
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

// runModels fetches both lists, prints the report, and returns the exit code (0 = printed, 1 = Ollama could not be read).
func runModels(addr ollamaAddress) int {
	// An empty context with no deadline; each request has its own timeout.
	ctx := context.Background()
	// Fetch the installed models.
	installed, err := fetchInstalled(ctx, addr.URL, defaultCheckTimeout)
	// A failure here means Ollama could not be read.
	if err != nil {
		// Print one OFFLINE line with the plain reason, like -check does.
		fmt.Println("OFFLINE  " + err.Error())
		// Exit code 1 means failure.
		return 1
	} // end of the installed check
	// Fetch the loaded models.
	loaded, err := fetchLoaded(ctx, addr.URL, defaultCheckTimeout)
	// A failure here also means Ollama could not be read.
	if err != nil {
		// Print one OFFLINE line with the plain reason.
		fmt.Println("OFFLINE  " + err.Error())
		// Exit code 1 means failure.
		return 1
	} // end of the loaded check
	// Print the whole report; time.Now() is the clock used for the "time until unload" column.
	fmt.Println(renderReport(installed, loaded, time.Now()))
	// Exit code 0 means success.
	return 0
} // end of runModels

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
	// Define a -check switch: false unless given on the command line.
	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
	// Define a -models switch: false unless given on the command line.
	modelsFlag := flag.Bool("models", false, "print the installed and loaded models as tables, and exit (0 = printed, 1 = Ollama not reachable)")
	// Read the command line now, so the variables above receive their values.
	flag.Parse()

	// The two one-shot modes cannot be combined; ask the person to choose one.
	if *checkFlag && *modelsFlag {
		// log.Fatal prints the message and exits with code 1.
		log.Fatal("use either -check or -models, not both")
	} // end of the combination check

	// Choose the Ollama address by precedence: option, then environment variable, then default.
	addr, err := resolve(*ollamaFlag, os.Getenv(envOllamaURL))
	// If the address is unusable, stop with a clear message and a failure exit code.
	if err != nil {
		// log.Fatalf prints the message and exits with code 1.
		log.Fatalf("%v", err)
	} // end of the address check
	// Print the address (any password shown as xxxxx) and which layer supplied it.
	log.Printf("Ollama address: %s (from %s)", addr.URL.Redacted(), addr.Source)

	// In -models mode, print both tables and leave without starting the web page.
	if *modelsFlag {
		// Run it and leave with its exit code.
		os.Exit(runModels(addr))
	} // end of the models mode

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

	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the web interface from web.go,
	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
	server := &http.Server{Addr: *listen, Handler: newWebHandler(addr, defaultCheckTimeout), ReadHeaderTimeout: 5 * time.Second}

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
# Run every test quietly; a failure stops the script and shows Go's own message.
go test -count=1 ./...
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build and tests worked.
echo "PASS  tests and build"

# Patch script 05 (the smoke test): its body check expects the old plain text, but "/" is now the HTML page.
# The Python below changes only that one block; it says "already patched" if you run it twice, and fails loudly if the block is missing.
python3 - << 'EOF_PY'
# Read the smoke-test script as text.
import pathlib, sys
# The file to patch.
path = pathlib.Path("scripts/05-smoke-test.sh")
# Load its whole text.
text = path.read_text()
# The old block: the check for the plain hello message.
old = '''# The body must be exactly our message
if [ "$BODY" = "OllamaControlCenter is running" ]; then
  # Record a pass
  record_result ok "GET / body is the expected message"
else
  # Record a failure and show what came back
  record_result bad "GET / body is the expected message (got: $BODY)"
# End of the body check
fi
'''
# The new block: the check that the body is the monitor page.
new = '''# The body must be the monitor page (since Step 5a, "/" is the HTML page and no longer the plain hello text)
if [[ "$BODY" == *"<title>OllamaControlCenter</title>"* ]]; then
  # Record a pass
  record_result ok "GET / is the monitor page"
else
  # Record a failure and show the start of what came back
  record_result bad "GET / is the monitor page (got: ${BODY:0:80})"
# End of the body check
fi
'''
# If the new block is already there, there is nothing to do.
if new in text:
    # Say so and finish this step.
    print("script 05 already patched")
# If the old block is there, replace it.
elif old in text:
    # Write the file back with the new block (count=1 replaces only the first match).
    path.write_text(text.replace(old, new, 1))
    # Say what happened.
    print("script 05 patched: body check now expects the monitor page")
# If neither block is found, something else changed; stop instead of guessing.
else:
    # Explain the problem on the error stream.
    print("ERROR: the body check in script 05 was not found; not patching", file=sys.stderr)
    # Fail loudly.
    sys.exit(1)
EOF_PY

# Run the patched smoke test (it builds with script 04, starts the monitor on port 18765, checks it, and stops it).
scripts/05-smoke-test.sh

# ---------- Page check against the real Ollama ----------
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
# Temporary file for the monitor's messages.
LOG_FILE="$(mktemp)"
# Start the monitor in the background on the spare port, watching the chosen Ollama.
OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -listen "127.0.0.1:$TEST_PORT" -ollama-url "$OLLAMA_TEST_URL" > "$LOG_FILE" 2>&1 &
# Remember the background process so it can be stopped.
PID=$!
# Stop the monitor and delete the log when the script ends for any reason.
trap 'kill "$PID" 2> /dev/null || true; rm -f "$LOG_FILE"' EXIT
# Wait up to 5 seconds for the page to answer.
for _ in $(seq 1 50); do
  # Any answer at all means it is up.
  if curl -s -o /dev/null "http://127.0.0.1:$TEST_PORT/"; then break; fi # end of the answer check
  # Wait a moment before asking again.
  sleep 0.1
done # end of the waiting loop

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL CONDITION_RESULT: prints PASS when the second word is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check

# Fetch the page body and its headers (-D - prints the headers to the screen first; -s hides the progress bar).
PAGE="$(curl -s -D /tmp/occ-headers.$$ "http://127.0.0.1:$TEST_PORT/")"
# Read the headers into a variable (tr removes the carriage returns that HTTP adds).
HEADERS="$(tr -d '\r' < /tmp/occ-headers.$$)"; rm -f /tmp/occ-headers.$$
# Fetch the stylesheet headers only (-I asks for the headers).
CSS_HEADERS="$(curl -s -I "http://127.0.0.1:$TEST_PORT/app.css" | tr -d '\r')"
# Fetch the status code of an unknown path.
CODE_404="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$TEST_PORT/nothing-here")"

# Check 1: the page answers with status 200.
check "GET / returns 200" "$(printf '%s' "$HEADERS" | head -1 | grep -q ' 200' && echo yes || echo no)"
# Check 2: the page is HTML.
check "GET / is text/html" "$(printf '%s' "$HEADERS" | grep -qi '^content-type: text/html' && echo yes || echo no)"
# Check 3: the page has the product title.
check "page has the title" "$(printf '%s' "$PAGE" | grep -qF '<title>OllamaControlCenter</title>' && echo yes || echo no)"
# Check 4: the page shows a status word (Online or Offline), never neither.
check "page shows Online or Offline" "$(printf '%s' "$PAGE" | grep -qE '<strong>(Online|Offline)</strong>' && echo yes || echo no)"
# Check 5: the safety policy header is present.
check "Content-Security-Policy header present" "$(printf '%s' "$HEADERS" | grep -qi '^content-security-policy: default-src .none.' && echo yes || echo no)"
# Check 6: no-sniff header is present.
check "X-Content-Type-Options is nosniff" "$(printf '%s' "$HEADERS" | grep -qi '^x-content-type-options: nosniff' && echo yes || echo no)"
# Check 7: the stylesheet is served as CSS.
check "/app.css is text/css" "$(printf '%s' "$CSS_HEADERS" | grep -qi '^content-type: text/css' && echo yes || echo no)"
# Check 8: unknown paths give 404.
check "unknown path returns 404" "$([ "$CODE_404" = "404" ] && echo yes || echo no)"
# Check 9: no scripts and no inline styles reached the browser.
check "page has no script or inline style" "$(printf '%s' "$PAGE" | grep -qiE '<script|<style| style=' && echo no || echo yes)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Show the status line exactly as the page contains it (read-only).
echo "Status line in the page:"
# Print only the line with the status paragraph.
printf '%s\n' "$PAGE" | grep 'class="status'
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
