#!/usr/bin/env bash
# Script 70c: a follow-up to script 70b on the same branch. The Settings page gets the same Back to the monitor button as the other pages, and its Save settings, Back to defaults and Cancel buttons now have the same size. No version change (0.22.0).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/settings-panel" ] || { echo "FAIL  not on feature/settings-panel"; exit 1; }
# Script 70 (the Settings page) must be applied already.
grep -q "Nothing is saved yet" web/settings.html || { echo "FAIL  script 70b was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "Back to the monitor</a></p>" web/settings.html && grep -q "btn-plain\" href=\"/\">Back to the monitor" web/settings.html; then
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
index 5bea1fe..7cb7776 100644
--- a/appsettings_test.go
+++ b/appsettings_test.go
@@ -576,6 +576,11 @@ func TestSettingsLinkAndArrow(t *testing.T) {
 		// Report it.
 		t.Errorf("the Settings page has no back arrow at the top (%d, %d)", i, j)
 	} // end of the arrow check
+	// The button at the bottom is the same as on the other pages.
+	if !strings.Contains(page, `<a class="btn-plain" href="/">Back to the monitor</a>`) {
+		// Report it.
+		t.Errorf("the Settings page lacks the Back to the monitor button")
+	} // end of the button check
 	// A page never caches, because it shows live values.
 	if _, h, _ := get(t, r.h, http.MethodGet, "/settings"); h.Get("Cache-Control") != "no-store" {
 		// Report it.
diff --git a/web/settings.html b/web/settings.html
index 399173a..9450757 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -64,11 +64,11 @@
 {{/* Where the files are kept. */}}
 <p class="muted">Saved in <code>{{if .Folder}}{{.Folder}}{{else}}(no folder found: kept only until the monitor stops){{end}}</code>. The check history file holds only the time, the result and the answer time of each check: no model names and no prompts. Turning the history off deletes that file.</p>
 {{/* The buttons. */}}
-<p><button type="submit" name="action" value="save" class="btn-plain ctlbtn">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain ctlbtn">Back to defaults</button> <a class="btn-plain ctlbtn" href="/settings">Cancel</a></p>
+<p><button type="submit" name="action" value="save" class="btn-plain">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain">Back to defaults</button> <a class="btn-plain" href="/settings">Cancel</a></p>
 {{/* End of the form. */}}
 </form>
-{{/* A plain way back besides the arrow. */}}
-<p><a href="/">Back to the monitor</a></p>
+{{/* A plain way back besides the arrow: the same button as on the other pages. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
 {{/* End of the box. */}}
 </section>
 {{/* End of the page content. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
723540011a8aae1d04b83984feda13b407a487e20c3e8cd324b5e7facd8be2f7  web/settings.html
a90c59bc14a06caf6d9da4fc476a24c71987d7985716a70ba98cb3290aa31f28  appsettings_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter, open Settings and check that Save settings, Back to defaults and Cancel look alike and that a Back to the monitor button is at the bottom"
# List the changed files; nothing is committed yet.
git status --short
