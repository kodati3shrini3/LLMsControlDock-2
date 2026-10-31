#!/usr/bin/env bash
# Script 69s: a small fix on the same branch as 69r, applied before it is committed. On a row of a loaded model the delete icon (first column) and the Modelfile icon (state column) sat on different lines, because each stack kept an empty slot for an icon that a loaded model does not get. The empty slots are gone, so both icons now stand alone on the same line as the model name and the word Loaded. Rows of models that are not loaded are unchanged.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/charts-memory" ] || { echo "FAIL  not on feature/charts-memory"; exit 1; }
# Script 69r (the memory of loaded models) must be applied already.
[ -e chartmem.go ] || { echo "FAIL  script 69r was not applied yet"; exit 1; }
# Refuse to run twice.
if ! grep -q "if .Loaded}}<span class=\"gearslot\"" web/index.html; then
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
index a0372e8..1bead9e 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -1244,10 +1244,10 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 		// Report the problem.
 		t.Errorf("a loaded model has a gear")
 	} // end of the loaded check
-	// The loaded row has two empty slots: one where the performance icon would be, one where the gear would be.
-	if strings.Count(body, `class="gearslot"`) != 2 {
+	// The loaded row keeps no empty slots: its icons stand alone, so the delete icon and the Modelfile icon sit on one line.
+	if strings.Count(body, `class="gearslot"`) != 0 {
 		// Report the problem.
-		t.Errorf("the loaded row has no empty gear slot")
+		t.Errorf("the loaded row still has an empty slot, which pushes its icons onto different lines")
 	} // end of the slot check
 	// The gear comes before the state words in its cell.
 	if i, j := strings.Index(body, `class="gearform"`), strings.Index(body, `class="statelabel"`); !(i >= 0 && j >= 0 && i < strings.LastIndex(body, `class="statelabel"`)) {
diff --git a/web/index.html b/web/index.html
index ca3cee9..1d88be6 100644
--- a/web/index.html
+++ b/web/index.html
@@ -370,10 +370,10 @@
 <tr data-model="{{.Name}}" data-loaded="{{if .Loaded}}1{{else}}0{{end}}">{{/* start of a table row. */}}
 {{/* The model name is the row heading and stays visible while scrolling. */}}
 <th scope="row" class="stickycol">
-{{/* The performance icon comes before the name; a loaded model may be in use, so it gets an empty slot of the same width instead, and the names stay in line. */}}
-{{/* Two icons stacked in a fixed-width column: the performance icon on top (empty slot on a loaded model) and the delete icon just below it (for every model). */}}
+{{/* The performance icon comes before the name; a loaded model may be in use, so it gets none. */}}
+{{/* Icons stacked in a fixed-width column: the performance icon on top (not for a loaded model, whose column then holds the delete icon alone, level with the Modelfile icon next to it) and the delete icon just below it (for every model). */}}
 <span class="iconstack">
-{{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
+{{if not .Loaded}}
 {{/* A small form that sends the model name and the page token to the performance page, which changes nothing. */}}
 <form class="gearform" method="post" action="/performance">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -413,7 +413,7 @@
 {{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
-{{/* Two small icons stacked in a fixed-width column, centred above each other: the Modelfile page icon on top (for every model) and the gear just below it (only for a model that is not loaded; a loaded model gets an empty slot, so the state words stay in line). */}}
+{{/* Two small icons stacked in a fixed-width column, centred above each other: the Modelfile page icon on top (for every model) and the gear just below it (only for a model that is not loaded; on a loaded row the Modelfile icon is alone, level with the delete icon of the first column). */}}
 <span class="iconstack">
 {{/* A small form that sends the model name and the page token to the Modelfile page, which only reads and changes nothing. */}}
 <form class="gearform" method="post" action="/modelfile">
@@ -431,7 +431,7 @@
 </span>
 {{/* End of the form. */}}
 </form>
-{{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
+{{if not .Loaded}}
 {{/* A small form that sends the model name and the page token to the settings page, which changes nothing. */}}
 <form class="gearform" method="post" action="/gear">
 {{/* The page token proves the form comes from this monitor. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
37e32c8a3c332467628d5ae7fb41709fa9bf85ef3ee244b8585bdaac57796ad7  web/index.html
3bf73b5f4294ad6e849a2a76d8afd84cc5920275e97b76f592c99c0694aa390d  gear_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and load a model and check that its delete icon and file icon sit on the same line as its name"
# List the changed files; nothing is committed yet.
git status --short
