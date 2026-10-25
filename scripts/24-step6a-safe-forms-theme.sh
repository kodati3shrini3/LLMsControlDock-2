#!/usr/bin/env bash
# Script 24: Step 6a, safe forms for the monitor page (Host-name check, same-origin check, page token) and the first form that uses them: a small light/dark theme switch in the page header.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with scripts 05, 19, 20 and 22.
TEST_PORT="${TEST_PORT:-18769}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write guard.go (Host-name check, same-origin check, page token); the quoted EOF_GUARD marker saves every character exactly as typed.
cat > guard.go << 'EOF_GUARD'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// crypto/rand makes the page token from random numbers that a program cannot predict.
	"crypto/rand"
	// crypto/subtle compares two texts in constant time, so the time taken cannot give the token away.
	"crypto/subtle"
	// encoding/hex writes the random bytes as readable letters and digits.
	"encoding/hex"
	// net splits "host:port" addresses.
	"net"
	// net/http provides requests and status codes.
	"net/http"
	// strings makes host names lower case before they are compared.
	"strings"
) // end of imports

// mustToken makes the page token: 16 random bytes written as 32 letters and digits (the name starts with "must" because it stops the program if it fails, like template.Must).
func mustToken() string {
	// 16 random bytes are 128 bits, far too many to guess.
	b := make([]byte, 16)
	// Fill them from the operating system's random source.
	if _, err := rand.Read(b); err != nil {
		// Without randomness the page cannot be made safe, so stop at start-up.
		panic("cannot create the page token: " + err.Error())
	} // end of the random check
	// Write the bytes as 32 letters and digits.
	return hex.EncodeToString(b)
} // end of mustToken

// tokenValid says whether the token sent with a form is the page token; an empty token is never valid.
func tokenValid(want, got string) bool {
	// An empty page token would match an empty form value, so refuse it first.
	if want == "" {
		// Never valid.
		return false
	} // end of the empty check
	// Compare in constant time; the result is 1 when the texts are equal.
	return subtle.ConstantTimeCompare([]byte(want), []byte(got)) == 1
} // end of tokenValid

// sameOrigin says whether a request was sent by a form on this very page (requirement S2: only the monitor's own page may change anything).
func sameOrigin(r *http.Request) bool {
	// Modern browsers always say where a request came from; only "same-origin" is accepted.
	if site := r.Header.Get("Sec-Fetch-Site"); site != "" {
		// Compare with the one accepted value.
		return site == "same-origin"
	} // end of the Sec-Fetch-Site check
	// Older browsers send an Origin header with form posts; it must name this very address.
	if origin := r.Header.Get("Origin"); origin != "" {
		// "null" and every other address are refused because they do not match.
		return origin == "http://"+r.Host
	} // end of the Origin check
	// Neither header: the request did not come from a browser page (a script or curl, for example), so refuse it.
	return false
} // end of sameOrigin

// allowedHosts lists the Host header values that count as "this computer, this port" for the given listen address.
func allowedHosts(listen string) map[string]bool {
	// The address exactly as it was given to -listen is always allowed.
	set := map[string]bool{strings.ToLower(listen): true}
	// Split it into host and port; if that fails, only the exact text is allowed.
	_, port, err := net.SplitHostPort(listen)
	// A failure means no port can be added to the names below.
	if err != nil {
		// Return what we have.
		return set
	} // end of the split check
	// The three names a browser on this computer uses for itself.
	for _, host := range []string{"127.0.0.1", "localhost", "[::1]"} {
		// The name with the port.
		set[host+":"+port] = true
		// Browsers leave the port out when it is the default web port, 80.
		if port == "80" {
			// The name alone.
			set[host] = true
		} // end of the port-80 check
	} // end of the name loop
	// Hand back the list.
	return set
} // end of allowedHosts

// hostGuard refuses every request whose Host header is not one of this computer's own names, which stops DNS rebinding (a web page elsewhere tricking the browser into talking to this monitor).
func hostGuard(next http.Handler, listen string) http.Handler {
	// Work out the allowed names once.
	allowed := allowedHosts(listen)
	// Return a handler that checks the Host header and then calls the wrapped one.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Host names are not case sensitive, so compare in lower case.
		if !allowed[strings.ToLower(r.Host)] {
			// Never cache a refusal.
			w.Header().Set("Cache-Control", "no-store")
			// Refuse with a plain message.
			http.Error(w, "unexpected Host header", http.StatusForbidden)
			// Stop here.
			return
		} // end of the host check
		// The name is fine; hand the request on.
		next.ServeHTTP(w, r)
	}) // end of the wrapper
} // end of hostGuard
EOF_GUARD

# Write theme.go (theme cookie and the POST handler); the quoted EOF_THEME marker saves every character exactly as typed.
cat > theme.go << 'EOF_THEME'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides cookies, redirects and status codes.
	"net/http"
) // end of imports

// themeCookieName is the name of the cookie that remembers the chosen theme in this browser (it holds only the word light or dark).
const themeCookieName = "occ_theme"

// themeCookieMaxAge keeps the choice for one year, in seconds.
const themeCookieMaxAge = 365 * 24 * 60 * 60

// themeFromRequest reads the saved theme from the cookie: "light", "dark", or "" for follow the system (also used for a missing or unknown value).
func themeFromRequest(r *http.Request) string {
	// Read the cookie; an error means it is not there.
	c, err := r.Cookie(themeCookieName)
	// No cookie: follow the system.
	if err != nil {
		// The empty text means follow the system.
		return ""
	} // end of the cookie check
	// Only the two known words are accepted, so a changed cookie can never put other text into the page.
	if c.Value == "light" || c.Value == "dark" {
		// A valid choice.
		return c.Value
	} // end of the value check
	// Anything else is ignored.
	return ""
} // end of themeFromRequest

// themeHandler handles the POST that the theme switch sends: it checks where the request came from, checks the page token, saves the choice in a cookie and goes back to the page.
func themeHandler(token string) http.HandlerFunc {
	// Return the handler function.
	return func(w http.ResponseWriter, r *http.Request) {
		// Never read more than 1 KB of form data; the real form is tiny.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// Only a form on this very page may send this request.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return
		} // end of the origin check
		// Read the form fields.
		if err := r.ParseForm(); err != nil {
			// A broken or too large form.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the form check
		// The token proves the form came from a page this monitor made.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Act on the chosen theme.
		switch choice := r.PostFormValue("theme"); choice {
		// A fixed theme: remember it in the cookie.
		case "light", "dark":
			// Save it for one year; HttpOnly keeps it from page scripts, SameSite=Strict keeps it from other sites.
			http.SetCookie(w, &http.Cookie{Name: themeCookieName, Value: choice, Path: "/", MaxAge: themeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Follow the system: delete the cookie (a negative MaxAge means delete).
		case "system":
			// Send an empty cookie that expires at once.
			http.SetCookie(w, &http.Cookie{Name: themeCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		// Anything else is a mistake.
		default:
			// Refuse.
			http.Error(w, "unknown theme", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the theme choice
		// Go back to the page, which now uses the new theme (303 makes the browser ask with GET).
		http.Redirect(w, r, "/", http.StatusSeeOther)
	} // end of the handler
} // end of themeHandler
EOF_THEME

# Write guard_test.go; the quoted EOF_GUARDTEST marker saves every character exactly as typed.
cat > guard_test.go << 'EOF_GUARDTEST'
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
EOF_GUARDTEST

# Write webtheme_test.go; the quoted EOF_THEMETEST marker saves every character exactly as typed.
cat > webtheme_test.go << 'EOF_THEMETEST'
// Package main tells Go that this test file belongs to the same program as web.go and theme.go.
package main

import ( // import lists the packages this test file uses.
	// io reads a whole reply body.
	"io"
	// net/http provides requests, cookies and status codes.
	"net/http"
	// net/http/httptest records replies without starting a real server.
	"net/http/httptest"
	// net/url builds form data.
	"net/url"
	// regexp finds the token in the page.
	"regexp"
	// strings searches and builds text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// themeRig is a handler plus the token that its page carries.
type themeRig struct {
	// h is the web handler under test.
	h http.Handler
	// token is the token found in the page the handler served.
	token string
} // end of themeRig

// newThemeRig builds a handler for an online fake Ollama and reads the token from its page.
func newThemeRig(t *testing.T) themeRig {
	// Mark this as a helper.
	t.Helper()
	// A fake Ollama that is online.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Build the handler once, because the token belongs to one handler.
	h := handlerFor(t, srv.URL)
	// Fetch the page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the hidden token field.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
	// The page must carry a token.
	if m == nil {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// Hand back the pair.
	return themeRig{h: h, token: m[1]}
} // end of newThemeRig

// post sends a form to the handler with the given headers and returns the recorded reply.
func post(t *testing.T, h http.Handler, path string, form url.Values, headers map[string]string) *http.Response {
	// Mark this as a helper.
	t.Helper()
	// Build the request with the form as its body.
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(form.Encode()))
	// Tell the server the body is a form.
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	// Set the headers of the case.
	for k, v := range headers {
		// One header.
		req.Header.Set(k, v)
	} // end of the header loop
	// Run the handler.
	rec := httptest.NewRecorder()
	// Serve.
	h.ServeHTTP(rec, req)
	// Hand back the finished reply.
	return rec.Result()
} // end of post

// fromThisPage is the header a browser sends when a form on this page is submitted.
var fromThisPage = map[string]string{"Sec-Fetch-Site": "same-origin"}

// TestThemeToggleOnPage checks the switch, the token and that Auto is hidden by default.
func TestThemeToggleOnPage(t *testing.T) {
	// Build the rig and fetch the page again for its text.
	rig := newThemeRig(t)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// The form posts to /theme.
	if !strings.Contains(body, `method="post" action="/theme"`) {
		// Report the problem.
		t.Errorf("the theme form is missing")
	} // end of the form check
	// The switch is two buttons: one to dark and one to light; the stylesheet shows one of them.
	for _, want := range []string{
		// The button that goes to dark, with its name for screen readers.
		`name="theme" value="dark" class="switch to-dark" aria-label="Switch to dark theme"`,
		// The button that goes to light.
		`name="theme" value="light" class="switch to-light" aria-label="Switch to light theme"`,
		// The symbols sit in the knobs and are hidden from screen readers.
		`<span class="knob" aria-hidden="true">☀</span>`, `<span class="knob" aria-hidden="true">☾</span>`,
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// Without a saved theme there is no Auto button and no fixed theme on the html tag.
	if strings.Contains(body, "autobtn") || strings.Contains(body, "data-theme") {
		// Report the problem.
		t.Errorf("Auto button or data-theme shown without a saved choice")
	} // end of the default check
} // end of TestThemeToggleOnPage

// TestThemeCookieIsUsed checks the page follows the saved theme, shows Auto only then, and ignores unknown values.
func TestThemeCookieIsUsed(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// A table of cookie values and the expected result.
	for _, tc := range []struct {
		// value is the cookie value.
		value string
		// attr is the expected html attribute, or empty for none.
		attr string
		// auto is true when the Auto button must be shown (a theme is saved).
		auto bool
	}{ // the cases follow
		// A saved dark choice.
		{"dark", `data-theme="dark"`, true},
		// A saved light choice.
		{"light", `data-theme="light"`, true},
		// A changed cookie must be ignored and must never reach the page.
		{"<script>alert(1)</script>", "", false},
		// An unknown word is ignored too.
		{"purple", "", false},
	} { // end of the table
		// Build the request with the cookie.
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		// Attach it.
		req.AddCookie(&http.Cookie{Name: themeCookieName, Value: tc.value})
		// Run the handler.
		rec := httptest.NewRecorder()
		// Serve.
		rig.h.ServeHTTP(rec, req)
		// Read the page.
		b, _ := io.ReadAll(rec.Result().Body)
		// Convert to text.
		body := string(b)
		// The attribute must match.
		if tc.attr != "" && !strings.Contains(body, tc.attr) {
			// Report the problem.
			t.Errorf("cookie %q: page lacks %s", tc.value, tc.attr)
		} // end of the attribute check
		// An empty expectation means no data-theme at all.
		if tc.attr == "" && strings.Contains(body, "data-theme") {
			// Report the problem.
			t.Errorf("cookie %q: data-theme should be absent", tc.value)
		} // end of the absence check
		// The Auto button is shown exactly when a theme is saved.
		if strings.Contains(body, `class="autobtn"`) != tc.auto {
			// Report the problem.
			t.Errorf("cookie %q: Auto button shown = %v, want %v", tc.value, !tc.auto, tc.auto)
		} // end of the Auto check
		// No script may ever appear.
		if strings.Contains(body, "<script>") {
			// Report the problem.
			t.Errorf("cookie %q put a script into the page", tc.value)
		} // end of the script check
	} // end of the loop
} // end of TestThemeCookieIsUsed

// TestThemePostSetsCookie checks a valid post saves the theme and goes back to the page.
func TestThemePostSetsCookie(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Post "dark" with the right token from this page.
	res := post(t, rig.h, "/theme", url.Values{"token": {rig.token}, "theme": {"dark"}}, fromThisPage)
	// It must redirect to the page.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Report the problem.
		t.Fatalf("status %d, Location %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// Exactly one cookie must be set.
	cookies := res.Cookies()
	// Check the count.
	if len(cookies) != 1 {
		// Stop the test.
		t.Fatalf("%d cookies, want 1", len(cookies))
	} // end of the count check
	// A short name for it.
	c := cookies[0]
	// Check every property that matters for safety.
	if c.Name != themeCookieName || c.Value != "dark" || c.Path != "/" || !c.HttpOnly || c.SameSite != http.SameSiteStrictMode || c.MaxAge <= 0 {
		// Report the problem.
		t.Errorf("unexpected cookie: %+v", c)
	} // end of the cookie check
} // end of TestThemePostSetsCookie

// TestThemePostSystemDeletesCookie checks that System removes the saved choice.
func TestThemePostSystemDeletesCookie(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Post "system".
	res := post(t, rig.h, "/theme", url.Values{"token": {rig.token}, "theme": {"system"}}, fromThisPage)
	// It must redirect.
	if res.StatusCode != http.StatusSeeOther {
		// Stop the test.
		t.Fatalf("status %d, want 303", res.StatusCode)
	} // end of the status check
	// The cookie must be an expiring empty one.
	cookies := res.Cookies()
	// Check it.
	if len(cookies) != 1 || cookies[0].Value != "" || cookies[0].MaxAge >= 0 {
		// Report the problem.
		t.Errorf("unexpected cookies: %+v", cookies)
	} // end of the cookie check
} // end of TestThemePostSystemDeletesCookie

// TestThemePostRefusals checks every way a post can be refused, and that a refusal never sets a cookie.
func TestThemePostRefusals(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
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
		// A page on another site posts the form (with a guessed token).
		{"cross-site", url.Values{"token": {rig.token}, "theme": {"dark"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// A script without any browser headers.
		{"no origin headers", url.Values{"token": {rig.token}, "theme": {"dark"}}, map[string]string{}, http.StatusForbidden},
		// The right origin but no token.
		{"missing token", url.Values{"theme": {"dark"}}, fromThisPage, http.StatusForbidden},
		// The right origin but a wrong token.
		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "theme": {"dark"}}, fromThisPage, http.StatusForbidden},
		// A theme name that does not exist.
		{"unknown theme", url.Values{"token": {rig.token}, "theme": {"purple"}}, fromThisPage, http.StatusBadRequest},
		// No theme at all.
		{"no theme", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
		// A body larger than the 1 KB limit.
		{"too large", url.Values{"token": {rig.token}, "theme": {"dark"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Send it.
			res := post(t, rig.h, "/theme", tc.form, tc.headers)
			// Compare the status.
			if res.StatusCode != tc.want {
				// Report the difference.
				t.Errorf("status %d, want %d", res.StatusCode, tc.want)
			} // end of the status check
			// A refusal must never set a cookie.
			if len(res.Cookies()) != 0 {
				// Report the problem.
				t.Errorf("a refused request set a cookie: %+v", res.Cookies())
			} // end of the cookie check
		}) // end of the subtest
	} // end of the loop
} // end of TestThemePostRefusals

// TestThemeRoutes checks that /theme accepts only POST.
func TestThemeRoutes(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// A GET must be refused with 405 (method not allowed).
	if status, _, _ := get(t, rig.h, http.MethodGet, "/theme"); status != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("GET /theme = %d, want 405", status)
	} // end of the GET check
} // end of TestThemeRoutes

// TestTokenDiffersBetweenHandlers checks that each handler has its own token, so a token from one run is useless in another.
func TestTokenDiffersBetweenHandlers(t *testing.T) {
	// Two rigs.
	a, b := newThemeRig(t), newThemeRig(t)
	// The tokens must differ.
	if a.token == b.token {
		// Report the problem.
		t.Errorf("two handlers share a token")
	} // end of the check
	// A token from handler A must not work on handler B.
	res := post(t, b.h, "/theme", url.Values{"token": {a.token}, "theme": {"dark"}}, fromThisPage)
	// It must be refused.
	if res.StatusCode != http.StatusForbidden {
		// Report the problem.
		t.Errorf("a foreign token gave status %d, want 403", res.StatusCode)
	} // end of the status check
} // end of TestTokenDiffersBetweenHandlers

// TestPolicyAllowsOnlySameFormTarget checks the safety policy changed in exactly the intended way.
func TestPolicyAllowsOnlySameFormTarget(t *testing.T) {
	// Forms may send to this same address only.
	if !strings.Contains(contentSecurityPolicy, "form-action 'self'") {
		// Report the problem.
		t.Errorf("form-action should be 'self': %s", contentSecurityPolicy)
	} // end of the form check
	// Scripts must still be forbidden.
	if strings.Contains(contentSecurityPolicy, "script-src") || !strings.Contains(contentSecurityPolicy, "default-src 'none'") {
		// Report the problem.
		t.Errorf("scripts must stay forbidden: %s", contentSecurityPolicy)
	} // end of the script check
} // end of TestPolicyAllowsOnlySameFormTarget

// TestStylesheetHasThemeRules checks the rules the theme switch depends on.
func TestStylesheetHasThemeRules(t *testing.T) {
	// The stylesheet text is embedded in the program.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// A chosen dark theme has its own colours.
		"chosen dark": `:root[data-theme="dark"]`,
		// The automatic dark theme steps aside when a theme was chosen.
		"automatic dark steps aside": `:root:not([data-theme="light"]):not([data-theme="dark"])`,
		// The switch is drawn as a small rounded track.
		"switch track": ".switch {",
		// The knob is a round disc.
		"switch knob": ".knob {",
		// Under the dark theme the switch to light is shown.
		"switch to light when dark": `:root[data-theme="dark"] .switch.to-light`,
		// The switch also follows the computer's dark setting when no theme was chosen.
		"switch follows the computer": `:root:not([data-theme]) .switch.to-light`,
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestStylesheetHasThemeRules
EOF_THEMETEST

# Edit the existing files with a small Python program; the quoted EOF_PY marker saves every character exactly as typed.
python3 - << 'EOF_PY'
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

# The safety policy now lets a form send to this same page (it was "no forms at all"); web.go.
replace_once("web.go",
    "form-action 'none'",
    "form-action 'self'")
# The comment above the policy says the same (web.go).
replace_once("web.go",
    "no scripts, no frames, no forms.",
    "no scripts, no frames, and forms that send only to this same page.")
# Two new fields for the page data: the saved theme and the page token (web.go).
replace_once("web.go",
    "} // end of pageData\n",
    "\t// Theme is the saved choice, light or dark; empty means follow the system.\n\tTheme string\n\t// Token is the page token that every form on the page carries.\n\tToken string\n} // end of pageData\n")
# The token and the theme route are made when the handler is built (web.go).
replace_once("web.go",
    "\t// Create a router for the two routes.\n\tmux := http.NewServeMux()\n",
    "\t// Create the page token: an unguessable value that every form on the page carries, so only this page can send a form (requirement S2).\n\ttoken := mustToken()\n\t// Create a router for the routes.\n\tmux := http.NewServeMux()\n\t// Route: a POST request for \"/theme\" saves the chosen theme in a cookie (the checks are in theme.go).\n\tmux.HandleFunc(\"POST /theme\", themeHandler(token))\n")
# The page data gets the theme and the token (web.go).
replace_once("web.go",
    "\t\t\t// The reason, if offline.\n\t\t\tReason: res.Reason,\n\t\t} // end of the data\n",
    "\t\t\t// The reason, if offline.\n\t\t\tReason: res.Reason,\n\t\t\t// The saved theme choice, from the cookie; empty means follow the system.\n\t\t\tTheme: themeFromRequest(r),\n\t\t\t// The page token for the forms.\n\t\t\tToken: token,\n\t\t} // end of the data\n")

# The server is wrapped in the Host-name check (main.go).
replace_once("main.go",
    "Handler: newWebHandler(addr, defaultCheckTimeout),",
    "Handler: hostGuard(newWebHandler(addr, defaultCheckTimeout), *listen),")
# The comment above it says so (main.go).
replace_once("main.go",
    "Handler is the web interface from web.go,",
    "Handler is the web interface from web.go wrapped in the Host-name check from guard.go,")

# The page remembers the theme in the html tag (web/index.html).
replace_once("web/index.html",
    "<html lang=\"en\">\n",
    "<html lang=\"en\"{{if .Theme}} data-theme=\"{{.Theme}}\"{{end}}>\n")
# The header gets the theme switch (web/index.html).
replace_once("web/index.html",
    "<header>\n{{/* The main heading. */}}\n<h1>OllamaControlCenter</h1>\n{{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}\n<p class=\"muted\">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>\n</header>",
    "<header class=\"headrow\">\n{{/* The title block on the left. */}}\n<div>\n{{/* The main heading. */}}\n<h1>OllamaControlCenter</h1>\n{{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}\n<p class=\"muted\">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>\n{{/* End of the title block. */}}\n</div>\n{{/* The theme form on the right: it sends the choice to the monitor, which saves it in a cookie. */}}\n<form class=\"themeform\" method=\"post\" action=\"/theme\">\n{{/* The page token proves the form comes from this page. */}}\n<input type=\"hidden\" name=\"token\" value=\"{{.Token}}\">\n{{/* A small Auto button, shown only after a theme was saved, to go back to following the computer's setting. */}}\n{{if .Theme}}\n{{/* The button sends the word system, which deletes the cookie. */}}\n<button type=\"submit\" name=\"theme\" value=\"system\" class=\"autobtn\" aria-label=\"Follow the computer's theme setting\">Auto</button>\n{{/* End of the Auto button. */}}\n{{end}}\n{{/* The switch is two buttons that look like one slider; the stylesheet shows only the one that switches to the other theme. */}}\n<button type=\"submit\" name=\"theme\" value=\"dark\" class=\"switch to-dark\" aria-label=\"Switch to dark theme\"><span class=\"knob\" aria-hidden=\"true\">☀</span></button>\n{{/* The same switch seen from the dark theme: the knob sits on the right. */}}\n<button type=\"submit\" name=\"theme\" value=\"light\" class=\"switch to-light\" aria-label=\"Switch to light theme\"><span class=\"knob\" aria-hidden=\"true\">☾</span></button>\n{{/* End of the theme form. */}}\n</form>\n</header>")

# The automatic dark theme applies only when the person has not chosen light or dark (web/app.css).
replace_once("web/app.css",
    "@media (prefers-color-scheme: dark) {\n  /* The dark set of colours. */\n  :root {\n",
    "@media (prefers-color-scheme: dark) {\n  /* The dark set of colours, used only when no theme was chosen with the buttons. */\n  :root:not([data-theme=\"light\"]):not([data-theme=\"dark\"]) {\n")
# The same dark colours for a chosen dark theme, and the styles of the theme buttons (web/app.css).
replace_once("web/app.css",
    "/* Page-wide basics: the system font, our colours, and comfortable line spacing. */\n",
    """/* The dark set again, used when the person chose Dark with the buttons (a chosen Light needs no rule: the light colours above are the default). */
:root[data-theme="dark"] {
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
  /* Colour of the dot for a loaded model (contrast 8:1 on the page). */
  --dot-on: #3fb950;
  /* Category row background: a deep slate blue band (text contrast 10.1:1). */
  --cat-bg: #1f3550;
  /* Category row text colour: pale blue. */
  --cat-text: #dbe9fb;
  /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
  --cat-accent: #7fb2f0;
  /* Tell the browser to draw its own controls in dark colours. */
  color-scheme: dark;
} /* end of rule */

/* Page-wide basics: the system font, our colours, and comfortable line spacing. */
""")
# The header row and the theme switch get their styles at the end of app.css, once (recognised by the ".headrow {" rule).
path = pathlib.Path("web/app.css")
# Read the file.
text = path.read_text()
# Only add the rules when they are not there yet.
if "\n.headrow {" not in text:
    # Append the rules.
    text += """
/* The header: title on the left, theme switch on the right; they wrap under each other in a narrow window. */
.headrow {
  /* Put the two blocks side by side. */
  display: flex;
  /* Let them wrap in a narrow window. */
  flex-wrap: wrap;
  /* Title left, theme buttons right. */
  justify-content: space-between;
  /* Line the blocks up at the top. */
  align-items: flex-start;
  /* Space between the blocks when they wrap. */
  gap: 0.5rem 1rem;
} /* end of rule */

/* The theme form: the Auto button (when shown) and the switch in one line. */
.themeform {
  /* Side by side. */
  display: flex;
  /* Centre them vertically. */
  align-items: center;
  /* Space between the Auto button and the switch. */
  gap: 0.6rem;
  /* No extra space around the form. */
  margin: 0;
} /* end of rule */

/* The theme switch: a small rounded slider with a knob. */
.switch {
  /* A box that holds the knob. */
  display: inline-flex;
  /* Centre the knob vertically. */
  align-items: center;
  /* Small: about the size of two letters. */
  width: 2.8rem;
  /* A low, pill-shaped height. */
  height: 1.5rem;
  /* A little room around the knob. */
  padding: 0.1rem;
  /* The border counts inside the size. */
  box-sizing: border-box;
  /* A solid outline, visible without colour. */
  border: 2px solid var(--border);
  /* Rounded ends. */
  border-radius: 999px;
  /* Track colour from the variables. */
  background: var(--panel);
  /* A hand cursor shows it can be clicked. */
  cursor: pointer;
} /* end of rule */

/* The switch that goes to the light theme is hidden until the dark theme is showing; its knob sits on the right. */
.switch.to-light {
  /* Hidden by default. */
  display: none;
  /* Knob on the right edge. */
  justify-content: flex-end;
} /* end of rule */

/* A chosen dark theme: hide the switch to dark, show the switch to light. */
:root[data-theme="dark"] .switch.to-dark {
  /* Hide it. */
  display: none;
} /* end of rule */

/* A chosen dark theme: show the switch to light. */
:root[data-theme="dark"] .switch.to-light {
  /* Show it. */
  display: inline-flex;
} /* end of rule */

/* The computer's own dark setting, when no theme was chosen with the switch. */
@media (prefers-color-scheme: dark) {
  /* No chosen theme: hide the switch to dark. */
  :root:not([data-theme]) .switch.to-dark {
    /* Hide it. */
    display: none;
  } /* end of rule */
  /* No chosen theme: show the switch to light. */
  :root:not([data-theme]) .switch.to-light {
    /* Show it. */
    display: inline-flex;
  } /* end of rule */
} /* end of rule */

/* The knob: a round disc with the sun or the moon in it. */
.knob {
  /* Centre the symbol. */
  display: inline-flex;
  /* Centre it vertically. */
  align-items: center;
  /* Centre it horizontally. */
  justify-content: center;
  /* A small disc. */
  width: 1.1rem;
  /* Same height as width, so it is round. */
  height: 1.1rem;
  /* Make it a circle. */
  border-radius: 50%;
  /* The disc uses the text colour... */
  background: var(--text);
  /* ...and the symbol uses the page colour. */
  color: var(--bg);
  /* A small symbol, large enough to tell the sun from the moon. */
  font-size: 0.85rem;
  /* No extra line height. */
  line-height: 1;
} /* end of rule */

/* The switch under the mouse: a stronger outline. */
.switch:hover {
  /* Outline in the text colour. */
  border-color: var(--text);
} /* end of rule */

/* The small Auto button: plain text with a dotted underline, so it stays quiet. */
.autobtn {
  /* Use the page font. */
  font: inherit;
  /* Small text. */
  font-size: 0.75rem;
  /* No button box. */
  background: none;
  /* No border. */
  border: 0;
  /* No padding. */
  padding: 0;
  /* Secondary text colour. */
  color: var(--muted);
  /* A dotted underline shows it can be clicked. */
  text-decoration: underline dotted;
  /* A hand cursor. */
  cursor: pointer;
} /* end of rule */
"""
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: web/app.css (added the header and theme switch rules)")
EOF_PY

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
# Read the page token from the hidden form field (grep -o prints only the match, sed keeps only the 32 characters; || true so a missing token is reported by the check, not by stopping here).
TOKEN="$(grep -o 'name="token" value="[0-9a-f]*"' <<< "$PAGE" | sed 's/.*value="//; s/"//' || true)"
# Ask for the safety headers of the page (-D - prints the headers; -o /dev/null drops the body).
HEADERS="$(curl -s -D - -o /dev/null "$BASE/")"

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

# Check 1: the page has the theme switch, which is two buttons (to dark and to light).
check "page has the theme switch (2 buttons)" "$([ "$(grep -o 'name="theme" value="' <<< "$PAGE" | wc -l || true)" = "2" ] && echo yes || echo no)"
# Check 2: the page carries a 32-character token.
check "page carries a 32-character token" "$([ "${#TOKEN}" = "32" ] && echo yes || echo no)"
# Check 3: a request with a foreign Host name (the DNS rebinding trick) is refused.
check "foreign Host name is refused (403)" "$([ "$(status -H 'Host: attacker.example:'"$TEST_PORT" "$BASE/")" = "403" ] && echo yes || echo no)"
# Check 4: a form post without browser headers (a script or curl) is refused.
check "post without browser headers is refused (403)" "$([ "$(status -d "theme=dark&token=$TOKEN" "$BASE/theme")" = "403" ] && echo yes || echo no)"
# Check 5: a post that claims to come from another site is refused.
check "post from another site is refused (403)" "$([ "$(status -H 'Sec-Fetch-Site: cross-site' -d "theme=dark&token=$TOKEN" "$BASE/theme")" = "403" ] && echo yes || echo no)"
# Check 6: a post from this page but with a wrong token is refused.
check "post with a wrong token is refused (403)" "$([ "$(status -H 'Sec-Fetch-Site: same-origin' -d 'theme=dark&token=00000000000000000000000000000000' "$BASE/theme")" = "403" ] && echo yes || echo no)"
# Check 7: a post that looks exactly like the page's own form is accepted and sends the browser back to the page (303).
check "post that looks like the page's form is accepted (303)" "$([ "$(status -H 'Sec-Fetch-Site: same-origin' -d "theme=dark&token=$TOKEN" "$BASE/theme")" = "303" ] && echo yes || echo no)"
# Check 8: the cookie that comes back is HttpOnly and SameSite=Strict (grep -i ignores capital letters).
COOKIE="$(curl -s -D - -o /dev/null -H 'Sec-Fetch-Site: same-origin' -d "theme=dark&token=$TOKEN" "$BASE/theme" | grep -i '^set-cookie' || true)"
# The cookie must carry both protections.
check "theme cookie is HttpOnly and SameSite=Strict" "$(grep -qi 'httponly' <<< "$COOKIE" && grep -qi 'samesite=strict' <<< "$COOKIE" && echo yes || echo no)"
# Check 9: a GET to the theme address is refused (it accepts only POST).
check "GET to /theme is refused (405)" "$([ "$(status "$BASE/theme")" = "405" ] && echo yes || echo no)"
# Check 10: the safety policy allows forms only to this page and still has no script rule.
check "policy has form-action 'self' and no script-src" "$(grep -qi "form-action 'self'" <<< "$HEADERS" && ! grep -qi 'script-src' <<< "$HEADERS" && echo yes || echo no)"
# Check 11: the page still has no script, no style tag and no inline style.
check "page has no script or inline style" "$(grep -qiE '<script|<style| style=' <<< "$PAGE" && echo no || echo yes)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
