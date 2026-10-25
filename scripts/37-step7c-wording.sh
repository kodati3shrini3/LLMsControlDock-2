#!/usr/bin/env bash
# Script 37: wording and layout changes on the feature branch: the settings column is called "Set in the model" (and "not set"), three long column headings are drawn on two lines, and the label "In plain words" is removed from every tooltip.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-settings-table" ] || { echo "FAIL  not on feature/model-settings-table"; exit 1; }
# Script 36 must be applied first (it creates settings.go).
[ -f settings.go ] || { echo "FAIL  script 36 was not applied yet (settings.go is missing)"; exit 1; }
# Refuse when this change was already applied.
if grep -q 'row.Saved = "not set"' gear.go; then
  # Say so and stop.
  echo "FAIL  this script was already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear.go b/gear.go
index ae3abb1..8de029a 100644
--- a/gear.go
+++ b/gear.go
@@ -392,7 +392,7 @@ func evaluate(f gearFacts, form url.Values, tips map[string]tipView) ([]settingR
 		// Nothing saved.
 		case !present:
 			// Say what that means.
-			row.Saved = "not saved"
+			row.Saved = "not set"
 		// Saved but not usable.
 		case !readable:
 			// Show it as it is.
@@ -630,7 +630,7 @@ func sameSaved(a, b map[string][]string, skip map[string]bool) bool {
 } // end of sameSaved
 
 // gearTipKeys maps the short names used in the template to the headings of the help texts; each setting is added by its parameter name.
-var gearTipKeys = map[string]string{"saved": "Saved in the model", "default": "Ollama's default", "range": "Allowed values"}
+var gearTipKeys = map[string]string{"saved": "Set in the model", "default": "Ollama's default", "range": "Allowed values"}
 
 // gearHandlers builds the three handlers: the settings page (shows, changes nothing), the review page (checks the typed values and asks "are you sure?"), and the save (changes the model).
 func gearHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
diff --git a/gear_test.go b/gear_test.go
index 8015258..8263957 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -637,7 +637,7 @@ func TestGearShowsSettings(t *testing.T) {
 		// The saved values appear in the Saved column.
 		`">1</td>`, `">64</td>`, `">0.95</td>`, `">&#34;&lt;end_of_turn&gt;&#34;</td>`,
 		// Settings with nothing saved say so.
-		`">not saved</td>`,
+		`">not set</td>`,
 		// Ollama's defaults.
 		"automatic (docs: 2048)", `">0.8</td>`, `">40</td>`, `">0.9</td>`, "0 (off)", "1 (off)", `">64</td>`, "-1 (no limit)", `">none</td>`,
 		// The allowed values.
@@ -647,7 +647,7 @@ func TestGearShowsSettings(t *testing.T) {
 		// The rule about removing.
 		"never emptied",
 		// The help bubbles, each with the three standard parts.
-		"In plain words:", "Example:", "Helps you decide:",
+		"Example:", "Helps you decide:",
 	} { // end of the list
 		// Look for it.
 		if !strings.Contains(body, want) {
@@ -655,6 +655,11 @@ func TestGearShowsSettings(t *testing.T) {
 			t.Errorf("page lacks %q", want)
 		} // end of the check
 	} // end of the loop
+	// The column is called "Set in the model" and the label "In plain words" is gone.
+	if !strings.Contains(body, ">Set in the model</span>") || strings.Contains(body, "Saved in the model") || strings.Contains(body, "In plain words") {
+		// Report the problem.
+		t.Errorf("wording of the column or the bubbles is wrong")
+	} // end of the wording check
 	// Every setting has a field and a help bubble.
 	for _, s := range settingSpecs {
 		// The field.
@@ -859,7 +864,7 @@ func TestGearReviewThenSave(t *testing.T) {
 	// Step 2: review.
 	status, body, _ := gearPost(t, rig, "/gear/review", "alpha:1b", typed...)
 	// The confirmation page with the values to be saved.
-	for _, want := range []string{"This changes the model itself", "<th scope=\"row\">Context size</th><td>not saved</td><td><strong>8192</strong></td>", "<th scope=\"row\">Temperature</th><td>1</td><td><strong>0.2</strong></td>", "<th scope=\"row\">Top-k</th><td>64</td><td><strong>40</strong></td>", `<strong>&#34;AAA&#34;, &#34;BBB&#34;</strong>`, `action="/gear/save"`, `name="s_stop" value="AAA"`, `name="s_stop" value="BBB"`, `name="s_num_ctx" value="8192"`, "Yes, save them into the model", "Cancel, do not change"} {
+	for _, want := range []string{"This changes the model itself", "<th scope=\"row\">Context size</th><td>not set</td><td><strong>8192</strong></td>", "<th scope=\"row\">Temperature</th><td>1</td><td><strong>0.2</strong></td>", "<th scope=\"row\">Top-k</th><td>64</td><td><strong>40</strong></td>", `<strong>&#34;AAA&#34;, &#34;BBB&#34;</strong>`, `action="/gear/save"`, `name="s_stop" value="AAA"`, `name="s_stop" value="BBB"`, `name="s_num_ctx" value="8192"`, "Yes, save them into the model", "Cancel, do not change"} {
 		// Look for it.
 		if status != http.StatusOK || !strings.Contains(body, want) {
 			// Report the gap.
diff --git a/tableview.go b/tableview.go
index 684f771..111f382 100644
--- a/tableview.go
+++ b/tableview.go
@@ -24,10 +24,33 @@ type tipView struct {
 type columnView struct {
 	// Title is the heading text.
 	Title string
+	// Lines is the heading split into the lines it is drawn on (one line for most headings).
+	Lines []string
 	// Tip is the help bubble.
 	Tip tipView
 } // end of columnView
 
+// headingLines splits the three long column headings into two lines, to save width; every other heading stays on one line. The full title is still used for the help text and for the terminal view.
+func headingLines(title string) []string {
+	// The three headings and where they break.
+	switch title {
+	// Size on disk.
+	case "Size on disk":
+		// Two lines.
+		return []string{"Size", "on disk"}
+	// Max context length.
+	case "Max context length":
+		// Two lines.
+		return []string{"Max context", "length"}
+	// Embedding length.
+	case "Embedding length":
+		// Two lines.
+		return []string{"Embedding", "length"}
+	} // end of the switch
+	// Everything else is one line.
+	return []string{title}
+} // end of headingLines
+
 // rowView is one model row: its name (the sticky first column) and the nine other cells.
 type rowView struct {
 	// Name is the model name, never shortened.
@@ -150,7 +173,7 @@ func buildTableViewAt(installed []installedModel, loaded []loadedModel, now time
 	// One heading per column, in the fixed order.
 	for i, title := range installedColumns {
 		// Add the heading with its bubble.
-		view.Columns = append(view.Columns, columnView{Title: title, Tip: makeTip(fmt.Sprintf("tip-col-%d", i), title)})
+		view.Columns = append(view.Columns, columnView{Title: title, Lines: headingLines(title), Tip: makeTip(fmt.Sprintf("tip-col-%d", i), title)})
 	} // end of the column loop
 	// One section per non-empty category.
 	for gi, g := range groups {
diff --git a/tooltips.go b/tooltips.go
index fc79407..fcbbf60 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -20,7 +20,7 @@ var installedColumns = []string{"Model", "State", "Size on disk", "Family", "Par
 var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Loaded context length", "Time until unload"}
 
 // gearHeadings are the headings on the settings page and the Load page that have a help bubble, in the order they appear; a test checks each has a text.
-var gearHeadings = []string{"Saved in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
+var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
 // helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
 // The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
@@ -203,14 +203,14 @@ var helpTexts = map[string]tooltip{
 		Decide: "How much memory to spend against how long a text it can handle.",
 	}, // end of Context size
 	// What is stored in the model.
-	"Saved in the model": {
+	"Set in the model": {
 		// What it means.
 		Plain: "Settings stored inside the model in Ollama. Programs that do not send their own value use them.",
 		// A real case.
 		Example: "After saving 8192, the next load of the model starts at 8192.",
 		// What it helps with.
 		Decide: "What every program gets when it loads this model.",
-	}, // end of Saved in the model
+	}, // end of Set in the model
 	// The default column.
 	"Ollama's default": {
 		// What it means.
diff --git a/web/gear.html b/web/gear.html
index e515dfa..a8ef773 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -50,7 +50,7 @@
 {{/* Ollama's own default. */}}
 <td data-label="Ollama's default">{{.Default}}</td>
 {{/* What the model has saved now. */}}
-<td data-label="Saved in the model">{{.Saved}}</td>
+<td data-label="Set in the model">{{.Saved}}</td>
 {{/* The field, or the reason there is none. */}}
 <td data-label="New value">
 {{/* A refusal for this setting, first. */}}
diff --git a/web/index.html b/web/index.html
index 59c76f3..e271fed 100644
--- a/web/index.html
+++ b/web/index.html
@@ -94,7 +94,7 @@
 {{/* The area that opens the bubble when the pointer is over it or the focus is inside it. */}}
 <div class="tipbox">
 {{/* The heading text; tabindex 0 lets the keyboard reach it, aria-describedby ties it to its bubble. */}}
-<span class="help" tabindex="0" aria-describedby="{{$c.Tip.ID}}">{{$c.Title}}</span>
+<span class="help" tabindex="0" aria-describedby="{{$c.Tip.ID}}">{{range $j, $l := $c.Lines}}{{if $j}}<br>{{end}}{{$l}}{{end}}</span>
 {{/* The bubble; it is fixed to the window, so the scroll box never cuts it off. */}}
 <span class="tip" role="tooltip" id="{{$c.Tip.ID}}">{{template "tip" $c.Tip}}</span>
 {{/* End of the bubble area. */}}
@@ -215,7 +215,7 @@
 {{/* The help bubble content: three labelled parts, and the task names when there are any. */}}
 {{define "tip"}}
 {{/* What the heading means. */}}
-<span class="tip-part"><strong>In plain words:</strong> {{.Plain}}</span>
+<span class="tip-part">{{.Plain}}</span>
 {{/* A real example. */}}
 <span class="tip-part"><strong>Example:</strong> {{.Example}}</span>
 {{/* What it helps you decide. */}}
diff --git a/web/tips.html b/web/tips.html
index fed78ab..c47c7e2 100644
--- a/web/tips.html
+++ b/web/tips.html
@@ -2,7 +2,7 @@
 {{/* The bubble content: three labelled parts, and the task names when there are any. */}}
 {{define "tip"}}
 {{/* What the heading means. */}}
-<span class="tip-part"><strong>In plain words:</strong> {{.Plain}}</span>
+<span class="tip-part">{{.Plain}}</span>
 {{/* A real example. */}}
 <span class="tip-part"><strong>Example:</strong> {{.Example}}</span>
 {{/* What it helps you decide. */}}
diff --git a/webtable_test.go b/webtable_test.go
index afb97e1..82df022 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -142,7 +142,7 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Every column title must be a focusable heading.
 	for _, col := range installedColumns {
 		// The heading element holds the title text.
-		if !strings.Contains(body, ">"+html.EscapeString(col)+"</span>") {
+		if !strings.Contains(body, ">"+drawnHeading(col)+"</span>") {
 			// Report the gap.
 			t.Errorf("no heading element for column %q", col)
 		} // end of the heading check
@@ -315,6 +315,46 @@ func TestStylesheetHasTableAndBubbleRules(t *testing.T) {
 	} // end of the loop
 } // end of TestStylesheetHasTableAndBubbleRules
 
+// drawnHeading is a column title the way the page draws it: the lines joined by a line break, each escaped.
+func drawnHeading(col string) string {
+	// Escape each line, then join them with a break.
+	var parts []string
+	// Go through the lines.
+	for _, l := range headingLines(col) {
+		// Escape it.
+		parts = append(parts, html.EscapeString(l))
+	} // end of the loop
+	// Join.
+	return strings.Join(parts, "<br>")
+} // end of drawnHeading
+
+// TestLongHeadingsUseTwoLines checks the three long headings are drawn on two lines, the others on one, and that the help text of the page no longer carries the label "In plain words".
+func TestLongHeadingsUseTwoLines(t *testing.T) {
+	// Fake Ollama with the six real models.
+	body := pageFor(t, fullOllama(t, realModels, realPsBody))
+	// The three two-line headings.
+	for _, want := range []string{">Size<br>on disk</span>", ">Max context<br>length</span>", ">Embedding<br>length</span>"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The short headings stay on one line.
+	for _, want := range []string{">Model</span>", ">Family</span>", ">Parameters</span>", ">Quantization</span>", ">Last modified</span>", ">Abilities</span>"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The label is gone from every bubble, and the other two labels stay.
+	if strings.Contains(body, "In plain words") || !strings.Contains(body, "<strong>Example:</strong>") || !strings.Contains(body, "<strong>Helps you decide:</strong>") {
+		// Report the problem.
+		t.Errorf("the bubble labels are wrong")
+	} // end of the label check
+} // end of TestLongHeadingsUseTwoLines
+
 // TestTableColumnOrder checks the headings appear on the page in the order the person asked for.
 func TestTableColumnOrder(t *testing.T) {
 	// Fake Ollama with the six real models.
@@ -326,7 +366,7 @@ func TestTableColumnOrder(t *testing.T) {
 	// Go through the titles in order.
 	for _, col := range want {
 		// Find the heading element after the previous one.
-		i := strings.Index(body[pos:], ">"+col+"</span>")
+		i := strings.Index(body[pos:], ">"+drawnHeading(col)+"</span>")
 		// A missing or early heading means the order is wrong.
 		if i < 0 {
 			// Report the problem.
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
4e0b6807b9f178a37554e821a949564afc4f83cf07239d170cf96321a7083693  gear.go
3d621e5c3fd27d8f7bd482ae0f3c0dcc06d15ab857ae837860e8011a96890331  gear_test.go
d23d1ccf95a42cb16c2864d53592cfeaa3721825df8356f45731916ab48cd592  tableview.go
e63e56c3d09f214b9db9922c4438b78b8889d63745d51a19b7972f7a5c584f0c  tooltips.go
969fc1d163e774953bd4bc1edaa8e3f60d56f3d4503742ad4843cc39884a84b3  web/gear.html
f443021f509d293726682a60675cd206f229636e8695a01274f1672950b56808  web/index.html
c7711ee656680c8e032440fad3f7b95a5ea31578f847010ab6d4147fafd489ef  web/tips.html
cf244f0c7d22ef13ef971188fea9deac66a7e250423784d070b0203884a80dce  webtable_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the changed files match the tested versions"
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
