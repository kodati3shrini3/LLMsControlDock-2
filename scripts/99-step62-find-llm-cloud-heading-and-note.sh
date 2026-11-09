#!/usr/bin/env bash
# Script 99 (Find LLM, the Cloud models section catches the eye): the heading Cloud models now has a large cloud symbol beside it (1.7 times the heading text, so it keeps its proportion at any text size, in the cloud blue of the theme), and the note under it is a framed block with a thick bar and a faint tint in the same blue, with the three key phrases in bold: These models run on Ollama's servers, not on this computer; Nothing is downloaded; They may need an Ollama account. The wording is unchanged. One new test, and the existing heading checks follow the new heading.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 97): cd ~/LLMsControlDock && bash scripts/99-step62-find-llm-cloud-heading-and-note.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 98), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm_test.go"]="c508944db7c6e9ee374f5f95a4be9f61f9d19abba630f69062fb1f99a5435d9a"
BEFORE["web/app.css"]="0de65dad32e7cfb4757052daba67653e48876cf9e371f5c477a600f0f72eb308"
BEFORE["web/findllm.html"]="48c914887b1664b7b2b71c6d41c5c7458c489a635d1f79612b5977ce20f0aa6f"
AFTER["findllm_test.go"]="0f26a856390d14224e678ba652d7ff875c590dcedb6c136c13b64c06cc841e96"
AFTER["web/app.css"]="ffeef565330b0cacfd412468afef16f8d94af3f56191d1d478385bf7e942b4c3"
AFTER["web/findllm.html"]="7976aaccb6efde1a199ed7a95739571e458c1708a527f0622dfafa34d87dd7d0"

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

# Script 98 must have been applied: the fields of use exist.
grep -q 'var findDomains' findllm.go || fail "script 98 must be applied first"
# Report it.
pass "script 98 (Field of use) is applied"

# Refuse to run twice: the new heading exists when this change was applied before.
if grep -q 'class="cloudhead"' web/findllm.html; then fail "web/findllm.html already has the cloud heading: this script was already applied"; fi
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
index 68b63aa..4b93cef 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -426,7 +426,7 @@ func TestFindSearchShowsFitAndNoFit(t *testing.T) {
 		t.Fatalf("status %d: %s", status, body)
 	} // end of the status check
 	// The model, its official link, the small version that fits with its command, and the large one with the reason.
-	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", `<h2 id="cloudmodels">Cloud models</h2>`, tipCloud, tipVersionFits, tipVersionNoFit, tipModelFits} {
+	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", `<h2 id="cloudmodels" class="cloudhead">`, tipCloud, tipVersionFits, tipVersionNoFit, tipModelFits} {
 		// Look for it in the page text with the character codes turned back into characters (the apostrophe is written as a code).
 		if !strings.Contains(html.UnescapeString(body), want) {
 			// Report.
@@ -439,7 +439,7 @@ func TestFindSearchShowsFitAndNoFit(t *testing.T) {
 		t.Error("the embedding model was listed")
 	} // end of the embedding check
 	// The cloud-only model is listed, but only in the cloud section (after its heading), and has no download command.
-	if at, cloudAt := strings.Index(body, ">cloudy"), strings.Index(body, `<h2 id="cloudmodels">`); at < 0 || cloudAt < 0 || at < cloudAt || strings.Contains(body, "ollama pull cloudy") {
+	if at, cloudAt := strings.Index(body, ">cloudy"), strings.Index(body, `<h2 id="cloudmodels" class="cloudhead">`); at < 0 || cloudAt < 0 || at < cloudAt || strings.Contains(body, "ollama pull cloudy") {
 		// Report.
 		t.Error("the cloud-only model is missing from the cloud section, or has a download command")
 	} // end of the cloud check
@@ -1696,3 +1696,57 @@ func TestFindDomainChoice(t *testing.T) {
 		t.Error("the ticked field or Match ANY is not kept after the search")
 	} // end of the kept check
 } // end of TestFindDomainChoice
+
+// TestCloudHeadingAndNote checks that the Cloud models section catches the eye: a large symbol in the heading, sized from the text, and a framed note with bold key phrases, readable in light and dark themes.
+func TestCloudHeadingAndNote(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// A search that brings the cloud model: tools, no size, no memory class.
+	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// The heading holds the symbol, hidden from screen readers, and the words.
+	if !strings.Contains(body, `<h2 id="cloudmodels" class="cloudhead"><svg class="cloudbig"`) || !strings.Contains(body, `aria-hidden="true"`) || !strings.Contains(body, "<span>Cloud models</span></h2>") {
+		// Report.
+		t.Error("the Cloud models heading lacks its large symbol")
+	} // end of the heading check
+	// The note is a framed note with the three key phrases in bold.
+	for _, want := range []string{`<p class="cloudnote" role="note">`, "<strong>These models run on Ollama's servers, not on this computer,</strong>", "<strong>Nothing is downloaded.</strong>", "<strong>They may need an Ollama account.</strong>", "so your free disk space and memory do not apply to them."} {
+		// Look for it, as a person reads it.
+		if !strings.Contains(html.UnescapeString(body), want) {
+			// Report.
+			t.Errorf("the note lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The style sheet.
+	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
+	// The three rules exist, and the symbol is sized from the text.
+	for _, want := range []string{".cloudhead {", ".cloudbig {", "width: 1.7em;", ".cloudnote {", "border-left: 6px solid var(--icon-cloud);"} {
+		// Look for it.
+		if !strings.Contains(css, want) {
+			// Report.
+			t.Errorf("the style sheet lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The note's text must stay readable on its tint: the tint is 12 percent of the cloud colour over the panel colour.
+	for _, th := range []struct{ name, panel, text, cloud string }{{"light", "#f4f6f8", "#1a1a1a", "#1565a8"}, {"dark", "#1b1f24", "#ececec", "#86c5f2"}} {
+		// The tinted background.
+		bg := mixHex(th.cloud, th.panel, 0.12)
+		// The ratio of the text on it.
+		if r := contrastOf(th.text, bg); r < 7 {
+			// Report.
+			t.Errorf("%s theme: note text on its tint has contrast %.2f, want at least 7", th.name, r)
+		} // end of the ratio check
+		// The cloud colour on the panel, for the symbol and the bar.
+		if r := contrastOf(th.cloud, th.panel); r < 4.5 {
+			// Report.
+			t.Errorf("%s theme: cloud colour on the panel has contrast %.2f, want at least 4.5", th.name, r)
+		} // end of the cloud ratio check
+	} // end of the theme loop
+} // end of TestCloudHeadingAndNote
diff --git a/web/app.css b/web/app.css
index ede4655..6aaea00 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2900,3 +2900,41 @@ html[data-size="medium"] svg[width="22"] {
   /* The secondary colour, readable in every theme. */
   color: var(--muted);
 } /* end of rule */
+
+/* The heading of the Cloud models section: the symbol and the words side by side, level with each other. */
+.cloudhead {
+  /* Symbol and words in one row. */
+  display: flex;
+  /* Centre them on one line. */
+  align-items: center;
+  /* Space between the symbol and the words. */
+  gap: 0.5rem;
+} /* end of rule */
+
+/* The large cloud symbol in that heading. */
+.cloudbig {
+  /* Sized from the heading's own text, so it stays in proportion at any text size. */
+  width: 1.7em;
+  /* Same as the width. */
+  height: 1.7em;
+  /* Never squeezed in the row. */
+  flex: none;
+  /* The cloud colour of the theme. */
+  color: var(--icon-cloud);
+} /* end of rule */
+
+/* The framed note under it: a thick bar and a faint tint in the cloud colour, so it is noticed. */
+.cloudnote {
+  /* A thick bar on the left in the cloud colour. */
+  border-left: 6px solid var(--icon-cloud);
+  /* A faint tint of the cloud colour over the panel colour. */
+  background: color-mix(in srgb, var(--icon-cloud) 12%, var(--panel));
+  /* Room inside the frame. */
+  padding: 0.6rem 0.9rem;
+  /* Slightly rounded on the right. */
+  border-radius: 0 0.4rem 0.4rem 0;
+  /* Space around the frame. */
+  margin: 0.4rem 0 1rem;
+  /* A little larger than the text around it. */
+  font-size: 1.05em;
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index 864dad1..621f808 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -134,8 +134,9 @@
 {{end}}
 {{/* The cloud-only models: no versions are read and nothing is downloaded, so there is no fit check, only the cloud symbol with its tooltip. */}}
 {{if .CloudResults}}
-<h2 id="cloudmodels">Cloud models</h2>
-<p class="muted">These models run on Ollama's servers, not on this computer, so your free disk space and memory do not apply to them. Nothing is downloaded. They may need an Ollama account.</p>
+{{/* A large cloud symbol in the heading, sized from the heading's own text, and a framed note whose key phrases are bold, so the person notices that these models are not local. */}}
+<h2 id="cloudmodels" class="cloudhead"><svg class="cloudbig" viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 18h10a4 4 0 0 0 .6-7.95A5.5 5.5 0 0 0 7.1 9.2 4.4 4.4 0 0 0 7 18z"/></svg><span>Cloud models</span></h2>
+<p class="cloudnote" role="note"><strong>These models run on Ollama's servers, not on this computer,</strong> so your free disk space and memory do not apply to them. <strong>Nothing is downloaded.</strong> <strong>They may need an Ollama account.</strong></p>
 {{range .CloudResults}}
 <div class="findresult">
 <h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a> {{template "stateicon" .Icon}}</h3>
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
echo "NEXT  start bin/LLMsControlDock and run a Find LLM search that shows cloud models and look at the heading and the note (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
