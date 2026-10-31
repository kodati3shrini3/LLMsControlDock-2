#!/usr/bin/env bash
# Script 69r: F8 part 2, the memory of loaded models in the Charts box. For each loaded model it shows a bar (length relative to the largest loaded model), the size Ollama reports, how much sits in GPU memory, and when Ollama will unload it (as of the moment the page was made; the table below still counts live). Ollama does not report how much memory the machine has, so no total is drawn. Version 0.20.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/charts-memory" ] || { echo "FAIL  not on feature/charts-memory"; exit 1; }
# Script 69q (the chart scale, part of the merged charts) must be applied already.
grep -q "minScale" charts.go || { echo "FAIL  scripts 69p and 69q were not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e chartmem.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index b74b13f..b722304 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.19.0"
+const appVersion = "0.20.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/chartmem.go b/chartmem.go
new file mode 100644
index 0000000..2f0f361
--- /dev/null
+++ b/chartmem.go
@@ -0,0 +1,168 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the texts.
+	"fmt"
+	// sort puts the largest model first.
+	"sort"
+	// time gives the moment for the unload timers.
+	"time"
+) // end of imports
+
+// memBarWidth is the width of a memory bar in drawing units; the picture scales to the box.
+const memBarWidth = 300
+
+// memBarHeight is the height of a memory bar in drawing units.
+const memBarHeight = 10
+
+// memRow is one loaded model in the memory part of the Charts box.
+type memRow struct {
+	// Name is the model name, never shortened.
+	Name string
+	// Size is the size Ollama reports for the running model, as text.
+	Size string
+	// Fill is the length of the filled part of the bar, in drawing units.
+	Fill int
+	// Percent is the same length as a share of the largest loaded model, for the text alternative.
+	Percent int
+	// Where says how much of the model sits in GPU memory.
+	Where string
+	// Timer says when Ollama will unload the model, as of the moment the page was made.
+	Timer string
+} // end of memRow
+
+// memView is what the memory part of the Charts box shows.
+type memView struct {
+	// Message explains why there is no list (offline, unreadable, nothing loaded); empty when there are rows.
+	Message string
+	// Rows are the loaded models, largest first.
+	Rows []memRow
+	// Total is the sum of the sizes as text, shown when there are rows.
+	Total string
+	// BarWidth and BarHeight are the size of one bar drawing.
+	BarWidth, BarHeight int
+} // end of memView
+
+// whereText says how much of a model sits in GPU memory, using only what Ollama reports.
+func whereText(m loadedModel) string {
+	// Without a size there is nothing to compare.
+	if m.Size <= 0 {
+		// Say so.
+		return "memory split not reported"
+	} // end of the size check
+	// All of it in GPU memory.
+	if m.SizeVRAM >= m.Size {
+		// All.
+		return "all in GPU memory"
+	} // end of the all-in-GPU case
+	// None of it in GPU memory.
+	if m.SizeVRAM <= 0 {
+		// None.
+		return "none in GPU memory (all in processor memory)"
+	} // end of the none case
+	// A share, rounded to a whole percent.
+	pct := int(float64(m.SizeVRAM)*100/float64(m.Size) + 0.5)
+	// The rest is in processor memory.
+	return fmt.Sprintf("%d %% in GPU memory, %d %% in processor memory", pct, 100-pct)
+} // end of whereText
+
+// unloadText says in plain words when Ollama will unload the model, as of the given moment.
+func unloadText(m loadedModel, now time.Time) string {
+	// The same rules as the table's timer.
+	text, _, _ := timerFor(m, now)
+	// Fixed texts first.
+	switch text {
+	// Set to stay loaded.
+	case longKeepText:
+		// Say it.
+		return "stays loaded (no unload time)"
+	// Ollama gave no time.
+	case "not reported":
+		// Say it.
+		return "unload time not reported"
+	// The time has arrived.
+	case "unloading now":
+		// Say it.
+		return "unloading now"
+	} // end of the switch
+	// A normal countdown.
+	return "unloads in " + text
+} // end of unloadText
+
+// buildMemory turns the loaded models into the memory part of the Charts box; online and listsOK say whether the list could be read at all.
+func buildMemory(loaded []loadedModel, online, listsOK bool, now time.Time) memView {
+	// The sizes of the drawings.
+	v := memView{BarWidth: memBarWidth, BarHeight: memBarHeight}
+	// Ollama does not answer: the loaded models are not known.
+	if !online {
+		// Say so.
+		v.Message = "Ollama is not answering, so the loaded models are not known."
+		// Done.
+		return v
+	} // end of the offline case
+	// The list could not be read just now.
+	if !listsOK {
+		// Say so.
+		v.Message = "The list of loaded models could not be read just now."
+		// Done.
+		return v
+	} // end of the unreadable case
+	// Nothing loaded.
+	if len(loaded) == 0 {
+		// Say so.
+		v.Message = "No model is loaded."
+		// Done.
+		return v
+	} // end of the empty case
+	// A sorted copy, so the caller's list stays as it was: the largest first, then by name.
+	sorted := append([]loadedModel(nil), loaded...)
+	// Sort.
+	sort.SliceStable(sorted, func(i, j int) bool {
+		// The larger first.
+		if sorted[i].Size != sorted[j].Size {
+			// Larger first.
+			return sorted[i].Size > sorted[j].Size
+		} // end of the size check
+		// Same size: by name.
+		return sorted[i].Name < sorted[j].Name
+	}) // end of the sort
+	// The largest and the sum.
+	largest, sum := sorted[0].Size, int64(0)
+	// Add up.
+	for _, m := range sorted {
+		// A negative size counts as nothing.
+		if m.Size > 0 {
+			// Add it.
+			sum += m.Size
+		} // end of the size check
+	} // end of the loop
+	// One row per model.
+	for _, m := range sorted {
+		// The share of the largest, as a whole percent; nothing when no size is known.
+		pct := 0
+		// Only with a known size.
+		if m.Size > 0 && largest > 0 {
+			// Round to a whole percent, and keep at least 1 so a small model still shows a sliver.
+			pct = int(float64(m.Size)*100/float64(largest) + 0.5)
+			// A sliver.
+			if pct < 1 {
+				// At least one percent.
+				pct = 1
+			} // end of the sliver check
+		} // end of the share
+		// The size text.
+		size := "size not reported"
+		// With a size.
+		if m.Size > 0 {
+			// Write it.
+			size = formatSize(m.Size)
+		} // end of the size text
+		// Add the row.
+		v.Rows = append(v.Rows, memRow{Name: m.Name, Size: size, Fill: pct * memBarWidth / 100, Percent: pct, Where: whereText(m), Timer: unloadText(m, now)})
+	} // end of the loop
+	// The sum.
+	v.Total = formatSize(sum)
+	// Hand it back.
+	return v
+} // end of buildMemory
diff --git a/chartmem_test.go b/chartmem_test.go
new file mode 100644
index 0000000..97cccae
--- /dev/null
+++ b/chartmem_test.go
@@ -0,0 +1,150 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http provides the method name.
+	"net/http"
+	// strings searches the text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time builds the moments.
+	"time"
+) // end of imports
+
+// lm builds a loaded model with a size, a GPU share and an unload time.
+func lm(name string, size, vram int64, expires string) loadedModel {
+	// The model.
+	return loadedModel{Name: name, Size: size, SizeVRAM: vram, ExpiresAt: expires}
+} // end of lm
+
+// TestMemoryMessages checks the three reasons for an empty list.
+func TestMemoryMessages(t *testing.T) {
+	// The cases.
+	for name, tc := range map[string]struct {
+		// online and listsOK are the inputs.
+		online, listsOK bool
+		// loaded is the list.
+		loaded []loadedModel
+		// want is the message.
+		want string
+	}{
+		"offline":    {false, false, nil, "Ollama is not answering, so the loaded models are not known."},
+		"unreadable": {true, false, nil, "The list of loaded models could not be read just now."},
+		"none":       {true, true, nil, "No model is loaded."},
+	} { // end of the cases
+		// Build.
+		v := buildMemory(tc.loaded, tc.online, tc.listsOK, chartNow())
+		// Compare.
+		if v.Message != tc.want || len(v.Rows) != 0 {
+			// Report it.
+			t.Errorf("%s: %q with %d rows", name, v.Message, len(v.Rows))
+		} // end of the check
+	} // end of the loop
+} // end of TestMemoryMessages
+
+// TestMemoryRows checks the order, the bar lengths, the sum and the texts.
+func TestMemoryRows(t *testing.T) {
+	// Now, and an unload time 4 min 12 s later.
+	now := chartNow()
+	// The time text.
+	soon := now.Add(4*time.Minute + 12*time.Second).Format(time.RFC3339Nano)
+	// The models, the largest in the middle.
+	in := []loadedModel{
+		lm("small:1b", 1_000_000_000, 1_000_000_000, "2318-01-01T00:00:00Z"),
+		lm("big:27b", 20_000_000_000, 8_000_000_000, soon),
+		lm("tiny:1b", 10_000_000, 0, ""),
+	}
+	// Build.
+	v := buildMemory(in, true, true, now)
+	// Three rows, largest first.
+	if len(v.Rows) != 3 || v.Rows[0].Name != "big:27b" || v.Rows[1].Name != "small:1b" || v.Rows[2].Name != "tiny:1b" {
+		// Report it.
+		t.Fatalf("order wrong: %+v", v.Rows)
+	} // end of the order check
+	// The caller's list is untouched.
+	if in[0].Name != "small:1b" {
+		// Report it.
+		t.Errorf("the caller's list was reordered")
+	} // end of the copy check
+	// The largest fills the bar; the small one is 5 %; the tiny one still shows a sliver of 1 %.
+	if v.Rows[0].Percent != 100 || v.Rows[0].Fill != memBarWidth || v.Rows[1].Percent != 5 || v.Rows[1].Fill != 15 || v.Rows[2].Percent != 1 || v.Rows[2].Fill != 3 {
+		// Report it.
+		t.Errorf("bars wrong: %+v", v.Rows)
+	} // end of the bar check
+	// The sizes and the sum.
+	if v.Rows[0].Size != "20.0 GB" || v.Rows[2].Size != "10 MB" || v.Total != "21.0 GB" {
+		// Report it.
+		t.Errorf("sizes wrong: %q %q total %q", v.Rows[0].Size, v.Rows[2].Size, v.Total)
+	} // end of the size check
+	// The GPU share: 40 percent, all, and none.
+	if v.Rows[0].Where != "40 % in GPU memory, 60 % in processor memory" || v.Rows[1].Where != "all in GPU memory" || v.Rows[2].Where != "none in GPU memory (all in processor memory)" {
+		// Report it.
+		t.Errorf("where wrong: %q / %q / %q", v.Rows[0].Where, v.Rows[1].Where, v.Rows[2].Where)
+	} // end of the where check
+	// The timers: counting, set to stay loaded, and not reported.
+	if v.Rows[0].Timer != "unloads in 4 min 12 s" || v.Rows[1].Timer != "stays loaded (no unload time)" || v.Rows[2].Timer != "unload time not reported" {
+		// Report it.
+		t.Errorf("timers wrong: %q / %q / %q", v.Rows[0].Timer, v.Rows[1].Timer, v.Rows[2].Timer)
+	} // end of the timer check
+} // end of TestMemoryRows
+
+// TestMemoryUnknownSizeAndExpired checks a model without a size and a timer that has arrived.
+func TestMemoryUnknownSizeAndExpired(t *testing.T) {
+	// A model without a size and an expired one.
+	v := buildMemory([]loadedModel{lm("nosize:1b", 0, 0, ""), lm("late:1b", 5_000_000_000, 5_000_000_000, chartNow().Add(-time.Minute).Format(time.RFC3339Nano))}, true, true, chartNow())
+	// The sized one first.
+	if v.Rows[0].Name != "late:1b" || v.Rows[0].Timer != "unloading now" {
+		// Report it.
+		t.Errorf("expired row wrong: %+v", v.Rows[0])
+	} // end of the expired check
+	// The unsized one has no bar and says so.
+	if r := v.Rows[1]; r.Size != "size not reported" || r.Fill != 0 || r.Where != "memory split not reported" {
+		// Report it.
+		t.Errorf("unsized row wrong: %+v", r)
+	} // end of the unsized check
+	// The sum counts only the known size.
+	if v.Total != "5.0 GB" {
+		// Report it.
+		t.Errorf("total %q", v.Total)
+	} // end of the total check
+} // end of TestMemoryUnknownSizeAndExpired
+
+// TestMainPageShowsTheMemory checks the memory part on the page, with a hostile model name escaped.
+func TestMainPageShowsTheMemory(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// With nothing loaded.
+	if page := pageWithCookie(t, rig, nil); !strings.Contains(page, "Memory of loaded models") || !strings.Contains(page, "No model is loaded.") {
+		// Report it.
+		t.Errorf("the empty memory part is missing")
+	} // end of the empty check
+	// A model with a hostile name is loaded.
+	f.mu.Lock()
+	// In memory.
+	f.loaded["<b>x</b>:1b"] = true
+	// Release the fake.
+	f.mu.Unlock()
+	// The page.
+	page := pageWithCookie(t, rig, nil)
+	// The parts.
+	for _, w := range []string{"Memory of loaded models", `class="memlist"`, `class="membarsvg"`, "&lt;b&gt;x&lt;/b&gt;:1b", "4.0 GB", "Together 4.0 GB.", "Times left are as of"} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report the gap.
+			t.Errorf("the page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The name must be escaped everywhere in the memory part.
+	if strings.Contains(page, "<b>x</b>") {
+		// Report it.
+		t.Errorf("a model name was not escaped")
+	} // end of the escape check
+	// Folded away with the rest of the Charts box.
+	if folded := pageWithCookie(t, rig, &http.Cookie{Name: detailsCookieName, Value: "closed"}); strings.Contains(folded, "Memory of loaded models") {
+		// Report it.
+		t.Errorf("the memory part stays when the details are folded")
+	} // end of the fold check
+} // end of TestMainPageShowsTheMemory
diff --git a/tooltips.go b/tooltips.go
index 9cffbc0..3cd85ad 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -43,7 +43,7 @@ var helpTexts = map[string]tooltip{
 	// The charts under the event log.
 	"Charts": {
 		// What it means.
-		Plain: "Ollama's answers over the last 30 minutes: how often it answered and how fast.",
+		Plain: "Ollama's answers over the last 30 minutes, and the memory of loaded models: how often it answered, how fast.",
 		// A real case.
 		Example: "A hatched block in the state bar means a check failed in that half minute.",
 		// What it helps with.
diff --git a/web.go b/web.go
index 7ba3f17..c17d9e0 100644
--- a/web.go
+++ b/web.go
@@ -81,6 +81,8 @@ type pageData struct {
 	Charts chartsView
 	// ChartsTip is the help bubble of the heading "Charts".
 	ChartsTip tipView
+	// Memory is the memory part of the Charts box: the loaded models with their size, GPU share and unload time.
+	Memory memView
 	// NumbersOpen is true when the person opened the table of numbers under the charts (the address then ends in ?numbers=open); the page does not update by itself meanwhile.
 	NumbersOpen bool
 	// DetailsClosed is true when the person folded the monitoring details (API health and Event log) away; a cookie remembers it.
@@ -337,6 +339,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 		data.Charts = buildCharts(mon.hist.since(now.Add(-chartWindow)), now, mon.background.Load(), data.NumbersOpen)
 		// The bubble.
 		data.ChartsTip = chartsTip
+		// The loaded models with their memory, from the same lists the event log used.
+		data.Memory = buildMemory(evLoaded, res.Online, listsOK, now)
 		// Build the whole page in memory first, so a template error produces a clean 500 and not a half page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/web/app.css b/web/app.css
index f495899..1cfc80e 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2157,3 +2157,57 @@ html[data-size="medium"] svg[width="22"] {
   /* Small gap above. */
   margin: 0.25rem 0;
 } /* end of rule */
+
+/* The list of loaded models in the Charts box. */
+.memlist {
+  /* No bullets: each model has its own bar. */
+  list-style: none;
+  /* No indent. */
+  padding: 0;
+  /* Space above and below the list. */
+  margin: 0.5rem 0;
+} /* end of rule */
+
+/* One loaded model. */
+.memlist li {
+  /* Space between models. */
+  margin: 0 0 0.9rem;
+} /* end of rule */
+
+/* The name and size line above a bar. */
+.memname {
+  /* On its own line. */
+  display: block;
+  /* A little space below. */
+  margin-bottom: 0.15rem;
+} /* end of rule */
+
+/* The bar drawing: full width, but never huge on a wide screen. */
+.membarsvg {
+  /* Fill the box up to the limit below. */
+  width: 100%;
+  /* Not wider than this, so the bars stay compact. */
+  max-width: 30rem;
+  /* The height follows the shape of the drawing. */
+  height: auto;
+  /* On its own line. */
+  display: block;
+  /* A little space around it. */
+  margin: 0.15rem 0;
+} /* end of rule */
+
+/* The empty frame of a bar: an outline keeps its full length visible without colour. */
+.memback {
+  /* Nothing inside. */
+  fill: transparent;
+  /* The border colour of the page. */
+  stroke: var(--border);
+  /* A thin outline. */
+  stroke-width: 1;
+} /* end of rule */
+
+/* The filled part of a bar. */
+.memfill {
+  /* The accent colour of the page. */
+  fill: var(--cat-accent);
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 6aecc4e..ca3cee9 100644
--- a/web/index.html
+++ b/web/index.html
@@ -214,6 +214,22 @@
 </svg>
 <p class="chartaxis muted"><span>{{.Charts.StartLabel}}</span><span>{{.Charts.MidLabel}}</span><span>{{.Charts.EndLabel}}</span></p>
 <p class="muted">{{.Charts.AnswerAlt}}</p>
+{{/* The memory of the loaded models: one bar per model, relative to the largest, with its GPU share and unload time. */}}
+<p class="chartlabel">Memory of loaded models</p>
+{{if .Memory.Message}}
+<p>{{.Memory.Message}}</p>
+{{else}}
+<ul class="memlist">
+{{range .Memory.Rows}}
+<li>
+<span class="memname"><strong>{{.Name}}</strong> {{.Size}}</span>
+<svg class="membarsvg" viewBox="0 0 {{$.Memory.BarWidth}} {{$.Memory.BarHeight}}" role="img" aria-label="{{.Name}}: {{.Size}}, {{.Percent}} percent of the largest loaded model"><rect class="memback" x="0.5" y="0.5" width="{{$.Memory.BarWidth}}" height="{{$.Memory.BarHeight}}"/><rect class="memfill" x="0" y="0" width="{{.Fill}}" height="{{$.Memory.BarHeight}}"/></svg>
+<span class="muted">{{.Where}}; {{.Timer}}.</span>
+</li>
+{{end}}
+</ul>
+<p class="muted">Together {{.Memory.Total}}. Each bar compares a model with the largest loaded model; Ollama does not report how much memory the machine has, so no total is drawn. Times left are as of {{.UpdatedAt}}; the table below counts live.</p>
+{{end}}
 {{/* The twistie for the numbers: a link, so the choice needs no script; the page pauses while it is open. */}}
 {{if .Charts.NumbersOpen}}
 <p class="keytoggle" id="numbers"><a href="/#numbers"><span aria-hidden="true">&#9662;</span> The numbers <span class="keyhint">(click to hide)</span></a></p>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
04841c4210569cde7279c3ca9ef565a878bf3542bd44998dda6d4843f6f1e3fa  about.go
7742a80272b8e676c165f61baa3432087b33109219e5f0505680d379784f29ed  tooltips.go
d86c8eb3d80c9f284630ae8c6582575071bf9b1375f3df0a9fbe41e213a2ef76  web.go
447dccbfb6fa4b4af5f29e87a30a1cb82333e9f757cbdcae1244c8a40ed3ae8c  web/index.html
a63ae01ae4b47ee274f1736d49f05544fd3e2977fbc911fc523be79cea89190b  web/app.css
57c670e99ccc36efe8eec266f5b2856a0abb213d26b73929de966a99f64fe38e  chartmem.go
007fab2f9e5ce71868e6f747e16aeb1e41390bb97383122e4874ce01285dcebc  chartmem_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and look for Memory of loaded models at the bottom of the Charts box"
# List the changed files; nothing is committed yet.
git status --short
