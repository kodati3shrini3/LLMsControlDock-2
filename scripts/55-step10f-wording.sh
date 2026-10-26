#!/usr/bin/env bash
# Script 55: shorter Performance entry in the key, and the parameters tooltip and key entry now say "view and modify".
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/monitor-controls" ] || { echo "FAIL  not on feature/monitor-controls"; exit 1; }
# Script 54 must be applied first (it puts the reading hints first in the key).
grep -A1 'class="legend' web/index.html | grep -q 'Dotted headings' || { echo "FAIL  script 54 was not applied yet"; exit 1; }
# Refuse to run twice: after this change the parameters tooltip says "View and modify".
if grep -q 'View and modify the model' web/index.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear_test.go b/gear_test.go
index 464ece6..a0b297b 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -1221,7 +1221,7 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 	// Fetch the page.
 	_, _, body := get(t, rig.h, http.MethodGet, "/")
 	// The not-loaded model has a gear form with an accessible name.
-	for _, want := range []string{`action="/gear"`, `aria-label="Inference parameters of embed:1b"`, `class="gear"`, `id="tipgear-embed:1b"`, `View the model's Inference parameters`} {
+	for _, want := range []string{`action="/gear"`, `aria-label="Inference parameters of embed:1b"`, `class="gear"`, `id="tipgear-embed:1b"`, `View and modify the model's Inference parameters`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
diff --git a/web/index.html b/web/index.html
index 069de42..40d4d70 100644
--- a/web/index.html
+++ b/web/index.html
@@ -153,8 +153,8 @@
 <li><span class="sym"><span class="dotsample">Aa</span></span><span><strong>Dotted headings</strong>: point at one, or press Tab, to see what it means</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8l-4 4 4 4"/><path d="M17 8l4 4-4 4"/></svg></span><span><strong>Sideways scroll</strong>: the table scrolls sideways</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: only for models that are not loaded</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; not shown while the model is loaded, because it may be in use</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: view and modify them; only for models that are not loaded</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
 </ul>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
@@ -265,7 +265,7 @@
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
 <button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></button>
 {{/* The tip. */}}
-<span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View the model's Inference parameters</span>
+<span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View and modify the model's Inference parameters</span>
 {{/* End of the tip area. */}}
 </span>
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
53b78a2f6659d572cb7e201684642e7294b083bf3df2fd97be831e5bd5f9712e  gear_test.go
7d85f21e71cea03ffb84319a2019851483e0623370b2538de47fc08ead849a07  web/index.html
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
