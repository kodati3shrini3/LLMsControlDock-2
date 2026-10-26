#!/usr/bin/env bash
# Script 53: drawn icons for the table and the compare button (blue, bigger scale), and a key above the models table that explains each symbol.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on main: this change belongs on its own feature branch.
[ "$(git branch --show-current)" = "feature/monitor-controls" ] || { echo "FAIL  not on feature/monitor-controls"; exit 1; }
# Script 52 must be applied first (it words the Stop tooltip).
grep -q 'Stop this OllamaControlCenter monitor program' web/index.html || { echo "FAIL  script 52 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'class="legend' web/index.html; then
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
index c677e47..0fd4d6d 100644
--- a/control_test.go
+++ b/control_test.go
@@ -372,3 +372,42 @@ func TestControlIconsAndZone(t *testing.T) {
 		} // end of the zone check
 	} // end of the loop
 } // end of TestControlIconsAndZone
+
+// TestKeyAndDrawnIcons checks the key above the models table and that the table icons are drawn, not emoji characters.
+func TestKeyAndDrawnIcons(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The main page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// None of the old emoji-like characters may remain on the page.
+	for _, bad := range []string{"📄", "⚙", "📈", "⚖"} {
+		// Look for it.
+		if strings.Contains(body, bad) {
+			// Report it.
+			t.Errorf("the page still contains %q", bad)
+		} // end of the character check
+	} // end of the loop
+	// The key names all six things.
+	for _, want := range []string{"Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Compare tested models</strong>", "Dotted headings</strong>", "Sideways scroll</strong>", `class="legend muted"`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("the key lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Six entries in the key.
+	if n := strings.Count(body, `<li><span class="sym">`); n != 6 {
+		// Report it.
+		t.Errorf("the key has %d entries, want 6", n)
+	} // end of the count check
+	// The compare button has the bigger drawn scale.
+	if !strings.Contains(body, `<svg class="ico ico-big"`) {
+		// Report it.
+		t.Errorf("the compare button has no big drawn icon")
+	} // end of the compare check
+	// The three row icons (modelfile, parameters, performance) are drawn buttons of the table.
+	if n := strings.Count(body, `class="gear" aria-label=`); n < 3 {
+		// Report it.
+		t.Errorf("only %d icon buttons in the table", n)
+	} // end of the row check
+} // end of TestKeyAndDrawnIcons
diff --git a/gear_test.go b/gear_test.go
index b0dcd31..464ece6 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -1243,8 +1243,8 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 		// Report the problem.
 		t.Errorf("gear position: %d %d", i, j)
 	} // end of the order check
-	// The hint line explains the gear.
-	if !strings.Contains(body, "appears only for models that are not loaded") {
+	// The key above the table explains the parameters icon.
+	if !strings.Contains(body, "only for models that are not loaded") {
 		// Report the problem.
 		t.Errorf("no hint about the gear")
 	} // end of the hint check
diff --git a/perf_test.go b/perf_test.go
index d432677..1df2446 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -1050,7 +1050,7 @@ func TestMainPagePerformanceIcon(t *testing.T) {
 	// The cell of the row heading.
 	cell := row[:strings.Index(row, "</th>")]
 	// Everything must be in the cell, and the name must come last.
-	for _, want := range []string{`action="/performance"`, `aria-label="Performance of embed:1b"`, `id="tipperf-embed:1b"`, "Performance: see how fast this model runs on this machine", "📈"} {
+	for _, want := range []string{`action="/performance"`, `aria-label="Performance of embed:1b"`, `id="tipperf-embed:1b"`, "Performance: see how fast this model runs on this machine", `<svg class="ico"`} {
 		// Look for it.
 		if !strings.Contains(cell, want) {
 			// Report the gap.
@@ -1058,7 +1058,7 @@ func TestMainPagePerformanceIcon(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// The name comes after the icon.
-	if !strings.HasSuffix(strings.TrimSpace(cell), "embed:1b") || strings.Index(cell, "📈") > strings.LastIndex(cell, "embed:1b") {
+	if !strings.HasSuffix(strings.TrimSpace(cell), "embed:1b") || strings.Index(cell, `<svg class="ico"`) > strings.LastIndex(cell, "embed:1b") {
 		// Report the problem.
 		t.Errorf("the icon is not before the name")
 	} // end of the order check
diff --git a/web/app.css b/web/app.css
index 096877e..00ee386 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1298,3 +1298,85 @@ button.btn-plain {
   /* A small gap before the words. */
   margin-right: 0.15rem;
 } /* end of rule */
+
+/* The compare button is blue like the category bands, so it stands out as a feature button; both themes use their own variables. */
+.comparebtn {
+  /* The soft blue of the category bands. */
+  background: var(--cat-bg);
+  /* Dark blue text in light mode, pale blue in dark mode: readable on the fill. */
+  color: var(--cat-text);
+  /* A blue outline. */
+  border-color: var(--cat-accent);
+} /* end of rule */
+
+/* The scale in the compare button is a little bigger than the other icons, with more room before the words. */
+.ico-big {
+  /* More room before the words. */
+  margin-right: 0.35rem;
+  /* Sits level with the words. */
+  vertical-align: -5px;
+} /* end of rule */
+
+/* The icons inside the round icon buttons of the table need no gap and sit in the middle of the line. */
+.gear .ico {
+  /* No gap: there are no words next to them. */
+  margin-right: 0;
+  /* Level with the middle of the line. */
+  vertical-align: middle;
+} /* end of rule */
+
+/* The key above the models table: icon, bold name and a short explanation, in columns that wrap. */
+.legend {
+  /* No bullets. */
+  list-style: none;
+  /* A little room below. */
+  margin: 0 0 0.8rem;
+  /* No inner space. */
+  padding: 0;
+  /* Columns of at least 15rem, as many as fit. */
+  display: grid;
+  /* The column rule. */
+  grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
+  /* Space between rows and columns. */
+  gap: 0.5rem 1rem;
+} /* end of rule */
+
+/* One entry of the key: icon at the left, words at the right. */
+.legend li {
+  /* Side by side. */
+  display: flex;
+  /* The icon lines up with the first line. */
+  align-items: flex-start;
+  /* Space between icon and words. */
+  gap: 0.55rem;
+  /* A comfortable line height. */
+  line-height: 1.35;
+} /* end of rule */
+
+/* The icon column has a fixed width so the words line up. */
+.legend .sym {
+  /* Never shrinks. */
+  flex: none;
+  /* A fixed width. */
+  min-width: 1.6rem;
+  /* Centred. */
+  text-align: center;
+} /* end of rule */
+
+/* The icons of the key sit level with the first line. */
+.legend .ico {
+  /* No gap. */
+  margin-right: 0;
+  /* A little lower to line up with the text. */
+  vertical-align: -4px;
+} /* end of rule */
+
+/* The key's sample of a dotted heading, drawn the same way as the real ones. */
+.dotsample {
+  /* A dotted underline like the table headings. */
+  text-decoration: underline dotted;
+  /* A little offset so the dots are clear. */
+  text-underline-offset: 3px;
+  /* Bold like a heading. */
+  font-weight: 600;
+} /* end of rule */
diff --git a/web/compare.html b/web/compare.html
index 80b51ec..b2e50b2 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -21,7 +21,7 @@
 <h1>Compare models</h1>
 {{/* Nothing saved yet. */}}
 {{if .Empty}}
-<p>No model has been through a performance test yet. Use the chart icon 📈 before a model name on the monitor page to test one, then come back here.</p>
+<p>No model has been through a performance test yet. Use the chart icon before a model name on the monitor page to test one, then come back here.</p>
 {{range .Notes}}<p class="muted">{{.}}</p>{{end}}
 {{else}}
 {{/* What the figures say, in plain words. */}}
diff --git a/web/index.html b/web/index.html
index 6664b39..ccddb78 100644
--- a/web/index.html
+++ b/web/index.html
@@ -122,7 +122,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the words. */}}
-<button type="submit" class="btn-plain comparebtn" aria-describedby="tipcompare"><span aria-hidden="true">⚖</span> Compare tested models ({{.CompareCount}})</button>
+<button type="submit" class="btn-plain comparebtn" aria-describedby="tipcompare"><svg class="ico ico-big" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg> Compare tested models ({{.CompareCount}})</button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipcompare">Compare models that have already been through a performance test</span>
 {{/* End of the tip area. */}}
@@ -148,7 +148,15 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The button Compare tested models, at the top right of this panel, puts the tested models side by side. The table scrolls sideways.</p>
+{{/* A key above the table: what each symbol and the dotted headings do. */}}
+<ul class="legend muted" aria-label="How to read this table">
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: only for models that are not loaded</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; not shown while the model is loaded, because it may be in use</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
+<li><span class="sym"><span class="dotsample">Aa</span></span><span><strong>Dotted headings</strong>: point at one, or press Tab, to see what it means</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8l-4 4 4 4"/><path d="M17 8l4 4-4 4"/></svg></span><span><strong>Sideways scroll</strong>: the table scrolls sideways</span></li>
+</ul>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -215,7 +223,7 @@
 {{/* The area that opens the tip: pointing at the icon or reaching it with Tab shows what it is for. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Performance of {{.Name}}" aria-describedby="tipperf-{{.Name}}"><span aria-hidden="true">📈</span></button>
+<button type="submit" class="gear" aria-label="Performance of {{.Name}}" aria-describedby="tipperf-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipperf-{{.Name}}">Performance: see how fast this model runs on this machine</span>
 {{/* End of the tip area. */}}
@@ -238,7 +246,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><span aria-hidden="true">📄</span></button>
+<button type="submit" class="gear" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipfile-{{.Name}}">Show the model's Modelfile (read-only)</span>
 {{/* End of the tip area. */}}
@@ -255,7 +263,7 @@
 {{/* The area that opens the tip: pointing at the gear or reaching it with Tab shows what it is for. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><span aria-hidden="true">⚙</span></button>
+<button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View the model's Inference parameters</span>
 {{/* End of the tip area. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
4232de2695b1cdc2591b193552f44519414367445845f2fadca7bccd247b25ee  control_test.go
8c351dcea1c3deab4b53c8de5f44069daf362b99976c2c6f4581fffa2d4f9302  gear_test.go
c45e947799122fc9c817c1b9de4e965d9e5201a6d1747749d839a327075b8db2  perf_test.go
cfe3e9c57f680420f5e761e15486f4cf4f900350ac61653c1b9d3e0557fc3fd2  web/app.css
223a65c3280899695e54f857543707f0bbe654c517737bbcac852ee2ac9d7642  web/compare.html
fba09387fb5cecc2f89ed94301270f9b54cea8b5955bb35ffaf9d1346c449171  web/index.html
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
