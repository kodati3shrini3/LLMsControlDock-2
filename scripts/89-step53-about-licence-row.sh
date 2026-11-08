#!/usr/bin/env bash
# Script 89 (About page licence row): the Licence row of the About page now says "Apache License 2.0" (a link to the LICENSE file) and "© 2026 termGate Consulting Limited." instead of "All rights reserved". One new test file checks that LICENSE, NOTICE, README and the About page tell the same story. The version stays 0.31.0.
# Run it from the project folder, on the same branch as scripts 87 and 88 (never on main): cd ~/OllamaControlCenter && bash scripts/89-step53-about-licence-row.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by scripts 87 and 88), and AFTER it.
declare -A BEFORE AFTER
BEFORE["about.go"]="f47af5ffefafb3e6287a6d163ce25b862ee4dcb65c54265aebe5275ca666db27"
BEFORE["about_test.go"]="264edde3e2416df45b5b8f5bf1376a685d9db97193d6d1cbf572a0c03a7a9473"
BEFORE["web/about.html"]="ec81bc2f758af5f1bed4e10666f9d5c45cfcaf776a64d6dedf10262e69733584"
AFTER["about.go"]="f7e4c976dd51d15e2281826638a0392fad0ec0468e9701a01d6a7737e67c9317"
AFTER["about_test.go"]="f157baf46522493f0737d8072a00f24c878272572c8e49c11bf59ca31ef84f67"
AFTER["web/about.html"]="9488c9da8329839ab0d2c284b20449faf2f7f4bccdaea5a3c32155db8d3fca89"
AFTER["licence_test.go"]="d8d1bf3ff28e005f689f78327ea5101f341aaf344145f276bf596391b4876760"

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
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on the rename branch (rename/llmscontroldock)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Scripts 87 and 88 must be applied: their files exist.
[ -e legacyname.go ] && [ -e README.md ] && [ -e NOTICE ] && [ -f LICENSE ] || fail "legacyname.go, README.md, NOTICE or LICENSE is missing: apply scripts 87 and 88 and step 8 first"
# Report it.
pass "scripts 87 and 88 were applied (legacyname.go, README.md, NOTICE, LICENSE exist)"

# Refuse to run twice: the new test file exists when the change was applied before.
if [ -e licence_test.go ]; then fail "licence_test.go exists: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_89_END'
diff --git a/about.go b/about.go
index 377e00f..c98bb2f 100644
--- a/about.go
+++ b/about.go
@@ -40,8 +40,14 @@ const appAssistant = "Claude (Sonnet 5.5), Anthropic"
 // appDedication is the dedication shown on the About page.
 const appDedication = "Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this program."
 
-// appCopyright is the copyright line shown on the About page.
-const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
+// appCopyright is the copyright line shown on the About page; it is the same holder as in the NOTICE file.
+const appCopyright = "© 2026 termGate Consulting Limited."
+
+// appLicence is the name of the licence under which the program is shared (the same licence as the LICENSE file).
+const appLicence = "Apache License 2.0"
+
+// appLicenceURL is where the licence text is: the LICENSE file in the repository.
+const appLicenceURL = appRepository + "/blob/main/LICENSE"
 
 // appRepository is the address of the source code; the repository is private, so only its owner can open it.
 const appRepository = "https://github.com/kodati3shrini3/LLMsControlDock"
@@ -112,6 +118,10 @@ type aboutPage struct {
 	Dedication string
 	// Copyright is appCopyright.
 	Copyright string
+	// Licence is appLicence.
+	Licence string
+	// LicenceURL is appLicenceURL.
+	LicenceURL string
 	// Repository is appRepository.
 	Repository string
 	// Revision is the short source revision, or empty when the build did not record one.
@@ -207,6 +217,10 @@ func aboutHandler() http.HandlerFunc {
 			Dedication: appDedication,
 			// The copyright line.
 			Copyright: appCopyright,
+			// The licence name.
+			Licence: appLicence,
+			// The address of the licence text.
+			LicenceURL: appLicenceURL,
 			// The source address.
 			Repository: appRepository,
 			// The revision.
diff --git a/about_test.go b/about_test.go
index bc47d3c..131665e 100644
--- a/about_test.go
+++ b/about_test.go
@@ -66,8 +66,10 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		"built with uncommitted changes",
 		// The revision date with its time zone written out.
 		"committed 27 Oct 2026 17:50 UTC",
-		// The licence line.
-		"2026 Shrinivas Kodati. All rights reserved.",
+		// The copyright holder, the same as in the NOTICE file.
+		"© 2026 termGate Consulting Limited.",
+		// The licence, as a link to the LICENSE file.
+		`href="https://github.com/kodati3shrini3/LLMsControlDock/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">Apache License 2.0<span class="sr-only"> (opens in a new window)</span></a>`,
 		// The repository link, safe to follow.
 		`href="https://github.com/kodati3shrini3/LLMsControlDock" target="_blank" rel="noopener noreferrer"`,
 		// The way back.
@@ -84,6 +86,11 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// Report the problem.
 		t.Errorf("the About page contains a script")
 	} // end of the script check
+	// The old claim must be gone: the program is shared under Apache-2.0, so "All rights reserved" would contradict it.
+	if strings.Contains(body, "All rights reserved") {
+		// Report the problem.
+		t.Errorf("the About page still says All rights reserved")
+	} // end of the old-claim check
 	// The strict policy applies to it too.
 	if !strings.Contains(header.Get("Content-Security-Policy"), "default-src 'none'") {
 		// Report the problem.
diff --git a/licence_test.go b/licence_test.go
new file mode 100644
index 0000000..1c36a8f
--- /dev/null
+++ b/licence_test.go
@@ -0,0 +1,80 @@
+// Package main tells Go that this test file belongs to the same program as about.go.
+package main
+
+// Imports: the standard library only.
+import (
+	// os reads the public project files.
+	"os"
+	// strings searches their text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// readProjectFile reads one public file from the project folder (the folder the tests run in) and fails the test when it is missing.
+func readProjectFile(t *testing.T, name string) string {
+	// Mark this as a helper.
+	t.Helper()
+	// Read it.
+	b, err := os.ReadFile(name)
+	// A missing file is a missing public file.
+	if err != nil {
+		// Report.
+		t.Fatalf("%s is missing from the project folder: %v", name, err)
+	} // end of the read check
+	// The text.
+	return string(b)
+} // end of readProjectFile
+
+// TestLicenceFilesAgreeWithThePage checks that the LICENSE file, the NOTICE file, the README and the About page all tell the same story: the same licence, the same copyright holder, and no leftover claim of "All rights reserved".
+func TestLicenceFilesAgreeWithThePage(t *testing.T) {
+	// The official licence text: its title and version line, and the end marker once.
+	lic := readProjectFile(t, "LICENSE")
+	// The title and the version.
+	if !strings.Contains(lic, "Apache License") || !strings.Contains(lic, "Version 2.0, January 2004") {
+		// Report.
+		t.Error("LICENSE is not the Apache License 2.0")
+	} // end of the licence check
+	// The end of the terms, once.
+	if strings.Count(lic, "END OF TERMS AND CONDITIONS") != 1 {
+		// Report.
+		t.Error("LICENSE must hold the end marker exactly once")
+	} // end of the end-marker check
+	// The page names the same licence as the file.
+	if appLicence != "Apache License 2.0" {
+		// Report.
+		t.Errorf("the About page names %q, not the Apache License 2.0", appLicence)
+	} // end of the name check
+	// The copyright holder is the text of the page without the sign and the year.
+	holder := strings.TrimSuffix(strings.TrimPrefix(appCopyright, "© 2026 "), ".")
+	// The NOTICE names the same holder and the program.
+	notice := readProjectFile(t, "NOTICE")
+	// The holder.
+	if !strings.Contains(notice, "Copyright 2026 "+holder) {
+		// Report.
+		t.Errorf("NOTICE does not say Copyright 2026 %s", holder)
+	} // end of the holder check
+	// The program name.
+	if !strings.HasPrefix(notice, "LLMsControlDock\n") {
+		// Report.
+		t.Error("NOTICE must start with the program name")
+	} // end of the name check
+	// The README names the licence, the holder and the version of this program.
+	readme := readProjectFile(t, "README.md")
+	// Each fact.
+	for _, want := range []string{"Apache License 2.0", "Copyright 2026 " + holder, "version " + appVersion} {
+		// Look for it.
+		if !strings.Contains(readme, want) {
+			// Report.
+			t.Errorf("README.md does not contain %q", want)
+		} // end of the look
+	} // end of the fact loop
+	// No file may claim "All rights reserved" next to an open licence.
+	for name, text := range map[string]string{"NOTICE": notice, "README.md": readme} {
+		// Look for it.
+		if strings.Contains(text, "All rights reserved") {
+			// Report.
+			t.Errorf("%s says All rights reserved", name)
+		} // end of the look
+	} // end of the claim loop
+} // end of TestLicenceFilesAgreeWithThePage
diff --git a/web/about.html b/web/about.html
index e277f00..6cfe3ac 100644
--- a/web/about.html
+++ b/web/about.html
@@ -44,7 +44,7 @@
 {{/* Where the data goes. */}}
 <tr><th scope="row">Privacy</th><td>Runs only on this computer. The one request to the outside is the optional check of Ollama's public library when a model is deleted, and it sends only the model's name. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
 {{/* The licence. */}}
-<tr><th scope="row">Licence</th><td>{{.Copyright}}</td></tr>
+<tr><th scope="row">Licence</th><td><a href="{{.LicenceURL}}" target="_blank" rel="noopener noreferrer">{{.Licence}}<span class="sr-only"> (opens in a new window)</span></a>. {{.Copyright}}</td></tr>
 {{/* End of the table. */}}
 </table>
 {{/* The dedication, set apart so it stands out. */}}
OCC_PATCH_89_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# The old claim must be gone from the page template and the program.
if grep -q 'All rights reserved' about.go web/about.html; then fail "All rights reserved is still in about.go or web/about.html"; fi
# Report it.
pass "no All rights reserved in about.go or web/about.html"

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
echo "NEXT  restart bin/LLMsControlDock and open the About page: the Licence row must show Apache License 2.0 (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
