#!/usr/bin/env bash
# Script 92c (Find LLM, change after slice 2): the Find LLM button moves from the top row into the Installed models panel, before "Compare tested models", with the same size and look. The top row goes back to what it was, so the rule added by script 92b is taken out again. The test follows the button.
# Run it from the project folder, on the branch feature/find-llm-page after scripts 92 and 92b: cd ~/LLMsControlDock && bash scripts/92c-step55c-find-llm-button-in-panel.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of each file BEFORE the change (as left by script 92b) and AFTER it.
declare -A BEFORE AFTER
BEFORE["web/index.html"]="d9ead188703b0181f48465e949d7bf73e5a88af16b75552b332a3b3eb4a9983d"
BEFORE["web/app.css"]="3982732efc48319ece84aba5d317c97bff76e0284d6e01d598b7c980ad305dbb"
BEFORE["findllm_test.go"]="5f4d9880342dbb682516038a8742a5edbc5bffc99b440c3dcf2b868f8a2d15b0"
AFTER["web/index.html"]="563fbbdaca2ea0147ff36b74549d578113ab276e0d8a0732c7433988170e79b2"
AFTER["web/app.css"]="c19a0530e09ff127eed0771559400bdcbba7d8f3b6e71a48b0d086893a2a8190"
AFTER["findllm_test.go"]="660dfb42f56ffb2b8013aa3c7c2f3a68518f58f34546f7350f2352e1d290954c"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-page"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Scripts 92 and 92b must have been applied: the page file and the 92b rule exist.
[ -e findllm.go ] && grep -q 'The title block may shrink' web/app.css || fail "scripts 92 and 92b must be applied first"
# Report it.
pass "scripts 92 and 92b are applied"

# Refuse to run twice: the new wrapper is in the page when this change was applied before.
if grep -q 'panelactions' web/index.html; then fail "web/index.html already has the change: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_92C_END'
--- a/web/index.html
+++ b/web/index.html
@@ -94,11 +94,6 @@
 <a class="btn-plain ctlbtn" href="/settings" aria-describedby="tipsettings"><svg class="ico" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h9"/><path d="M17 6h3"/><circle cx="15" cy="6" r="2"/><path d="M4 12h3"/><path d="M11 12h9"/><circle cx="9" cy="12" r="2"/><path d="M4 18h11"/><path d="M19 18h1"/><circle cx="17" cy="18" r="2"/></svg> Settings</a>
 <span class="tip tip-icon" role="tooltip" id="tipsettings">Settings: Ollama address, check interval, timeout, chart history, access from other machines</span>
 </span>
-{{/* Find LLM: a plain link to the Find LLM page; the page itself asks nothing from the internet until its own button is pressed. */}}
-<span class="tipbox">
-<a class="btn-plain ctlbtn" href="/findllm" aria-describedby="tipfindllm"><svg class="ico" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg> Find LLM</a>
-<span class="tip tip-icon" role="tooltip" id="tipfindllm">Find LLM: lists only models that Ollama supports and can install; installs nothing</span>
-</span>
 {{/* Stop: a small form that goes to the question page; nothing is stopped yet. */}}
 <form method="post" action="/stop">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -299,6 +294,24 @@
 {{/* The heading row: the heading on the left and, when there is a table, the compare button on the right. */}}
 <div class="panelhead">
 <h2 id="installed-title">Installed models{{if .HasTable}} ({{.Table.Total}}){{end}}</h2>
+{{/* The buttons at the right of the heading: Find LLM always, then Compare tested models when there is a table. */}}
+<div class="panelactions">
+{{/* Find LLM: a small GET form with the same size and look as the compare button; it only opens the Find LLM page, which asks nothing from the internet until its own button is pressed. */}}
+<div class="comparebar">
+{{/* The form changes nothing; it only goes to the page. */}}
+<form method="get" action="/findllm">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the words. */}}
+<button type="submit" class="btn-plain comparebtn" aria-describedby="tipfindllm"><svg class="ico ico-big" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg> Find LLM</button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipfindllm">Find LLM: lists only models that Ollama supports and can install; installs nothing</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the Find LLM form. */}}
+</form>
+{{/* End of the Find LLM button bar. */}}
+</div>
 {{if .HasTable}}{{if .Table.Groups}}
 {{/* The compare button: a labelled button above the table, with the number of models that have been tested. */}}
 <div class="comparebar">
@@ -319,6 +332,8 @@
 {{/* End of the compare button bar. */}}
 </div>
 {{end}}{{end}}
+{{/* End of the buttons at the right of the heading. */}}
+</div>
 </div>
 {{/* Case 1: Ollama answered but the lists could not be read; say why in plain words. */}}
 {{if .TableError}}
--- a/web/app.css
+++ b/web/app.css
@@ -391,14 +391,6 @@
   gap: 1rem;
 } /* end of rule */
 
-/* The title block may shrink and wrap its lines, so the buttons stay at the top right even when there are six of them; below 20rem of title width the buttons drop under the title as before. */
-.headrow > :first-child {
-  /* Take the space that is left beside the buttons; start from nothing so the long line under the title does not push the buttons down. */
-  flex: 1 1 0;
-  /* Never narrower than this; if the buttons need more room, they wrap under the title. */
-  min-width: 20rem;
-} /* end of rule */
-
 /* The last line of the title block leaves no space of its own: the header's gap and the bar below decide the distance, so it is the same 1rem whether the buttons sit beside the title or below it. */
 .headrow #watchline {
   /* No space below the line. */
@@ -1199,6 +1191,18 @@
   margin: 0.2rem 0;
 } /* end of rule */
 
+/* The buttons at the right of the Installed models heading sit side by side and wrap on a narrow window. */
+.panelactions {
+  /* Side by side. */
+  display: flex;
+  /* Wrap when the window is narrow. */
+  flex-wrap: wrap;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between the buttons. */
+  gap: 0.5rem;
+} /* end of rule */
+
 /* The bar with the compare button needs no outer space in the heading row. */
 .comparebar {
   /* No outer space. */
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -473,8 +473,8 @@
 	rig := newThemeRig(t)
 	// The home page.
 	_, _, body := get(t, rig.h, http.MethodGet, "/")
-	// The button and its tooltip.
-	for _, want := range []string{`href="/findllm"`, "Find LLM", "installs nothing"} {
+	// The button (in the Installed models panel, beside Compare tested models) and its tooltip.
+	for _, want := range []string{`action="/findllm"`, "Find LLM", "installs nothing"} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report.
OCC_PATCH_92C_END
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
echo "NEXT  start bin/LLMsControlDock and look at the Installed models panel (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
