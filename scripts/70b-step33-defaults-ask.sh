#!/usr/bin/env bash
# Script 70b: a follow-up to script 70 on the same branch. Back to defaults no longer saves: it fills the form with the default values and says nothing is saved yet; Save settings keeps them and the new Cancel button leaves your settings as they were. No version change (0.22.0).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/settings-panel" ] || { echo "FAIL  not on feature/settings-panel"; exit 1; }
# Script 70 (the Settings page) must be applied already.
[ -e settingspage.go ] || { echo "FAIL  script 70 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "Nothing is saved yet" web/settings.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/appsettings_test.go b/appsettings_test.go
index 06e5b8f..5bea1fe 100644
--- a/appsettings_test.go
+++ b/appsettings_test.go
@@ -254,17 +254,36 @@ func TestSettingsPageSaves(t *testing.T) {
 		// Report it.
 		t.Errorf("overlap status %d", res.StatusCode)
 	} // end of the overlap check
-	// Back to the defaults.
+	// Save something first, so "Back to defaults" has something to change.
+	r.save(t, url.Values{"interval": {"30"}, "timeout": {"8"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
+	// Back to the defaults only fills the form; it saves nothing.
 	res = r.save(t, url.Values{"action": {"defaults"}})
-	// Redirect with the reset note.
-	if res.StatusCode != http.StatusSeeOther || !strings.Contains(res.Header.Get("Location"), "saved=reset") {
+	// The page is shown again (no redirect).
+	if res.StatusCode != http.StatusOK {
 		// Report it.
-		t.Errorf("defaults: status %d location %q", res.StatusCode, res.Header.Get("Location"))
-	} // end of the defaults check
-	// Everything is cleared.
+		t.Errorf("defaults: status %d", res.StatusCode)
+	} // end of the status check
+	// The page says nothing is saved yet and offers Cancel.
+	page := bodyOf(res)
+	// The words.
+	for _, w := range []string{"Nothing is saved yet", ">Cancel</a>", `name="interval" type="number" inputmode="numeric" min="5" max="300" step="1" aria-label="Check interval (seconds)" value="10"`} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report it.
+			t.Errorf("the defaults page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The saved values are untouched until Save is pressed.
+	if got := r.mon.store.get(); got.IntervalSeconds != 30 || got.HistoryMinutes != 60 {
+		// Report it.
+		t.Errorf("Back to defaults changed the saved settings: %+v", got)
+	} // end of the untouched check
+	// Pressing Save with the default values clears the saved settings.
+	r.save(t, url.Values{"interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"no"}, "savehistory": {"no"}})
+	// Now everything is cleared.
 	if got := r.mon.store.get(); got != (appSettings{}) {
 		// Report it.
-		t.Errorf("defaults left values: %+v", got)
+		t.Errorf("saving the defaults left values: %+v", got)
 	} // end of the cleared check
 } // end of TestSettingsPageSaves
 
diff --git a/settingspage.go b/settingspage.go
index e77eb8f..d432e9b 100644
--- a/settingspage.go
+++ b/settingspage.go
@@ -63,7 +63,7 @@ type settingsPage struct {
 	Rows []settingsRow
 	// Problems are the things wrong with what was typed.
 	Problems []string
-	// Saved is "saved", "reset" or empty, for the note after saving.
+	// Saved is "saved", "draft" (defaults filled in but not saved) or empty, for the note above the table.
 	Saved string
 	// RestartNeeded is true when a restart value differs from what runs now.
 	RestartNeeded bool
@@ -284,17 +284,10 @@ func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.Hand
 			// Stop here.
 			return
 		} // end of the token check
-		// Back to the defaults: save nothing at all.
+		// Back to the defaults: nothing is saved here. The form is filled with the default values, and the person decides: Save settings keeps them, Cancel leaves everything as it was.
 		if r.PostFormValue("action") == "defaults" {
-			// An empty settings value removes the file.
-			if err := mon.store.put(appSettings{}); err != nil {
-				// Show the problem.
-				render(w, r, formFromSettings(mon.store.get()), []string{"The settings could not be saved: " + err.Error()}, "", http.StatusInternalServerError)
-				// Stop here.
-				return
-			} // end of the save check
-			// Show the page again with the note.
-			http.Redirect(w, r, "/settings?saved=reset", http.StatusSeeOther)
+			// The default values as the form shows them.
+			render(w, r, formFromSettings(appSettings{}), nil, "draft", http.StatusOK)
 			// Stop here.
 			return
 		} // end of the defaults case
diff --git a/web/settings.html b/web/settings.html
index 4f26879..399173a 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -25,8 +25,8 @@
 <p>Check the values, change what you need and press <strong>Save settings</strong>. A value left empty (or equal to the default) uses the default. Values marked <strong>restart</strong> are used the next time the monitor starts; the others apply at once. The look of the page (light or dark, text size) is changed with the buttons at the top of the monitor page.</p>
 {{/* A note after saving. */}}
 {{if eq .Saved "saved"}}<p class="muted" role="status"><strong>Saved.</strong> {{if .RestartNeeded}}The values marked restart are used the next time the monitor starts.{{else}}The changes are in use now.{{end}}</p>{{end}}
-{{/* A note after going back to the defaults. */}}
-{{if eq .Saved "reset"}}<p class="muted" role="status"><strong>All settings are back to their defaults.</strong> {{if .RestartNeeded}}The values marked restart are used the next time the monitor starts.{{end}}</p>{{end}}
+{{/* A note after "Back to defaults": the default values are filled in, but nothing is saved yet. */}}
+{{if eq .Saved "draft"}}<p class="warn" role="status"><strong>Nothing is saved yet.</strong> The default values are filled in below. Press <strong>Save settings</strong> to keep them, or <strong>Cancel</strong> to leave your settings as they were.</p>{{end}}
 {{/* A note about a damaged settings file or a missing folder. */}}
 {{if .Note}}<p class="warn"><strong>⚠</strong> {{.Note}}</p>{{end}}
 {{/* Problems with what was typed; nothing was saved. */}}
@@ -64,7 +64,7 @@
 {{/* Where the files are kept. */}}
 <p class="muted">Saved in <code>{{if .Folder}}{{.Folder}}{{else}}(no folder found: kept only until the monitor stops){{end}}</code>. The check history file holds only the time, the result and the answer time of each check: no model names and no prompts. Turning the history off deletes that file.</p>
 {{/* The buttons. */}}
-<p><button type="submit" name="action" value="save" class="btn-plain ctlbtn">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain ctlbtn">Back to defaults</button></p>
+<p><button type="submit" name="action" value="save" class="btn-plain ctlbtn">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain ctlbtn">Back to defaults</button> <a class="btn-plain ctlbtn" href="/settings">Cancel</a></p>
 {{/* End of the form. */}}
 </form>
 {{/* A plain way back besides the arrow. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
71023a0a4450eb1403d307f46f03a6534721514ddc06c993426bbeac0af4d3ba  settingspage.go
e019fe364b5e2cc6c1059a4404a6c185d7b6ad1ea70c4364a7a4209cc782833c  web/settings.html
5ef6083d156a49fd904a2c1cce2009e72e7e2dc1506324bda1f9931ac76cabb9  appsettings_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter, open Settings, change the interval, press Back to defaults and check that the page says Nothing is saved yet; then press Cancel and check your values are as before"
# List the changed files; nothing is committed yet.
git status --short
