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
