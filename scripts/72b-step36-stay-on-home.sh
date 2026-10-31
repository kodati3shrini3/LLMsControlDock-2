#!/usr/bin/env bash
# Script 72b: a follow-up to script 72 on the same branch. Pressing Yes, create it on the monitor page now stays on the monitor page and shows a one-time note there (the note about Allow Launching, or the reason if no icon could be made). The buttons on the Settings page still show their result on the Settings page. No version change (0.23.0).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/desktop-icon" ] || { echo "FAIL  not on feature/desktop-icon"; exit 1; }
# Script 72 (the desktop icon) must be applied already.
[ -e desktopicon.go ] || { echo "FAIL  script 72 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "iconFlashCookie" desktopicon.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/desktopicon.go b/desktopicon.go
index 12524e2..044b8cc 100644
--- a/desktopicon.go
+++ b/desktopicon.go
@@ -371,6 +371,9 @@ func iconResultWords(okWord string, err error) string {
 	return "failed"
 } // end of iconResultWords
 
+// iconFlashCookie holds, for a moment, the result of the icon button pressed on the monitor page; the page shows it once and deletes it.
+const iconFlashCookie = "occ_icon"
+
 // desktopHandler answers the three buttons: create, decline and remove (the page token and the same-origin check protect it like every other button).
 func desktopHandler(token string, d desktopIcon) http.HandlerFunc {
 	// The handler.
@@ -402,8 +405,19 @@ func desktopHandler(token string, d desktopIcon) http.HandlerFunc {
 		switch r.PostFormValue("action") {
 		// Create the launcher.
 		case "create":
-			// Do it and show the result on the Settings page.
-			http.Redirect(w, r, "/settings?icon="+iconResultWords("created", d.create()), http.StatusSeeOther)
+			// Do it.
+			word := iconResultWords("created", d.create())
+			// From the question on the monitor page: stay on that page and show the result there, once.
+			if r.PostFormValue("from") == "home" {
+				// A short-lived note, read once by the monitor page.
+				http.SetCookie(w, &http.Cookie{Name: iconFlashCookie, Value: word, Path: "/", MaxAge: 120, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+				// Back to the monitor page.
+				http.Redirect(w, r, "/", http.StatusSeeOther)
+				// Stop here.
+				return
+			} // end of the home case
+			// From the Settings page: show the result there.
+			http.Redirect(w, r, "/settings?icon="+word, http.StatusSeeOther)
 		// Do not ask again.
 		case "decline":
 			// Keep the answer, then go back to the monitor.
diff --git a/desktopicon_test.go b/desktopicon_test.go
index e3c8fdf..19eaa4b 100644
--- a/desktopicon_test.go
+++ b/desktopicon_test.go
@@ -8,6 +8,8 @@ import ( // import lists the packages this test file uses.
 	"errors"
 	// net/http provides status codes.
 	"net/http"
+	// net/http/httptest builds the requests with their own cookies.
+	"net/http/httptest"
 	// net/url builds the forms.
 	"net/url"
 	// os looks at the files.
@@ -351,13 +353,76 @@ func TestDesktopBannerAndButtons(t *testing.T) {
 		// Report it.
 		t.Errorf("a refused request created the launcher: %v", err)
 	} // end of the nothing check
-	// "Yes, create it".
-	res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}}, fromThisPage)
-	// It goes to the Settings page with the fixed word.
-	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/settings?icon=created" {
+	// "Yes, create it", pressed on the monitor page.
+	res := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}, "from": {"home"}}, fromThisPage)
+	// It stays on the monitor page and leaves a short-lived note.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
 		// Report it.
 		t.Fatalf("create: status %d location %q", res.StatusCode, res.Header.Get("Location"))
 	} // end of the create check
+	// The note cookie.
+	var flash *http.Cookie
+	// Find it.
+	for _, c := range res.Cookies() {
+		// The one we look for.
+		if c.Name == iconFlashCookie {
+			// Keep it.
+			flash = c
+		} // end of the name check
+	} // end of the loop
+	// It must be there with the fixed word.
+	if flash == nil || flash.Value != "created" {
+		// Stop.
+		t.Fatalf("flash cookie: %+v", flash)
+	} // end of the cookie check
+	// The monitor page shows the note once, and deletes the cookie.
+	req := httptest.NewRequest(http.MethodGet, "/", nil)
+	// Send the cookie back.
+	req.AddCookie(flash)
+	// Serve.
+	rec := httptest.NewRecorder()
+	// Run it.
+	r.h.ServeHTTP(rec, req)
+	// The page text.
+	home := rec.Body.String()
+	// The sentence and the stay-on-home result.
+	if !strings.Contains(home, "Desktop icon created. On Ubuntu") || rec.Code != http.StatusOK {
+		// Report it.
+		t.Errorf("the monitor page does not show the note (status %d)", rec.Code)
+	} // end of the note check
+	// The cookie is deleted.
+	gone := false
+	// Look for the deletion.
+	for _, c := range rec.Result().Cookies() {
+		// A deletion has a negative age.
+		if c.Name == iconFlashCookie && c.MaxAge < 0 {
+			// Seen.
+			gone = true
+		} // end of the deletion check
+	} // end of the loop
+	// It must be deleted.
+	if !gone {
+		// Report it.
+		t.Errorf("the note cookie was not deleted")
+	} // end of the deleted check
+	// An unknown word shows nothing.
+	req2 := httptest.NewRequest(http.MethodGet, "/", nil)
+	// A made-up word.
+	req2.AddCookie(&http.Cookie{Name: iconFlashCookie, Value: "<script>"})
+	// Serve.
+	rec2 := httptest.NewRecorder()
+	// Run it.
+	r.h.ServeHTTP(rec2, req2)
+	// Nothing is echoed.
+	if strings.Contains(rec2.Body.String(), "<script>") {
+		// Report it.
+		t.Errorf("an unknown note word was echoed")
+	} // end of the echo check
+	// From the Settings page the result is shown on the Settings page.
+	if res2 := post(t, r.h, "/desktopicon", url.Values{"token": {r.token}, "action": {"create"}}, fromThisPage); res2.Header.Get("Location") != "/settings?icon=created" {
+		// Report it.
+		t.Errorf("create from settings: location %q", res2.Header.Get("Location"))
+	} // end of the settings check
 	// The launcher is there.
 	if _, err := os.Stat(filepath.Join(r.f.desk, desktopFileName)); err != nil {
 		// Report it.
diff --git a/web.go b/web.go
index 9d3c47a..7cd5fca 100644
--- a/web.go
+++ b/web.go
@@ -87,6 +87,8 @@ type pageData struct {
 	NumbersOpen bool
 	// DetailsClosed is true when the person folded the monitoring details (API health and Event log) away; a cookie remembers it.
 	DetailsClosed bool
+	// IconNote is the one-time sentence about the desktop icon that was just created (empty when there is none).
+	IconNote string
 	// DesktopBanner is true when the first-run question about a desktop icon is shown.
 	DesktopBanner bool
 	// DesktopDir and DesktopExe are the folder and the program the question names.
@@ -321,6 +323,13 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 			// When this page was made.
 			UpdatedAt: time.Now().Format("15:04:05 MST"),
 		} // end of the data
+		// The result of the icon button, shown once: read the short-lived note and delete it, so the automatic reload does not show it again.
+		if c, err := r.Cookie(iconFlashCookie); err == nil {
+			// Only the known words show a sentence.
+			data.IconNote = iconNotes[c.Value]
+			// Delete the note.
+			http.SetCookie(w, &http.Cookie{Name: iconFlashCookie, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		} // end of the note check
 		// The first-run question: only where a desktop exists and the person has not answered yet.
 		if desktop.available() && desktop.choice() == "" {
 			// Show it, naming the folder and the program.
diff --git a/web/index.html b/web/index.html
index 660247a..4dbcc43 100644
--- a/web/index.html
+++ b/web/index.html
@@ -20,6 +20,8 @@
 {{if and (not .Paused) (not .KeyOpen) (not .NumbersOpen)}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
+{{/* The result of the icon button, shown once. */}}
+{{if .IconNote}}<p class="muted" role="status"><strong>{{.IconNote}}</strong></p>{{end}}
 {{/* The first-run question: only on a system with a desktop, and only until the person has answered. */}}
 {{if .DesktopBanner}}
 <section class="panel" role="region" aria-label="Desktop icon">
@@ -31,6 +33,8 @@
 <form method="post" action="/desktopicon">
 {{/* The page token proves the form comes from this page. */}}
 <input type="hidden" name="token" value="{{.Token}}">
+{{/* Tells the monitor to stay on this page afterwards. */}}
+<input type="hidden" name="from" value="home">
 {{/* The buttons. */}}
 <p><button type="submit" name="action" value="create" class="btn-plain">Yes, create it</button> <button type="submit" name="action" value="decline" class="btn-plain">No, don't ask again</button></p>
 {{/* End of the form. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
17a9ffa629da1121b79bd7bc86e6ed7947a486ecbcf9580d80a462ec8a96b58d  desktopicon.go
c7021c43a6c280485c64dacacc7d8de693ec39be4af5a149889f88ebfaf5427b  desktopicon_test.go
181cc3f91af2dfa0e527d73e9312bd119d93c52fb12f88c2ab486004bb632fef  web.go
4f757dc7677b690f7647624a1b1f795a6e509eab7c3924704cfb8fa75234a60b  web/index.html
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
# Tell the person how to use the new command.
echo "NEXT  to see the first-run question again run: rm -f ~/.config/OllamaControlCenter/desktop-icon.json ~/Desktop/OllamaControlCenter.desktop ; then start ./bin/OllamaControlCenter, reload the page, press Yes, create it and check that you stay on the monitor page with a note above the header"
# List the changed files; nothing is committed yet.
git status --short
