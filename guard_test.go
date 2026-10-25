// Package main tells Go that this test file belongs to the same program as guard.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides requests and status codes.
	"net/http"
	// net/http/httptest records replies without starting a real server.
	"net/http/httptest"
	// regexp checks the shape of the token.
	"regexp"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestMustToken checks the token has the right shape and is different every time.
func TestMustToken(t *testing.T) {
	// Make two tokens.
	a, b := mustToken(), mustToken()
	// Each must be exactly 32 lower-case hexadecimal characters.
	for _, tok := range []string{a, b} {
		// Check the shape.
		if !regexp.MustCompile(`^[0-9a-f]{32}$`).MatchString(tok) {
			// Report the problem.
			t.Errorf("token %q is not 32 hexadecimal characters", tok)
		} // end of the shape check
	} // end of the loop
	// Two tokens must differ; equal tokens would mean the random source is broken.
	if a == b {
		// Report the problem.
		t.Errorf("two tokens are equal: %q", a)
	} // end of the difference check
} // end of TestMustToken

// TestTokenValid checks which form values are accepted.
func TestTokenValid(t *testing.T) {
	// A table of page token, form value and expected answer.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// want is the page token.
		want string
		// got is the value from the form.
		got string
		// ok is the expected answer.
		ok bool
	}{ // the cases follow
		// The same token.
		{"equal", "abc123", "abc123", true},
		// A different token.
		{"different", "abc123", "abc124", false},
		// A missing form value.
		{"empty form value", "abc123", "", false},
		// An empty page token must never match an empty form value.
		{"both empty", "", "", false},
		// A longer value that starts the same.
		{"longer", "abc123", "abc1234", false},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Compare.
			if got := tokenValid(tc.want, tc.got); got != tc.ok {
				// Report the difference.
				t.Errorf("tokenValid(%q, %q) = %v, want %v", tc.want, tc.got, got, tc.ok)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestTokenValid

// TestSameOrigin checks which requests count as coming from this page.
func TestSameOrigin(t *testing.T) {
	// A table of headers and the expected answer; httptest requests have the Host example.com.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// headers are the request headers to set.
		headers map[string]string
		// ok is the expected answer.
		ok bool
	}{ // the cases follow
		// A modern browser sending from this page.
		{"same-origin", map[string]string{"Sec-Fetch-Site": "same-origin"}, true},
		// A modern browser sending from another site.
		{"cross-site", map[string]string{"Sec-Fetch-Site": "cross-site"}, false},
		// A modern browser sending from another site of the same family.
		{"same-site", map[string]string{"Sec-Fetch-Site": "same-site"}, false},
		// A request that did not start from a page at all (typed address).
		{"none", map[string]string{"Sec-Fetch-Site": "none"}, false},
		// An older browser sending from this page.
		{"origin matches", map[string]string{"Origin": "http://example.com"}, true},
		// An older browser sending from another address.
		{"origin differs", map[string]string{"Origin": "http://evil.example"}, false},
		// A browser that hides the origin.
		{"origin null", map[string]string{"Origin": "null"}, false},
		// The modern header wins over a matching Origin.
		{"cross-site beats origin", map[string]string{"Sec-Fetch-Site": "cross-site", "Origin": "http://example.com"}, false},
		// A script or curl sends neither header.
		{"no headers", map[string]string{}, false},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Build a request.
			req := httptest.NewRequest(http.MethodPost, "/theme", nil)
			// Set the headers of the case.
			for k, v := range tc.headers {
				// One header.
				req.Header.Set(k, v)
			} // end of the header loop
			// Compare.
			if got := sameOrigin(req); got != tc.ok {
				// Report the difference.
				t.Errorf("sameOrigin = %v, want %v", got, tc.ok)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestSameOrigin

// TestAllowedHosts checks which Host values are accepted for a given listen address.
func TestAllowedHosts(t *testing.T) {
	// The default listen address.
	set := allowedHosts("127.0.0.1:8765")
	// These must be accepted.
	for _, ok := range []string{"127.0.0.1:8765", "localhost:8765", "[::1]:8765"} {
		// Look it up.
		if !set[ok] {
			// Report the problem.
			t.Errorf("%q should be allowed", ok)
		} // end of the check
	} // end of the loop
	// These must be refused: another name, another port, no port, empty.
	for _, bad := range []string{"evil.example:8765", "127.0.0.1:9999", "127.0.0.1", "localhost", ""} {
		// Look it up.
		if set[bad] {
			// Report the problem.
			t.Errorf("%q should be refused", bad)
		} // end of the check
	} // end of the loop
	// On the default web port, browsers leave the port out.
	if !allowedHosts("127.0.0.1:80")["localhost"] {
		// Report the problem.
		t.Errorf("localhost without a port should be allowed on port 80")
	} // end of the port-80 check
	// An unparsable listen address allows only itself.
	if got := allowedHosts("nonsense"); len(got) != 1 || !got["nonsense"] {
		// Report the problem.
		t.Errorf("unexpected set for a bad address: %v", got)
	} // end of the bad-address check
} // end of TestAllowedHosts

// TestHostGuard checks that a wrong Host never reaches the wrapped handler.
func TestHostGuard(t *testing.T) {
	// Count how often the wrapped handler runs.
	calls := 0
	// A wrapped handler that counts and answers 200.
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Count the call.
		calls++
	}) // end of the inner handler
	// Wrap it for the default listen address.
	h := hostGuard(inner, "127.0.0.1:8765")
	// A table of Host values and the expected status.
	for _, tc := range []struct {
		// host is the Host header value.
		host string
		// want is the expected status.
		want int
	}{ // the cases follow
		// The address itself.
		{"127.0.0.1:8765", http.StatusOK},
		// The usual name, in capitals (names are not case sensitive).
		{"LocalHost:8765", http.StatusOK},
		// A rebinding attack uses a name that points at this computer.
		{"attacker.example:8765", http.StatusForbidden},
		// The right name with the wrong port.
		{"localhost:80", http.StatusForbidden},
	} { // end of the table
		// Build a request with that Host.
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		// Set the Host.
		req.Host = tc.host
		// Run the handler.
		rec := httptest.NewRecorder()
		// Serve.
		h.ServeHTTP(rec, req)
		// Compare.
		if rec.Code != tc.want {
			// Report the difference.
			t.Errorf("Host %q: status %d, want %d", tc.host, rec.Code, tc.want)
		} // end of the compare
	} // end of the loop
	// Only the two good hosts may have reached the wrapped handler.
	if calls != 2 {
		// Report the difference.
		t.Errorf("the wrapped handler ran %d times, want 2", calls)
	} // end of the call count
} // end of TestHostGuard
