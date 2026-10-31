#!/usr/bin/env bash
# Script 69u: a follow-up to 69t on the same branch. The round back arrow now sits inside the box of each sub-page, in its top right corner, level with the heading (for example at the far right of "Compare models"), instead of above the box. A long heading stops before the arrow. The buttons at the bottom stay. No version change (0.21.0).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/charts-memory" ] || { echo "FAIL  not on feature/charts-memory"; exit 1; }
# Script 69t (the back arrow) must be applied already (on this branch).
[ -e backarrow_test.go ] || { echo "FAIL  script 69t was not applied yet"; exit 1; }
# Refuse to run twice.
if ! grep -q "class=\"pagebar\"" web/about.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/backarrow_test.go b/backarrow_test.go
index 615a9fe..6670ff9 100644
--- a/backarrow_test.go
+++ b/backarrow_test.go
@@ -104,7 +104,7 @@ func TestBackArrowOnTheRenderedPages(t *testing.T) {
 	// Check each.
 	for name, body := range pages {
 		// The arrow, its accessible name and its tooltip.
-		for _, w := range []string{backArrowMarkup, `class="pagebar"`, `id="tipback">Back to the monitor</span>`} {
+		for _, w := range []string{backArrowMarkup, `class="tipbox backtop"`, `id="tipback">Back to the monitor</span>`} {
 			// Look for it.
 			if !strings.Contains(body, w) {
 				// Report the gap.
@@ -112,7 +112,7 @@ func TestBackArrowOnTheRenderedPages(t *testing.T) {
 			} // end of the check
 		} // end of the loop
 		// The arrow comes before the first heading.
-		if i, j := strings.Index(body, `class="pagebar"`), strings.Index(body, "<h1"); i < 0 || j < 0 || i > j {
+		if i, j := strings.Index(body, `class="tipbox backtop"`), strings.Index(body, "<h1"); i < 0 || j < 0 || i > j {
 			// Report it.
 			t.Errorf("%s page: the arrow is not at the top (%d, %d)", name, i, j)
 		} // end of the order check
diff --git a/web/about.html b/web/about.html
index 6f9e0a4..7ac8552 100644
--- a/web/about.html
+++ b/web/about.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* One card holds everything. */}}
 <section class="panel aboutcard">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The name of the program. */}}
 <h1>About Ollama Control Center</h1>
 {{/* One line that says what it is. */}}
diff --git a/web/app.css b/web/app.css
index fa565c3..8e96a8c 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .pagebar .tipbox {
+.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -2212,14 +2212,32 @@ html[data-size="medium"] svg[width="22"] {
   fill: var(--cat-accent);
 } /* end of rule */
 
-/* The strip at the top of every sub-page that holds the round back arrow, at the right. */
-.pagebar {
-  /* Push the arrow to the right edge. */
-  display: flex;
-  /* At the right. */
-  justify-content: flex-end;
-  /* Space below it, the same as the gap between boxes. */
-  margin: 0 0 1rem;
+/* A box that holds the round back arrow is the base for placing it. */
+.panel:has(> .backtop) {
+  /* The arrow is placed against this box. */
+  position: relative;
+} /* end of rule */
+
+/* The area of the arrow: in the top right corner of its own box, level with the heading. */
+.backtop {
+  /* Placed against the box. */
+  position: absolute;
+  /* Level with the first line of the heading. */
+  top: 0.62rem;
+  /* In from the right edge by the same inner space as the text. */
+  right: 1rem;
+} /* end of rule */
+
+/* The About card has more room above its heading, so its arrow sits lower to stay level with it. */
+.aboutcard .backtop {
+  /* Lower by the extra room. */
+  top: calc(0.62rem + 0.75rem);
+} /* end of rule */
+
+/* What follows the arrow (the heading) stops before it, so a long heading never runs under the arrow. */
+.backtop + * {
+  /* Room for the arrow and a little air. */
+  padding-right: 3.2rem;
 } /* end of rule */
 
 /* The round back arrow: an outline in the border colour, so it is visible without colour. */
@@ -2256,7 +2274,7 @@ html[data-size="medium"] svg[width="22"] {
 } /* end of rule */
 
 /* The bubble of the back arrow ends at the right edge of the arrow, so it never runs out of the window. */
-.pagebar .tip-icon {
+.backtop .tip-icon {
   /* No left anchor. */
   left: auto;
   /* Its right edge lines up with the arrow. */
diff --git a/web/compare-saved.html b/web/compare-saved.html
index aadb2cd..c410ed0 100644
--- a/web/compare-saved.html
+++ b/web/compare-saved.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The page heading. */}}
 <h1>Comparison saved</h1>
 {{/* What was saved and where; the program wrote the file itself, so the browser asks nothing. */}}
diff --git a/web/compare.html b/web/compare.html
index 932b1a1..bea8e07 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the comparison. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The page heading. */}}
 <h1>Compare models</h1>
 {{/* The short notice, always at the top, with a link to the full text at the bottom. */}}
diff --git a/web/control.html b/web/control.html
index d1bc354..b0f2fc4 100644
--- a/web/control.html
+++ b/web/control.html
@@ -16,13 +16,13 @@
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 <main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
 {{/* After the monitor has stopped there is nothing to go back to, so the last page has no arrow. */}}
 {{if ne .Kind "stopped"}}
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{end}}
-{{/* A panel that holds the message. */}}
-<section class="panel">
 {{/* Version 1: the question. */}}
 {{if eq .Kind "stopask"}}
 <h1>Stop the monitor?</h1>
diff --git a/web/delete.html b/web/delete.html
index 5e73e0b..96e1778 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* Version 1: the model is not loaded and the person must confirm. */}}
 {{if eq .Kind "confirm"}}
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
diff --git a/web/gear.html b/web/gear.html
index bd5a937..3ca9bd6 100644
--- a/web/gear.html
+++ b/web/gear.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
 <h1>Settings for <code>{{.Model}}</code></h1>
 {{/* Version 1: the settings and the form. */}}
diff --git a/web/load.html b/web/load.html
index bb58ba8..c89f06a 100644
--- a/web/load.html
+++ b/web/load.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
 <h1>Load <code>{{.Model}}</code></h1>
 {{/* Version 1: the model can be loaded and the person must confirm. */}}
diff --git a/web/modelfile.html b/web/modelfile.html
index f7ac0f1..db24d84 100644
--- a/web/modelfile.html
+++ b/web/modelfile.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
 <h1>Modelfile of <code>{{.Model}}</code></h1>
 {{/* Version 1: the Modelfile text. */}}
diff --git a/web/performance.html b/web/performance.html
index 8724eab..edbddd2 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -106,10 +106,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
 <h1>Performance of <code>{{.Model}}</code></h1>
 {{/* Version 1: the start page. */}}
diff --git a/web/retest.html b/web/retest.html
index 4711071..1188c90 100644
--- a/web/retest.html
+++ b/web/retest.html
@@ -16,10 +16,10 @@
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the page. */}}
 <section class="panel" aria-live="polite">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* ---- The question before the re-test starts. ---- */}}
 {{if eq .Kind "ask"}}
 <h1>Re-test the group "{{.Title}}"?</h1>
diff --git a/web/unload.html b/web/unload.html
index 9d60ab8..ea4aeec 100644
--- a/web/unload.html
+++ b/web/unload.html
@@ -15,10 +15,10 @@
 <body>{{/* start of the visible page. */}}
 {{/* The page content. */}}
 <main>
-{{/* The back arrow at the top right: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
-<div class="pagebar"><span class="tipbox"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span></div>
 {{/* A panel that holds the message. */}}
 <section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
 {{/* The heading names the model, so there is no doubt which one is meant. */}}
 <h1>Unload <code>{{.Model}}</code></h1>
 {{/* Version 1: the model is loaded and the person must confirm. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
ab25ee1922942fb82677e26362b6adfb973e7af61f99f9c3a04ceec5938d7ff4  web/app.css
db0152c6f524c93df04b586fe0a57116289a4ddd6700ec67a9adf36c0f62f172  web/about.html
8f5b5fa3f4a47ac163b0fb53d253ec60f78505e1a5f00807df08bd042440b352  web/compare-saved.html
c58b7f2ec23d137e9a61ced8ae9badfcfa67381f526898077b825dde8ead585d  web/compare.html
1dcb036f487b92d1484e8119dd62fb94c847de6861653f478ef1e7c13efe8bd6  web/control.html
79720a52ad841a934d9414ae0b6ac2ceee7a4165fb6e80a774d128ad9b99e76b  web/delete.html
39b28b58812dbc2f3734b0c3a2165735a0227caa7245af0e5b35a0fae019f929  web/gear.html
e787a1e2e99d9450bf33ddfb496d8029fd29f84240af1682c54c8ffbb0d7d65b  web/load.html
3f400299904aeefd1c318cac82069d47c1401fc6c4561f8952026c98016c423b  web/modelfile.html
e9d426672cd90eeb04bf29910313a2bc1e9dba0a9ee81a8cc29f724140bdde16  web/performance.html
d17ddc85136886a5ed31f8d8c46883a4e001bad84995c5f058eb0cd508fccf1c  web/retest.html
66ac3b23aaf2ad1a9aed3b86068d319587c6c9da219ae2ef35642055b3a95d58  web/unload.html
d1d059ea8a4be958edafb35118e28e4b03b7f16367e65c16371472bf1ca318a9  backarrow_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and open the Compare models page and look for the round back arrow inside the box, at the far right of the heading"
# List the changed files; nothing is committed yet.
git status --short
