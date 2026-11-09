#!/usr/bin/env bash
# Script 96 (button colours and hover highlight): the magnifier of the Find LLM button is now teal and the scales of the Compare tested models button are gold (the colours were defined in script 94 but no rule applied them). Every kind of button now gets a faint fill and a stronger outline when the pointer is over it or the keyboard focus is on it, mixed from the theme colours so the light, dark and automatic themes each get their own shade. Only colours change, so the tooltips work as before. One new test (it fails if a defined icon colour is never used, if a button kind has no highlight, or if the highlight touches tooltips).
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 95): cd ~/LLMsControlDock && bash scripts/96-step59-button-colours-and-hover.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 95), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm_test.go"]="a81b005c3a4a615b6a2ceccbb4102262c6b14670793a715f4498a83153044974"
BEFORE["web/app.css"]="39b1b9c2131040e2e9198198c1cbed00bfe0ae80cb8d8ce92e02a7669b75b837"
AFTER["findllm_test.go"]="1673b6d65c8e3fb7414acca196aed67b7e75c09119c3bfce66d5f17c44b4cac5"
AFTER["web/app.css"]="3e85f03ca14b31ae9293b8d3498c45d740d506250b4302a78d76c4e873d34717"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-installed-speed"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 95 must have been applied: the state icon tooltip texts exist.
grep -q 'tipVersionFits' findllm.go || fail "script 95 must be applied first"
# Report it.
pass "script 95 (state icons) is applied"

# Refuse to run twice: the rule that colours the Find LLM icon exists when this change was applied before.
if grep -q '^\.ico-find {' web/app.css; then fail "web/app.css already has the button colour rules: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/findllm_test.go b/findllm_test.go
index d744686..7bfd7d8 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -4,6 +4,8 @@ package main
 import ( // import lists the standard-library packages this test file uses.
 	// encoding/json checks what is saved for a deleted model.
 	"encoding/json"
+	// fmt formats the mixed colour of the highlight test.
+	"fmt"
 	// html escapes a help text the way the page does.
 	"html"
 	// io reads a reply body.
@@ -1283,3 +1285,94 @@ func TestStateIconsOnThePage(t *testing.T) {
 		t.Error("a size class should remove the cloud section and say why")
 	} // end of the class check
 } // end of TestStateIconsOnThePage
+
+// mixHex mixes two #rrggbb colours: the share p (0 to 1) of a, the rest of b, as color-mix does in the sRGB space.
+func mixHex(a, b string, p float64) string {
+	// The result starts as the hash sign.
+	out := "#"
+	// Each of the red, green and blue pairs.
+	for i := 1; i < 7; i += 2 {
+		// The two channel values.
+		x, _ := strconv.ParseInt(a[i:i+2], 16, 32)
+		// The second colour's channel.
+		y, _ := strconv.ParseInt(b[i:i+2], 16, 32)
+		// The mixed channel, rounded.
+		out += fmt.Sprintf("%02x", int(math.Round(float64(x)*p+float64(y)*(1-p))))
+	} // end of the channel loop
+	// The mixed colour.
+	return out
+} // end of mixHex
+
+// TestButtonHighlightAndIconRules checks that every icon colour is really applied, that every kind of button has a highlight when pointed at or focused, that the highlight never touches the tooltips, and that the two button icons stay readable on the highlighted button.
+func TestButtonHighlightAndIconRules(t *testing.T) {
+	// The style sheet.
+	_, _, css := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/app.css")
+	// Every icon colour that is defined must also be used by a rule: a defined but unused colour is the bug that hid the teal and the gold.
+	for _, name := range regexp.MustCompile(`--(icon-[a-z]+): #`).FindAllStringSubmatch(css, -1) {
+		// The use: the colour is read by a rule somewhere.
+		if !strings.Contains(css, "var(--"+name[1]+")") {
+			// Report.
+			t.Errorf("--%s is defined but no rule uses it", name[1])
+		} // end of the use check
+	} // end of the loop
+	// The two button icons have their own rules.
+	for _, want := range []string{".ico-find {\n  /* The theme's teal; the symbol is drawn in the current colour. */\n  color: var(--icon-find);", ".ico-compare {\n  /* The theme's gold; the symbol is drawn in the current colour. */\n  color: var(--icon-compare);"} {
+		// Look for it.
+		if !strings.Contains(css, want) {
+			// Report.
+			t.Errorf("the style sheet lacks the rule %q", want[:12])
+		} // end of the look
+	} // end of the loop
+	// Every kind of button: pointed at, and reached with the keyboard.
+	for _, sel := range []string{".btn-plain", ".comparebtn", ".btn-solid", ".btn-load", ".btn-go", ".btn-danger", ".unload", ".load", ".switch", ".autobtn", ".gear", ".copybtn", ".backcircle"} {
+		// The rule must name both states.
+		for _, state := range []string{":hover", ":focus-visible"} {
+			// Look for it.
+			if !strings.Contains(css, sel+state) {
+				// Report.
+				t.Errorf("%s has no %s rule", sel, state)
+			} // end of the look
+		} // end of the state loop
+	} // end of the loop
+	// The highlight block starts at its own heading comment.
+	i := strings.Index(css, "/* Button highlight:")
+	// It must exist.
+	if i < 0 {
+		// Stop here.
+		t.Fatal("the highlight block is missing")
+	} // end of the block check
+	// The block itself.
+	block := css[i:]
+	// The highlight changes colours only: nothing that could hide, move or block a tooltip.
+	for _, bad := range []string{"pointer-events", "overflow", "display:", "visibility", "position", "z-index", "opacity", "content:"} {
+		// Look for it.
+		if strings.Contains(block, bad) {
+			// Report.
+			t.Errorf("the highlight block contains %q, which could disturb the tooltips", bad)
+		} // end of the look
+	} // end of the loop
+	// The tooltip rules are still there: they open on pointing and on focus.
+	for _, want := range []string{".tipbox:hover > .tip", ".tipbox:focus-within > .tip"} {
+		// Look for it.
+		if !strings.Contains(css, want) {
+			// Report.
+			t.Errorf("the tooltip rule %q is gone", want)
+		} // end of the look
+	} // end of the loop
+	// The panel colour, the text colour and the two icon colours, light then dark.
+	for _, th := range []struct{ name, panel, bg, text, find, compare string }{{"light", "#f4f6f8", "#ffffff", "#1a1a1a", "#0a6b73", "#7a5f00"}, {"dark", "#1b1f24", "#121417", "#ececec", "#4fd1c5", "#e3c04d"}} {
+		// The highlighted button: 8 percent of the text colour over the page or the panel.
+		for _, under := range []string{th.panel, th.bg} {
+			// The washed colour.
+			hl := mixHex(th.text, under, 0.08)
+			// Both icons.
+			for _, c := range []string{th.find, th.compare} {
+				// The ratio.
+				if r := contrastOf(c, hl); r < 4.5 {
+					// Report.
+					t.Errorf("%s theme: icon %s on the highlighted button (%s) has contrast %.2f, want at least 4.5", th.name, c, hl, r)
+				} // end of the ratio check
+			} // end of the icon loop
+		} // end of the background loop
+	} // end of the theme loop
+} // end of TestButtonHighlightAndIconRules
diff --git a/web/app.css b/web/app.css
index 7f33c13..a4e9337 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2768,3 +2768,101 @@ html[data-size="medium"] svg[width="22"] {
   /* Rounded like the other rings. */
   border-radius: 0.3rem;
 } /* end of rule */
+
+/* The colour of the magnifier in the Find LLM button: teal, from the theme variables. */
+.ico-find {
+  /* The theme's teal; the symbol is drawn in the current colour. */
+  color: var(--icon-find);
+} /* end of rule */
+
+/* The colour of the scales in the Compare tested models button: gold, from the theme variables. */
+.ico-compare {
+  /* The theme's gold; the symbol is drawn in the current colour. */
+  color: var(--icon-compare);
+} /* end of rule */
+
+/* Button highlight: a button under the pointer or reached with the keyboard gets a faint fill and a stronger outline, so the person sees it can be clicked. Every colour is mixed from the theme variables, so light, dark and automatic themes each get their own shade. Only colours change: nothing here touches the tooltips, which open from the wrapper around the button. */
+
+/* Outlined buttons and links drawn like buttons (Pause, Refresh, Settings, Back to the monitor, Cancel and so on). */
+.btn-plain:hover, .btn-plain:focus-visible {
+  /* A faint wash of the text colour over whatever is behind the button. */
+  background: color-mix(in srgb, var(--text) 8%, transparent);
+  /* The outline turns to the full text colour. */
+  border-color: var(--text);
+} /* end of rule */
+
+/* The two feature buttons (Find LLM and Compare tested models) keep their blue family: the wash comes from the rule above, and the outline turns to the deep blue (pale blue in dark themes). */
+.comparebtn:hover, .comparebtn:focus-visible {
+  /* The outline turns to the button's text colour. */
+  border-color: var(--cat-text);
+} /* end of rule */
+
+/* Filled red confirming button: a little towards the text colour (darker in light themes, lighter in dark themes), with the outline following. */
+.btn-solid:hover, .btn-solid:focus-visible {
+  /* The fill moves slightly towards the text colour. */
+  background: color-mix(in srgb, var(--btn) 82%, var(--text));
+  /* The outline moves further, so the edge shows. */
+  border-color: color-mix(in srgb, var(--btn) 55%, var(--text));
+} /* end of rule */
+
+/* Filled blue button of the load pages. */
+.btn-load:hover, .btn-load:focus-visible {
+  /* The fill moves slightly towards the text colour. */
+  background: color-mix(in srgb, var(--load) 82%, var(--text));
+  /* The outline moves further, so the edge shows. */
+  border-color: color-mix(in srgb, var(--load) 55%, var(--text));
+} /* end of rule */
+
+/* Filled green button. */
+.btn-go:hover, .btn-go:focus-visible {
+  /* The fill moves slightly towards the text colour. */
+  background: color-mix(in srgb, var(--go) 82%, var(--text));
+  /* The outline moves further, so the edge shows. */
+  border-color: color-mix(in srgb, var(--go) 55%, var(--text));
+} /* end of rule */
+
+/* Filled danger button (a link or a button). */
+.btn-danger:hover, .btn-danger:focus-visible {
+  /* The fill moves slightly towards the text colour. */
+  background: color-mix(in srgb, var(--danger) 82%, var(--text));
+  /* The outline moves further, so the edge shows. */
+  border-color: color-mix(in srgb, var(--danger) 55%, var(--text));
+} /* end of rule */
+
+/* The small theme and text-size switches: a faint wash on the track (the outline already turns darker). */
+.switch:hover, .switch:focus-visible {
+  /* A faint wash of the text colour over the panel colour. */
+  background: color-mix(in srgb, var(--text) 8%, var(--panel));
+} /* end of rule */
+
+/* The small Auto buttons: a faint fill and a solid underline. */
+.autobtn:hover, .autobtn:focus-visible {
+  /* A faint wash of the text colour. */
+  background: color-mix(in srgb, var(--text) 10%, transparent);
+  /* The normal text colour instead of the quiet one. */
+  color: var(--text);
+  /* A solid underline instead of a dotted one. */
+  text-decoration-style: solid;
+  /* Slightly rounded wash. */
+  border-radius: 0.2rem;
+} /* end of rule */
+
+/* The round icon buttons in the table: a faint round wash behind the icon (their colour changes stay as they were). */
+.gear:hover, .gear:focus-visible {
+  /* A faint wash of the text colour. */
+  background: color-mix(in srgb, var(--text) 10%, transparent);
+  /* Slightly rounded wash. */
+  border-radius: 0.3rem;
+} /* end of rule */
+
+/* The Copy buttons: a faint wash inside the stronger outline. */
+.copybtn:hover, .copybtn:focus-visible {
+  /* A faint wash of the text colour. */
+  background: color-mix(in srgb, var(--text) 8%, transparent);
+} /* end of rule */
+
+/* The round back arrow: a faint wash of the accent colour. */
+.backcircle:hover, .backcircle:focus-visible {
+  /* A little accent colour mixed into the panel colour. */
+  background: color-mix(in srgb, var(--cat-accent) 12%, var(--panel));
+} /* end of rule */
OCC_PATCH_94_END
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
echo "NEXT  start bin/LLMsControlDock and hard-reload the page and point at the buttons (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
