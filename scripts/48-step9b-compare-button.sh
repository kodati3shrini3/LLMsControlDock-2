#!/usr/bin/env bash
# Script 48: replaces the small scales icon beside "Model" by a labelled button "Compare tested models (N)" above the table.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-comparison" ] || { echo "FAIL  not on feature/model-comparison"; exit 1; }
# Script 47 must be applied first (it creates compare.go).
[ -f compare.go ] || { echo "FAIL  script 47 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'comparebtn' web/app.css; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/compare.go b/compare.go
index 8f338a8..681fc0c 100644
--- a/compare.go
+++ b/compare.go
@@ -114,6 +114,14 @@ func (s *perfStore) latestRuns(promptVersion string) ([]perfRun, int) {
 	return out, skipped
 } // end of latestRuns
 
+// testedModels says how many models have a saved test with the current prompt, which is the number of rows the comparison page would show.
+func (s *perfStore) testedModels() int {
+	// The latest runs of the current prompt.
+	runs, _ := s.latestRuns(perfPromptVersion)
+	// One for each model.
+	return len(runs)
+} // end of testedModels
+
 // cmpGB turns bytes into decimal gigabytes (the unit Ollama and the rest of this program use).
 func cmpGB(b int64) float64 {
 	// Decimal gigabytes.
diff --git a/compare_test.go b/compare_test.go
index fede61d..c134894 100644
--- a/compare_test.go
+++ b/compare_test.go
@@ -240,6 +240,11 @@ func TestLatestRuns(t *testing.T) {
 		// Report it.
 		t.Errorf("latestRuns = %+v, skipped %d", got, skipped)
 	} // end of the check
+	// The number shown on the main page's button is the number of models that would be compared.
+	if n := s.testedModels(); n != 1 {
+		// Report it.
+		t.Errorf("testedModels = %d, want 1", n)
+	} // end of the count check
 } // end of TestLatestRuns
 
 // TestCompareRoute checks the page through the real handler: saved test runs show up, the form rules hold, and the main page has the icon.
@@ -301,11 +306,11 @@ func TestCompareRoute(t *testing.T) {
 		// Report it.
 		t.Errorf("GET /compare = %d", status)
 	} // end of the GET check
-	// The main page has exactly one compare icon, in the header, with the tip the person asked for.
+	// The main page has exactly one compare button, above the table, with the number of tested models and the tip the person asked for.
 	_, _, main := get(t, rig.h, http.MethodGet, "/")
 	// Count and look.
-	if strings.Count(main, `action="/compare"`) != 1 || !strings.Contains(main, "Compare models that have already been through a performance test") || strings.Index(main, `action="/compare"`) > strings.Index(main, "<tbody>") {
+	if strings.Count(main, `action="/compare"`) != 1 || !strings.Contains(main, "Compare models that have already been through a performance test") || strings.Index(main, `action="/compare"`) > strings.Index(main, `<table class="models">`) || !strings.Contains(main, "Compare tested models (2)") {
 		// Report it.
-		t.Errorf("main page icon wrong (count %d)", strings.Count(main, `action="/compare"`))
+		t.Errorf("main page button wrong (count %d)", strings.Count(main, `action="/compare"`))
 	} // end of the icon check
 } // end of TestCompareRoute
diff --git a/web/app.css b/web/app.css
index d21d295..2522d8a 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox {
+.gearform .tipbox, .comparebar .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -1148,13 +1148,6 @@ button.btn-plain {
   background: var(--bg);
 } /* end of rule */
 
-/* The compare icon sits right after the word Model in the first heading. */
-.comparehead {
-  /* A little room after the heading text. */
-  margin-left: 0.4rem;
-  /* On the same line as the heading text. */
-  vertical-align: middle;
-} /* end of rule */
 
 /* The comparison table: long values such as the busy reason wrap instead of making the table very wide. */
 .comparetable td, .comparetable th {
@@ -1169,3 +1162,23 @@ button.btn-plain {
   /* A comfortable gap above the next heading. */
   margin-top: 1.4rem;
 } /* end of rule */
+
+/* The bar with the compare button: a little room above and below it. */
+.comparebar {
+  /* Space between the hint and the table. */
+  margin: 0.5rem 0 0.9rem;
+} /* end of rule */
+
+/* The compare button is a little bolder than the other outlined buttons, so it is seen as an action. */
+.comparebtn {
+  /* Bold text. */
+  font-weight: 600;
+  /* Same font as the page, not the browser's button font. */
+  font: inherit;
+  /* Bold again after the font shorthand reset it. */
+  font-weight: 600;
+  /* A hand cursor. */
+  cursor: pointer;
+  /* Transparent background like the link version. */
+  background: transparent;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 5f6e2e5..2c0685f 100644
--- a/web/index.html
+++ b/web/index.html
@@ -79,7 +79,25 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The scales icon ⚖ beside the heading Model compares the models that have been tested. The table scrolls sideways.</p>
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The button Compare tested models above the table puts the tested models side by side. The table scrolls sideways.</p>
+{{/* The compare button: a labelled button above the table, with the number of models that have been tested. */}}
+<div class="comparebar">
+{{/* A small form that opens the comparison page and changes nothing. */}}
+<form method="post" action="/compare">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the words. */}}
+<button type="submit" class="btn-plain comparebtn" aria-describedby="tipcompare"><span aria-hidden="true">⚖</span> Compare tested models ({{.CompareCount}})</button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipcompare">Compare models that have already been through a performance test</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the compare form. */}}
+</form>
+{{/* End of the compare button bar. */}}
+</div>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -99,23 +117,6 @@
 <span class="tip" role="tooltip" id="{{$c.Tip.ID}}">{{template "tip" $c.Tip}}</span>
 {{/* End of the bubble area. */}}
 </div>
-{{/* In the first heading only: the compare icon, a small form that opens the comparison page and changes nothing. */}}
-{{if eq $i 0}}
-<form class="gearform comparehead" method="post" action="/compare">
-{{/* The page token proves the form comes from this monitor. */}}
-<input type="hidden" name="token" value="{{$.Token}}">
-{{/* The area that opens the tip. */}}
-<span class="tipbox">
-{{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Compare models that have been tested" aria-describedby="tipcompare"><span aria-hidden="true">⚖</span></button>
-{{/* The tip. */}}
-<span class="tip tip-icon" role="tooltip" id="tipcompare">Compare models that have already been through a performance test</span>
-{{/* End of the tip area. */}}
-</span>
-{{/* End of the compare form. */}}
-</form>
-{{/* End of the first-column check. */}}
-{{end}}
 {{/* End of the heading cell. */}}
 </th>
 {{/* End of the column loop. */}}
diff --git a/web.go b/web.go
index 04782d0..b0ce63f 100644
--- a/web.go
+++ b/web.go
@@ -53,6 +53,8 @@ type pageData struct {
 	Theme string
 	// Token is the page token that every form on the page carries.
 	Token string
+	// CompareCount is how many models have a saved performance test that can be compared.
+	CompareCount int
 } // end of pageData
 
 // secureHeaders wraps a handler so every reply, including errors, carries the same safety headers.
@@ -149,6 +151,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			Theme: themeFromRequest(r),
 			// The page token for the forms.
 			Token: token,
+			// How many models can be compared.
+			CompareCount: perfHistory.testedModels(),
 		} // end of the data
 		// Only an online Ollama can be asked for its model lists.
 		if res.Online {
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
0e546d36ca1a04f44c7984b05fb11a8b4fd8ac99fb8edc119477c421c0bcd747  compare.go
4273558baf858e74f6039f6a993b9a02880305b6d446f1891e2eed33dbf78afa  compare_test.go
ed7b6ca5d1781a73d76aef7af19b7fb403e45f02e5163b0739e751f0bebd5f97  web.go
c8199e0fc9d180296f005d575526016dd78ff73d02b36e00b805007e5d746f05  web/app.css
15fc468d765c5575fc8a1a218b4b378f0b8d9c31c02689c0318f90a386935618  web/index.html
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
