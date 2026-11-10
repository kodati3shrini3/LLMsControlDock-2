#!/usr/bin/env bash
# Script 115 (installer wording): two lines of the -install printout read naturally: 'Graphics cards: 1 found: NVIDIA GB10, ...' (no stray ';' after the colon), and 'Settings folder exists already, kept: <path>' instead of 'Keep (it exists already) the settings folder'. Only printed text changes. Tests follow.
# Run it on the branch feature/help-performance-guide, after script 114 (uncommitted is fine): cd ~/LLMsControlDock && bash scripts/115-step78-install-wording.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 114), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["install.go"]="6ac53c7edf87b22e45a939926c0923398bcb7cbdcd7f354ce9c27dc1a204fd3e"
BEFORE["install_test.go"]="bb2824f1bb8dbeca1f4d67004243d76a0c432e4e4ef39ae3cfd54e4c950623ab"
AFTER["install.go"]="d1009796c4ba54fa9627bb92238e43c8a578e017de8622e678d1e19be72e35ec"
AFTER["install_test.go"]="0dba6f79206094a29b5611ca92dd71b614092aff735a3a8656ace957eab619c5"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/help-performance-guide (git switch feature/help-performance-guide)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 114 must have been applied: install.go exists.
[ -e install.go ] || fail "script 114 must be applied first"
# Report it.
pass "script 114 is applied"

# Refuse to run twice: the new joining function is already there when this change was applied before.
if grep -q 'func joinReportLines' install.go; then fail "the wording fix is already in install.go: this script was already applied"; fi
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
diff --git a/install.go b/install.go
index 6cf25ce..1edc06d 100644
--- a/install.go
+++ b/install.go
@@ -248,7 +248,7 @@ func runInstall(e installEnv) int {
 	// Each row of the report.
 	for _, row := range reportRows(rep) {
 		// The label and the value on one line.
-		fmt.Fprintf(w, "  %-22s %s\n", row.Label+":", strings.Join(row.Lines, "; "))
+		fmt.Fprintf(w, "  %-22s %s\n", row.Label+":", joinReportLines(row.Lines))
 	} // end of the row loop
 	// Ollama.
 	if res.Online {
@@ -367,6 +367,30 @@ func runInstall(e installEnv) int {
 	return 0
 } // end of runInstall
 
+// joinReportLines puts the lines of one report row on one line: a line that ends with a colon (such as "1 found:") is followed by a space, every other line by "; ".
+func joinReportLines(lines []string) string {
+	// The line being built.
+	var b strings.Builder
+	// Each line.
+	for i, l := range lines {
+		// Between two lines.
+		if i > 0 {
+			// After a colon, a space; otherwise a semicolon and a space.
+			if strings.HasSuffix(lines[i-1], ":") {
+				// A space.
+				b.WriteString(" ")
+			} else {
+				// A semicolon and a space.
+				b.WriteString("; ")
+			} // end of the separator choice
+		} // end of the separator check
+		// The line itself.
+		b.WriteString(l)
+	} // end of the loop
+	// The joined text.
+	return b.String()
+} // end of joinReportLines
+
 // inPath says whether a folder is one of the folders of a PATH list.
 func inPath(dir, pathList string) bool {
 	// Each folder of the list.
@@ -396,15 +420,15 @@ func installPlan(e installEnv) ([]installStep, error) {
 		} // end of the place check
 		// A copy for the closure below.
 		dir, what := f.dir, f.what
-		// Whether it exists already.
-		state := "create"
-		// It does.
+		// The plan line when the folder is new.
+		plan := fmt.Sprintf("Create the %s folder: %s", what, dir)
+		// It exists already.
 		if _, err := os.Stat(dir); err == nil {
-			// Nothing to create.
-			state = "keep (it exists already)"
+			// Nothing to create; say so.
+			plan = fmt.Sprintf("%s folder exists already, kept: %s", strings.ToUpper(what[:1])+what[1:], dir)
 		} // end of the exists check
 		// The step.
-		steps = append(steps, installStep{Plan: fmt.Sprintf("%s the %s folder: %s", strings.ToUpper(state[:1])+state[1:], what, dir), Do: func() (string, error) {
+		steps = append(steps, installStep{Plan: plan, Do: func() (string, error) {
 			// The same permissions the program uses: the person only.
 			if err := os.MkdirAll(dir, 0o700); err != nil {
 				// Say what failed.
diff --git a/install_test.go b/install_test.go
index a9fafed..687ab0c 100644
--- a/install_test.go
+++ b/install_test.go
@@ -232,6 +232,11 @@ func TestRunInstall(t *testing.T) {
 		// Report.
 		t.Error("the missing desktop was not reported")
 	} // end of the icon check
+	// A second run says the folders exist already, in plain words.
+	if _, out2 := r.run("no\n"); !strings.Contains(out2, "Settings folder exists already, kept: "+configRoot()) || strings.Contains(out2, "Keep (") {
+		// Report.
+		t.Errorf("second run folder lines:\n%s", out2)
+	} // end of the folder wording check
 	// A second run shows both versions before replacing.
 	code, out = r.run("no\n")
 	// The plan names the installed version.
@@ -319,3 +324,28 @@ func TestAboutShowsThePlaces(t *testing.T) {
 		} // end of the look
 	} // end of the loop
 } // end of TestAboutShowsThePlaces
+
+// TestJoinReportLines checks that a report row reads naturally on one line: a space after a colon, "; " between other lines.
+func TestJoinReportLines(t *testing.T) {
+	// The cases.
+	for _, c := range []struct {
+		// The lines and the wanted text.
+		lines []string
+		want  string
+	}{
+		// The graphics card row of the DGX.
+		{[]string{"1 found:", "NVIDIA GB10, compute capability 12.1"}, "1 found: NVIDIA GB10, compute capability 12.1"},
+		// Two plain lines.
+		{[]string{"a", "b"}, "a; b"},
+		// One line.
+		{[]string{"only"}, "only"},
+		// Nothing.
+		{nil, ""},
+	} {
+		// Join.
+		if got := joinReportLines(c.lines); got != c.want {
+			// Report.
+			t.Errorf("joinReportLines(%q) = %q, want %q", c.lines, got, c.want)
+		} // end of the check
+	} // end of the loop
+} // end of TestJoinReportLines
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
echo "NEXT  start bin/LLMsControlDock and run bin/LLMsControlDock -install and answer no (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
