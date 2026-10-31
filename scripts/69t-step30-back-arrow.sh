#!/usr/bin/env bash
# Script 69t: a round back arrow at the top right of every sub-page, including the Compare models page (also About, Performance, Modelfile, Delete, Gear, Load, Unload, Stop and the others). It is a plain link to the monitor, its words are in its tooltip and its accessible name, and the buttons at the bottom of the pages stay. The last page after Stop has no arrow, because the monitor has stopped. Applied on the same branch as 69r and 69s, before they are committed. Version 0.21.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/charts-memory" ] || { echo "FAIL  not on feature/charts-memory"; exit 1; }
# Scripts 69r and 69s (the memory of loaded models and the icon alignment) must be applied already (on this branch).
{ [ -e chartmem.go ] && ! grep -q "if .Loaded}}<span class=\"gearslot\"" web/index.html; } || { echo "FAIL  scripts 69r and 69s were not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e backarrow_test.go ]; then
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
index b722304..6921328 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.20.0"
+const appVersion = "0.21.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/backarrow_test.go b/backarrow_test.go
new file mode 100644
index 0000000..615a9fe
--- /dev/null
+++ b/backarrow_test.go
@@ -0,0 +1,132 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http provides the method name.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// os reads the template files.
+	"os"
+	// path/filepath lists the template files.
+	"path/filepath"
+	// strings searches the text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// backArrowMarkup is the round arrow link every sub-page carries at its top right.
+const backArrowMarkup = `<a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback">`
+
+// TestEverySubPageTemplateHasTheBackArrow checks, in the template files, that each sub-page has the arrow once, and the main page and the tips file have none.
+func TestEverySubPageTemplateHasTheBackArrow(t *testing.T) {
+	// Every template file.
+	files, err := filepath.Glob("web/*.html")
+	// The folder must be readable.
+	if err != nil || len(files) < 10 {
+		// Stop.
+		t.Fatalf("template files not found: %v (%d)", err, len(files))
+	} // end of the check
+	// Go through them.
+	for _, f := range files {
+		// Read it.
+		raw, err := os.ReadFile(f)
+		// It must be readable.
+		if err != nil {
+			// Stop.
+			t.Fatalf("cannot read %s: %v", f, err)
+		} // end of the read check
+		// How many arrows it has.
+		n := strings.Count(string(raw), backArrowMarkup)
+		// The main page and the shared bubble texts have none; every other page has exactly one.
+		want := 1
+		// The two exceptions.
+		if f == "web/index.html" || f == "web/tips.html" {
+			// None.
+			want = 0
+		} // end of the exception check
+		// Compare.
+		if n != want {
+			// Report it.
+			t.Errorf("%s has %d back arrows, want %d", f, n, want)
+		} // end of the count check
+	} // end of the loop
+} // end of TestEverySubPageTemplateHasTheBackArrow
+
+// TestBackArrowOnTheRenderedPages checks real pages: the arrow is there with its tooltip, the button at the bottom stays, and the last Stop page has no arrow.
+func TestBackArrowOnTheRenderedPages(t *testing.T) {
+	// A fake with one model loaded, so the unload page exists.
+	f := newPerfFake()
+	// Mark it loaded.
+	f.mu.Lock()
+	// In memory.
+	f.loaded["chat:1b"] = true
+	// Release the fake.
+	f.mu.Unlock()
+	// Count the stop requests instead of stopping.
+	stops := 0
+	// Remember the real one.
+	old := stopRequest
+	// Replace it.
+	stopRequest = func() { stops++ }
+	// Put it back at the end.
+	t.Cleanup(func() { stopRequest = old })
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// The main page has no arrow.
+	if _, _, body := get(t, rig.h, http.MethodGet, "/"); strings.Contains(body, `class="backcircle"`) {
+		// Report it.
+		t.Errorf("the main page has a back arrow")
+	} // end of the main-page check
+	// The pages to look at.
+	pages := map[string]string{}
+	// The About page is a plain GET.
+	_, _, pages["about"] = get(t, rig.h, http.MethodGet, "/about")
+	// The model pages are forms.
+	for name, path := range map[string]string{"modelfile": "/modelfile", "unload": "/unload", "load": "/load", "delete": "/delete", "gear": "/gear", "performance": "/performance"} {
+		// The model that fits the page: the unload page needs a loaded one.
+		model := "embed:1b"
+		// The unload page.
+		if name == "unload" {
+			// The loaded one.
+			model = "chat:1b"
+		} // end of the model choice
+		// Send it.
+		_, body, _ := perfPost(t, rig, path, model)
+		// Keep it.
+		pages[name] = body
+	} // end of the loop
+	// The question page of Stop.
+	res := post(t, rig.h, "/stop", url.Values{"token": {rig.token}}, fromThisPage)
+	// Keep it.
+	pages["stop"] = bodyOf(res)
+	// Check each.
+	for name, body := range pages {
+		// The arrow, its accessible name and its tooltip.
+		for _, w := range []string{backArrowMarkup, `class="pagebar"`, `id="tipback">Back to the monitor</span>`} {
+			// Look for it.
+			if !strings.Contains(body, w) {
+				// Report the gap.
+				t.Errorf("%s page lacks %q", name, w)
+			} // end of the check
+		} // end of the loop
+		// The arrow comes before the first heading.
+		if i, j := strings.Index(body, `class="pagebar"`), strings.Index(body, "<h1"); i < 0 || j < 0 || i > j {
+			// Report it.
+			t.Errorf("%s page: the arrow is not at the top (%d, %d)", name, i, j)
+		} // end of the order check
+		// The links at the bottom stay: besides the arrow, the page still has its own way back (a Back to the monitor button, or the safe choice of a question page).
+		if n := strings.Count(body, `href="/"`); n < 2 {
+			// Report it.
+			t.Errorf("%s page has %d links to the monitor, want the arrow plus its own button", name, n)
+		} // end of the link check
+	} // end of the loop
+	// The last Stop page: the monitor is closing, so there is nothing to go back to.
+	last := post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
+	// No arrow.
+	if body := bodyOf(last); strings.Contains(body, `class="backcircle"`) || !strings.Contains(body, "stopped") && !strings.Contains(body, "Stopped") {
+		// Report it.
+		t.Errorf("the last Stop page is wrong: %q", body)
+	} // end of the last-page check
+} // end of TestBackArrowOnTheRenderedPages
diff --git a/web/about.html b/web/about.html
index c849bff..6f9e0a4 100644
--- a/web/about.html
+++ b/web/about.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* One card holds everything. */}}
 <section class="panel aboutcard">
 {{/* The name of the program. */}}
diff --git a/web/app.css b/web/app.css
index 1cfc80e..fa565c3 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox {
+.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .pagebar .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -2211,3 +2211,58 @@ html[data-size="medium"] svg[width="22"] {
   /* The accent colour of the page. */
   fill: var(--cat-accent);
 } /* end of rule */
+
+/* The strip at the top of every sub-page that holds the round back arrow, at the right. */
+.pagebar {
+  /* Push the arrow to the right edge. */
+  display: flex;
+  /* At the right. */
+  justify-content: flex-end;
+  /* Space below it, the same as the gap between boxes. */
+  margin: 0 0 1rem;
+} /* end of rule */
+
+/* The round back arrow: an outline in the border colour, so it is visible without colour. */
+.backcircle {
+  /* Centre the arrow in the circle. */
+  display: inline-flex;
+  /* Centre vertically. */
+  align-items: center;
+  /* Centre horizontally. */
+  justify-content: center;
+  /* A big enough target to hit with a finger. */
+  width: 2.4rem;
+  /* As high as wide, so it is round. */
+  height: 2.4rem;
+  /* The outline of the page. */
+  border: 2px solid var(--border);
+  /* A circle. */
+  border-radius: 50%;
+  /* The panel colour inside. */
+  background: var(--panel);
+  /* The text colour for the arrow. */
+  color: var(--text);
+  /* No underline. */
+  text-decoration: none;
+} /* end of rule */
+
+/* Pointing at it or reaching it with the keyboard turns it to the accent colour. */
+.backcircle:hover,
+.backcircle:focus-visible {
+  /* The accent colour for the outline. */
+  border-color: var(--cat-accent);
+  /* And for the arrow. */
+  color: var(--cat-accent);
+} /* end of rule */
+
+/* The bubble of the back arrow ends at the right edge of the arrow, so it never runs out of the window. */
+.pagebar .tip-icon {
+  /* No left anchor. */
+  left: auto;
+  /* Its right edge lines up with the arrow. */
+  right: anchor(right);
+  /* As wide as its words. */
+  width: max-content;
+  /* Never wider than the normal bubble. */
+  max-width: min(26rem, 92vw);
+} /* end of rule */
diff --git a/web/compare-saved.html b/web/compare-saved.html
index 930a009..aadb2cd 100644
--- a/web/compare-saved.html
+++ b/web/compare-saved.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* The page heading. */}}
diff --git a/web/compare.html b/web/compare.html
index 5f4388f..932b1a1 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the comparison. */}}
 <section class="panel">
 {{/* The page heading. */}}
diff --git a/web/control.html b/web/control.html
index 1c3b10d..d1bc354 100644
--- a/web/control.html
+++ b/web/control.html
@@ -16,6 +16,11 @@
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 <main>
+{{/* After the monitor has stopped there is nothing to go back to, so the last page has no arrow. */}}
+{{if ne .Kind "stopped"}}
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
+{{end}}
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* Version 1: the question. */}}
diff --git a/web/delete.html b/web/delete.html
index 2839e52..5e73e0b 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* Version 1: the model is not loaded and the person must confirm. */}}
diff --git a/web/gear.html b/web/gear.html
index 7914457..bd5a937 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
diff --git a/web/load.html b/web/load.html
index d50a4d3..bb58ba8 100644
--- a/web/load.html
+++ b/web/load.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
diff --git a/web/modelfile.html b/web/modelfile.html
index 3fd979f..f7ac0f1 100644
--- a/web/modelfile.html
+++ b/web/modelfile.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
diff --git a/web/performance.html b/web/performance.html
index a4bca1d..8724eab 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -106,6 +106,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
diff --git a/web/retest.html b/web/retest.html
index 91aff72..4711071 100644
--- a/web/retest.html
+++ b/web/retest.html
@@ -16,6 +16,8 @@
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the page. */}}
 <section class="panel" aria-live="polite">
 {{/* ---- The question before the re-test starts. ---- */}}
diff --git a/web/unload.html b/web/unload.html
index 9689b1b..9d60ab8 100644
--- a/web/unload.html
+++ b/web/unload.html
@@ -15,6 +15,8 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
+{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1041e9b9b0386c13a8382197faacea1da14fa7d917aaaaf3311346b24f3ddb88  about.go
6ad5e2e8910fe6c51509557493e9a4d24760e8319279f25e958b68c4e31cc914  web/app.css
527fd742e01d61298379e5ee6450a2906b19e1ab7662fb12350263760c707314  web/about.html
9af17e71b97dcceb096a64eb765216be52dfb2bd1d0f8c88a97dcf694f18ffe5  web/compare-saved.html
1cebcb7cd2f88492bd249932f726fae6afcaea7a32c8752db378360820a31490  web/compare.html
8885a8e61e4651936a47dcd635840d2ca2c41a79ecb3552e5ff84e8c53caa321  web/control.html
0c9a01021d005ca230a68ad36aa49e5c005c71750ccb570f770310d03b1de10a  web/delete.html
f1dc14bb8e265abd34e28fae0b44fbce658374f47b3d4a52e7dbc1d66bd5113c  web/gear.html
3c49ecab6eead2a845aa5e0e20cfb6a03db0dc373ef78325ba71311b2c10deff  web/load.html
b52b06e0040d19932333e31b81eef5de92c7498047ec979f402fb5f0ac7e9984  web/modelfile.html
33c579bea7a7d3fcbfeca263524b61c1413c1bc8845c3e9834b0c9d44088d8ee  web/performance.html
514fca3e569bfca7cb710b5cf1c79c4b15460959deb2bee191bebacb37ebe99c  web/retest.html
181da6178303e212284eafb601c977923de8f7c5974c9343718e82a8ee57c56a  web/unload.html
4e7f2a0d19bf5351ee8ce00ef370e1bd4b0742c284bd17d4f10a028bf23d92c7  backarrow_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and open a sub-page (for example About) and look for the round back arrow at its top right"
# List the changed files; nothing is committed yet.
git status --short
