#!/usr/bin/env bash
# Script 46: fixes three look-and-feel issues: the model tooltip hidden under the category band, plain table headings, and misaligned buttons on the performance pages.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-performance-test" ] || { echo "FAIL  not on feature/model-performance-test"; exit 1; }
# Script 45 must be applied first (it adds the tooltip anchoring).
grep -q 'position-anchor: --tipicon' web/app.css || { echo "FAIL  script 45 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'perfclear' web/performance.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/web/app.css b/web/app.css
index 7555876..8eb9c32 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1105,3 +1105,45 @@ button.btn-plain {
     max-width: none;
   } /* end of rule */
 } /* end of rule */
+
+/* The column headings of the performance tables look like the headings on the main page: the panel colour behind them. */
+.settingtable thead th {
+  /* Panel colour so the heading row differs from the rows. */
+  background: var(--panel);
+} /* end of rule */
+
+/* A model name cell that is pointed at (or has the keyboard focus) rises above the category bands, so its bubble is never hidden under them. */
+.stickycol:hover, .stickycol:focus-within {
+  /* Above the category heading box (3) and the corner cell (4). */
+  z-index: 6;
+} /* end of rule */
+
+/* Buttons and links in a row are exactly the same size and sit on one line. */
+.choices form {
+  /* No outer space, so the form does not push the row out of line. */
+  margin: 0;
+} /* end of rule */
+
+/* Link buttons and real buttons share one box model. */
+.choices .btn-plain, .choices .btn-load {
+  /* Same box for a link and a button. */
+  display: inline-block;
+  /* Same height rule. */
+  box-sizing: border-box;
+  /* Same line height. */
+  line-height: 1.4;
+  /* No outer space. */
+  margin: 0;
+} /* end of rule */
+
+/* The performance tables are drawn like the table on the main page: an outline, white rows and a grey heading row. */
+.perftable {
+  /* The outline in the border colour, like the main table's frame. */
+  border: 2px solid var(--border);
+} /* end of rule */
+
+/* The rows are in the page colour, so the grey heading row stands out from them. */
+.perftable tbody th, .perftable tbody td {
+  /* Page colour behind the rows. */
+  background: var(--bg);
+} /* end of rule */
diff --git a/web/performance.html b/web/performance.html
index 87f4fa6..5300db2 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -26,6 +26,16 @@
 {{/* End of the group. */}}
 {{end}}
 {{/* The history table of one model. */}}
+{{define "perfclear"}}
+{{if .HistoryCount}}
+{{/* A small form that sends the model name and the page token to the clear question. */}}
+<form method="post" action="/performance/clear">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-plain">Clear all saved results ({{.HistoryCount}})…</button>
+</form>
+{{end}}
+{{end}}
 {{define "perfhistory"}}
 {{/* Only when there are saved runs. */}}
 {{if .HistoryRows}}
@@ -50,14 +60,6 @@
 {{end}}
 {{/* Where the numbers are kept, and the button that clears them. */}}
 {{if .SaveNote}}<p class="muted">{{.SaveNote}}</p>{{end}}
-{{if .HistoryCount}}
-{{/* A small form that sends the model name and the page token to the clear question. */}}
-<form method="post" action="/performance/clear">
-<input type="hidden" name="token" value="{{.Token}}">
-<input type="hidden" name="model" value="{{.Model}}">
-<button type="submit" class="btn-plain">Clear all saved results ({{.HistoryCount}})…</button>
-</form>
-{{end}}
 {{end}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
@@ -117,6 +119,8 @@
 </div>
 {{/* The saved tests. */}}
 {{template "perfhistory" .}}
+{{/* The clear button on its own row. */}}
+<div class="choices">{{template "perfclear" .}}</div>
 {{/* Version 2: the result. */}}
 {{else if eq .Kind "result"}}
 {{/* The warnings. */}}
@@ -132,6 +136,7 @@
 {{template "perfhistory" .}}
 {{/* The links. */}}
 <div class="choices">
+{{template "perfclear" .}}
 <form method="post" action="/performance">
 <input type="hidden" name="token" value="{{.Token}}">
 <input type="hidden" name="model" value="{{.Model}}">
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
c99bddfebe3f9584e217b9b063789c3ccad7a82f7aa2f25b27bf7da4c0b43c0b  web/app.css
6def395c9e9f2da0fe4a4e11c22d3ce23acaef33e3ec3cc70c5e4736a5381122  web/performance.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The file is exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
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
