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
	for _, want := range []string{"<title>LLMsControlDock</title>", "✔", "<strong>Online</strong>", "version 0.34.4", srv.URL, "(from command-line option)"} {
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

// TestPageHasNoInlineCode checks the page works under the safety policy: no inline scripts (only the monitor's own script file), no style tags, no style attributes.
func TestPageHasNoInlineCode(t *testing.T) {
	// A fake Ollama that is online.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Ask the page.
	_, _, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/")
	// None of these may appear.
	for _, bad := range []string{"<script>", "<style", " style=", " onclick=", " onload="} {
		// Look for it.
		if strings.Contains(body, bad) {
			// Report the problem.
			t.Errorf("page contains %q, which the safety policy would block", bad)
		} // end of the check
	} // end of the loop
	// Every script tag must load the monitor's own file; the policy blocks everything else.
	if n, ok := strings.Count(body, "<script"), strings.Count(body, `<script src="/countdown.js" defer></script>`); n != ok {
		// Report the problem.
		t.Errorf("page has %d script tags but only %d load /countdown.js", n, ok)
	} // end of the script check
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
		// The page that shows the table is the only one that may run the monitor's own script; every other reply keeps the strict policy.
		wantNow := map[string]string{}
		// Copy the table.
		for k, v := range want {
			// Copy one entry.
			wantNow[k] = v
		} // end of the copy
		// The fake Ollama answers every address, so the page shows a table and gets the script policy.
		if path == "/" {
			// Swap the policy.
			wantNow["Content-Security-Policy"] = contentSecurityPolicyMainPage
		} // end of the page case
		// Check every header.
		for name, value := range wantNow {
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
	}{ // the cases follow
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
