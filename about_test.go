// Package main tells Go that this test file belongs to the same program as about.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides requests and status codes.
	"net/http"
	// net/http/httptest records replies without starting a real server.
	"net/http/httptest"
	// runtime/debug provides the build-info type that the test fakes.
	"runtime/debug"
	// strings searches text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// withBuildInfo replaces the build-info reader for one test.
func withBuildInfo(t *testing.T, info *debug.BuildInfo) {
	// Mark this as a helper.
	t.Helper()
	// Remember the real one.
	old := readBuildInfo
	// Put it back when the test ends.
	t.Cleanup(func() { readBuildInfo = old })
	// Install the fake: nil means "nothing recorded".
	readBuildInfo = func() (*debug.BuildInfo, bool) { return info, info != nil }
} // end of withBuildInfo

// TestAboutPageShowsTheRequiredFacts checks the names, the dedication, the version and the safe headers.
func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
	// A build that recorded a revision, a UTC time and uncommitted changes.
	withBuildInfo(t, &debug.BuildInfo{Settings: []debug.BuildSetting{
		// The commit.
		{Key: "vcs.revision", Value: "0123456789abcdef0123456789abcdef01234567"},
		// Its time in UTC.
		{Key: "vcs.time", Value: "2026-10-27T17:50:00Z"},
		// Uncommitted changes.
		{Key: "vcs.modified", Value: "true"},
	}})
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the page.
	status, header, body := get(t, rig.h, http.MethodGet, "/about")
	// It must be a normal page.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") {
		// Stop the test.
		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the status check
	// What must be there, word for word.
	for _, want := range []string{
		// The heading.
		"About Ollama Control Center",
		// The developer.
		"Shrinivas Kodati",
		// The developer's LinkedIn profile, safe to follow.
		`href="https://www.linkedin.com/in/shrinikodati/" target="_blank" rel="noopener noreferrer">LinkedIn profile<span class="sr-only"> (opens in a new window)</span></a>`,
		// The assistant with its version.
		"Claude (Sonnet 5.5), Anthropic",
		// The dedication, exactly as the developer wrote it.
		"Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this.",
		// The version.
		appVersion,
		// The short revision, twelve characters.
		"<code>0123456789ab</code>",
		// The uncommitted-changes note.
		"built with uncommitted changes",
		// The revision date with its time zone written out.
		"committed 27 Oct 2026 17:50 UTC",
		// The licence line.
		"2026 Shrinivas Kodati. All rights reserved.",
		// The repository link, safe to follow.
		`href="https://github.com/kodati3shrini3/OllamaControlCenter" target="_blank" rel="noopener noreferrer"`,
		// The way back.
		`href="/"`,
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("About page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// No scripts on this page.
	if strings.Contains(body, "<script") {
		// Report the problem.
		t.Errorf("the About page contains a script")
	} // end of the script check
	// The strict policy applies to it too.
	if !strings.Contains(header.Get("Content-Security-Policy"), "default-src 'none'") {
		// Report the problem.
		t.Errorf("no strict content policy on the About page")
	} // end of the policy check
} // end of TestAboutPageShowsTheRequiredFacts

// TestAboutPageWithoutBuildInfo checks the page says plainly when the build recorded nothing.
func TestAboutPageWithoutBuildInfo(t *testing.T) {
	// A build with no record.
	withBuildInfo(t, nil)
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/about")
	// The plain words.
	if !strings.Contains(body, "not recorded in this build") {
		// Report the problem.
		t.Errorf("no plain note about the missing revision")
	} // end of the note check
} // end of TestAboutPageWithoutBuildInfo

// TestAboutPageDateIsAlwaysUTC checks a revision time given with another offset is shown in UTC with the zone named.
func TestAboutPageDateIsAlwaysUTC(t *testing.T) {
	// A time with an offset of one hour.
	withBuildInfo(t, &debug.BuildInfo{Settings: []debug.BuildSetting{
		// A short hash.
		{Key: "vcs.revision", Value: "abc"},
		// 19:06 at +01:00 is 18:06 UTC.
		{Key: "vcs.time", Value: "2026-10-27T19:06:00+01:00"},
	}})
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/about")
	// It must be converted.
	if !strings.Contains(body, "27 Oct 2026 18:06 UTC") {
		// Report the problem.
		t.Errorf("revision date not shown in UTC")
	} // end of the date check
} // end of TestAboutPageDateIsAlwaysUTC

// TestAboutPageFollowsThemeAndSize checks the saved theme and text size apply to this page too.
func TestAboutPageFollowsThemeAndSize(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// A request with both cookies.
	req := httptest.NewRequest(http.MethodGet, "/about", nil)
	// The theme.
	req.AddCookie(&http.Cookie{Name: themeCookieName, Value: "dark"})
	// The size.
	req.AddCookie(&http.Cookie{Name: sizeCookieName, Value: "medium"})
	// Serve.
	rec := httptest.NewRecorder()
	// Run it.
	rig.h.ServeHTTP(rec, req)
	// Both must be on the html tag.
	if body := rec.Body.String(); !strings.Contains(body, `data-theme="dark"`) || !strings.Contains(body, `data-size="medium"`) {
		// Report the problem.
		t.Errorf("theme or size missing on the About page")
	} // end of the check
} // end of TestAboutPageFollowsThemeAndSize

// TestAboutPageIsReadOnly checks the page accepts only GET.
func TestAboutPageIsReadOnly(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// A POST must be refused with 405.
	if status, _, _ := get(t, rig.h, http.MethodPost, "/about"); status != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("POST /about = %d, want 405", status)
	} // end of the method check
} // end of TestAboutPageIsReadOnly
