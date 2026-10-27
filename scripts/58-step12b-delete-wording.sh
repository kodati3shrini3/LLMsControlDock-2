#!/usr/bin/env bash
# Script 58: wording of the delete feature: inference parameters are not restored (warning and restore page), a shorter Delete key entry, and a new Restore key entry.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-model" ] || { echo "FAIL  not on feature/delete-model"; exit 1; }
# Script 57 must be applied first.
[ -e delete.go ] || { echo "FAIL  script 57 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'tune them again' web/delete.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/control_test.go b/control_test.go
index c3fc584..fe2a2a3 100644
--- a/control_test.go
+++ b/control_test.go
@@ -387,21 +387,21 @@ func TestKeyAndDrawnIcons(t *testing.T) {
 			t.Errorf("the page still contains %q", bad)
 		} // end of the character check
 	} // end of the loop
-	// The key names all seven things.
-	for _, want := range []string{"Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Delete</strong>", "Compare tested models</strong>", "Dotted headings</strong>", "Sideways scroll</strong>", `class="legend muted"`} {
+	// The key names all eight things.
+	for _, want := range []string{"Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Delete</strong>", "Restore</strong>", "Compare tested models</strong>", "Dotted headings</strong>", "Sideways scroll</strong>", `class="legend muted"`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
 			t.Errorf("the key lacks %q", want)
 		} // end of the check
 	} // end of the loop
-	// Seven entries in the key.
-	if n := strings.Count(body, `<li><span class="sym">`); n != 7 {
+	// Eight entries in the key.
+	if n := strings.Count(body, `<li><span class="sym">`); n != 8 {
 		// Report it.
-		t.Errorf("the key has %d entries, want 7", n)
+		t.Errorf("the key has %d entries, want 8", n)
 	} // end of the count check
-	// The two reading hints come first in the key, then the five icon explanations.
-	order := []string{"Dotted headings</strong>", "Sideways scroll</strong>", "Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Delete</strong>", "Compare tested models</strong>"}
+	// The two reading hints come first in the key, then the six icon explanations.
+	order := []string{"Dotted headings</strong>", "Sideways scroll</strong>", "Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Delete</strong>", "Restore</strong>", "Compare tested models</strong>"}
 	// Walk the list and make sure each entry comes after the one before.
 	last := -1
 	// Each entry.
diff --git a/delete_test.go b/delete_test.go
index cdca480..b31a17d 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -238,7 +238,7 @@ func TestDeleteWarningChangesNothing(t *testing.T) {
 		t.Fatalf("status %d", res.StatusCode)
 	} // end of the status check
 	// The warning words and both choices.
-	for _, want := range []string{"This removes the model from this computer", "1.3 GB", "Restore", "Yes, delete it", "No, keep it", `action="/delete/confirm"`} {
+	for _, want := range []string{"This removes the model from this computer", "1.3 GB", "Restore", "not</strong> restored", "tune them again", "cannot be downloaded again", "Yes, delete it", "No, keep it", `action="/delete/confirm"`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
@@ -345,7 +345,7 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 	// The restore page shows the manual command.
 	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
 	// The words.
-	for _, want := range []string{"ollama pull alpha:1b", "latest version", "cannot be downloaded again"} {
+	for _, want := range []string{"ollama pull alpha:1b", "latest version", "Inference parameters you changed are not restored", "cannot be downloaded again"} {
 		// Look for it.
 		if !strings.Contains(restore, want) {
 			// Report the gap.
diff --git a/web/delete.html b/web/delete.html
index e2e5956..b0842c8 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -32,7 +32,11 @@
 {{/* Saved settings. */}}
 <li>Settings saved inside the model, such as inference parameters you changed here, are removed with it.</li>
 {{/* How to get it back. */}}
-<li>You can bring it back with <strong>Restore</strong>. That downloads it again (about {{.SizeText}}, from the Ollama library) and gives you the latest version of the same name, which may differ from today&#39;s. A model you made yourself, from a Modelfile or an import, cannot be downloaded again.</li>
+<li>You can bring it back with <strong>Restore</strong>: it downloads the model again (about {{.SizeText}}) and gives you the latest version of the same name.</li>
+{{/* The lost tuning. */}}
+<li>A restored model is a fresh copy: any changes you made to its inference parameters are <strong>not</strong> restored, and you must tune them again.</li>
+{{/* Models that cannot come back. */}}
+<li>A model you made yourself (from a Modelfile or an import) cannot be downloaded again.</li>
 {{/* End of the consequences. */}}
 </ul>
 {{/* What the monitor keeps. */}}
@@ -114,7 +118,11 @@
 {{/* What is remembered. */}}
 <p>Deleted on {{.When}}. Size then: <strong>{{.SizeText}}</strong>.{{if .Digest}} Fingerprint then: <code>{{.Digest}}</code>.{{end}}</p>
 {{/* What Restore means. */}}
-<p>Restoring means downloading the model again from the Ollama library. You get the latest version of this name, which may differ from the one that was deleted. A model you made yourself, from a Modelfile or an import, cannot be downloaded again.</p>
+<p>Restoring means downloading the model again from the Ollama library. You get the latest version of this name, which may differ from the one that was deleted.</p>
+{{/* The lost tuning. */}}
+<p><strong>Inference parameters you changed are not restored.</strong> The model comes back as a fresh copy, so tune them again.</p>
+{{/* Models that cannot come back. */}}
+<p>A model you made yourself (from a Modelfile or an import) cannot be downloaded again.</p>
 {{/* The manual way, until the in-page download arrives. */}}
 <p>For now, run this in a terminal on the computer that runs Ollama:</p>
 {{/* The command. */}}
diff --git a/web/index.html b/web/index.html
index 1886788..f2b2526 100644
--- a/web/index.html
+++ b/web/index.html
@@ -155,7 +155,8 @@
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: view and modify them; only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; only for models that are not loaded</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span><span><strong>Delete</strong>: below the performance icon; asks first, and a deleted model stays in the table to restore</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span><span><strong>Delete</strong>: removes a model from this computer; asks first</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></span><span><strong>Restore</strong>: on a greyed, deleted row; shows how to download the model again</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
 </ul>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
60d6b0f3b2b435434f81f67cedee4a268b37d23ec7a4be942731e4161b647d74  control_test.go
a0b95ee47bf6661ed5ad4f19e2c330a8ab83692cbe623bf16f3ddaa4648f5ed4  delete_test.go
00cad20b33cd4fbc4096ca152fa4e2b2f2a33be7d42415c17c7046b6062eaa71  web/delete.html
1179f59562af4f27ae906bf3c31fcd0b0e3602eda41151d821c37ff7ad4ec201  web/index.html
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
