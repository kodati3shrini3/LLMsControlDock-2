#!/usr/bin/env bash
# Script 41: adds a hover tip to the gear, and a page icon just below it that opens a read-only page with the model's Modelfile (the text of "ollama show --modelfile").
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/modelfile-view" ] || { echo "FAIL  not on feature/modelfile-view"; exit 1; }
# Script 40 must be applied first (the settings table style).
grep -q 'notset' web/gear.html || { echo "FAIL  script 40 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -f modelfile.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/gear.go b/gear.go
index 8de029a..50174c0 100644
--- a/gear.go
+++ b/gear.go
@@ -59,6 +59,8 @@ const gearTimeout = 2 * time.Minute
 type showReply struct {
 	// Parameters is the saved parameters as text, one "name value" pair per line.
 	Parameters string `json:"parameters"`
+	// Modelfile is the model's Modelfile as text (the same text as "ollama show --modelfile"); the Modelfile page shows it, read-only.
+	Modelfile string `json:"modelfile"`
 	// ModelInfo holds the model's own facts; each value stays raw text until it is needed, so a long list inside it costs nothing.
 	ModelInfo map[string]json.RawMessage `json:"model_info"`
 } // end of showReply
diff --git a/gear_test.go b/gear_test.go
index 2880370..7f9bcdf 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -50,6 +50,8 @@ type gearFake struct {
 	creates []string
 	// calls records every other POST as "path body".
 	calls []string
+	// modelfile is the Modelfile text /api/show reports (a default is used when empty).
+	modelfile string
 	// createDelay makes /api/create slow, with the fake's lock released meanwhile, so other requests can slip in (like real life).
 	createDelay time.Duration
 } // end of gearFake
@@ -202,7 +204,7 @@ func (f *gearFake) start(t *testing.T) string {
 				return
 			} // end of the unknown check
 			// The reply, with the parameters as one string.
-			out, _ := json.Marshal(map[string]any{"parameters": f.paramsText(), "model_info": json.RawMessage(f.modelInfo)})
+			out, _ := json.Marshal(map[string]any{"parameters": f.paramsText(), "modelfile": f.modelfileText(), "model_info": json.RawMessage(f.modelInfo)})
 			// Send it.
 			w.Write(out)
 		// The create request.
@@ -1219,7 +1221,7 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 	// Fetch the page.
 	_, _, body := get(t, rig.h, http.MethodGet, "/")
 	// The not-loaded model has a gear form with an accessible name.
-	for _, want := range []string{`action="/gear"`, `aria-label="Settings for embed:1b"`, `class="gear"`} {
+	for _, want := range []string{`action="/gear"`, `aria-label="Inference parameters of embed:1b"`, `class="gear"`, `id="tipgear-embed:1b"`, `View the model's Inference parameters`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
@@ -1227,7 +1229,7 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// The loaded model has none, and only one gear form exists.
-	if strings.Contains(body, `aria-label="Settings for alpha:1b"`) || strings.Count(body, `action="/gear"`) != 1 {
+	if strings.Contains(body, `aria-label="Inference parameters of alpha:1b"`) || strings.Count(body, `action="/gear"`) != 1 {
 		// Report the problem.
 		t.Errorf("a loaded model has a gear")
 	} // end of the loaded check
@@ -1334,3 +1336,62 @@ func TestKeepAliveReachesEmbeddingFallback(t *testing.T) {
 		t.Errorf("requests: %v", f.calls)
 	} // end of the check
 } // end of TestKeepAliveReachesEmbeddingFallback
+
+// TestMainPageModelfileIconForEveryModel checks every model, loaded or not, has the Modelfile icon with its own tip, placed after the gear and before the state words.
+func TestMainPageModelfileIconForEveryModel(t *testing.T) {
+	// A fake with one model loaded.
+	f := newGearFake()
+	// Mark it loaded.
+	f.loaded = []string{"alpha:1b"}
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// One Modelfile form per model, and none of them is missing for the loaded one.
+	if n, models := strings.Count(body, `action="/modelfile"`), strings.Count(body, `<tr data-model=`); n != models || n < 2 {
+		// Report the problem.
+		t.Errorf("%d Modelfile forms for %d models", n, models)
+	} // end of the count check
+	// The loaded model has its icon, label and tip.
+	for _, want := range []string{`aria-label="Modelfile of alpha:1b"`, `id="tipfile-alpha:1b"`, `Show the model's Modelfile (read-only)`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Every icon has its tip wired with aria-describedby, and the tip exists.
+	for _, m := range regexp.MustCompile(`aria-describedby="(tip(?:gear|file)-[^"]+)"`).FindAllStringSubmatch(body, -1) {
+		// Look for the target.
+		if !strings.Contains(body, `id="`+m[1]+`"`) {
+			// Report the dangling reference.
+			t.Errorf("%q points at nothing", m[1])
+		} // end of the target check
+	} // end of the loop
+	// The Modelfile icon comes after the gear in the first not-loaded row.
+	if i, j := strings.Index(body, `action="/gear"`), strings.Index(body, `action="/modelfile"`); !(i >= 0 && j > i) {
+		// Report the problem.
+		t.Errorf("icon order: gear %d, modelfile %d", i, j)
+	} // end of the order check
+} // end of TestMainPageModelfileIconForEveryModel
+
+// modelfileText is the Modelfile the fake reports.
+func (f *gearFake) modelfileText() string {
+	// A chosen text wins.
+	if f.modelfile != "" {
+		// Use it.
+		return f.modelfile
+	} // end of the chosen-text check
+	// A small realistic Modelfile.
+	return "# Modelfile generated by \"ollama show\"\nFROM /root/.ollama/models/blobs/sha256-abc\nTEMPLATE \"\"\"{{ .Prompt }}\"\"\"\nPARAMETER temperature 1\n"
+} // end of modelfileText
+
+// callCount says how many requests of any kind the fake has received.
+func (f *gearFake) callCount() int {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// The number.
+	return len(f.calls) + len(f.creates)
+} // end of callCount
diff --git a/modelfile.go b/modelfile.go
new file mode 100644
index 0000000..50a2611
--- /dev/null
+++ b/modelfile.go
@@ -0,0 +1,140 @@
+// Package main tells Go that this file belongs to the program itself.
+package main
+
+import ( // import lists the packages this file uses.
+	// bytes builds the page in memory before it is sent.
+	"bytes"
+	// html/template builds the page and escapes every inserted text, so a Modelfile can never inject markup.
+	"html/template"
+	// embed stores the page template inside the executable.
+	_ "embed"
+	// log writes the real reason for an error for the person running the program.
+	"log"
+	// net/http provides the request and response types.
+	"net/http"
+	// unicode/utf8 finds a safe place to cut a long text.
+	"unicode/utf8"
+	// fmt builds the text of a refusal from Ollama.
+	"fmt"
+) // end of imports
+
+// modelfileTemplateText holds the Modelfile page, stored inside the executable at build time.
+//
+//go:embed web/modelfile.html
+var modelfileTemplateText string
+
+// maxModelfileShown is the most Modelfile text the page shows (512 KiB; a real Modelfile with its licence is far smaller).
+const maxModelfileShown = 512 * 1024
+
+// modelfilePage is everything the Modelfile page needs.
+type modelfilePage struct {
+	// Theme is the chosen colour theme, or empty to follow the system.
+	Theme string
+	// Kind is modelfile, notinstalled or error.
+	Kind string
+	// Model is the model name.
+	Model string
+	// Text is the Modelfile text.
+	Text string
+	// Truncated is true when the text was cut because it was very long.
+	Truncated bool
+	// Detail is the plain reason shown on the error page.
+	Detail string
+} // end of modelfilePage
+
+// cutText shortens a text to at most max bytes without splitting a character; the flag says whether anything was cut.
+func cutText(text string, max int) (string, bool) {
+	// A short text stays as it is.
+	if len(text) <= max {
+		// Nothing was cut.
+		return text, false
+	} // end of the length check
+	// Step back to the start of a character, so no character is split.
+	for max > 0 && !utf8.RuneStart(text[max]) {
+		// One byte back.
+		max--
+	} // end of the loop
+	// Hand back the shortened text.
+	return text[:max], true
+} // end of cutText
+
+// modelfileHandler builds the handler of the read-only Modelfile page: it only reads from Ollama and changes nothing.
+func modelfileHandler(addr ollamaAddress, token string) http.HandlerFunc {
+	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
+	page := template.Must(template.New("modelfile").Parse(modelfileTemplateText))
+	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
+	show := func(w http.ResponseWriter, r *http.Request, status int, data modelfilePage) {
+		// Add the theme.
+		data.Theme = themeFromRequest(r)
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("modelfile page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the status line.
+		w.WriteHeader(status)
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of show
+	// The handler itself.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// The same checks as every other form: same page, valid token, sensible model name.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Read the installed models now, not what the page showed earlier.
+		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, modelfilePage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the installed read check
+		// The model must exist.
+		if _, found := findInstalled(installed, name); !found {
+			// Say so.
+			show(w, r, http.StatusOK, modelfilePage{Kind: "notinstalled", Model: name})
+			// Stop here.
+			return
+		} // end of the installed check
+		// Read the model's details, which include its Modelfile.
+		info, status, err := fetchShow(r.Context(), addr.URL, name, gearTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, modelfilePage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the show read check
+		// Ollama does not know the model.
+		if status == http.StatusNotFound {
+			// Say so.
+			show(w, r, http.StatusOK, modelfilePage{Kind: "notinstalled", Model: name})
+			// Stop here.
+			return
+		} // end of the unknown check
+		// Any other refusal.
+		if status != http.StatusOK {
+			// Say so.
+			show(w, r, http.StatusBadGateway, modelfilePage{Kind: "error", Model: name, Detail: fmt.Sprintf("Ollama answered the details request with status %d", status)})
+			// Stop here.
+			return
+		} // end of the status check
+		// Shorten an extremely long text.
+		text, cut := cutText(info.Modelfile, maxModelfileShown)
+		// Show the Modelfile.
+		show(w, r, http.StatusOK, modelfilePage{Kind: "modelfile", Model: name, Text: text, Truncated: cut})
+	} // end of the handler
+} // end of modelfileHandler
diff --git a/modelfile_test.go b/modelfile_test.go
new file mode 100644
index 0000000..ac5b258
--- /dev/null
+++ b/modelfile_test.go
@@ -0,0 +1,142 @@
+// Package main tells Go that this test file belongs to the same program as modelfile.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// net/http provides requests and status codes.
+	"net/http"
+	// net/url builds form data.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+	// utf8 checks that a cut text is still valid.
+	"unicode/utf8"
+) // end of imports
+
+// TestModelfilePageShowsText checks the page shows the Modelfile of a loaded and of a not-loaded model, escapes it, has no script, and changes nothing.
+func TestModelfilePageShowsText(t *testing.T) {
+	// A fake with a hostile-looking Modelfile and one loaded model.
+	f := newGearFake()
+	// The text contains markup that must never become markup.
+	f.modelfile = "FROM x\nSYSTEM \"<script>alert(1)</script> & <b>bold</b>\"\nPARAMETER stop \"<end_of_turn>\"\n"
+	// Mark one model loaded: the page must still work for it.
+	f.loaded = []string{"alpha:1b"}
+	// Build the rig.
+	rig := gearRig(t, f)
+	// Both a loaded and a not-loaded model.
+	for _, model := range []string{"alpha:1b", "embed:1b"} {
+		// Open the page.
+		status, body, header := gearPost(t, rig, "/modelfile", model)
+		// It must work.
+		if status != http.StatusOK {
+			// Report the problem.
+			t.Fatalf("%s: status %d", model, status)
+		} // end of the status check
+		// The heading names the model, and the text is there, escaped.
+		for _, want := range []string{"Modelfile of <code>" + model + "</code>", "FROM x", "&lt;script&gt;alert(1)&lt;/script&gt; &amp; &lt;b&gt;bold&lt;/b&gt;", "&lt;end_of_turn&gt;", "Read-only", `class="modelfile"`} {
+			// Look for it.
+			if !strings.Contains(body, want) {
+				// Report the gap.
+				t.Errorf("%s: page lacks %q", model, want)
+			} // end of the check
+		} // end of the loop
+		// No raw markup from the text, no script, strict policy.
+		if strings.Contains(body, "<script") || strings.Contains(body, "<b>") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
+			// Report the problem.
+			t.Errorf("%s: the page allows or contains a script or raw markup", model)
+		} // end of the safety check
+		// There is nothing to type and nothing to submit on this page.
+		if strings.Contains(body, "<form") || strings.Contains(body, "<textarea") || strings.Contains(body, "<input") {
+			// Report the problem.
+			t.Errorf("%s: the Modelfile page has a form or a field", model)
+		} // end of the read-only check
+	} // end of the model loop
+	// Reading changed nothing.
+	if n := f.createCount(); n != 0 {
+		// Report the problem.
+		t.Errorf("%d create requests from a read-only page", n)
+	} // end of the effect check
+} // end of TestModelfilePageShowsText
+
+// TestModelfilePageUnknownModel checks a model Ollama does not have gets a plain message.
+func TestModelfilePageUnknownModel(t *testing.T) {
+	// A fake with two models.
+	rig := gearRig(t, newGearFake())
+	// Ask for a model that is not installed.
+	status, body, _ := gearPost(t, rig, "/modelfile", "nope:1b")
+	// The page says so.
+	if status != http.StatusOK || !strings.Contains(body, "not installed") {
+		// Report the problem.
+		t.Errorf("status %d, body lacks the not-installed text", status)
+	} // end of the check
+} // end of TestModelfilePageUnknownModel
+
+// TestModelfilePageRefusals checks the same refusals as the other forms: other sites, no token, wrong token, no model, too much data, and the wrong method.
+func TestModelfilePageRefusals(t *testing.T) {
+	// A fake and a rig.
+	f := newGearFake()
+	// Build the rig.
+	rig := gearRig(t, f)
+	// The cases.
+	for _, tc := range []struct {
+		// name describes the case.
+		name string
+		// form is the posted form.
+		form url.Values
+		// headers are the request headers.
+		headers map[string]string
+		// want is the expected status.
+		want int
+	}{ // the cases follow
+		// A page on another site posts the form.
+		{"cross-site", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
+		// A script without any browser headers.
+		{"no origin headers", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{}, http.StatusForbidden},
+		// The right origin but no token.
+		{"missing token", url.Values{"model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
+		// The right origin but a wrong token.
+		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
+		// No model name.
+		{"no model", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
+		// A body larger than the 2 KB limit.
+		{"too large", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
+	} { // end of the table
+		// Run each case as a named subtest.
+		t.Run(tc.name, func(t *testing.T) {
+			// Send it.
+			res := post(t, rig.h, "/modelfile", tc.form, tc.headers)
+			// Compare the status.
+			if res.StatusCode != tc.want {
+				// Report the difference.
+				t.Errorf("status %d, want %d", res.StatusCode, tc.want)
+			} // end of the status check
+		}) // end of the subtest
+	} // end of the table loop
+	// No refusal may have reached Ollama.
+	if n := f.callCount(); n != 0 {
+		// Report the problem.
+		t.Errorf("a refused request reached Ollama: %d calls", n)
+	} // end of the effect check
+	// A GET must be refused.
+	if status, _, _ := get(t, rig.h, http.MethodGet, "/modelfile"); status != http.StatusMethodNotAllowed {
+		// Report the problem.
+		t.Errorf("GET /modelfile = %d, want 405", status)
+	} // end of the method check
+} // end of TestModelfilePageRefusals
+
+// TestCutTextKeepsCharactersWhole checks a very long text is cut without splitting a character.
+func TestCutTextKeepsCharactersWhole(t *testing.T) {
+	// A short text stays whole.
+	if got, cut := cutText("abc", 10); got != "abc" || cut {
+		// Report the problem.
+		t.Errorf("short text changed: %q %v", got, cut)
+	} // end of the short check
+	// A text of four-byte characters, cut in the middle of one.
+	got, cut := cutText(strings.Repeat("😀", 10), 6)
+	// It was cut, at a character boundary.
+	if !cut || !utf8.ValidString(got) || got != "😀" {
+		// Report the problem.
+		t.Errorf("bad cut: %q %v", got, cut)
+	} // end of the long check
+} // end of TestCutTextKeepsCharactersWhole
diff --git a/web.go b/web.go
index 5f8025a..456a2d2 100644
--- a/web.go
+++ b/web.go
@@ -104,6 +104,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /gear/review", gearReview)
 	// Route: a POST request for "/gear/save" saves the size inside the model.
 	mux.HandleFunc("POST /gear/save", gearSave)
+	// Route: a POST request for "/modelfile" shows a model's Modelfile, read-only.
+	mux.HandleFunc("POST /modelfile", modelfileHandler(addr, token))
 	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
diff --git a/web/app.css b/web/app.css
index 5f22719..3ba3c3b 100644
--- a/web/app.css
+++ b/web/app.css
@@ -773,6 +773,46 @@ h2 {
   content: "]";
 } /* end of rule */
 
+/* The column that holds the gear and, just below it, the Modelfile icon. */
+.iconstack {
+  /* A box in the line that lays its children out in a column. */
+  display: inline-flex;
+  /* One icon under the other. */
+  flex-direction: column;
+  /* Level with the state words. */
+  vertical-align: middle;
+} /* end of rule */
+
+/* A tip for an icon is a single short line, so it is only as wide as its text (but never wider than the normal bubble). */
+.tip-icon {
+  /* Fit the text. */
+  width: max-content;
+  /* Never wider than the normal bubble. */
+  max-width: min(26rem, 92vw);
+} /* end of rule */
+
+/* The Modelfile text: a monospace box that keeps every line break and space and scrolls sideways instead of cutting lines. */
+.modelfile {
+  /* Same font list as code, same size as the text around it. */
+  font-family: ui-monospace, "SFMono-Regular", Menlo, Consolas, "DejaVu Sans Mono", monospace;
+  /* Normal text size. */
+  font-size: 1em;
+  /* Keep line breaks and spaces. */
+  white-space: pre;
+  /* Scroll sideways for long lines. */
+  overflow-x: auto;
+  /* Room inside. */
+  padding: 0.8rem 1rem;
+  /* A solid outline, visible without colour. */
+  border: 2px solid var(--border);
+  /* Slightly rounded corners. */
+  border-radius: 0.4rem;
+  /* Colours from the variables, so both themes work. */
+  background: var(--panel);
+  /* Text colour. */
+  color: var(--text);
+} /* end of rule */
+
 /* The gear form and the empty slot that replaces it on a loaded row; both have the same width, so the state words stay in line. */
 .gearform, .gearslot {
   /* A box in the line, so it can have a width. */
@@ -783,6 +823,12 @@ h2 {
   margin: 0;
 } /* end of rule */
 
+/* The empty slot is as tall as a gear button, so the Modelfile icon below stays in place on a loaded row. */
+.gearslot {
+  /* Same height as the button's line. */
+  height: 1.4em;
+} /* end of rule */
+
 /* The gear button: plain, so it does not compete with Load and Unload. */
 .gear {
   /* Use the page font. */
@@ -797,6 +843,8 @@ h2 {
   color: var(--muted);
   /* A hand cursor. */
   cursor: pointer;
+  /* Same line height as the empty slot, so the two icons keep their places. */
+  line-height: 1.4;
 } /* end of rule */
 
 /* Pointed at or focused: the normal text colour. */
diff --git a/web/index.html b/web/index.html
index e271fed..e5a308f 100644
--- a/web/index.html
+++ b/web/index.html
@@ -79,7 +79,7 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The gear ⚙ opens a model's settings; it appears only for models that are not loaded. The table scrolls sideways.</p>
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The gear ⚙ opens a model's inference parameters; it appears only for models that are not loaded. The page icon 📄 below it shows the model's Modelfile, read-only. The table scrolls sideways.</p>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -137,7 +137,8 @@
 <th scope="row" class="stickycol">{{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
-{{/* The gear opens this model's settings; a loaded model gets an empty slot of the same width, so the state words stay in line. */}}
+{{/* Two small icons stacked in a fixed-width column: the gear on top (only for a model that is not loaded; a loaded model gets an empty slot, so the state words stay in line) and the Modelfile page icon just below it (for every model). */}}
+<span class="iconstack">
 {{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
 {{/* A small form that sends the model name and the page token to the settings page, which changes nothing. */}}
 <form class="gearform" method="post" action="/gear">
@@ -145,12 +146,36 @@
 <input type="hidden" name="token" value="{{$.Token}}">
 {{/* The model name. */}}
 <input type="hidden" name="model" value="{{.Name}}">
-{{/* The button: the symbol is hidden from screen readers, which read the label instead. */}}
-<button type="submit" class="gear" aria-label="Settings for {{.Name}}"><span aria-hidden="true">⚙</span></button>
+{{/* The area that opens the tip: pointing at the gear or reaching it with Tab shows what it is for. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
+<button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><span aria-hidden="true">⚙</span></button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View the model's Inference parameters</span>
+{{/* End of the tip area. */}}
+</span>
 {{/* End of the form. */}}
 </form>
 {{/* End of the gear. */}}
 {{end}}
+{{/* A small form that sends the model name and the page token to the Modelfile page, which only reads and changes nothing. */}}
+<form class="gearform" method="post" action="/modelfile">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{$.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Name}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
+<button type="submit" class="gear" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><span aria-hidden="true">📄</span></button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipfile-{{.Name}}">Show the model's Modelfile (read-only)</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the form. */}}
+</form>
+{{/* End of the icon column. */}}
+</span>
 <span class="statelabel"><span class="dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}" aria-hidden="true"></span> {{.StateWord}}</span>
 {{- /* Only a loaded model gets the Unload button; it opens a warning page first, so one click never unloads anything. */ -}}
 {{if .Loaded}}
diff --git a/web/modelfile.html b/web/modelfile.html
new file mode 100644
index 0000000..42684da
--- /dev/null
+++ b/web/modelfile.html
@@ -0,0 +1,55 @@
+{{/* Modelfile page template: shows a model's Modelfile, read-only. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Modelfile - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
+{{/* The heading names the model, so there is no doubt which one is meant. */}}
+<h1>Modelfile of <code>{{.Model}}</code></h1>
+{{/* Version 1: the Modelfile text. */}}
+{{if eq .Kind "modelfile"}}
+{{/* What this page is. */}}
+<p class="muted">Read-only: this is the text that <code>ollama show --modelfile</code> prints for this model. Nothing here can be changed.</p>
+{{/* The text itself, in a box that scrolls sideways instead of cutting lines; the template escapes every character. */}}
+<pre class="modelfile" tabindex="0" aria-label="Modelfile text">{{.Text}}</pre>
+{{/* A note when a very long text was cut. */}}
+{{if .Truncated}}
+{{/* The note, with a symbol and a bold lead, so colour is never the only signal. */}}
+<p class="warn" role="alert"><strong>⚠ Shortened.</strong> The Modelfile is very long, so only the first part is shown.</p>
+{{/* End of the note. */}}
+{{end}}
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 2: the model is not installed. */}}
+{{else if eq .Kind "notinstalled"}}
+{{/* Say so. */}}
+<p>This model is not installed, so it has no Modelfile to show.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 3: something went wrong. */}}
+{{else}}
+{{/* Say what went wrong, in the plain words the program already uses. */}}
+<p><strong>Could not do this.</strong> {{.Detail}}</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the versions. */}}
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/webtable_test.go b/webtable_test.go
index 82df022..4bce601 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -134,8 +134,8 @@ func TestTablePageRealModels(t *testing.T) {
 func TestTableHelpForEveryHeading(t *testing.T) {
 	// Fake Ollama with the six real models.
 	body := pageFor(t, fullOllama(t, realModels, realPsBody))
-	// Ten column bubbles plus two category bubbles.
-	if n := strings.Count(body, `role="tooltip"`); n != 12 {
+	// Ten column bubbles plus two category bubbles; the short tips of the row icons are counted apart.
+	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 12 {
 		// Report the difference.
 		t.Errorf("%d bubbles, want 12", n)
 	} // end of the bubble count
@@ -154,10 +154,10 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	} // end of the column loop
 	// Find every aria-describedby value.
 	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
-	// There must be one per bubble.
-	if len(refs) != 12 {
+	// There must be one per bubble (the row icons have their own, counted apart).
+	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 12 {
 		// Report the difference.
-		t.Errorf("%d aria-describedby attributes, want 12", len(refs))
+		t.Errorf("%d aria-describedby attributes, want 12", n)
 	} // end of the reference count
 	// Each one must point at an element that exists.
 	for _, m := range refs {
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
5b79846ea2bdcab8b6a7b5a6a555adb9d029deb63f38c13102f809200d4653ff  gear.go
558d9d1d7510e77254b1ae9c45ae565a7cf894a5758486bbae5439745d0df268  gear_test.go
cd4306e889e71de4692336d4e274e38a9b55ff52f22e446d47255d66bca3c01e  modelfile.go
d385053e062e74f24240f5eb6b53044b19ff3b2dac15fb0f122fc43a9ffae587  modelfile_test.go
43d5a5d1ad7e9c5a94563ad1236fffe0b0d7800c209ff4cf2dae4d1995c9c183  web.go
57cbe5eeb59a47f93e9e39faf9a25d2899780919333aeff02e2ea0e2d5636a73  web/app.css
f7deb9397e38798c64fde22f7b9c3d341334e4dbe69802d0fc9ad561af6f3194  web/index.html
e5027b1864b0da4cb66ea21bda311163a9d04e38c7b6cf64ce6c1413849ee05d  web/modelfile.html
68db5e4de29a8a2da0fa35e6b98bfb8d8c1befc04033b921107d2834d708388f  webtable_test.go
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
