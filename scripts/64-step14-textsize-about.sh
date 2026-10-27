#!/usr/bin/env bash
# Script 64: a text-size switch (M = 81% of the browser size, L = the browser size) under the theme switch, and an About page (developer, assistant, version, dedication) linked from the footer.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/about-and-text-size" ] || { echo "FAIL  not on feature/about-and-text-size"; exit 1; }
# Scripts 61 to 63 must be part of this branch already (merged into main).
[ -e timezone_test.go ] || { echo "FAIL  the delete-history change (scripts 61 to 63) is not in this branch yet"; exit 1; }
# Refuse to run twice.
if [ -e size.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
new file mode 100644
index 0000000..db56ace
--- /dev/null
+++ b/about.go
@@ -0,0 +1,182 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the packages this file uses.
+	// bytes builds the page in memory before it is sent.
+	"bytes"
+	// html/template builds the page and escapes every inserted text.
+	"html/template"
+	// embed stores the page template inside the executable.
+	_ "embed"
+	// log writes the real reason for an error for the person running the program.
+	"log"
+	// net/http provides the request and response types.
+	"net/http"
+	// runtime/debug reads what the Go tool recorded about this build.
+	"runtime/debug"
+	// runtime tells the Go version and the platform.
+	"runtime"
+	// time reads and shows the revision date.
+	"time"
+) // end of imports
+
+// aboutTemplateText holds the About page, stored inside the executable at build time.
+//
+//go:embed web/about.html
+var aboutTemplateText string
+
+// appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
+const appVersion = "0.13.0"
+
+// appDeveloper is the name of the developer, shown on the About page.
+const appDeveloper = "Shrinivas Kodati"
+
+// appDeveloperProfile is the developer's public LinkedIn profile, linked from the About page.
+const appDeveloperProfile = "https://www.linkedin.com/in/shrinikodati/"
+
+// appAssistant names the assistant and the model version that helped write the program; it is written by hand when the version changes.
+const appAssistant = "Claude (Sonnet 5.5), Anthropic"
+
+// appDedication is the dedication shown on the About page.
+const appDedication = "Dedicated to Ms. Meghna Kodati, without whom I would never have had the inspiration to develop this."
+
+// appCopyright is the copyright line shown on the About page.
+const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
+
+// appRepository is the address of the source code; the repository is private, so only its owner can open it.
+const appRepository = "https://github.com/kodatishrini-beep/OllamaControlCenter"
+
+// readBuildInfo reads the facts the Go tool recorded in the program; a test replaces it.
+var readBuildInfo = debug.ReadBuildInfo
+
+// aboutPage is everything the About page needs.
+type aboutPage struct {
+	// Theme is the saved colour theme, or empty to follow the system.
+	Theme string
+	// Size is the saved text size, or empty for the browser's own size.
+	Size string
+	// Version is appVersion.
+	Version string
+	// Developer is appDeveloper.
+	Developer string
+	// DeveloperProfile is appDeveloperProfile.
+	DeveloperProfile string
+	// Assistant is appAssistant.
+	Assistant string
+	// Dedication is appDedication.
+	Dedication string
+	// Copyright is appCopyright.
+	Copyright string
+	// Repository is appRepository.
+	Repository string
+	// Revision is the short source revision, or empty when the build did not record one.
+	Revision string
+	// Modified is true when the source had uncommitted changes at build time.
+	Modified bool
+	// RevisionDate is the date of the source revision in UTC, with the zone written out, or empty.
+	RevisionDate string
+	// Platform is the Go version, the operating system and the processor type.
+	Platform string
+} // end of aboutPage
+
+// revisionFromBuild picks the short revision, the modified flag and the revision date (always shown in UTC) out of the recorded build facts.
+func revisionFromBuild() (string, bool, string) {
+	// Ask the Go tool's record.
+	info, ok := readBuildInfo()
+	// Nothing recorded, for example under "go run" or when built outside a git folder.
+	if !ok {
+		// Empty means "not recorded".
+		return "", false, ""
+	} // end of the record check
+	// The three facts.
+	var rev, when string
+	// Whether the source differed from the revision.
+	modified := false
+	// Go through the recorded settings.
+	for _, s := range info.Settings {
+		// Pick the ones we show.
+		switch s.Key {
+		// The full commit hash.
+		case "vcs.revision":
+			// Keep it.
+			rev = s.Value
+		// The time of the commit, in UTC.
+		case "vcs.time":
+			// Keep it.
+			when = s.Value
+		// Whether there were uncommitted changes.
+		case "vcs.modified":
+			// The Go tool writes "true" or "false".
+			modified = s.Value == "true"
+		} // end of the key switch
+	} // end of the loop
+	// Twelve characters are enough to find a commit.
+	if len(rev) > 12 {
+		// Cut it.
+		rev = rev[:12]
+	} // end of the length check
+	// The date, shown with its zone.
+	shown := ""
+	// Read the recorded time.
+	if t, err := time.Parse(time.RFC3339, when); err == nil {
+		// Always UTC, written as such, so no one has to guess the zone.
+		shown = t.UTC().Format("2 Jan 2006 15:04 MST")
+	} // end of the time check
+	// Hand back.
+	return rev, modified, shown
+} // end of revisionFromBuild
+
+// aboutHandler builds the handler of the read-only About page; it changes nothing and needs no token.
+func aboutHandler() http.HandlerFunc {
+	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
+	page := template.Must(template.New("about").Parse(aboutTemplateText))
+	// The handler itself.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// The recorded build facts.
+		rev, modified, when := revisionFromBuild()
+		// Fill in what the template shows.
+		data := aboutPage{
+			// The saved theme.
+			Theme: themeFromRequest(r),
+			// The saved text size.
+			Size: sizeFromRequest(r),
+			// The version.
+			Version: appVersion,
+			// The developer.
+			Developer: appDeveloper,
+			// The developer's profile address.
+			DeveloperProfile: appDeveloperProfile,
+			// The assistant.
+			Assistant: appAssistant,
+			// The dedication.
+			Dedication: appDedication,
+			// The copyright line.
+			Copyright: appCopyright,
+			// The source address.
+			Repository: appRepository,
+			// The revision.
+			Revision: rev,
+			// Uncommitted changes.
+			Modified: modified,
+			// The revision date in UTC.
+			RevisionDate: when,
+			// Go version, system and processor.
+			Platform: runtime.Version() + " on " + runtime.GOOS + "/" + runtime.GOARCH,
+		} // end of the data
+		// Build the page in memory first, so a template error produces a clean 500 and not a half page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("about page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of the handler
+} // end of aboutHandler
diff --git a/about_test.go b/about_test.go
new file mode 100644
index 0000000..a33ff52
--- /dev/null
+++ b/about_test.go
@@ -0,0 +1,159 @@
+// Package main tells Go that this test file belongs to the same program as about.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// net/http provides requests and status codes.
+	"net/http"
+	// net/http/httptest records replies without starting a real server.
+	"net/http/httptest"
+	// runtime/debug provides the build-info type that the test fakes.
+	"runtime/debug"
+	// strings searches text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// withBuildInfo replaces the build-info reader for one test.
+func withBuildInfo(t *testing.T, info *debug.BuildInfo) {
+	// Mark this as a helper.
+	t.Helper()
+	// Remember the real one.
+	old := readBuildInfo
+	// Put it back when the test ends.
+	t.Cleanup(func() { readBuildInfo = old })
+	// Install the fake: nil means "nothing recorded".
+	readBuildInfo = func() (*debug.BuildInfo, bool) { return info, info != nil }
+} // end of withBuildInfo
+
+// TestAboutPageShowsTheRequiredFacts checks the names, the dedication, the version and the safe headers.
+func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
+	// A build that recorded a revision, a UTC time and uncommitted changes.
+	withBuildInfo(t, &debug.BuildInfo{Settings: []debug.BuildSetting{
+		// The commit.
+		{Key: "vcs.revision", Value: "0123456789abcdef0123456789abcdef01234567"},
+		// Its time in UTC.
+		{Key: "vcs.time", Value: "2026-10-27T17:50:00Z"},
+		// Uncommitted changes.
+		{Key: "vcs.modified", Value: "true"},
+	}})
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	status, header, body := get(t, rig.h, http.MethodGet, "/about")
+	// It must be a normal page.
+	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") {
+		// Stop the test.
+		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
+	} // end of the status check
+	// What must be there, word for word.
+	for _, want := range []string{
+		// The heading.
+		"About Ollama Control Center",
+		// The developer.
+		"Shrinivas Kodati",
+		// The developer's LinkedIn profile, safe to follow.
+		`href="https://www.linkedin.com/in/shrinikodati/" rel="noopener noreferrer">LinkedIn profile</a>`,
+		// The assistant with its version.
+		"Claude (Sonnet 5.5), Anthropic",
+		// The dedication, exactly as the developer wrote it.
+		"Dedicated to Ms. Meghna Kodati, without whom I would never have had the inspiration to develop this.",
+		// The version.
+		appVersion,
+		// The short revision, twelve characters.
+		"<code>0123456789ab</code>",
+		// The uncommitted-changes note.
+		"built with uncommitted changes",
+		// The revision date with its time zone written out.
+		"committed 27 Oct 2026 17:50 UTC",
+		// The licence line.
+		"2026 Shrinivas Kodati. All rights reserved.",
+		// The repository link, safe to follow.
+		`href="https://github.com/kodatishrini-beep/OllamaControlCenter" rel="noopener noreferrer"`,
+		// The way back.
+		`href="/"`,
+	} { // end of the list
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the problem.
+			t.Errorf("About page does not contain %q", want)
+		} // end of the check
+	} // end of the loop
+	// No scripts on this page.
+	if strings.Contains(body, "<script") {
+		// Report the problem.
+		t.Errorf("the About page contains a script")
+	} // end of the script check
+	// The strict policy applies to it too.
+	if !strings.Contains(header.Get("Content-Security-Policy"), "default-src 'none'") {
+		// Report the problem.
+		t.Errorf("no strict content policy on the About page")
+	} // end of the policy check
+} // end of TestAboutPageShowsTheRequiredFacts
+
+// TestAboutPageWithoutBuildInfo checks the page says plainly when the build recorded nothing.
+func TestAboutPageWithoutBuildInfo(t *testing.T) {
+	// A build with no record.
+	withBuildInfo(t, nil)
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/about")
+	// The plain words.
+	if !strings.Contains(body, "not recorded in this build") {
+		// Report the problem.
+		t.Errorf("no plain note about the missing revision")
+	} // end of the note check
+} // end of TestAboutPageWithoutBuildInfo
+
+// TestAboutPageDateIsAlwaysUTC checks a revision time given with another offset is shown in UTC with the zone named.
+func TestAboutPageDateIsAlwaysUTC(t *testing.T) {
+	// A time with an offset of one hour.
+	withBuildInfo(t, &debug.BuildInfo{Settings: []debug.BuildSetting{
+		// A short hash.
+		{Key: "vcs.revision", Value: "abc"},
+		// 19:06 at +01:00 is 18:06 UTC.
+		{Key: "vcs.time", Value: "2026-10-27T19:06:00+01:00"},
+	}})
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/about")
+	// It must be converted.
+	if !strings.Contains(body, "27 Oct 2026 18:06 UTC") {
+		// Report the problem.
+		t.Errorf("revision date not shown in UTC")
+	} // end of the date check
+} // end of TestAboutPageDateIsAlwaysUTC
+
+// TestAboutPageFollowsThemeAndSize checks the saved theme and text size apply to this page too.
+func TestAboutPageFollowsThemeAndSize(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// A request with both cookies.
+	req := httptest.NewRequest(http.MethodGet, "/about", nil)
+	// The theme.
+	req.AddCookie(&http.Cookie{Name: themeCookieName, Value: "dark"})
+	// The size.
+	req.AddCookie(&http.Cookie{Name: sizeCookieName, Value: "medium"})
+	// Serve.
+	rec := httptest.NewRecorder()
+	// Run it.
+	rig.h.ServeHTTP(rec, req)
+	// Both must be on the html tag.
+	if body := rec.Body.String(); !strings.Contains(body, `data-theme="dark"`) || !strings.Contains(body, `data-size="medium"`) {
+		// Report the problem.
+		t.Errorf("theme or size missing on the About page")
+	} // end of the check
+} // end of TestAboutPageFollowsThemeAndSize
+
+// TestAboutPageIsReadOnly checks the page accepts only GET.
+func TestAboutPageIsReadOnly(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// A POST must be refused with 405.
+	if status, _, _ := get(t, rig.h, http.MethodPost, "/about"); status != http.StatusMethodNotAllowed {
+		// Report the problem.
+		t.Errorf("POST /about = %d, want 405", status)
+	} // end of the method check
+} // end of TestAboutPageIsReadOnly
diff --git a/compare.go b/compare.go
index 681fc0c..a335a06 100644
--- a/compare.go
+++ b/compare.go
@@ -61,6 +61,8 @@ type cmpTable struct {
 type comparePage struct {
 	// Theme is the colour scheme asked for in the address, or empty.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token for the "Back" form.
 	Token string
 	// Tables are the comparison tables (text models, embedding models).
@@ -552,6 +554,8 @@ func compareHandler(addr ollamaAddress, token string, store *perfStore) http.Han
 		data := buildCompare(runs, skipped, installed, err == nil)
 		// Add what every page needs.
 		data.Theme, data.Token = themeFromRequest(r), token
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Where the figures live.
 		path, note := store.where()
 		// A file, or the reason there is none.
diff --git a/control.go b/control.go
index f5b1822..4074cdf 100644
--- a/control.go
+++ b/control.go
@@ -197,6 +197,8 @@ func watchHandler(token string) http.HandlerFunc {
 type controlPage struct {
 	// Theme is the colour scheme asked for in the cookie, or empty.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token for the confirm form.
 	Token string
 	// Kind is stopask (the question) or stopped (the last page).
@@ -243,6 +245,8 @@ func stopHandlers(token string) (http.HandlerFunc, http.HandlerFunc) {
 	show := func(w http.ResponseWriter, r *http.Request, data controlPage) {
 		// What every version needs.
 		data.Theme, data.Token = themeFromRequest(r), token
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/delete.go b/delete.go
index 88edc78..4b9e9e7 100644
--- a/delete.go
+++ b/delete.go
@@ -109,6 +109,8 @@ type deletePage struct {
 	ShowPull bool
 	// Theme is the saved theme choice, as on the main page.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token for the forms on this page.
 	Token string
 } // end of deletePage
@@ -158,6 +160,8 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore, hist
 	show := func(w http.ResponseWriter, r *http.Request, status int, data deletePage) {
 		// Add what every version of the page needs.
 		data.Theme, data.Token = themeFromRequest(r), token
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/gear.go b/gear.go
index 50174c0..7882d7f 100644
--- a/gear.go
+++ b/gear.go
@@ -341,6 +341,8 @@ type gearPage struct {
 	Max int64
 	// Theme is the saved theme choice, as on the main page.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token for the forms on this page.
 	Token string
 	// Tips holds the help bubbles by short name.
@@ -656,6 +658,8 @@ func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 	show := func(w http.ResponseWriter, r *http.Request, status int, data gearPage) {
 		// Add what every version of the page needs.
 		data.Theme, data.Token, data.Tips = themeFromRequest(r), token, tips
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/load.go b/load.go
index 58b56c4..538da4c 100644
--- a/load.go
+++ b/load.go
@@ -216,6 +216,8 @@ type loadPage struct {
 	Detail string
 	// Theme is the saved theme choice, as on the main page.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token for the forms on this page.
 	Token string
 } // end of loadPage
@@ -264,6 +266,8 @@ func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 	show := func(w http.ResponseWriter, r *http.Request, status int, data loadPage) {
 		// Add what every version of the page needs.
 		data.Theme, data.Token, data.DefaultText = themeFromRequest(r), token, defaultKeepText
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// The choices and the bubble for the keep-alive row.
 		data.KeepOptions, data.KeepTip = keepChoices, keepTip
 		// Build the page.
diff --git a/modelfile.go b/modelfile.go
index 50a2611..349f2db 100644
--- a/modelfile.go
+++ b/modelfile.go
@@ -30,6 +30,8 @@ const maxModelfileShown = 512 * 1024
 type modelfilePage struct {
 	// Theme is the chosen colour theme, or empty to follow the system.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Kind is modelfile, notinstalled or error.
 	Kind string
 	// Model is the model name.
@@ -66,6 +68,8 @@ func modelfileHandler(addr ollamaAddress, token string) http.HandlerFunc {
 	show := func(w http.ResponseWriter, r *http.Request, status int, data modelfilePage) {
 		// Add the theme.
 		data.Theme = themeFromRequest(r)
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/perfpage.go b/perfpage.go
index 3f8f1ec..d385f3d 100644
--- a/perfpage.go
+++ b/perfpage.go
@@ -57,6 +57,8 @@ type perfGroup struct {
 type perfPage struct {
 	// Theme is the saved colour theme, or empty to follow the system.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token every form carries.
 	Token string
 	// Kind chooses the version of the page.
@@ -448,6 +450,8 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.Hand
 	show := func(w http.ResponseWriter, r *http.Request, status int, data perfPage) {
 		// Add what every version needs.
 		data.Theme, data.Token = themeFromRequest(r), token
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/size.go b/size.go
new file mode 100644
index 0000000..82ba179
--- /dev/null
+++ b/size.go
@@ -0,0 +1,80 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http provides cookies, redirects and status codes.
+	"net/http"
+) // end of imports
+
+// sizeCookieName is the name of the cookie that remembers the chosen text size in this browser (it holds only the word medium).
+const sizeCookieName = "occ_size"
+
+// sizeCookieMaxAge keeps the choice for one year, in seconds.
+const sizeCookieMaxAge = 365 * 24 * 60 * 60
+
+// sizeFromRequest reads the saved text size from the cookie: "medium", or "" for large, which is the browser's own text size (also used for a missing or unknown value).
+func sizeFromRequest(r *http.Request) string {
+	// Look for the cookie.
+	c, err := r.Cookie(sizeCookieName)
+	// No cookie: follow the browser.
+	if err != nil {
+		// Large is the default.
+		return ""
+	} // end of the cookie check
+	// Only one saved value is known.
+	if c.Value == "medium" {
+		// Medium: 81 percent of the browser's text size.
+		return "medium"
+	} // end of the value check
+	// Anything else is ignored, so a damaged cookie can never break the page.
+	return ""
+} // end of sizeFromRequest
+
+// sizeHandler handles the POST that the text-size switch sends: it checks where the request came from, checks the page token, saves or clears the choice in a cookie and goes back to the page.
+func sizeHandler(token string) http.HandlerFunc {
+	// The handler itself.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// A size form is tiny; refuse anything larger than 1 KB.
+		r.Body = http.MaxBytesReader(w, r.Body, 1024)
+		// The request must come from this monitor's own page.
+		if !sameOrigin(r) {
+			// Refuse without saying more.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// A broken or too large form.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the form check
+		// The page token proves the form came from a page this monitor made.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the token check
+		// Act on the choice.
+		switch choice := r.PostFormValue("size"); choice {
+		// Medium is remembered.
+		case "medium":
+			// Save the word medium; the cookie is not readable by scripts and is never sent to other sites.
+			http.SetCookie(w, &http.Cookie{Name: sizeCookieName, Value: "medium", Path: "/", MaxAge: sizeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		// Large and Auto both mean: follow the browser's own text size, so the saved choice is removed.
+		case "large", "auto":
+			// An empty value with a negative age deletes the cookie.
+			http.SetCookie(w, &http.Cookie{Name: sizeCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		// Anything else is a mistake.
+		default:
+			// Refuse.
+			http.Error(w, "unknown text size", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the size choice
+		// Go back to the main page; 303 makes the browser use GET, so a reload does not send the form again.
+		http.Redirect(w, r, "/", http.StatusSeeOther)
+	} // end of the handler
+} // end of sizeHandler
diff --git a/size_test.go b/size_test.go
new file mode 100644
index 0000000..df5ce97
--- /dev/null
+++ b/size_test.go
@@ -0,0 +1,267 @@
+// Package main tells Go that this test file belongs to the same program as size.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// net/http provides requests, cookies and status codes.
+	"net/http"
+	// net/http/httptest records replies without starting a real server.
+	"net/http/httptest"
+	// net/url builds form data.
+	"net/url"
+	// os reads the template and stylesheet sources.
+	"os"
+	// path/filepath lists the template files.
+	"path/filepath"
+	// regexp finds icon sizes in the templates.
+	"regexp"
+	// strings searches and builds text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// pageWithSizeCookie fetches a path with the size cookie set to the given value.
+func pageWithSizeCookie(t *testing.T, h http.Handler, path, value string) string {
+	// Mark this as a helper.
+	t.Helper()
+	// Build the request.
+	req := httptest.NewRequest(http.MethodGet, path, nil)
+	// Attach the cookie.
+	req.AddCookie(&http.Cookie{Name: sizeCookieName, Value: value})
+	// Run the handler.
+	rec := httptest.NewRecorder()
+	// Serve.
+	h.ServeHTTP(rec, req)
+	// Hand back the page text.
+	return rec.Body.String()
+} // end of pageWithSizeCookie
+
+// TestSizeSwitchOnPage checks the default look of the switch: Large, knob L on the right, no Auto, no data-size.
+func TestSizeSwitchOnPage(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// What must be there.
+	for _, want := range []string{
+		// The form posts to /textsize.
+		`method="post" action="/textsize"`,
+		// The switch to Medium, with its knob showing L, and a keyboard-friendly help bubble.
+		`name="size" value="medium" class="switch switch-right" aria-describedby="tipsize"`,
+		// The knob letter.
+		`<span class="knob knob-letter" aria-hidden="true">L</span>`,
+		// The help bubble with both sizes explained.
+		`role="tooltip" id="tipsize">Text size: now Large (L)`,
+		// The About link in the footer.
+		`<a href="/about">About Ollama Control Center</a>`,
+	} { // end of the list
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the problem.
+			t.Errorf("page does not contain %q", want)
+		} // end of the check
+	} // end of the loop
+	// No saved size: no data-size on the html tag and no Auto for the size.
+	if strings.Contains(body, "data-size") || strings.Contains(body, `value="auto"`) {
+		// Report the problem.
+		t.Errorf("data-size or the size Auto button shown without a saved choice")
+	} // end of the default check
+} // end of TestSizeSwitchOnPage
+
+// TestSizeCookieIsUsed checks the page follows the saved size, shows Auto only then, and ignores unknown values.
+func TestSizeCookieIsUsed(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Medium is saved.
+	body := pageWithSizeCookie(t, rig.h, "/", "medium")
+	// What must be there.
+	for _, want := range []string{
+		// The html tag carries the size, which the stylesheet turns into 81 percent.
+		`data-size="medium"`,
+		// The Auto button for the size.
+		`name="size" value="auto" class="autobtn"`,
+		// The switch back to Large, with the M knob.
+		`name="size" value="large" class="switch" aria-describedby="tipsize"`, `>M</span>`,
+	} { // end of the list
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the problem.
+			t.Errorf("medium page does not contain %q", want)
+		} // end of the check
+	} // end of the loop
+	// Values that are not "medium" must be ignored and must never reach the page.
+	for _, bad := range []string{"large", "<script>alert(1)</script>", "huge", ""} {
+		// Fetch with the odd value.
+		body := pageWithSizeCookie(t, rig.h, "/", bad)
+		// Nothing of it may show.
+		if strings.Contains(body, "data-size") || strings.Contains(body, "<script>alert") {
+			// Report the problem.
+			t.Errorf("cookie value %q changed the page", bad)
+		} // end of the check
+	} // end of the loop
+} // end of TestSizeCookieIsUsed
+
+// TestSizePostSetsAndClearsCookie checks Medium saves a safe cookie, and Large or Auto remove it.
+func TestSizePostSetsAndClearsCookie(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Post "medium".
+	res := post(t, rig.h, "/textsize", url.Values{"token": {rig.token}, "size": {"medium"}}, fromThisPage)
+	// It must redirect to the page.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
+		// Stop the test.
+		t.Fatalf("status %d, Location %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// Exactly one cookie.
+	cookies := res.Cookies()
+	// Check the count.
+	if len(cookies) != 1 {
+		// Stop the test.
+		t.Fatalf("%d cookies, want 1", len(cookies))
+	} // end of the count check
+	// A short name.
+	c := cookies[0]
+	// Every property that matters for safety.
+	if c.Name != sizeCookieName || c.Value != "medium" || c.Path != "/" || !c.HttpOnly || c.SameSite != http.SameSiteStrictMode || c.MaxAge <= 0 {
+		// Report the problem.
+		t.Errorf("unexpected cookie: %+v", c)
+	} // end of the cookie check
+	// Large and Auto both clear it.
+	for _, word := range []string{"large", "auto"} {
+		// Post it.
+		res := post(t, rig.h, "/textsize", url.Values{"token": {rig.token}, "size": {word}}, fromThisPage)
+		// The cookie must be an expiring empty one.
+		cs := res.Cookies()
+		// Check it.
+		if res.StatusCode != http.StatusSeeOther || len(cs) != 1 || cs[0].Value != "" || cs[0].MaxAge >= 0 {
+			// Report the problem.
+			t.Errorf("%s: status %d, cookies %+v", word, res.StatusCode, cs)
+		} // end of the check
+	} // end of the loop
+} // end of TestSizePostSetsAndClearsCookie
+
+// TestSizePostRefusals checks every way a post can be refused, and that a refusal never sets a cookie.
+func TestSizePostRefusals(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// A table of cases.
+	for _, tc := range []struct {
+		// name labels the case.
+		name string
+		// form is the posted form.
+		form url.Values
+		// headers are the request headers.
+		headers map[string]string
+		// want is the expected status.
+		want int
+	}{ // the cases follow
+		// Another site posts the form.
+		{"cross-site", url.Values{"token": {rig.token}, "size": {"medium"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
+		// No browser headers at all.
+		{"no origin headers", url.Values{"token": {rig.token}, "size": {"medium"}}, map[string]string{}, http.StatusForbidden},
+		// No token.
+		{"missing token", url.Values{"size": {"medium"}}, fromThisPage, http.StatusForbidden},
+		// A wrong token.
+		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "size": {"medium"}}, fromThisPage, http.StatusForbidden},
+		// A size that does not exist.
+		{"unknown size", url.Values{"token": {rig.token}, "size": {"huge"}}, fromThisPage, http.StatusBadRequest},
+		// No size at all.
+		{"no size", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
+		// A body larger than the 1 KB limit.
+		{"too large", url.Values{"token": {rig.token}, "size": {"medium"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
+	} { // end of the table
+		// Run each case as a named subtest.
+		t.Run(tc.name, func(t *testing.T) {
+			// Send it.
+			res := post(t, rig.h, "/textsize", tc.form, tc.headers)
+			// Compare the status.
+			if res.StatusCode != tc.want {
+				// Report the difference.
+				t.Errorf("status %d, want %d", res.StatusCode, tc.want)
+			} // end of the status check
+			// A refusal must never set a cookie.
+			if len(res.Cookies()) != 0 {
+				// Report the problem.
+				t.Errorf("a refused request set a cookie: %+v", res.Cookies())
+			} // end of the cookie check
+		}) // end of the subtest
+	} // end of the loop
+	// A GET must be refused with 405.
+	if status, _, _ := get(t, rig.h, http.MethodGet, "/textsize"); status != http.StatusMethodNotAllowed {
+		// Report the problem.
+		t.Errorf("GET /textsize = %d, want 405", status)
+	} // end of the GET check
+} // end of TestSizePostRefusals
+
+// TestEveryPageCarriesTheSize is a guard: every page template must put the saved size on its html tag, or that page would ignore the choice.
+func TestEveryPageCarriesTheSize(t *testing.T) {
+	// All templates.
+	files, err := filepath.Glob("web/*.html")
+	// A failure here is a broken test setup.
+	if err != nil || len(files) < 10 {
+		// Stop the test.
+		t.Fatalf("templates not found: %v (%d files)", err, len(files))
+	} // end of the glob check
+	// Check each.
+	for _, f := range files {
+		// Read it.
+		data, err := os.ReadFile(f)
+		// A failure here is a broken test setup.
+		if err != nil {
+			// Stop the test.
+			t.Fatalf("cannot read %s: %v", f, err)
+		} // end of the read check
+		// Only full pages have an html tag.
+		if !strings.Contains(string(data), "<html") {
+			// Skip it.
+			continue
+		} // end of the page check
+		// The attribute must be there.
+		if !strings.Contains(string(data), `{{if .Size}} data-size="{{.Size}}"{{end}}`) {
+			// Report the problem.
+			t.Errorf("%s does not carry the saved text size on its html tag", f)
+		} // end of the attribute check
+	} // end of the loop
+} // end of TestEveryPageCarriesTheSize
+
+// TestMediumScalesTheIcons is a guard: the stylesheet must shrink the page to 81 percent, and every icon size used in a template must have its own 81 percent rule.
+func TestMediumScalesTheIcons(t *testing.T) {
+	// The stylesheet.
+	css, err := os.ReadFile("web/app.css")
+	// A failure here is a broken test setup.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("cannot read the stylesheet: %v", err)
+	} // end of the read check
+	// The root rule.
+	if !strings.Contains(string(css), "html[data-size=\"medium\"] {\n  /* Percent of the browser's own size works in every browser and keeps the person's own browser setting as the base. */\n  font-size: 81%;") {
+		// Report the problem.
+		t.Errorf("the 81 percent rule is missing")
+	} // end of the root check
+	// All templates.
+	files, _ := filepath.Glob("web/*.html")
+	// An svg with a pixel width.
+	svg := regexp.MustCompile(`<svg[^>]* width="([0-9]+)"`)
+	// How many icons were found, so the test cannot pass by finding nothing.
+	found := 0
+	// Check each template.
+	for _, f := range files {
+		// Read it.
+		data, _ := os.ReadFile(f)
+		// Every icon.
+		for _, m := range svg.FindAllStringSubmatch(string(data), -1) {
+			// Count it.
+			found++
+			// Its rule must exist.
+			if !strings.Contains(string(css), `html[data-size="medium"] svg[width="`+m[1]+`"]`) {
+				// Report the problem.
+				t.Errorf("%s: no Medium rule for icons %s pixels wide", f, m[1])
+			} // end of the rule check
+		} // end of the icon loop
+	} // end of the file loop
+	// Icons must exist.
+	if found == 0 {
+		// Stop the test.
+		t.Fatalf("no icons found")
+	} // end of the count check
+} // end of TestMediumScalesTheIcons
diff --git a/unload.go b/unload.go
index b74eb64..e1f7a79 100644
--- a/unload.go
+++ b/unload.go
@@ -197,6 +197,8 @@ type unloadPage struct {
 	Detail string
 	// Theme is the saved theme choice, as on the main page.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token for the forms on this page.
 	Token string
 } // end of unloadPage
@@ -246,6 +248,8 @@ func unloadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Ha
 	show := func(w http.ResponseWriter, r *http.Request, status int, data unloadPage) {
 		// Add what every version of the page needs.
 		data.Theme, data.Token = themeFromRequest(r), token
+		// The saved text size, from the cookie; empty means the browser's own size.
+		data.Size = sizeFromRequest(r)
 		// Build the page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/web.go b/web.go
index 869bd1d..fe51159 100644
--- a/web.go
+++ b/web.go
@@ -51,6 +51,8 @@ type pageData struct {
 	TableError string
 	// Theme is the saved choice, light or dark; empty means follow the system.
 	Theme string
+	// Size is the saved text size, medium, or empty for the browser's own size.
+	Size string
 	// Token is the page token that every form on the page carries.
 	Token string
 	// CompareCount is how many models have a saved performance test that can be compared.
@@ -92,6 +94,10 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux := http.NewServeMux()
 	// Route: a POST request for "/theme" saves the chosen theme in a cookie (the checks are in theme.go).
 	mux.HandleFunc("POST /theme", themeHandler(token))
+	// Route: a POST request for "/textsize" saves the chosen text size in a cookie (the checks are in size.go).
+	mux.HandleFunc("POST /textsize", sizeHandler(token))
+	// Route: a GET request for "/about" shows the read-only About page (see about.go).
+	mux.HandleFunc("GET /about", aboutHandler())
 	// Make the two unload handlers: the first asks "are you sure?", the second unloads (the checks are in unload.go).
 	unloadAsk, unloadConfirm := unloadHandlers(addr, token)
 	// Route: a POST request for "/unload" shows the warning page and changes nothing.
@@ -183,6 +189,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			Reason: res.Reason,
 			// The saved theme choice, from the cookie; empty means follow the system.
 			Theme: themeFromRequest(r),
+			// The saved text size, from the cookie; empty means the browser's own size.
+			Size: sizeFromRequest(r),
 			// The page token for the forms.
 			Token: token,
 			// How many models can be compared.
diff --git a/web/about.html b/web/about.html
new file mode 100644
index 0000000..cc849f9
--- /dev/null
+++ b/web/about.html
@@ -0,0 +1,57 @@
+{{/* About page template: who made the program, what it is and which version this is. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in; the theme and the text size come from the saved choices. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>About Ollama Control Center</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* One card holds everything. */}}
+<section class="panel aboutcard">
+{{/* The name of the program. */}}
+<h1>About Ollama Control Center</h1>
+{{/* One line that says what it is. */}}
+<p class="muted aboutlead">A local monitor and control page for Ollama.</p>
+{{/* What it does, in plain words. */}}
+<p>It shows which models are installed and which are loaded in memory, lets you load, unload, tune and delete models, tells you how to download a deleted model again, and compares how fast tested models answer.</p>
+{{/* The facts, as a table: a label on the left, the value on the right. */}}
+<table class="aboutfacts">
+{{/* The table has a caption for screen readers. */}}
+<caption class="sr-only">Facts about this program</caption>
+{{/* Who developed it. */}}
+<tr><th scope="row">Developed by</th><td>{{.Developer}} &middot; <a href="{{.DeveloperProfile}}" rel="noopener noreferrer">LinkedIn profile</a></td></tr>
+{{/* Who assisted. */}}
+<tr><th scope="row">Assisted by</th><td>{{.Assistant}}</td></tr>
+{{/* The version. */}}
+<tr><th scope="row">Version</th><td>{{.Version}}</td></tr>
+{{/* The source revision, when the build recorded one. */}}
+<tr><th scope="row">Source revision</th><td>{{if .Revision}}<code>{{.Revision}}</code>{{if .Modified}} (built with uncommitted changes){{end}}{{if .RevisionDate}}, committed {{.RevisionDate}}{{end}}{{else}}not recorded in this build{{end}}</td></tr>
+{{/* The platform. */}}
+<tr><th scope="row">Built with</th><td>Go standard library only, no third-party code ({{.Platform}})</td></tr>
+{{/* Where the source lives. */}}
+<tr><th scope="row">Source code</th><td><a href="{{.Repository}}" rel="noopener noreferrer">{{.Repository}}</a> (private repository; opens only for its owner)</td></tr>
+{{/* Where the data goes. */}}
+<tr><th scope="row">Privacy</th><td>Runs only on this computer. The one request to the outside is the optional check of Ollama's public library when a model is deleted, and it sends only the model's name.</td></tr>
+{{/* The licence. */}}
+<tr><th scope="row">Licence</th><td>{{.Copyright}}</td></tr>
+{{/* End of the table. */}}
+</table>
+{{/* The dedication, set apart so it stands out. */}}
+<blockquote class="dedication">{{.Dedication}}</blockquote>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the card. */}}
+</section>
+{{/* End of the main content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/app.css b/web/app.css
index fa4581e..7182842 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox, .controls .tipbox {
+.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -1484,3 +1484,206 @@ a.btn-load {
   /* Break long words. */
   overflow-wrap: anywhere;
 } /* end of rule */
+
+/* Text size Medium: the whole page is 81 percent of the browser's own text size; every size in this stylesheet is in rem, so everything follows. */
+html[data-size="medium"] {
+  /* Percent of the browser's own size works in every browser and keeps the person's own browser setting as the base. */
+  font-size: 81%;
+} /* end of rule */
+
+/* Icons are drawn with a size in pixels in the page; in Medium they shrink to the same 81 percent. */
+html[data-size="medium"] svg[width="10"] {
+  /* 81 percent of 10 pixels. */
+  width: 8.1px;
+  /* Same height. */
+  height: 8.1px;
+} /* end of rule */
+/* 81 percent of 14 pixels. */
+html[data-size="medium"] svg[width="14"] {
+  /* Width. */
+  width: 11.34px;
+  /* Height. */
+  height: 11.34px;
+} /* end of rule */
+/* 81 percent of 18 pixels. */
+html[data-size="medium"] svg[width="18"] {
+  /* Width. */
+  width: 14.58px;
+  /* Height. */
+  height: 14.58px;
+} /* end of rule */
+/* 81 percent of 20 pixels. */
+html[data-size="medium"] svg[width="20"] {
+  /* Width. */
+  width: 16.2px;
+  /* Height. */
+  height: 16.2px;
+} /* end of rule */
+/* 81 percent of 22 pixels. */
+html[data-size="medium"] svg[width="22"] {
+  /* Width. */
+  width: 17.82px;
+  /* Height. */
+  height: 17.82px;
+} /* end of rule */
+
+/* The two look switches, text size on top and theme below, lined up on the right. */
+.lookstack {
+  /* One above the other. */
+  display: flex;
+  /* In a column. */
+  flex-direction: column;
+  /* Against the right edge. */
+  align-items: flex-end;
+  /* A little air between the rows. */
+  gap: 0.45rem;
+} /* end of rule */
+
+/* The small "Text" label before the size switch: dotted underline says a tooltip is there. */
+.sizelabel {
+  /* Small, like the Auto label. */
+  font-size: 0.75rem;
+  /* Quiet colour. */
+  color: var(--muted);
+  /* A dotted line hints at the tooltip. */
+  border-bottom: 1px dotted var(--muted);
+  /* Shows that help is available. */
+  cursor: help;
+  /* A little room before the switch. */
+  margin-right: 0.4rem;
+} /* end of rule */
+
+/* A switch whose knob sits on the right (Large). */
+.switch-right {
+  /* Push the knob to the right edge. */
+  justify-content: flex-end;
+} /* end of rule */
+
+/* A knob that holds a letter instead of a symbol. */
+.knob-letter {
+  /* Slightly smaller and bold, so M and L read clearly. */
+  font-size: 0.7rem;
+  /* Bold letter. */
+  font-weight: 700;
+} /* end of rule */
+
+/* Text for screen readers only. */
+.sr-only {
+  /* Take it out of the layout. */
+  position: absolute;
+  /* One pixel is enough for a screen reader. */
+  width: 1px;
+  /* One pixel high. */
+  height: 1px;
+  /* Hide anything outside. */
+  overflow: hidden;
+  /* Clip it away. */
+  clip-path: inset(50%);
+  /* Keep it on one line. */
+  white-space: nowrap;
+} /* end of rule */
+
+/* The quiet footer with the About link. */
+.sitefooter {
+  /* Centred under the page. */
+  text-align: center;
+  /* Space above and below. */
+  margin: 1.5rem 0 2rem;
+  /* Small and quiet. */
+  font-size: 0.85rem;
+} /* end of rule */
+
+/* The About card: narrower than the tables so lines stay easy to read. */
+.aboutcard {
+  /* A comfortable reading width. */
+  max-width: 44rem;
+  /* Centred. */
+  margin: 2rem auto;
+  /* More air inside than a normal panel. */
+  padding: 1.5rem 1.75rem;
+} /* end of rule */
+
+/* The line under the About heading. */
+.aboutlead {
+  /* Close to the heading. */
+  margin-top: 0;
+  /* A little larger than body text. */
+  font-size: 1.05rem;
+} /* end of rule */
+
+/* The facts table of the About page. */
+.aboutfacts {
+  /* Full width. */
+  width: 100%;
+  /* Lines between rows, not between cells. */
+  border-collapse: collapse;
+  /* Air around the table. */
+  margin: 1rem 0 1.25rem;
+} /* end of rule */
+
+/* Labels and values of the About table. */
+.aboutfacts th, .aboutfacts td {
+  /* Left aligned. */
+  text-align: left;
+  /* Air inside the cells. */
+  padding: 0.55rem 0.75rem 0.55rem 0;
+  /* A thin line above each row. */
+  border-top: 1px solid var(--border);
+  /* Start at the top when a value wraps. */
+  vertical-align: top;
+} /* end of rule */
+
+/* The labels. */
+.aboutfacts th {
+  /* A fixed column, so the values line up. */
+  width: 10rem;
+  /* Quiet colour. */
+  color: var(--muted);
+  /* Semi-bold. */
+  font-weight: 600;
+} /* end of rule */
+
+/* The dedication: set apart with a bar and the category colours, in italics. */
+.dedication {
+  /* Space around it. */
+  margin: 1.25rem 0;
+  /* Air inside. */
+  padding: 1rem 1.25rem;
+  /* The accent bar on the left. */
+  border-left: 6px solid var(--cat-accent);
+  /* Soft band colour from the variables, so it works in light and dark. */
+  background: var(--cat-bg);
+  /* Text colour that is readable on the band. */
+  color: var(--cat-text);
+  /* Italics for a personal line. */
+  font-style: italic;
+  /* Slightly larger. */
+  font-size: 1.05rem;
+  /* Rounded on the right only, next to the bar. */
+  border-radius: 0 0.5rem 0.5rem 0;
+} /* end of rule */
+
+/* The look switches are at the top right edge of the window, so their bubbles open downwards, lined up with the right edge of their box. */
+.lookstack .tip-icon {
+  /* The top edge of the bubble sits on the bottom edge of the box. */
+  top: anchor(bottom);
+  /* No bottom edge: the top decides. */
+  bottom: auto;
+  /* No left edge: the right edge decides. */
+  left: auto;
+  /* The bubble's right edge sits on the box's right edge. */
+  right: anchor(right);
+  /* A little gap below the box. */
+  margin: 0.25rem 0 0 0;
+} /* end of rule */
+
+/* On a narrow window the bubbles span the window again. */
+@media (max-width: 40rem) {
+  /* The look bubbles. */
+  .lookstack .tip-icon {
+    /* Near the left edge. */
+    left: 0.5rem;
+    /* Near the right edge. */
+    right: 0.5rem;
+  } /* end of rule */
+} /* end of rule */
diff --git a/web/compare.html b/web/compare.html
index b2e50b2..4c5be02 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -1,7 +1,7 @@
 {{/* Comparison page: the latest saved performance test of each model side by side. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/control.html b/web/control.html
index 4029188..1c3b10d 100644
--- a/web/control.html
+++ b/web/control.html
@@ -1,7 +1,7 @@
 {{/* Stop pages: the question and the last page. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/delete.html b/web/delete.html
index 2b0f600..4555601 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -1,7 +1,7 @@
 {{/* Delete page template: one page with several versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/gear.html b/web/gear.html
index f8473a3..7914457 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -1,7 +1,7 @@
 {{/* Settings page template: one page with several versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/index.html b/web/index.html
index 1021e52..fab2cf3 100644
--- a/web/index.html
+++ b/web/index.html
@@ -1,7 +1,7 @@
 {{/* Page template: the comments in this file are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Use UTF-8 so the symbols in the status line display correctly. */}}
 <meta charset="utf-8">
@@ -69,6 +69,44 @@
 </form>
 {{/* End of the controls. */}}
 </div>
+{{/* The two look switches are stacked: the text size on top, the theme below it. */}}
+<div class="lookstack">
+{{/* The text size form: it sends the choice to the monitor, which saves it in a cookie; Large is the browser's own size, Medium is 81 percent of it. */}}
+<form class="themeform" method="post" action="/textsize">
+{{/* The page token proves the form comes from this page. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* A small Auto button, shown only while Medium is saved, to go back to following the browser's text size. */}}
+{{if .Size}}
+{{/* Its own help bubble, which works from the keyboard as well as the mouse. */}}
+<span class="tipbox">
+{{/* The button sends the word auto, which deletes the cookie. */}}
+<button type="submit" name="size" value="auto" class="autobtn" aria-describedby="tipsizeauto" aria-label="Follow the browser's text size">Auto</button>
+{{/* The bubble. */}}
+<span class="tip tip-icon" role="tooltip" id="tipsizeauto">Go back to your browser's own text size</span>
+{{/* End of the Auto box. */}}
+</span>
+{{/* End of the Auto button. */}}
+{{end}}
+{{/* The label and the switch share one help bubble. */}}
+<span class="tipbox">
+{{/* A short label, "Text" (not "Aa", which the key box already uses for dotted headings); the bubble explains the two sizes. */}}
+<span class="sizelabel" aria-hidden="true">Text</span>
+{{/* Medium is saved: the knob shows M on the left; a click goes back to Large. */}}
+{{if eq .Size "medium"}}
+<button type="submit" name="size" value="large" class="switch" aria-describedby="tipsize" aria-label="Text size is Medium; switch to Large"><span class="knob knob-letter" aria-hidden="true">M</span></button>
+{{/* The bubble for Medium. */}}
+<span class="tip tip-icon" role="tooltip" id="tipsize">Text size: now Medium (M), 81% of your browser's text size. Click for Large (L), your browser's own size.</span>
+{{/* Large is in use: the knob shows L on the right; a click goes to Medium. */}}
+{{else}}
+<button type="submit" name="size" value="medium" class="switch switch-right" aria-describedby="tipsize" aria-label="Text size is Large; switch to Medium"><span class="knob knob-letter" aria-hidden="true">L</span></button>
+{{/* The bubble for Large. */}}
+<span class="tip tip-icon" role="tooltip" id="tipsize">Text size: now Large (L), your browser's own text size. Click for Medium (M), 81% of it.</span>
+{{/* End of the size choice. */}}
+{{end}}
+{{/* End of the label and switch box. */}}
+</span>
+{{/* End of the text size form. */}}
+</form>
 {{/* The theme form on the right: it sends the choice to the monitor, which saves it in a cookie. */}}
 <form class="themeform" method="post" action="/theme">
 {{/* The page token proves the form comes from this page. */}}
@@ -85,6 +123,8 @@
 <button type="submit" name="theme" value="light" class="switch to-light" aria-label="Switch to light theme"><span class="knob" aria-hidden="true">☾</span></button>
 {{/* End of the theme form. */}}
 </form>
+{{/* End of the stacked switches. */}}
+</div>
 {{/* End of the right side of the header. */}}
 </div>
 </header>{{/* end of the header. */}}
@@ -390,6 +430,12 @@
 </section>
 {{/* End of the main content. */}}
 </main>
+{{/* The footer: a quiet link to the About page. */}}
+<footer class="sitefooter">
+{{/* The link. */}}
+<a href="/about">About Ollama Control Center</a>
+{{/* End of the footer. */}}
+</footer>
 {{/* The monitor's own script ticks the timers and asks the monitor for fresh figures every few seconds; it is loaded only when a table is shown. */}}
 {{if .HasTable}}<script src="/countdown.js" defer></script>{{end}}
 </body>{{/* end of the visible page. */}}
diff --git a/web/load.html b/web/load.html
index 798c235..d50a4d3 100644
--- a/web/load.html
+++ b/web/load.html
@@ -1,7 +1,7 @@
 {{/* Load page template: one page with six versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/modelfile.html b/web/modelfile.html
index 42684da..3fd979f 100644
--- a/web/modelfile.html
+++ b/web/modelfile.html
@@ -1,7 +1,7 @@
 {{/* Modelfile page template: shows a model's Modelfile, read-only. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/performance.html b/web/performance.html
index 5300db2..46d1a21 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -63,7 +63,7 @@
 {{end}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
diff --git a/web/unload.html b/web/unload.html
index 3851de3..9689b1b 100644
--- a/web/unload.html
+++ b/web/unload.html
@@ -1,7 +1,7 @@
 {{/* Unload page template: one page with five versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
-<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
 <head>{{/* start of the head. */}}
 {{/* Text encoding. */}}
 <meta charset="utf-8">
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
9857db6d17e9da20e7b81eee1a4571b60a4cd1ac3fb85f1b90bd15e331572208  size.go
9fd752b503c4d6f12987e58eb9bf3ba59e86d2dcec1007bd0c52106c28370e2a  size_test.go
4e4b4d755011f132aa6d5f27244f77a1542f2be6ded41714a8a0c9e20244de31  about.go
e28adaf78fe44e7535a58cb896831a53085af029351329bf5aa9e8bedd3bd817  about_test.go
4b9b37a88ed6b0bc279aa4e50eddf90866659cb6dd3a9aa6f1623eef36e05a25  web/about.html
0758560e503c252287fcd5d850217f66e1f1af8fc8dc02462b52bf65324e6c99  compare.go
07b95b08742137d38e3cbeba9ff870d042864110d3c3f00193b5c3795e037bc9  control.go
56f4184eceeda7cb8133fcacf8597119a3d187563d1fdd59104e9ddc3db1829f  delete.go
d4d6344a7d07b835edaa34047ad88fd23fb0df7abe99995205f40c15e1ec0776  gear.go
2120b66b2bf3c2878a16c045e04f36f587ae8485eac55ef6e384f097a051762e  load.go
f0bfcb35a6a904ef45c4fecd3c723fc824e1b7d4abd4df48c35cf05bd4c05e11  modelfile.go
5b0483b0d071c8df02f33ef9fdc05bd3cd6f60837b9097d4dd8733e9bb8a3cdd  perfpage.go
4b7e634b3fc526c2f47bbafc8c68cb00faa89e865c41bbf90adaee4dff5daf96  unload.go
c284b573dd30be0f97b2a3c6f5be59c5ec47d711ee0b4de9637911e5a0c07c9b  web.go
51807d3d1ff4218670b27ad2f0cbb8d59d15e70fe54f79938ec5afe08c04a726  web/app.css
06a1ea02beda10e873b2a9f87c6556f0dd5c39976eeb9be930771da2065e6a8f  web/compare.html
19a31a40bc5fa70e501a01de5230a236b6bc87cb3e5569002262c849e44564f7  web/control.html
c4ef3daf86b9f7ea59a55386e2d4c7017dbcbb462289fb78d5fa0a44ba7d1979  web/delete.html
11e41f7e55b42d9375c8b5a18478b490b584987a7b897f1c8b6b8cc8f702f3ba  web/gear.html
2c86350e05baf2a88e72cee9666a7fe17e93ab3fb0c59764187a39adc4e86f49  web/index.html
f650c338c6147844f86582bc43cc0d8a8a6f2caa475251316f6456880d275ca8  web/load.html
a44f99ffab4f525960b6db5f8736caf061ab9f5eb1b655ae061a19a76f2bbe28  web/modelfile.html
ad507ebfc5ae0a04e79630c633b4c1ac1c5d1a6cf77811d34941ed8e0f6c9bd8  web/performance.html
17de9cd7e0ff390cf7b7da464916c0b975645dee7f55d5032064ce20874f1a71  web/unload.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# List the changed files; nothing is committed yet.
git status --short
