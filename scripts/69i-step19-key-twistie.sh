#!/usr/bin/env bash
# Script 69i: the key to the symbols above the models table becomes a twistie (closed by default). Opening it redraws the page with the key shown and the automatic updates paused, so the key does not vanish while it is read. No script is needed.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/key-twistie" ] || { echo "FAIL  not on feature/key-twistie"; exit 1; }
# Script 69h (API health panel) must be applied already (merged into main).
[ -e health.go ] || { echo "FAIL  script 69h was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e key_test.go ]; then
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
index fe2a2a3..da544ad 100644
--- a/control_test.go
+++ b/control_test.go
@@ -377,8 +377,8 @@ func TestControlIconsAndZone(t *testing.T) {
 func TestKeyAndDrawnIcons(t *testing.T) {
 	// A fake and a rig.
 	rig, _ := perfRig(t, newPerfFake())
-	// The main page.
-	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// The main page with the key open (it is closed by default).
+	_, _, body := get(t, rig.h, http.MethodGet, "/?key=open")
 	// None of the old emoji-like characters may remain on the page.
 	for _, bad := range []string{"📄", "⚙", "📈", "⚖"} {
 		// Look for it.
@@ -465,7 +465,7 @@ func TestKeyBox(t *testing.T) {
 		t.Errorf(".panelhead has no space below it")
 	} // end of the space check
 	// The key sits in the panel of the models table, after the heading row and before the table.
-	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	_, _, body := get(t, rig.h, http.MethodGet, "/?key=open")
 	// The three places.
 	head, key, table := strings.Index(body, `class="panelhead"`), strings.Index(body, `<ul class="legend`), strings.Index(body, `<table class="models"`)
 	// The order must be heading row, key, table.
diff --git a/gear_test.go b/gear_test.go
index f603dad..a0372e8 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -1254,7 +1254,9 @@ func TestMainPageGearOnlyForNotLoaded(t *testing.T) {
 		// Report the problem.
 		t.Errorf("gear position: %d %d", i, j)
 	} // end of the order check
-	// The key above the table explains the parameters icon.
+	// The key above the table explains the parameters icon; it is drawn only while it is open.
+	_, _, body = get(t, rig.h, http.MethodGet, "/?key=open")
+	// Look for the hint.
 	if !strings.Contains(body, "only for models that are not loaded") {
 		// Report the problem.
 		t.Errorf("no hint about the gear")
diff --git a/history_test.go b/history_test.go
index 702cbce..ed3401e 100644
--- a/history_test.go
+++ b/history_test.go
@@ -357,7 +357,7 @@ func TestRestorePageSaysWhenNothingWasKept(t *testing.T) {
 		t.Errorf("the restore page does not say nothing was kept: %s", body)
 	} // end of the check
 	// The key explains the history too.
-	_, _, page := get(t, rig.h, http.MethodGet, "/")
+	_, _, page := get(t, rig.h, http.MethodGet, "/?key=open")
 	// The key text.
 	if !strings.Contains(page, "how to download it again, and the parameters it had") {
 		// Report it.
diff --git a/key_test.go b/key_test.go
new file mode 100644
index 0000000..aeb9cdc
--- /dev/null
+++ b/key_test.go
@@ -0,0 +1,54 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http provides the request method names.
+	"net/http"
+	// strings searches the pages.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestKeyTwistie checks the key to the symbols: closed by default, open with ?key=open, and no automatic update while it is open.
+func TestKeyTwistie(t *testing.T) {
+	// A fake Ollama and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The page as it first opens.
+	_, _, closed := get(t, rig.h, http.MethodGet, "/")
+	// The page with the key opened.
+	_, _, open := get(t, rig.h, http.MethodGet, "/?key=open")
+	// Closed: the link to open it, the hint, no key box, and the automatic update is on.
+	for _, want := range []string{`href="/?key=open#key"`, "Key to the symbols", "(click to show)", `http-equiv="refresh"`, "Watching: the page updates itself"} {
+		// Look for it.
+		if !strings.Contains(closed, want) {
+			// Report the gap.
+			t.Errorf("closed page lacks %q", want)
+		} // end of the check
+	} // end of the closed loop
+	// Closed: the box with the entries is not drawn.
+	if strings.Contains(closed, `<ul class="legend`) || strings.Contains(closed, "Dotted headings</strong>") {
+		// Report the problem.
+		t.Errorf("the key box is drawn while closed")
+	} // end of the box check
+	// Open: the link to close it, the hint, the key box, no automatic update, and the page says why.
+	for _, want := range []string{`href="/#key"`, "(click to hide)", `<ul class="legend`, "Dotted headings</strong>", "Paused while the key to the symbols is open", "Close the key to carry on watching"} {
+		// Look for it.
+		if !strings.Contains(open, want) {
+			// Report the gap.
+			t.Errorf("open page lacks %q", want)
+		} // end of the check
+	} // end of the open loop
+	// Open: no refresh tag at all, and no claim that the page updates itself.
+	if strings.Contains(open, `http-equiv="refresh"`) || strings.Contains(open, "Watching: the page updates itself") {
+		// Report the problem.
+		t.Errorf("the open page still updates itself")
+	} // end of the refresh check
+	// Any other value of the parameter counts as closed.
+	_, _, odd := get(t, rig.h, http.MethodGet, "/?key=<script>")
+	// It must be closed and must not echo the value.
+	if strings.Contains(odd, `<ul class="legend`) || strings.Contains(odd, "<script>") {
+		// Report the problem.
+		t.Errorf("an odd value opened the key or was echoed")
+	} // end of the odd check
+} // end of TestKeyTwistie
diff --git a/web.go b/web.go
index f09910c..36490d2 100644
--- a/web.go
+++ b/web.go
@@ -73,6 +73,8 @@ type pageData struct {
 	CompareCount int
 	// Paused is true when the person paused the automatic updates (a cookie remembers it).
 	Paused bool
+	// KeyOpen is true when the person opened the key to the symbols (the address then ends in ?key=open); the page does not update by itself meanwhile.
+	KeyOpen bool
 	// RefreshSeconds is how often the page updates itself while it is being watched.
 	RefreshSeconds int
 	// UpdatedAt is the time of day this page was made, so a person can see how fresh it is.
@@ -243,6 +245,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			CompareCount: perfHistory.testedModels(),
 			// Whether the automatic updates are paused.
 			Paused: watchPaused(r),
+			// Whether the key to the symbols is open.
+			KeyOpen: r.URL.Query().Get("key") == "open",
 			// The update interval.
 			RefreshSeconds: watchRefreshSeconds,
 			// When this page was made.
diff --git a/web/app.css b/web/app.css
index 9973b26..5759cde 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1990,3 +1990,38 @@ html[data-size="medium"] svg[width="22"] {
   /* Break long addresses. */
   overflow-wrap: anywhere;
 } /* end of rule */
+
+/* The twistie line above the key: a small arrow, the name and a hint, all one link. */
+.keytoggle {
+  /* Space above and below. */
+  margin: 0.4rem 0 0.75rem;
+  /* Bold, like a heading of the key. */
+  font-weight: 600;
+} /* end of rule */
+
+/* The link keeps the text colour; underline appears on hover and focus so it still reads as clickable. */
+.keytoggle a {
+  /* The normal text colour. */
+  color: inherit;
+  /* No line until hover or focus. */
+  text-decoration: none;
+  /* A comfortable click area. */
+  display: inline-block;
+  /* Vertical padding makes the target taller. */
+  padding: 0.3rem 0;
+} /* end of rule */
+
+/* Hover and keyboard focus show the underline. */
+.keytoggle a:hover,
+.keytoggle a:focus-visible {
+  /* Underline. */
+  text-decoration: underline;
+} /* end of rule */
+
+/* The hint after the name is lighter. */
+.keyhint {
+  /* Normal weight. */
+  font-weight: 400;
+  /* The muted colour of the page. */
+  color: var(--muted);
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 3e3e429..5a5e1cf 100644
--- a/web/index.html
+++ b/web/index.html
@@ -14,7 +14,8 @@
 {{/* Load our own stylesheet; the safety policy allows only styles from this same address. */}}
 <link rel="stylesheet" href="/app.css">
 {{/* While the page is being watched it reloads itself; Pause removes this line. It needs no script. */}}
-{{if not .Paused}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
+{{/* No automatic update while the key is open, so it does not vanish while it is being read. */}}
+{{if and (not .Paused) (not .KeyOpen)}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 {{/* The page header. */}}
@@ -28,7 +29,7 @@
 {{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
 <p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
 {{/* Says whether the page updates by itself, and how fresh it is; the symbol and the words carry the meaning. */}}
-<p class="muted" id="watchline">{{if .Paused}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><path d="M4 2.5v11l9-5.5z"/></svg> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
+<p class="muted" id="watchline">{{if and .KeyOpen (not .Paused)}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused while the key to the symbols is open. Page made at {{.UpdatedAt}}. Close the key to carry on watching.{{else if .Paused}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><path d="M4 2.5v11l9-5.5z"/></svg> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
 {{/* End of the title block. */}}
 </div>
 {{/* The right side of the header: the monitor controls, then the theme switch. */}}
@@ -193,6 +194,14 @@
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
 {{/* A key above the table: what each symbol and the dotted headings do. */}}
+{{/* The twistie: a plain link that opens or closes the key; the program draws the page again, so no script is needed. */}}
+{{if .KeyOpen}}
+<p class="keytoggle" id="key"><a href="/#key"><span aria-hidden="true">&#9662;</span> Key to the symbols <span class="keyhint">(click to hide)</span></a></p>
+{{else}}
+<p class="keytoggle" id="key"><a href="/?key=open#key"><span aria-hidden="true">&#9656;</span> Key to the symbols <span class="keyhint">(click to show)</span></a></p>
+{{end}}
+{{/* The key itself, drawn only while it is open. */}}
+{{if .KeyOpen}}
 <ul class="legend muted" aria-label="How to read this table">
 <li><span class="sym"><span class="dotsample">Aa</span></span><span><strong>Dotted headings</strong>: point at one, or press Tab, to see what it means</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8l-4 4 4 4"/><path d="M17 8l4 4-4 4"/></svg></span><span><strong>Sideways scroll</strong>: the table scrolls sideways</span></li>
@@ -203,6 +212,7 @@
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></span><span><strong>Restore</strong>: on a greyed, deleted row; how to download it again, and the parameters it had</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
 </ul>
+{{end}}
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
22cabbd895cee47a950d2d8f9c3cf82319254eece0a428c262f9c9bf70d86505  web/index.html
17253c4d54883841ae59580b187b2db92c8ed3f248666c7826a3ba7282d5e3cf  web.go
2e75f92f8db6710a33caf40c7dded8071f1dd0aed0dba49305ef519fe6380839  web/app.css
b89ec860e7117d9a391b1ecd2395ec0c9aff9488526e550b96cb766d35babe69  control_test.go
2ba022ef94812c318982c5f7f0ff0dbc4a06160b8c618dcb083626507c4f332a  gear_test.go
c7a49048fc58c8c48f21350ede0e9ab27d5c49361e1119605c58944b617ef790  history_test.go
0500642c544d86ee33c69073005a4af2dff7f37ee8157ec1181db7ade66267d7  key_test.go
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
