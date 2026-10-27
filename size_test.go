// Package main tells Go that this test file belongs to the same program as size.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides requests, cookies and status codes.
	"net/http"
	// net/http/httptest records replies without starting a real server.
	"net/http/httptest"
	// net/url builds form data.
	"net/url"
	// os reads the template and stylesheet sources.
	"os"
	// path/filepath lists the template files.
	"path/filepath"
	// regexp finds icon sizes in the templates.
	"regexp"
	// strings searches and builds text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// pageWithSizeCookie fetches a path with the size cookie set to the given value.
func pageWithSizeCookie(t *testing.T, h http.Handler, path, value string) string {
	// Mark this as a helper.
	t.Helper()
	// Build the request.
	req := httptest.NewRequest(http.MethodGet, path, nil)
	// Attach the cookie.
	req.AddCookie(&http.Cookie{Name: sizeCookieName, Value: value})
	// Run the handler.
	rec := httptest.NewRecorder()
	// Serve.
	h.ServeHTTP(rec, req)
	// Hand back the page text.
	return rec.Body.String()
} // end of pageWithSizeCookie

// TestSizeSwitchOnPage checks the default look of the switch: Large, knob L on the right, no Auto, no data-size.
func TestSizeSwitchOnPage(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// What must be there.
	for _, want := range []string{
		// The form posts to /textsize.
		`method="post" action="/textsize"`,
		// The switch to Medium, with its knob showing L, and a keyboard-friendly help bubble.
		`name="size" value="medium" class="switch switch-right" aria-describedby="tipsize"`,
		// The knob letter.
		`<span class="knob knob-letter" aria-hidden="true">L</span>`,
		// The help bubble with both sizes explained.
		`role="tooltip" id="tipsize">Text size: now Large (L)`,
		// The About button in the footer bar.
		`<a class="brandbtn" href="/about">About this program</a>`,
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// No saved size: no data-size on the html tag and no Auto for the size.
	if strings.Contains(body, "data-size") || strings.Contains(body, `value="auto"`) {
		// Report the problem.
		t.Errorf("data-size or the size Auto button shown without a saved choice")
	} // end of the default check
} // end of TestSizeSwitchOnPage

// TestSizeCookieIsUsed checks the page follows the saved size, shows Auto only then, and ignores unknown values.
func TestSizeCookieIsUsed(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Medium is saved.
	body := pageWithSizeCookie(t, rig.h, "/", "medium")
	// What must be there.
	for _, want := range []string{
		// The html tag carries the size, which the stylesheet turns into 81 percent.
		`data-size="medium"`,
		// The Auto button for the size.
		`name="size" value="auto" class="autobtn"`,
		// The switch back to Large, with the M knob.
		`name="size" value="large" class="switch" aria-describedby="tipsize"`, `>M</span>`,
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("medium page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// Values that are not "medium" must be ignored and must never reach the page.
	for _, bad := range []string{"large", "<script>alert(1)</script>", "huge", ""} {
		// Fetch with the odd value.
		body := pageWithSizeCookie(t, rig.h, "/", bad)
		// Nothing of it may show.
		if strings.Contains(body, "data-size") || strings.Contains(body, "<script>alert") {
			// Report the problem.
			t.Errorf("cookie value %q changed the page", bad)
		} // end of the check
	} // end of the loop
} // end of TestSizeCookieIsUsed

// TestSizePostSetsAndClearsCookie checks Medium saves a safe cookie, and Large or Auto remove it.
func TestSizePostSetsAndClearsCookie(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Post "medium".
	res := post(t, rig.h, "/textsize", url.Values{"token": {rig.token}, "size": {"medium"}}, fromThisPage)
	// It must redirect to the page.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Stop the test.
		t.Fatalf("status %d, Location %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// Exactly one cookie.
	cookies := res.Cookies()
	// Check the count.
	if len(cookies) != 1 {
		// Stop the test.
		t.Fatalf("%d cookies, want 1", len(cookies))
	} // end of the count check
	// A short name.
	c := cookies[0]
	// Every property that matters for safety.
	if c.Name != sizeCookieName || c.Value != "medium" || c.Path != "/" || !c.HttpOnly || c.SameSite != http.SameSiteStrictMode || c.MaxAge <= 0 {
		// Report the problem.
		t.Errorf("unexpected cookie: %+v", c)
	} // end of the cookie check
	// Large and Auto both clear it.
	for _, word := range []string{"large", "auto"} {
		// Post it.
		res := post(t, rig.h, "/textsize", url.Values{"token": {rig.token}, "size": {word}}, fromThisPage)
		// The cookie must be an expiring empty one.
		cs := res.Cookies()
		// Check it.
		if res.StatusCode != http.StatusSeeOther || len(cs) != 1 || cs[0].Value != "" || cs[0].MaxAge >= 0 {
			// Report the problem.
			t.Errorf("%s: status %d, cookies %+v", word, res.StatusCode, cs)
		} // end of the check
	} // end of the loop
} // end of TestSizePostSetsAndClearsCookie

// TestSizePostRefusals checks every way a post can be refused, and that a refusal never sets a cookie.
func TestSizePostRefusals(t *testing.T) {
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
		// Another site posts the form.
		{"cross-site", url.Values{"token": {rig.token}, "size": {"medium"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// No browser headers at all.
		{"no origin headers", url.Values{"token": {rig.token}, "size": {"medium"}}, map[string]string{}, http.StatusForbidden},
		// No token.
		{"missing token", url.Values{"size": {"medium"}}, fromThisPage, http.StatusForbidden},
		// A wrong token.
		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "size": {"medium"}}, fromThisPage, http.StatusForbidden},
		// A size that does not exist.
		{"unknown size", url.Values{"token": {rig.token}, "size": {"huge"}}, fromThisPage, http.StatusBadRequest},
		// No size at all.
		{"no size", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
		// A body larger than the 1 KB limit.
		{"too large", url.Values{"token": {rig.token}, "size": {"medium"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Send it.
			res := post(t, rig.h, "/textsize", tc.form, tc.headers)
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
	// A GET must be refused with 405.
	if status, _, _ := get(t, rig.h, http.MethodGet, "/textsize"); status != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("GET /textsize = %d, want 405", status)
	} // end of the GET check
} // end of TestSizePostRefusals

// TestEveryPageCarriesTheSize is a guard: every page template must put the saved size on its html tag, or that page would ignore the choice.
func TestEveryPageCarriesTheSize(t *testing.T) {
	// All templates.
	files, err := filepath.Glob("web/*.html")
	// A failure here is a broken test setup.
	if err != nil || len(files) < 10 {
		// Stop the test.
		t.Fatalf("templates not found: %v (%d files)", err, len(files))
	} // end of the glob check
	// Check each.
	for _, f := range files {
		// Read it.
		data, err := os.ReadFile(f)
		// A failure here is a broken test setup.
		if err != nil {
			// Stop the test.
			t.Fatalf("cannot read %s: %v", f, err)
		} // end of the read check
		// Only full pages have an html tag.
		if !strings.Contains(string(data), "<html") {
			// Skip it.
			continue
		} // end of the page check
		// The attribute must be there.
		if !strings.Contains(string(data), `{{if .Size}} data-size="{{.Size}}"{{end}}`) {
			// Report the problem.
			t.Errorf("%s does not carry the saved text size on its html tag", f)
		} // end of the attribute check
	} // end of the loop
} // end of TestEveryPageCarriesTheSize

// TestMediumScalesTheIcons is a guard: the stylesheet must shrink the page to 81 percent, and every icon size used in a template must have its own 81 percent rule.
func TestMediumScalesTheIcons(t *testing.T) {
	// The stylesheet.
	css, err := os.ReadFile("web/app.css")
	// A failure here is a broken test setup.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot read the stylesheet: %v", err)
	} // end of the read check
	// The root rule.
	if !strings.Contains(string(css), "html[data-size=\"medium\"] {\n  /* Percent of the browser's own size works in every browser and keeps the person's own browser setting as the base. */\n  font-size: 81%;") {
		// Report the problem.
		t.Errorf("the 81 percent rule is missing")
	} // end of the root check
	// All templates.
	files, _ := filepath.Glob("web/*.html")
	// An svg with a pixel width.
	svg := regexp.MustCompile(`<svg[^>]* width="([0-9]+)"`)
	// How many icons were found, so the test cannot pass by finding nothing.
	found := 0
	// Check each template.
	for _, f := range files {
		// Read it.
		data, _ := os.ReadFile(f)
		// Every icon.
		for _, m := range svg.FindAllStringSubmatch(string(data), -1) {
			// Count it.
			found++
			// Its rule must exist.
			if !strings.Contains(string(css), `html[data-size="medium"] svg[width="`+m[1]+`"]`) {
				// Report the problem.
				t.Errorf("%s: no Medium rule for icons %s pixels wide", f, m[1])
			} // end of the rule check
		} // end of the icon loop
	} // end of the file loop
	// Icons must exist.
	if found == 0 {
		// Stop the test.
		t.Fatalf("no icons found")
	} // end of the count check
} // end of TestMediumScalesTheIcons
