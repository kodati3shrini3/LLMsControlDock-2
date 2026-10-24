// Package main tells Go that this test file belongs to the same program as check.go.
package main

import ( // import lists the packages this test file uses.
	// context supplies the (empty) context the check function needs.
	"context"
	// net opens and closes a port, to find one with nothing listening.
	"net"
	// net/http provides handler types and status codes for the fake Ollama.
	"net/http"
	// net/http/httptest starts throw-away servers inside the test.
	"net/http/httptest"
	// net/url parses addresses into the type the check function takes.
	"net/url"
	// strings checks whether text contains other text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the timeouts.
	"time"
) // end of imports

// mustParse turns text into a parsed address and stops the test if that fails.
func mustParse(t *testing.T, raw string) *url.URL {
	// Mark this as a helper, so failures point at the caller's line.
	t.Helper()
	// Parse the text.
	u, err := url.Parse(raw)
	// A parse error means the test itself is wrong.
	if err != nil {
		// Stop the test.
		t.Fatalf("bad test address %q: %v", raw, err)
	} // end of the parse check
	// Return the parsed address.
	return u
} // end of mustParse

// fakeOllama starts a pretend server that runs the given handler, and removes it when the test ends.
func fakeOllama(t *testing.T, handler http.HandlerFunc) *httptest.Server {
	// Mark this as a helper.
	t.Helper()
	// Start the server on a random free port.
	srv := httptest.NewServer(handler)
	// Schedule the shutdown for when the test finishes.
	t.Cleanup(srv.Close)
	// Hand the server back.
	return srv
} // end of fakeOllama

// replyWith builds a handler that always answers with the given status and body.
func replyWith(status int, body string) http.HandlerFunc {
	// Return the handler function.
	return func(w http.ResponseWriter, r *http.Request) {
		// Send the status line first.
		w.WriteHeader(status)
		// Then send the body text.
		w.Write([]byte(body))
	} // end of the handler
} // end of replyWith

// TestCheckOnline checks the success path, with and without a trailing slash on the address.
func TestCheckOnline(t *testing.T) {
	// Start a fake Ollama that answers the way the real one does.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Try the address as given and with a trailing slash.
	for _, suffix := range []string{"", "/"} {
		// Run each variant as a named subtest.
		t.Run("suffix "+suffix, func(t *testing.T) {
			// Call the function under test.
			got := checkOllama(context.Background(), mustParse(t, srv.URL+suffix), time.Second)
			// It must report online.
			if !got.Online {
				// Report the failure with the reason.
				t.Fatalf("expected online, got offline: %s", got.Reason)
			} // end of the online check
			// It must report the version the fake sent.
			if got.Version != "0.34.4" {
				// Report the difference.
				t.Errorf("version = %q, want 0.34.4", got.Version)
			} // end of the version check
		}) // end of the subtest
	} // end of the variant loop
} // end of TestCheckOnline

// TestCheckOffline checks every failure reason with a fake or a missing server.
func TestCheckOffline(t *testing.T) {
	// Find a port with nothing listening: open one, note it, close it.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	// Failing to open a port means the test machine cannot run this test.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot open a test port: %v", err)
	} // end of the listen check
	// Remember the address.
	closedAddr := l.Addr().String()
	// Close it, so connections to it are refused.
	l.Close()
	// A server that answers HTML instead of JSON.
	html := fakeOllama(t, replyWith(http.StatusOK, "<html>hello</html>"))
	// A server that answers JSON without a version field.
	noVersion := fakeOllama(t, replyWith(http.StatusOK, `{"other":1}`))
	// A server that answers 404.
	notFound := fakeOllama(t, replyWith(http.StatusNotFound, "nope"))
	// A server that answers only after 2 seconds.
	slow := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// Wait longer than the test's timeout.
		time.Sleep(2 * time.Second)
	}) // end of the slow handler
	// A secure server with a certificate the client does not trust.
	tlsSrv := httptest.NewTLSServer(replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Schedule its shutdown.
	t.Cleanup(tlsSrv.Close)
	// A table of cases: address, timeout, and text the reason must contain.
	cases := []struct {
		// name labels the case.
		name string
		// address is what we ask.
		address string
		// timeout is how long we wait.
		timeout time.Duration
		// wantReason is text the reason must contain.
		wantReason string
	}{
		// HTML instead of JSON.
		{"not json", html.URL, time.Second, "not JSON"},
		// JSON of the wrong shape.
		{"no version field", noVersion.URL, time.Second, "no version field"},
		// Wrong status code.
		{"status 404", notFound.URL, time.Second, "status 404"},
		// Too slow.
		{"timeout", slow.URL, 300 * time.Millisecond, "timed out"},
		// Nothing listening, and a password in the address that must not leak.
		{"connection refused", "http://me:secret@" + closedAddr, time.Second, "connection refused"},
		// A host name that cannot exist (the .invalid ending is reserved for this).
		{"name not found", "http://nohost.invalid:11434", 5 * time.Second, "host name was not found"},
		// An untrusted certificate.
		{"certificate", tlsSrv.URL, time.Second, "certificate"},
	} // end of the case table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Call the function under test.
			got := checkOllama(context.Background(), mustParse(t, tc.address), tc.timeout)
			// It must report offline.
			if got.Online {
				// Stop this subtest.
				t.Fatal("expected offline, got online")
			} // end of the offline check
			// The reason must say what went wrong.
			if !strings.Contains(got.Reason, tc.wantReason) {
				// Report the difference.
				t.Errorf("reason = %q, want it to contain %q", got.Reason, tc.wantReason)
			} // end of the reason check
			// The reason must never contain the password.
			if strings.Contains(got.Reason, "secret") {
				// Report the leak.
				t.Errorf("reason leaks the password: %q", got.Reason)
			} // end of the leak check
		}) // end of the subtest
	} // end of the case loop
} // end of TestCheckOffline
