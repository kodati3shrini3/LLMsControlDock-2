#!/usr/bin/env bash
# Script 93c (Find LLM, change after slice 3): subtle colours for four icons, in the table and in the key to the symbols: the tag symbol is amber-brown, the delete symbol is soft red, the Modelfile symbol is soft blue and the inference parameters symbol is soft violet. Each colour has a light-theme value and a dark-theme value, and every value reads at least 4.5:1 on the page and panel backgrounds (a test works the ratio out). Pointing at the delete icon still turns it to the strong problem colour; the blue and violet icons move towards the text colour. The shapes, the tooltips and the actions do not change. One new test.
# Run it from the project folder, on the branch feature/find-llm-tags after script 93b: cd ~/LLMsControlDock && bash scripts/93c-step56c-coloured-icons.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 93b), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm_test.go"]="2569db7a43facc4fe642a21c31556bad4fc9b84b00e5ac4e9f2d4f958c9cdcf0"
BEFORE["web/app.css"]="f8d78e2266ad12c86f39748adfcd7f3b941d03243bc91e41bc5e099de5fb264d"
BEFORE["web/index.html"]="6d2b427150aa5c444b012297bd054b84e3b9c3fe33a71e020635d8e3e5370129"
AFTER["findllm_test.go"]="c84ead807c8928155bf56da3413f24144dfd055697d32fa9552c49fed3999b59"
AFTER["web/app.css"]="f633347e14555f41d97ff4cd9ce7407dd2f92ccc0c7a96d9c8be8102bcd81705"
AFTER["web/index.html"]="18a71003c3ea367e73944fb9f587f19bceec1524efdcb505d23825a7636837f4"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-tags"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 93b must have been applied: the function that finds the facts of a deleted model exists.
grep -q 'lastFacts' perfstore.go || fail "script 93b must be applied first"
# Report it.
pass "script 93b (tag look and deleted tags) is applied"

# Refuse to run twice: the colour variable exists when this change was applied before.
if grep -q 'icon-tag' web/app.css; then fail "web/app.css already has the icon colours: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_93C_END'
diff --git a/findllm_test.go b/findllm_test.go
index d25a6e9..793228a 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -8,6 +8,8 @@ import ( // import lists the standard-library packages this test file uses.
 	"html"
 	// io reads a reply body.
 	"io"
+	// math raises the colour values to a power for the contrast figure.
+	"math"
 	// net/http gives the status codes.
 	"net/http"
 	// net/url builds the form values.
@@ -20,6 +22,8 @@ import ( // import lists the standard-library packages this test file uses.
 	"regexp"
 	// runtime says which system the test runs on.
 	"runtime"
+	// strconv reads the colour numbers.
+	"strconv"
 	// strings searches the page text.
 	"strings"
 	// sync/atomic reads the request counter safely.
@@ -866,3 +870,91 @@ func TestPerfLastFacts(t *testing.T) {
 		t.Error("lastFacts found facts for an untested model")
 	} // end of the absence check
 } // end of TestPerfLastFacts
+
+// contrastOf gives the WCAG contrast ratio of two colours written as #rrggbb.
+func contrastOf(a, b string) float64 {
+	// The relative luminance of one colour.
+	lum := func(hex string) float64 {
+		// The three channels.
+		var c [3]float64
+		// Read each.
+		for i := 0; i < 3; i++ {
+			// Two hex digits.
+			v, err := strconv.ParseUint(hex[1+2*i:3+2*i], 16, 8)
+			// A bad colour means the test is broken.
+			if err != nil {
+				// Stop with a clear value.
+				return -1
+			} // end of the parse check
+			// Scale to 0..1.
+			s := float64(v) / 255
+			// The sRGB curve.
+			if s <= 0.03928 {
+				// The straight part.
+				c[i] = s / 12.92
+			} else {
+				// The curved part.
+				c[i] = math.Pow((s+0.055)/1.055, 2.4)
+			} // end of the curve
+		} // end of the channel loop
+		// The weights of the three channels.
+		return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]
+	} // end of lum
+	// The two luminances.
+	la, lb := lum(a), lum(b)
+	// The lighter one first.
+	if la < lb {
+		// Swap.
+		la, lb = lb, la
+	} // end of the swap
+	// The ratio.
+	return (la + 0.05) / (lb + 0.05)
+} // end of contrastOf
+
+// TestIconColours checks that the four icons carry their colour classes, in the table and in the key, and that every icon colour reads at least 4.5:1 on the page and panel backgrounds of both themes.
+func TestIconColours(t *testing.T) {
+	// The page with the six real models and the key open.
+	_, _, body := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/?key=open")
+	// The classes: Modelfile and parameters buttons, the delete button, and the three key symbols.
+	for _, want := range []string{`class="gear gear-file"`, `class="gear gear-params"`, `class="gear gear-delete"`, `class="ico sym-file"`, `class="ico sym-params"`, `class="ico sym-delete"`, `class="tagicon"`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The style sheet.
+	_, _, css := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/app.css")
+	// The page and panel backgrounds: light, then dark.
+	bgs := map[string][]string{"light": {"#ffffff", "#f4f6f8"}, "dark": {"#121417", "#1b1f24"}}
+	// Each icon colour appears three times: light, dark by system choice, dark by saved choice.
+	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params"} {
+		// Every value written for it.
+		vals := regexp.MustCompile(`--`+name+`: (#[0-9a-f]{6});`).FindAllStringSubmatch(css, -1)
+		// Three values.
+		if len(vals) != 3 {
+			// Stop with this one.
+			t.Errorf("--%s has %d values, want 3", name, len(vals))
+			// Next colour.
+			continue
+		} // end of the count check
+		// The first is light, the other two are dark.
+		for i, v := range vals {
+			// Which backgrounds apply.
+			which := "dark"
+			// The first value.
+			if i == 0 {
+				// Light.
+				which = "light"
+			} // end of the choice
+			// Check against both backgrounds.
+			for _, bg := range bgs[which] {
+				// The ratio.
+				if r := contrastOf(v[1], bg); r < 4.5 {
+					// Report.
+					t.Errorf("--%s %s on %s (%s theme) has contrast %.2f, want at least 4.5", name, v[1], bg, which, r)
+				} // end of the ratio check
+			} // end of the background loop
+		} // end of the value loop
+	} // end of the colour loop
+} // end of TestIconColours
diff --git a/web/app.css b/web/app.css
index 26317b1..b9d4267 100644
--- a/web/app.css
+++ b/web/app.css
@@ -20,6 +20,14 @@
   --cat-bg: #dbe7f5;
   /* Category row text colour: deep navy. */
   --cat-text: #12304f;
+  /* Soft icon colours, each at least 4.5:1 on the page and panel backgrounds: the tag symbol is amber-brown, delete is red, the Modelfile is blue and the inference parameters are violet. */
+  --icon-tag: #96560a;
+  /* The delete symbol. */
+  --icon-delete: #b3261e;
+  /* The Modelfile symbol. */
+  --icon-file: #1f5fa8;
+  /* The inference parameters symbol. */
+  --icon-params: #6d3fb5;
   /* Category row accent bar on the left edge (contrast 6.4:1 on the page). */
   --cat-accent: #1f5fa8;
   /* Tell the browser to draw its own controls in light colours. */
@@ -50,6 +58,11 @@
     --cat-bg: #1f3550;
     /* Category row text colour: pale blue. */
     --cat-text: #dbe9fb;
+    /* Soft icon colours for the dark theme, each at least 4.5:1 on the dark page and panel. */
+    --icon-tag: #f0a64b;
+    --icon-delete: #ff8a80;
+    --icon-file: #7fb2f0;
+    --icon-params: #b79af0;
     /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
     --cat-accent: #7fb2f0;
     /* Tell the browser to draw its own controls in dark colours. */
@@ -79,6 +92,11 @@
   --cat-bg: #1f3550;
   /* Category row text colour: pale blue. */
   --cat-text: #dbe9fb;
+  /* Soft icon colours for the dark theme, each at least 4.5:1 on the dark page and panel. */
+  --icon-tag: #f0a64b;
+  --icon-delete: #ff8a80;
+  --icon-file: #7fb2f0;
+  --icon-params: #b79af0;
   /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
   --cat-accent: #7fb2f0;
   /* Tell the browser to draw its own controls in dark colours. */
@@ -2625,10 +2643,12 @@ html[data-size="medium"] svg[width="22"] {
   font-weight: 400;
 } /* end of rule */
 
-/* The tag symbol is as high as the text. */
+/* The tag symbol is as high as the text, and amber-brown so it reads as a label and not as a button. */
 .tagicon {
   /* Do not shrink in a narrow column. */
   flex: none;
+  /* The soft amber-brown. */
+  color: var(--icon-tag);
 } /* end of rule */
 
 /* A tag is plain text: no border, no background, no pointer. */
@@ -2652,3 +2672,33 @@ html[data-size="medium"] svg[width="22"] {
   /* A little room above, the same as between the name and the tags. */
   margin-top: 0.25rem;
 } /* end of rule */
+
+/* The Modelfile icon next to a model: blue. */
+.gear-file, .sym-file {
+  /* The soft blue. */
+  color: var(--icon-file);
+} /* end of rule */
+
+/* The inference parameters icon next to a model: violet. */
+.gear-params, .sym-params {
+  /* The soft violet. */
+  color: var(--icon-params);
+} /* end of rule */
+
+/* The delete icon next to a model: soft red; it turns to the strong problem colour when pointed at (see the rule above). */
+.gear-delete, .sym-delete {
+  /* The soft red. */
+  color: var(--icon-delete);
+} /* end of rule */
+
+/* Pointed at or focused, the blue and violet icons move towards the text colour, so the change is seen without losing the hue. */
+.gear-file:hover, .gear-file:focus-visible {
+  /* Mixed with the text colour. */
+  color: color-mix(in srgb, var(--icon-file) 65%, var(--text));
+} /* end of rule */
+
+/* The same for the violet icon. */
+.gear-params:hover, .gear-params:focus-visible {
+  /* Mixed with the text colour. */
+  color: color-mix(in srgb, var(--icon-params) 65%, var(--text));
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index d55391c..054afde 100644
--- a/web/index.html
+++ b/web/index.html
@@ -364,10 +364,10 @@
 <ul class="legend muted" aria-label="How to read this table">
 <li><span class="sym"><span class="dotsample">Aa</span></span><span><strong>Dotted headings</strong>: point at one, or press Tab, to see what it means</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8l-4 4 4 4"/><path d="M17 8l4 4-4 4"/></svg></span><span><strong>Sideways scroll</strong>: the table scrolls sideways</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: view and modify them; only for models that are not loaded</span></li>
+<li><span class="sym"><svg class="ico sym-file" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
+<li><span class="sym"><svg class="ico sym-params" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: view and modify them; only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; only for models that are not loaded</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span><span><strong>Delete</strong>: removes a model from this computer; asks first</span></li>
+<li><span class="sym"><svg class="ico sym-delete" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span><span><strong>Delete</strong>: removes a model from this computer; asks first</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></span><span><strong>Restore</strong>: on a greyed, deleted row; how to download it again, and the parameters it had</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
 </ul>
@@ -483,7 +483,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></button>
+<button type="submit" class="gear gear-file" aria-label="Modelfile of {{.Name}}" aria-describedby="tipfile-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipfile-{{.Name}}">Show the model's Modelfile (read-only)</span>
 {{/* End of the tip area. */}}
@@ -500,7 +500,7 @@
 {{/* The area that opens the tip: pointing at the gear or reaching it with Tab shows what it is for. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
-<button type="submit" class="gear" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></button>
+<button type="submit" class="gear gear-params" aria-label="Inference parameters of {{.Name}}" aria-describedby="tipgear-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipgear-{{.Name}}">View and modify the model's Inference parameters</span>
 {{/* End of the tip area. */}}
OCC_PATCH_93C_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and look at the coloured icons (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
