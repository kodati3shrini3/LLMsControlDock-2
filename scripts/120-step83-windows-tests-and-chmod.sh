#!/usr/bin/env bash
# Script 120 (Windows tests, line endings, chmod line): the four automated tests that failed on the Windows systems of the GitHub check are fixed (three assumed Unix paths, Unix file modes or Unix line endings; one wrote its test file into a folder that did not exist and counted the real state folder), the two licence files get their own line-ending rule in .gitattributes, the README and the release notes tell Linux and macOS users to run chmod +x, the README status row mentions the GitHub start-up check, and RELEASE-NOTES-0.33.0.md becomes the text that is published on the release page. No program code changes, so the published release files stay valid.
# Run it on a new branch (never main): cd ~/LLMsControlDock-2 && git switch -c feature/windows-tests-and-chmod && bash scripts/120-step83-windows-tests-and-chmod.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the six files BEFORE the change (as on main after PR 56) and AFTER it.
declare -A BEFORE AFTER
BEFORE[".gitattributes"]="dbbef157e7ac4a4835839fc627fbecb25d5e89d5ddb4a096ea6aa0ef05cc27cb"
BEFORE["README.md"]="0bd8100ce955f6b020e75a9acf472d5c244708ea525ee004c4bf706f3ddc3a13"
BEFORE["RELEASE-NOTES-0.33.0.md"]="4799fd9b85d0d9be333e1db5d3a6ad271f7b01daddc52fc3ba7ac5cff921757e"
BEFORE["install_test.go"]="0dba6f79206094a29b5611ca92dd71b614092aff735a3a8656ace957eab619c5"
BEFORE["selfusage_test.go"]="894e8abafa4f73a641a38aa4da7bb7ce3b8853d3ea07b33df130a082ebba885d"
BEFORE["syscheck_test.go"]="06f7812374ed13ecb604bbaaa2b6b20102fb4d592429e06dfd53277f004236db"
AFTER[".gitattributes"]="d2c701fc5692079c65c0b225e2b30833340ee6c88b3d86f706bf816d4230a531"
AFTER["README.md"]="331ff021e05918763b5d32dbc1396753ef5a576f7498e0fec5cbcddd48f331eb"
AFTER["RELEASE-NOTES-0.33.0.md"]="a69bd8a2c8b8735e80ee665b632783391b6d46fe08c90628a82d46a9acbee0c4"
AFTER["install_test.go"]="95be5031c0113a39d9026ccd83a0451e54065a0c0d3984a59b2a6a6ee2f9df49"
AFTER["selfusage_test.go"]="0589532be60a3043c32eb0288bd4413cfa50656090ae2facfe586acc00fe5030"
AFTER["syscheck_test.go"]="1e0f3bad8aa0c7ceb942fa3ad9d1c7a959b48374e343f76946e879653c9c6050"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git switch -c feature/windows-tests-and-chmod"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 119 must be in: the workflow tests the System check title.
grep -q 'System check - LLMsControlDock' .github/workflows/build.yml || fail "script 119 (workflow first-start check) is not in; update main first"
# Report it.
pass "script 119 is in"

# Refuse to run twice: the licence line is already in .gitattributes when this change was applied before.
if grep -q '^LICENSE text eol=lf' .gitattributes; then fail ".gitattributes already has the LICENSE line: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_96_END'
diff --git a/.gitattributes b/.gitattributes
index 1a32198..5292e54 100644
--- a/.gitattributes
+++ b/.gitattributes
@@ -9,5 +9,8 @@
 *.sh text eol=lf
 go.mod text eol=lf
 go.sum text eol=lf
+# The licence files have no file extension, so they need their own lines: without them Windows checks them out with CRLF and the licence test fails there.
+LICENSE text eol=lf
+NOTICE text eol=lf
 # Pictures and the built program are binary: never changed.
 *.png binary
diff --git a/README.md b/README.md
index 982ad4f..70ca5f2 100644
--- a/README.md
+++ b/README.md
@@ -29,11 +29,11 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 |---|---|---|
 | Linux arm64 (NVIDIA DGX Spark) | Ollama 0.34.4 | Tested |
 | Windows 11 x64 | Ollama 0.21.2 | Tested on three computers; `-install` not yet tested on Windows |
-| Linux x64, Windows arm64, macOS arm64 and x64 | none | Builds without errors; **not tested** |
+| Linux x64, Windows arm64, macOS arm64 and x64 | none | Start-up check passed on GitHub's test machines; **not used by hand** |
 
 ## Start it
 
-**Download:** each [release](https://github.com/kodati3shrini3/LLMsControlDock-2/releases) has one file per system and a `SHA256SUMS` file. Check the checksum before you run a file. The programs are not code-signed, so Windows SmartScreen may warn (macOS has not been tested). Or build it yourself: you need [Go](https://go.dev/doc/install) (the version named in `go.mod`) only to build, not to run.
+**Download:** each [release](https://github.com/kodati3shrini3/LLMsControlDock-2/releases) has one file per system and a `SHA256SUMS` file. Check the checksum before you run a file. On Linux and macOS, make the file runnable once with `chmod +x` and its file name. The programs are not code-signed, so Windows SmartScreen may warn (macOS has not been tested). Or build it yourself: you need [Go](https://go.dev/doc/install) (the version named in `go.mod`) only to build, not to run.
 
 ```bash
 git clone https://github.com/kodati3shrini3/LLMsControlDock-2.git && cd LLMsControlDock-2
diff --git a/RELEASE-NOTES-0.33.0.md b/RELEASE-NOTES-0.33.0.md
index 2d8464e..5289f07 100644
--- a/RELEASE-NOTES-0.33.0.md
+++ b/RELEASE-NOTES-0.33.0.md
@@ -26,12 +26,12 @@ Each file is one program for one system. Pick the one that matches your computer
 
 | System | File | Tested |
 |---|---|---|
-| Linux, ARM64 (Ubuntu on NVIDIA DGX Spark) | `LLMsControlDock-linux-arm64` | **Yes** |
-| Windows 11, x86-64 | `LLMsControlDock-windows-amd64.exe` | **Yes** (`-install` not yet tested on Windows) |
-| Linux, x86-64 | `LLMsControlDock-linux-amd64` | No, builds without errors |
-| Windows, ARM64 | `LLMsControlDock-windows-arm64.exe` | No, builds without errors |
-| macOS, Apple silicon | `LLMsControlDock-darwin-arm64` | No, builds without errors |
-| macOS, Intel | `LLMsControlDock-darwin-amd64` | No, builds without errors |
+| Linux, ARM64 (Ubuntu on NVIDIA DGX Spark) | `LLMsControlDock-linux-arm64` | **Used by hand**; start-up check on GitHub passed |
+| Windows 11, x86-64 | `LLMsControlDock-windows-amd64.exe` | **Used by hand** (`-install` not yet tested by hand on Windows); start-up check on GitHub passed |
+| Linux, x86-64 | `LLMsControlDock-linux-amd64` | Not used by hand; start-up check on GitHub passed |
+| Windows, ARM64 | `LLMsControlDock-windows-arm64.exe` | Not used by hand; start-up check on GitHub passed |
+| macOS, Apple silicon | `LLMsControlDock-darwin-arm64` | Not used by hand; start-up check on GitHub passed |
+| macOS, Intel | `LLMsControlDock-darwin-amd64` | Not used by hand; start-up check on GitHub passed |
 
 `SHA256SUMS` lists the checksum of every file. Check yours before running it:
 
@@ -47,21 +47,26 @@ sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SU
 
 ## First start
 
-1. Start the program; it prints the address (default `http://127.0.0.1:8765/`) and you open it in your browser.
-2. The System check page opens first. Press **Continue**.
-3. The executables are **not code-signed**. Windows SmartScreen may warn that the publisher is unknown: choose "More info" and "Run anyway" only if the checksum matched. macOS may also block an unsigned program; this has not been tested.
+1. Linux and macOS only: make the file runnable once, for example `chmod +x LLMsControlDock-linux-arm64` (use the name of your file).
+2. Start the program; it prints the address (default `http://127.0.0.1:8765/`) and you open it in your browser.
+3. The System check page opens first. Press **Continue**.
+4. The executables are **not code-signed**. Windows SmartScreen may warn that the publisher is unknown: choose "More info" and "Run anyway" only if the checksum matched. macOS may also block an unsigned program; this has not been tested.
 
 ## Verified so far
 
 - An automated suite of about 490 tests runs on every change.
 - A 39-check smoke and load test and a 54-check functional regression test (every page and button, checked against Ollama's own API) pass on the DGX Spark. These two are developer tools and are not part of the download.
 - Used by hand on Ubuntu ARM64 (DGX Spark) and on Windows 11 x86-64.
+- On 2026-11-13 GitHub built the same Go code on six machines (Linux x86-64 and ARM64, Windows x86-64 and ARM64, macOS Apple silicon and Intel). On each, the program started, answered its first page (the System check), showed version 0.33.0 on the About page and answered the Settings page. No Ollama was installed on these machines. [See the run](https://github.com/kodati3shrini3/LLMsControlDock-2/actions/runs/43384050578).
+- The automated tests passed on Linux x86-64, Linux ARM64 and both macOS systems. On both Windows systems four tests failed (see "Known limits").
+- The files in this release were built on the author's computer. GitHub built the same Go code separately, so its check did not run these exact files.
 
 ## Known limits
 
-- Tested on two systems only (table above). The other four builds compile but have never been run.
+- Used by hand on two systems only (table above). The other four started and answered their pages on GitHub's machines, but nobody has used them with a real Ollama.
+- Four automated tests fail on Windows: `TestGuardedRoot`, `TestRunInstall`, `TestLicenceFilesAgreeWithThePage` and `TestMeasureSelfUsesTheSystemCheck`. Three of them look like tests that assume Linux paths, file permissions or line endings, and the cause of the fourth is not yet confirmed. They will be looked at in a later version.
 - The executables are unsigned (see "First start").
-- `-install` has been tested on Linux only.
+- `-install` has been tested by hand on Linux only.
 - The speed-test limits (for example the 1000 ms response-time limit used in the load test) are the author's own choice, not a standard.
 - Memory use grew from 15 MB to 19 MB over about 14,700 requests in one run. One run cannot show whether that is a leak.
 
diff --git a/install_test.go b/install_test.go
index 687ab0c..37d15f3 100644
--- a/install_test.go
+++ b/install_test.go
@@ -18,6 +18,8 @@ import ( // import lists the standard-library packages this file uses.
 	"os"
 	// path/filepath builds the throw-away paths.
 	"path/filepath"
+	// runtime tells which system the test runs on (Unix file modes are not reported on Windows).
+	"runtime"
 	// strings looks for words in the output and the pages.
 	"strings"
 	// testing is Go's built-in test framework.
@@ -195,8 +197,8 @@ func TestRunInstall(t *testing.T) {
 	for _, p := range []string{configRoot(), dataRoot(), stateRoot()} {
 		// Look.
 		info, err := os.Stat(p)
-		// A folder with 0700.
-		if err != nil || !info.IsDir() || info.Mode().Perm() != 0o700 {
+		// A folder; on Unix with mode 0700 (Windows does not report Unix modes, so only the folder is checked there).
+		if err != nil || !info.IsDir() || (runtime.GOOS != "windows" && info.Mode().Perm() != 0o700) {
 			// Report.
 			t.Errorf("%s: %v %v", p, info, err)
 		} // end of the folder check
@@ -209,7 +211,7 @@ func TestRunInstall(t *testing.T) {
 		t.Errorf("copy: %q %v", got, err)
 	} // end of the bytes check
 	// Runnable.
-	if info, err := os.Stat(r.target); err != nil || info.Mode().Perm()&0o100 == 0 {
+	if info, err := os.Stat(r.target); err != nil || (runtime.GOOS != "windows" && info.Mode().Perm()&0o100 == 0) {
 		// Report.
 		t.Errorf("the copy is not runnable: %v %v", info, err)
 	} // end of the mode check
diff --git a/selfusage_test.go b/selfusage_test.go
index b082929..e651bad 100644
--- a/selfusage_test.go
+++ b/selfusage_test.go
@@ -88,12 +88,23 @@ func TestMeasureSelfUsesTheSystemCheck(t *testing.T) {
 	t.Cleanup(func() { executablePath = oldExe })
 	// Use it.
 	executablePath = func() (string, error) { return exe, nil }
-	// Some saved data.
-	os.WriteFile(filepath.Join(dataRoot(), "x.txt"), []byte("0123456789"), 0o600)
+	// The state folder goes to a throw-away place too, so the real one is never counted (the lookups are put back at the end).
+	stateBase := t.TempDir()
+	userStateDir = func() (string, error) { return stateBase, nil }
+	// The data folder does not exist yet: make it, or the file below cannot be written.
+	if err := os.MkdirAll(dataRoot(), 0o700); err != nil {
+		// Stop.
+		t.Fatalf("data folder: %v", err)
+	} // end of the folder check
+	// Some saved data: 10 bytes.
+	if err := os.WriteFile(filepath.Join(dataRoot(), "x.txt"), []byte("0123456789"), 0o600); err != nil {
+		// Stop.
+		t.Fatalf("data file: %v", err)
+	} // end of the file check
 	// Measure.
 	e := measureSelf(context.Background())
 	// The checks.
-	if e.MachineRAM != 64<<30 || e.RAMBytes != 256<<20 || e.RAMKind != "resident" || len(e.GPUs) != 1 || !strings.Contains(e.GPUs[0], "Test Card") || e.DataBytes < 10 || e.ExeBytes != 7 || e.FreeDisk <= 0 {
+	if e.MachineRAM != 64<<30 || e.RAMBytes != 256<<20 || e.RAMKind != "resident" || len(e.GPUs) != 1 || !strings.Contains(e.GPUs[0], "Test Card") || e.DataBytes != 10 || e.ExeBytes != 7 || e.FreeDisk <= 0 {
 		// Report.
 		t.Errorf("estimate %+v", e)
 	} // end of the checks
diff --git a/syscheck_test.go b/syscheck_test.go
index 4c962fa..0eb96f0 100644
--- a/syscheck_test.go
+++ b/syscheck_test.go
@@ -433,15 +433,19 @@ func TestUninstallSameFolder(t *testing.T) {
 
 // TestGuardedRoot checks that only the program's own folder inside the standard base folder may be deleted.
 func TestGuardedRoot(t *testing.T) {
+	// A real absolute base folder of the running system (a Unix-style path such as /home/ann is not absolute on Windows).
+	base := t.TempDir()
 	// A base folder lookup.
-	look := func() (string, error) { return "/home/ann/.config", nil }
+	look := func() (string, error) { return base, nil }
+	// The path separator of this system, for the paths below that must not be tidied up.
+	sep := string(filepath.Separator)
 	// The good path.
-	if !guardedRoot("/home/ann/.config/"+dataFolderName, look) {
+	if !guardedRoot(filepath.Join(base, dataFolderName), look) {
 		// Report it.
 		t.Errorf("the program's own folder was refused")
 	} // end of the good case
 	// The bad paths.
-	for _, p := range []string{"", "/", "/home/ann", "/home/ann/.config", "/home/ann/.config/Other", "/home/ann/.config/" + dataFolderName + "/sub", "relative/" + dataFolderName, "/home/ann/.config/../" + dataFolderName} {
+	for _, p := range []string{"", sep, filepath.Dir(base), base, filepath.Join(base, "Other"), filepath.Join(base, dataFolderName, "sub"), "relative" + sep + dataFolderName, base + sep + ".." + sep + filepath.Base(base) + sep + dataFolderName} {
 		// Each is refused.
 		if guardedRoot(p, look) {
 			// Report it.
OCC_PATCH_96_END
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
pass "all ${#AFTER[@]} changed files have the expected sha256"

# No unfinished marker may be left in the two documents.
if grep -n -E 'CONFIRM|DRAFT' README.md RELEASE-NOTES-0.33.0.md; then fail "an unfinished marker is left in the lines above"; fi
# Report it.
pass "README and release notes hold no unfinished markers"

# Both documents must carry the chmod line.
grep -q 'chmod +x' README.md && grep -q 'chmod +x LLMsControlDock-linux-arm64' RELEASE-NOTES-0.33.0.md || fail "the chmod line is missing in README.md or RELEASE-NOTES-0.33.0.md"
# Report it.
pass "README and release notes tell Linux and macOS users to run chmod +x"

# The licence files must have their own line-ending rule.
grep -q '^LICENSE text eol=lf' .gitattributes && grep -q '^NOTICE text eol=lf' .gitattributes || fail ".gitattributes lacks the LICENSE or NOTICE line"
# Report it.
pass ".gitattributes keeps LICENSE and NOTICE on LF"

# Only the six expected files may be changed among the files git tracks (no program code).
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED=".gitattributes README.md RELEASE-NOTES-0.33.0.md install_test.go selfusage_test.go syscheck_test.go "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only the six expected files changed (tests, documents, .gitattributes; no program code)"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code (and compiles the tests).
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once; the delete-confirm test failed once without a known cause, so a single failure of exactly that test is reported and not hidden: run the script's step again by hand if it happens.
go test -count=1 ./... || fail "go test failed (if only TestDeleteConfirmRefusesLoadedModel failed, tell Claude)"
# Report it.
pass "go test: all tests pass"

# Compile the program AND its tests (go vet does both) for the Windows and macOS systems, because the fixed tests must at least build there; the real run happens on GitHub.
for TARGET in windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Vet compiles the program and the tests for that system.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go vet ./... || fail "vet (compile of program and tests) for $TARGET failed"
  # Report it.
  pass "program and tests compile for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  commit, push, pull request and merge, then run the six-system check on GitHub (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
