#!/usr/bin/env bash
# Script 97b (Find LLM, Match ALL or Match ANY: heading removed, short tooltips added): the words How the ticks combine are no longer shown (the group keeps that name for screen readers). The explanation of each choice stays visible as text under its radio button, and each choice now also has a very short tooltip: All ticked items needed, and One ticked item is enough. The line With nothing ticked here, no ability is checked is not shown. The test of the choice checks the visible texts, the two tooltips (at most 40 characters, no markup characters) and that the heading words are not shown.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 97): cd ~/LLMsControlDock && bash scripts/97b-step60b-find-llm-match-text-and-tooltips.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 97), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm_test.go"]="f915b2017d6dfa70ee32edcaef2ca2c59afe71b3ce4029d1b78dc415b69bab9e"
BEFORE["web/app.css"]="b2faadd648a2c8f67d0ce62afe206ddb28fd5fe5a246e459dc86854374e29f98"
BEFORE["web/findllm.html"]="b610114b3440338d1f4d2fb82748167643a554af622644734f9bc76a923402ea"
AFTER["findllm_test.go"]="93f0002fde712447ce3fb3bcc43bf008a8a27d0f17bf1e898f6598676e573c9c"
AFTER["web/app.css"]="0de65dad32e7cfb4757052daba67653e48876cf9e371f5c477a600f0f72eb308"
AFTER["web/findllm.html"]="6c35723d3cd11977174de41a52b00239407ab45c4c019b50cdb0c2cf7aebf03b"

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

# Script 97 must have been applied: the all-or-any rule exists.
grep -q 'func abilitiesMatch' findllm.go || fail "script 97 must be applied first"
# Report it.
pass "script 97 (Match ALL or Match ANY) is applied"

# Refuse to run twice: the tooltip of the first choice exists when this change was applied before.
if grep -q 'tip-mode-all' web/findllm.html; then fail "web/findllm.html already has the choice tooltips: this script was already applied"; fi
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
index 6811312..b9bef3b 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1415,7 +1415,7 @@ func TestAbilitiesMatch(t *testing.T) {
 	} // end of the loop
 } // end of TestAbilitiesMatch
 
-// TestFindModeChoice checks the Match ALL or Match ANY choice on the page and in the search: it sits inside "What it should do", defaults to ALL, is explained in plain text (not in a tooltip), is kept after a search, and changes the result.
+// TestFindModeChoice checks the Match ALL or Match ANY choice on the page and in the search: it sits inside "What it should do", defaults to ALL, is explained in visible text under each option and also has a very short tooltip, is kept after a search, and changes the result.
 func TestFindModeChoice(t *testing.T) {
 	// The saved library list goes to a throw-away folder, never to the real data folder.
 	isolateFindData(t)
@@ -1443,7 +1443,7 @@ func TestFindModeChoice(t *testing.T) {
 		// Report.
 		t.Error("the choice is missing from the box or the default is not Match ALL")
 	} // end of the radio check
-	// The explanations are plain text in the box, never in a tooltip.
+	// The explanation of each choice is visible text in the box, outside any tooltip.
 	for _, want := range []string{"Match ALL ticked", "Match ANY ticked", "The model must do everything you ticked.", "The model needs at least one of the things you ticked."} {
 		// Look for it.
 		if !strings.Contains(box, want) {
@@ -1451,14 +1451,38 @@ func TestFindModeChoice(t *testing.T) {
 			t.Errorf("the box lacks the text %q", want)
 		} // end of the look
 	} // end of the loop
-	// The two choices must be written outside any tooltip bubble: no bubble contains them.
+	// The visible explanations sit in their own paragraphs, not inside a tooltip bubble.
 	for _, b := range regexp.MustCompile(`(?s)<span class="tip"[^>]*>.*?</span>`).FindAllString(box, -1) {
-		// A bubble that talks about the choice.
-		if strings.Contains(b, "Match ALL") || strings.Contains(b, "Match ANY") {
+		// A bubble that holds a long explanation.
+		if strings.Contains(b, "everything you ticked") || strings.Contains(b, "at least one of the things") {
 			// Report.
-			t.Error("the explanation of the choice is inside a tooltip")
+			t.Error("a tooltip repeats the long explanation instead of staying very short")
 		} // end of the bubble check
 	} // end of the loop
+	// The heading words take no room: the group keeps its name only as an aria-label for screen readers.
+	if strings.Contains(strings.ReplaceAll(box, `aria-label="How the ticks combine"`, ""), "How the ticks combine") || !strings.Contains(box, `aria-label="How the ticks combine"`) {
+		// Report.
+		t.Error("the words How the ticks combine are visible, or the group lost its accessible name")
+	} // end of the heading check
+	// Each choice also has a very short tooltip: one line, at most 40 characters, no markup characters.
+	for _, id := range []string{"tip-mode-all", "tip-mode-any"} {
+		// The bubble with this id, and the word that points to it.
+		m := regexp.MustCompile(`id="` + id + `">([^<]*)</span>`).FindStringSubmatch(box)
+		// It must exist, and the label must point to it.
+		if m == nil || !strings.Contains(box, `aria-describedby="`+id+`"`) {
+			// Report and go on.
+			t.Errorf("the choice has no tooltip %s", id)
+			// Next.
+			continue
+		} // end of the bubble check
+		// The text, as a person reads it.
+		tx := html.UnescapeString(m[1])
+		// Very short and clean.
+		if n := utf8.RuneCountInString(tx); n == 0 || n > 40 || strings.ContainsAny(tx, "<>{}\n") {
+			// Report.
+			t.Errorf("%s text %q is empty, longer than 40 characters, or has markup characters", id, tx)
+		} // end of the text check
+	} // end of the bubble loop
 	// The same search in both modes: tools or embedding is ticked (no model has both).
 	base := url.Values{"token": {rig.token}, "ab_tools": {"on"}, "ab_embedding": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}}
 	// Match ALL (nothing sent for the mode): no model has both.
diff --git a/web/app.css b/web/app.css
index 8682ec7..ede4655 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2893,12 +2893,6 @@ html[data-size="medium"] svg[width="22"] {
   padding-left: 1rem;
 } /* end of rule */
 
-/* The small heading of the choice. */
-.abmodetitle {
-  /* Close to the first choice. */
-  margin: 0 0 0.3rem;
-} /* end of rule */
-
 /* The explanation under each choice: the secondary text colour, indented under the radio button. */
 .modeexplain {
   /* Lines up under the words of the choice. */
diff --git a/web/findllm.html b/web/findllm.html
index 4e7b06a..e114356 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -51,14 +51,12 @@
 {{range .Abilities}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tip.ID}}">{{.Label}}</span><span class="tip" role="tooltip" id="{{.Tip.ID}}">{{template "tip" .Tip}}</span></span></label>
 {{end}}
 </div>
-{{/* How the ticks combine: always one of the two is chosen (Match ALL unless the person chose otherwise); the explanation is plain text on the page, not a tooltip. */}}
-<div class="abilitymode" role="radiogroup" aria-labelledby="abmodetitle">
-<p id="abmodetitle" class="abmodetitle"><strong>How the ticks combine</strong></p>
-<label class="tickrow"><input type="radio" name="ab_mode" value="all"{{if not .AnyMode}} checked{{end}}> <strong>Match ALL ticked</strong> <small class="muted">(the default)</small></label>
+{{/* How the ticks combine: always one of the two is chosen (Match ALL unless the person chose otherwise). The explanation of each choice is plain text under it, and each choice also has a very short tooltip; the group keeps its name for screen readers without showing it. */}}
+<div class="abilitymode" role="radiogroup" aria-label="How the ticks combine">
+<label class="tickrow"><input type="radio" name="ab_mode" value="all"{{if not .AnyMode}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="tip-mode-all"><strong>Match ALL ticked</strong></span><span class="tip" role="tooltip" id="tip-mode-all">All ticked items needed.</span></span> <small class="muted">(the default)</small></label>
 <p class="modeexplain"><small>The model must do everything you ticked. Example: Uses tools and Understands pictures lists only models that do both.</small></p>
-<label class="tickrow"><input type="radio" name="ab_mode" value="any"{{if .AnyMode}} checked{{end}}> <strong>Match ANY ticked</strong></label>
+<label class="tickrow"><input type="radio" name="ab_mode" value="any"{{if .AnyMode}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="tip-mode-any"><strong>Match ANY ticked</strong></span><span class="tip" role="tooltip" id="tip-mode-any">One ticked item is enough.</span></span></label>
 <p class="modeexplain"><small>The model needs at least one of the things you ticked. Example: Uses tools and Understands pictures lists models that do either one or both.</small></p>
-<p class="modeexplain"><small>With nothing ticked here, no ability is checked.</small></p>
 </div>
 </div>
 </fieldset>
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
echo "NEXT  start bin/LLMsControlDock and open Find LLM and look at the choice on the right of What it should do (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
