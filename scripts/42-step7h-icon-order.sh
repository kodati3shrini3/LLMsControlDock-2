#!/usr/bin/env bash
# Script 42: puts the Modelfile page icon on top and the gear below it, and centres the two icons above each other.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/modelfile-view" ] || { echo "FAIL  not on feature/modelfile-view"; exit 1; }
# Script 41 must be applied first (it creates modelfile.go).
[ -f modelfile.go ] || { echo "FAIL  script 41 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'centred above each other' web/index.html; then
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
index 7f9bcdf..72a1551 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -1368,8 +1368,8 @@ func TestMainPageModelfileIconForEveryModel(t *testing.T) {
 			t.Errorf("%q points at nothing", m[1])
 		} // end of the target check
 	} // end of the loop
-	// The Modelfile icon comes after the gear in the first not-loaded row.
-	if i, j := strings.Index(body, `action="/gear"`), strings.Index(body, `action="/modelfile"`); !(i >= 0 && j > i) {
+	// The Modelfile icon comes before (above) the gear in the first not-loaded row.
+	if i, j := strings.Index(body, `action="/gear"`), strings.Index(body, `action="/modelfile"`); !(j >= 0 && i > j) {
 		// Report the problem.
 		t.Errorf("icon order: gear %d, modelfile %d", i, j)
 	} // end of the order check
diff --git a/web/app.css b/web/app.css
index 3ba3c3b..d524790 100644
--- a/web/app.css
+++ b/web/app.css
@@ -781,6 +781,8 @@ h2 {
   flex-direction: column;
   /* Level with the state words. */
   vertical-align: middle;
+  /* Each icon is centred in the column, so the gear sits exactly under the page icon. */
+  align-items: center;
 } /* end of rule */
 
 /* A tip for an icon is a single short line, so it is only as wide as its text (but never wider than the normal bubble). */
@@ -819,6 +821,8 @@ h2 {
   display: inline-block;
   /* The same width for both. */
   width: 1.6rem;
+  /* The icon inside is centred in that width. */
+  text-align: center;
   /* No outer space. */
   margin: 0;
 } /* end of rule */
diff --git a/web/index.html b/web/index.html
index e5a308f..5250a93 100644
--- a/web/index.html
+++ b/web/index.html
@@ -79,7 +79,7 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The gear ⚙ opens a model's inference parameters; it appears only for models that are not loaded. The page icon 📄 below it shows the model's Modelfile, read-only. The table scrolls sideways.</p>
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The table scrolls sideways.</p>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -137,43 +137,43 @@
 <th scope="row" class="stickycol">{{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
-{{/* Two small icons stacked in a fixed-width column: the gear on top (only for a model that is not loaded; a loaded model gets an empty slot, so the state words stay in line) and the Modelfile page icon just below it (for every model). */}}
+{{/* Two small icons stacked in a fixed-width column, centred above each other: the Modelfile page icon on top (for every model) and the gear just below it (only for a model that is not loaded; a loaded model gets an empty slot, so the state words stay in line). */}}
 <span class="iconstack">
-{{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
-{{/* A small form that sends the model name and the page token to the settings page, which changes nothing. */}}
-<form class="gearform" method="post" action="/gear">
+{{/* A small form that sends the model name and the page token to the Modelfile page, which only reads and changes nothing. */}}
+<form class="gearform" method="post" action="/modelfile">
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{$.Token}}">
 {{/* The model name. */}}
 <input type="hidden" name="model" value="{{.Name}}">
-{{/* The area that opens the tip: pointing at the gear or reaching it with Tab shows what it is for. */}}
+{{/* The area that opens the tip. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><span aria-hidden="true">⚙</span></button>
+<button type="submit" class="gear" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><span aria-hidden="true">📄</span></button>
 {{/* The tip. */}}
-<span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View the model's Inference parameters</span>
+<span class="tip tip-icon" role="tooltip" id="tipfile-{{.Name}}">Show the model's Modelfile (read-only)</span>
 {{/* End of the tip area. */}}
 </span>
 {{/* End of the form. */}}
 </form>
-{{/* End of the gear. */}}
-{{end}}
-{{/* A small form that sends the model name and the page token to the Modelfile page, which only reads and changes nothing. */}}
-<form class="gearform" method="post" action="/modelfile">
+{{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
+{{/* A small form that sends the model name and the page token to the settings page, which changes nothing. */}}
+<form class="gearform" method="post" action="/gear">
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{$.Token}}">
 {{/* The model name. */}}
 <input type="hidden" name="model" value="{{.Name}}">
-{{/* The area that opens the tip. */}}
+{{/* The area that opens the tip: pointing at the gear or reaching it with Tab shows what it is for. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><span aria-hidden="true">📄</span></button>
+<button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><span aria-hidden="true">⚙</span></button>
 {{/* The tip. */}}
-<span class="tip tip-icon" role="tooltip" id="tipfile-{{.Name}}">Show the model's Modelfile (read-only)</span>
+<span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View the model's Inference parameters</span>
 {{/* End of the tip area. */}}
 </span>
 {{/* End of the form. */}}
 </form>
+{{/* End of the gear. */}}
+{{end}}
 {{/* End of the icon column. */}}
 </span>
 <span class="statelabel"><span class="dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}" aria-hidden="true"></span> {{.StateWord}}</span>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
0031b663e1cd05a685169597d71102eb271511b30b1ef0cb88e2f91ec4ad23d0  gear_test.go
21c2f13bd2fd2a011ff000a39c186a8f2a0c59d633c8a91a09a85739930fc1d9  web/app.css
2d101c5954bce8dd9f3a55af831ff1b4dfa5923c066dbd70d9b3d325a24377fe  web/index.html
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
