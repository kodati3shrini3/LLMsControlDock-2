#!/usr/bin/env bash
# Script 84 (environment requirements on the System check, version 0.30.0): the System check page now has a section "What this tool needs". It states the lowest Ollama version on which every feature was tested (0.34.4), every Ollama version that was tested with what was seen (0.34.4 fully, 0.21.2 in part), the Go version the program was built with and the one the project is developed with (1.27.1; Go is not needed to run), and how far each of the six builds was tested (Linux arm64 fully, Windows 11 x64 in part, the other four compile only). The Ollama version found on this computer is judged against that list (OK, warning, or "not judged" when the program is unsure). It adds environment.go and environment_test.go and changes about.go (version 0.30.0), syscheck.go (one field and one call) and web/systemcheck.html (the new section and one shared block for the verdict lines). go.mod is NOT touched.
# Run it from the project folder, on a feature branch (never on main): cd ~/OllamaControlCenter && git checkout main && git pull && git checkout -b feature/environment-requirements && bash scripts/84-step48-environment-requirements.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the three files this script changes, BEFORE the change (main after pull request 35).
EXPECT_ABOUT_BEFORE="d3984838cb6901cf819677bc1dab8f86f6f71fc78509664d449faa7205a1f11d"
# syscheck.go before the change.
EXPECT_SYSCHECK_BEFORE="346afec2bcce8a16a813d780a794a544d2d77e528f0fa429d1abd104e2b34a03"
# web/systemcheck.html before the change.
EXPECT_HTML_BEFORE="a0242e2f06adba3feab83ce0484f6c9b749564def96eedc9309b1eec7a19d571"
# The expected sha256 of the five files AFTER the change.
EXPECT_ABOUT_AFTER="da3ee399e59098ef3a22a014690075a1121510e7a1e868731ff8162e4731d4f9"
# syscheck.go after the change.
EXPECT_SYSCHECK_AFTER="4d37370d8c684e4390f4d1d088ebad01882a502aeca575ac4fd5b2dd620b86b2"
# web/systemcheck.html after the change.
EXPECT_HTML_AFTER="bcaffd25b65a6513a08c656eed5b7becb8e11c6f7b878db73e03a1d108b29891"
# environment.go (new) after the change.
EXPECT_ENV_AFTER="5dbdd9ecd92e21a04e2a4c198be12e2bcad97c4f81910632ee316c59899ea305"
# environment_test.go (new) after the change.
EXPECT_ENVTEST_AFTER="4a84ff383d4a9018a7ff54bd81421d79b125fb1c271560bd0199cf282b042a33"

# Count of passed checks, for the summary at the end.
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
# The project must be OllamaControlCenter: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the OllamaControlCenter folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; run: git checkout -b feature/environment-requirements"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Refuse to run twice: the new file already exists when the change was applied before.
[ ! -e environment.go ] || fail "environment.go already exists: this script was already applied on this branch"
# Report it.
pass "environment.go does not exist yet (script not applied before)"

# The files must be exactly the ones the change was made against; otherwise the patch could land in the wrong place.
[ "$(sha about.go)" = "$EXPECT_ABOUT_BEFORE" ] || fail "about.go is not the expected version (sha256 differs); tell Claude which commit you are on"
# syscheck.go.
[ "$(sha syscheck.go)" = "$EXPECT_SYSCHECK_BEFORE" ] || fail "syscheck.go is not the expected version (sha256 differs); tell Claude which commit you are on"
# The page template.
[ "$(sha web/systemcheck.html)" = "$EXPECT_HTML_BEFORE" ] || fail "web/systemcheck.html is not the expected version (sha256 differs); tell Claude which commit you are on"
# Report it.
pass "about.go, syscheck.go and web/systemcheck.html are the expected versions before the change"

# A temporary file for the patch, removed when the script ends (also on an error).
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_84_END'
diff --git a/about.go b/about.go
index 528f6f9..5337711 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.29.1"
+const appVersion = "0.30.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/environment.go b/environment.go
new file mode 100644
index 0000000..c91fca7
--- /dev/null
+++ b/environment.go
@@ -0,0 +1,327 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the sentences of the verdicts.
+	"fmt"
+	// runtime tells which Go version built this program.
+	"runtime"
+	// strconv turns the numbers of a version text into numbers.
+	"strconv"
+	// strings cuts and compares the version texts.
+	"strings"
+) // end of imports
+
+// minimumOllama is the lowest Ollama version on which EVERY feature of this tool was tested. It is the developer's own testing, not a minimum published by Ollama; lower it only with a new, recorded test.
+const minimumOllama = "0.34.4"
+
+// testedGo is the Go version this project is developed and tested with (the DGX Spark). A person who only runs the program does not need Go at all.
+const testedGo = "1.27.1"
+
+// testedDate is the date the Windows observations below were made, with the time zone (the rule of this project: every date names its zone).
+const testedDate = "3 November 2026, Europe/Brussels"
+
+// ollamaTest is one Ollama version this tool was tested with, and what was seen.
+type ollamaTest struct {
+	// Version is the Ollama version text, as /api/version reports it.
+	Version string
+	// Full is true when every feature was tested and worked.
+	Full bool
+	// Result says what was seen, in plain words.
+	Result string
+} // end of ollamaTest
+
+// ollamaTests are the Ollama versions this tool was tested with; add a row only after a real test.
+var ollamaTests = []ollamaTest{
+	// The version the tool was developed on (DGX Spark).
+	{Version: "0.34.4", Full: true, Result: "this is the version the tool was developed on."},
+	// The version seen on the Windows 11 laptop: the report and the main page worked, three things did not.
+	{Version: "0.21.2", Full: false, Result: "on Windows 11 (observed " + testedDate + ") the System check, the main page and the desktop icon worked; the model categories, the Max context length column and the speed test did not. Other features were not tested."},
+} // end of ollamaTests
+
+// platformTest says how far one build of the program was tested.
+type platformTest struct {
+	// OS is the Go operating-system name (linux, windows, darwin).
+	OS string
+	// Arch is the Go architecture name (amd64, arm64).
+	Arch string
+	// Label is the name shown to the person.
+	Label string
+	// Level is "ok" (tested fully) or "info" (tested in part, or not run).
+	Level string
+	// Text says what was tested.
+	Text string
+} // end of platformTest
+
+// notRunText is the sentence for a build that was compiled but never started on a real computer of its kind.
+const notRunText = "not run by the developer on a real computer of this kind. The program compiles for it; nothing more is claimed."
+
+// platformTests lists the six builds in a fixed order, with what was really tested.
+var platformTests = []platformTest{
+	// The developer's main machine.
+	{OS: "linux", Arch: "arm64", Label: "Linux arm64 (NVIDIA DGX Spark)", Level: "ok", Text: "every feature was tested and worked."},
+	// Linux on an Intel or AMD computer.
+	{OS: "linux", Arch: "amd64", Label: "Linux x64 (Intel/AMD)", Level: "info", Text: notRunText},
+	// Windows on an Intel or AMD computer: tested in part.
+	{OS: "windows", Arch: "amd64", Label: "Windows 11 x64 (Intel/AMD)", Level: "info", Text: "tested in part (observed " + testedDate + "): the System check, the main page and the desktop icon worked; the model categories and the speed test did not with Ollama 0.21.2. Other features were not tested. Windows 10 was not tested."},
+	// Windows on an ARM computer.
+	{OS: "windows", Arch: "arm64", Label: "Windows arm64 (ARM)", Level: "info", Text: notRunText},
+	// macOS on Apple silicon.
+	{OS: "darwin", Arch: "arm64", Label: "macOS arm64 (Apple silicon)", Level: "info", Text: notRunText},
+	// macOS on an Intel Mac.
+	{OS: "darwin", Arch: "amd64", Label: "macOS x64 (Intel Mac)", Level: "info", Text: notRunText},
+} // end of platformTests
+
+// semver is a version number of the form major.minor.patch, with a flag for a pre-release.
+type semver struct {
+	// Major, Minor and Patch are the three numbers.
+	Major, Minor, Patch int
+	// Pre is true for a pre-release such as 0.30.0-rc22.
+	Pre bool
+} // end of semver
+
+// parseOllamaVersion reads a version text such as 0.34.4, v0.34.4 or 0.30.0-rc22; ok is false when the text is not three numbers separated by dots.
+func parseOllamaVersion(text string) (semver, bool) {
+	// Spaces around the text do not matter, and a leading "v" is allowed.
+	s := strings.TrimPrefix(strings.TrimSpace(text), "v")
+	// Nothing to read.
+	if s == "" {
+		// Not a version.
+		return semver{}, false
+	} // end of the empty check
+	// Build information after a plus sign is ignored (it does not make a pre-release).
+	if i := strings.Index(s, "+"); i >= 0 {
+		// Cut it off.
+		s = s[:i]
+	} // end of the build-information cut
+	// Is there a pre-release part after a hyphen?
+	pre := false
+	// Look for the hyphen.
+	if i := strings.Index(s, "-"); i >= 0 {
+		// The text after it must not be empty.
+		if i == len(s)-1 {
+			// Not a version.
+			return semver{}, false
+		} // end of the empty-suffix check
+		// A pre-release.
+		pre = true
+		// Keep only the numbers.
+		s = s[:i]
+	} // end of the pre-release cut
+	// Exactly three parts separated by dots.
+	parts := strings.Split(s, ".")
+	// Anything else is not read.
+	if len(parts) != 3 {
+		// Not a version.
+		return semver{}, false
+	} // end of the count check
+	// The three numbers.
+	var n [3]int
+	// Read each part.
+	for i, p := range parts {
+		// Only digits, and not too many of them.
+		if p == "" || len(p) > 6 {
+			// Not a version.
+			return semver{}, false
+		} // end of the length check
+		// Turn the digits into a number.
+		v, err := strconv.Atoi(p)
+		// A sign or a letter makes it fail; a negative number is never a version.
+		if err != nil || v < 0 || strings.ContainsAny(p, "+-") {
+			// Not a version.
+			return semver{}, false
+		} // end of the number check
+		// Keep it.
+		n[i] = v
+	} // end of the part loop
+	// Hand back the three numbers.
+	return semver{Major: n[0], Minor: n[1], Patch: n[2], Pre: pre}, true
+} // end of parseOllamaVersion
+
+// compareVersions returns -1, 0 or 1 when a is lower than, equal to, or higher than b; the numbers are compared as numbers (0.100.0 is higher than 0.34.4), and the pre-release flag is ignored.
+func compareVersions(a, b semver) int {
+	// Major first.
+	if a.Major != b.Major {
+		// Lower or higher.
+		return cmpInt(a.Major, b.Major)
+	} // end of the major check
+	// Then minor.
+	if a.Minor != b.Minor {
+		// Lower or higher.
+		return cmpInt(a.Minor, b.Minor)
+	} // end of the minor check
+	// Then patch.
+	return cmpInt(a.Patch, b.Patch)
+} // end of compareVersions
+
+// cmpInt returns -1, 0 or 1 for two whole numbers.
+func cmpInt(a, b int) int {
+	// Lower.
+	if a < b {
+		// Minus one.
+		return -1
+	} // end of the lower case
+	// Higher.
+	if a > b {
+		// Plus one.
+		return 1
+	} // end of the higher case
+	// Equal.
+	return 0
+} // end of cmpInt
+
+// judgeOllamaVersion judges the Ollama version that was found against the versions this tool was tested with; when it is unsure it says so (level "info") and never guesses.
+func judgeOllamaVersion(online bool, text string) finding {
+	// No answer from Ollama: nothing to judge.
+	if !online || strings.TrimSpace(text) == "" {
+		// Say so.
+		return finding{"info", "Ollama's version is not known (Ollama did not answer), so it is not judged against the versions this tool was tested with."}
+	} // end of the offline case
+	// Read the version.
+	v, ok := parseOllamaVersion(text)
+	// Unreadable text: not judged.
+	if !ok {
+		// Say so, with the text as Ollama gave it.
+		return finding{"info", fmt.Sprintf("Ollama reported the version text %q, which this tool cannot read as a version number, so it is not judged.", text)}
+	} // end of the unreadable case
+	// 0.0.0 is what a development build reports.
+	if v.Major == 0 && v.Minor == 0 && v.Patch == 0 {
+		// Not judged.
+		return finding{"info", "Ollama reports version 0.0.0, which is what a development build reports, so it is not judged against the versions this tool was tested with."}
+	} // end of the development case
+	// A pre-release is not judged.
+	if v.Pre {
+		// Not judged.
+		return finding{"info", fmt.Sprintf("Ollama %s is a pre-release, so it is not judged. This tool was fully tested on %s.", strings.TrimSpace(text), minimumOllama)}
+	} // end of the pre-release case
+	// Is it exactly one of the tested versions?
+	for _, t := range ollamaTests {
+		// The tested version, read the same way.
+		tv, tok := parseOllamaVersion(t.Version)
+		// A broken table row is skipped (a test makes sure there is none).
+		if !tok {
+			// Next row.
+			continue
+		} // end of the table check
+		// Same three numbers.
+		if compareVersions(v, tv) == 0 {
+			// Fully tested.
+			if t.Full {
+				// Good.
+				return finding{"ok", fmt.Sprintf("Ollama %s is a version this tool was tested with: every feature was tested and worked; %s", t.Version, t.Result)}
+			} // end of the full case
+			// Tested in part: a real warning.
+			return finding{"warn", fmt.Sprintf("Ollama %s was tested only in part: %s This tool was fully tested on %s or newer, so some features may not work here.", t.Version, t.Result, minimumOllama)}
+		} // end of the same-version check
+	} // end of the table loop
+	// The lowest fully tested version.
+	min, _ := parseOllamaVersion(minimumOllama)
+	// Older than that: a warning.
+	if compareVersions(v, min) < 0 {
+		// Some features may not work.
+		return finding{"warn", fmt.Sprintf("Ollama %s is older than %s, the lowest version this tool was fully tested on, and was not tested itself. Some features may not work. A tested older version (0.21.2) did not show the model categories or run the speed test.", strings.TrimSpace(text), minimumOllama)}
+	} // end of the older case
+	// Newer than anything tested: information, no warning.
+	return finding{"info", fmt.Sprintf("Ollama %s is newer than any version this tool was tested with (the highest is %s). No problem is known, but it was not tested with this version.", strings.TrimSpace(text), minimumOllama)}
+} // end of judgeOllamaVersion
+
+// judgeGoVersion compares the Go version that built this program with the one the project is developed with; running the program needs no Go at all.
+func judgeGoVersion(built string) finding {
+	// The Go version as "1.27.1", without the "go" in front.
+	num := strings.TrimPrefix(built, "go")
+	// The same version.
+	if num == testedGo {
+		// Good.
+		return finding{"ok", fmt.Sprintf("This program was built with %s, the Go version the project is developed and tested with.", built)}
+	} // end of the same-version case
+	// A different version: information only.
+	return finding{"info", fmt.Sprintf("This program was built with %s; the project is developed and tested with Go %s. The program does not need Go to run.", built, testedGo)}
+} // end of judgeGoVersion
+
+// judgeSystem says how far the build running here was tested; a combination that is not one of the six is not judged.
+func judgeSystem(goos, goarch string) finding {
+	// Look for the combination.
+	for _, p := range platformTests {
+		// Found.
+		if p.OS == goos && p.Arch == goarch {
+			// The level and the sentence come from the table.
+			return finding{p.Level, fmt.Sprintf("This build is %s: %s", p.Label, p.Text)}
+		} // end of the match check
+	} // end of the loop
+	// Not one of the six.
+	return finding{"info", fmt.Sprintf("This build (%s/%s) is not one of the six builds this tool lists, so it is not judged.", goos, goarch)}
+} // end of judgeSystem
+
+// envLine is one labelled line of the requirements table.
+type envLine struct {
+	// Label names the item.
+	Label string
+	// Text says what is known about it.
+	Text string
+} // end of envLine
+
+// envView is what the System check page shows under "What this tool needs".
+type envView struct {
+	// MinOllama is the lowest Ollama version on which every feature was tested.
+	MinOllama string
+	// Tested are the Ollama versions that were tested, with the result of each.
+	Tested []envLine
+	// Found is the Ollama version found here, or the words "not found".
+	Found string
+	// OllamaVerdict judges the version found.
+	OllamaVerdict finding
+	// GoBuilt is the Go version that built this program, as the program reports it.
+	GoBuilt string
+	// GoTested is the Go version the project is developed and tested with.
+	GoTested string
+	// GoVerdict compares the two.
+	GoVerdict finding
+	// Systems are the six builds with what was tested for each.
+	Systems []envLine
+	// SystemVerdict says how far the build running here was tested.
+	SystemVerdict finding
+} // end of envView
+
+// goVersionNow is the Go version that built this program; a test replaces it.
+var goVersionNow = runtime.Version
+
+// buildEnvView collects everything the requirements section shows.
+func buildEnvView(online bool, version, goos, goarch string) envView {
+	// The version found, or the words that say none was.
+	found := "not found"
+	// An answer.
+	if online && strings.TrimSpace(version) != "" {
+		// Show the text as Ollama gave it.
+		found = strings.TrimSpace(version)
+	} // end of the found check
+	// The tested Ollama versions, one line each.
+	var tested []envLine
+	// Go through the table.
+	for _, t := range ollamaTests {
+		// Label it with the version.
+		// The words in front say how far the test went.
+		lead := "tested in part: "
+		// A full test says so.
+		if t.Full {
+			// Every feature.
+			lead = "every feature was tested and worked; "
+		} // end of the lead choice
+		// The line.
+		tested = append(tested, envLine{Label: t.Version, Text: lead + t.Result})
+	} // end of the table loop
+	// The six builds, one line each.
+	var systems []envLine
+	// Go through the table.
+	for _, p := range platformTests {
+		// Label it with the build name.
+		systems = append(systems, envLine{Label: p.Label, Text: p.Text})
+	} // end of the table loop
+	// The Go version of this program.
+	built := goVersionNow()
+	// Put it together.
+	return envView{
+		MinOllama: minimumOllama, Tested: tested, Found: found, OllamaVerdict: judgeOllamaVersion(online, version),
+		GoBuilt: built, GoTested: testedGo, GoVerdict: judgeGoVersion(built),
+		Systems: systems, SystemVerdict: judgeSystem(goos, goarch),
+	} // end of the view
+} // end of buildEnvView
diff --git a/environment_test.go b/environment_test.go
new file mode 100644
index 0000000..dedd93a
--- /dev/null
+++ b/environment_test.go
@@ -0,0 +1,476 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http holds the status codes and the method names.
+	"net/http"
+	// strings searches the page and the sentences.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+	// time gives the fake Ollama handler its time limit.
+	"time"
+) // end of imports
+
+// TestParseOllamaVersion checks how version texts are read, including the odd ones a real Ollama may send.
+func TestParseOllamaVersion(t *testing.T) {
+	// The cases: the text, whether it is a version, and whether it is a pre-release.
+	cases := []struct {
+		name string
+		text string
+		ok   bool
+		pre  bool
+		want semver
+	}{
+		// The ordinary form.
+		{"plain", "0.34.4", true, false, semver{0, 34, 4, false}},
+		// A leading v is allowed.
+		{"leading v", "v0.34.4", true, false, semver{0, 34, 4, false}},
+		// Spaces around it do not matter.
+		{"spaces", "  0.21.2 \n", true, false, semver{0, 21, 2, false}},
+		// A release candidate is a pre-release.
+		{"release candidate", "0.30.0-rc22", true, true, semver{0, 30, 0, true}},
+		// Build information is not a pre-release.
+		{"build info", "0.34.4+abc123", true, false, semver{0, 34, 4, false}},
+		// Big numbers are compared as numbers later.
+		{"three digits", "0.100.0", true, false, semver{0, 100, 0, false}},
+		// Empty text.
+		{"empty", "", false, false, semver{}},
+		// Two parts only.
+		{"two parts", "0.34", false, false, semver{}},
+		// Four parts.
+		{"four parts", "0.34.4.1", false, false, semver{}},
+		// Letters.
+		{"letters", "a.b.c", false, false, semver{}},
+		// A hyphen with nothing after it.
+		{"empty suffix", "0.34.4-", false, false, semver{}},
+		// A sign inside a number.
+		{"signed number", "0.-3.4", false, false, semver{}},
+		// A plus sign inside a number.
+		{"plus number", "0.+3.4", false, false, semver{}},
+		// A number that is far too long.
+		{"too long", "0.1234567.4", false, false, semver{}},
+		// Words.
+		{"words", "unknown", false, false, semver{}},
+	} // end of the cases
+	// Run each case.
+	for _, c := range cases {
+		// A named subtest.
+		t.Run(c.name, func(t *testing.T) {
+			// Read the text.
+			got, ok := parseOllamaVersion(c.text)
+			// The verdict on the text.
+			if ok != c.ok {
+				// Report it.
+				t.Fatalf("parse(%q) ok = %v, want %v", c.text, ok, c.ok)
+			} // end of the ok check
+			// For a version, the numbers and the flag must match.
+			if ok && got != c.want {
+				// Report it.
+				t.Fatalf("parse(%q) = %+v, want %+v", c.text, got, c.want)
+			} // end of the value check
+		}) // end of the subtest
+	} // end of the loop
+} // end of TestParseOllamaVersion
+
+// TestCompareVersionsAsNumbers checks that versions are compared as numbers and not as text.
+func TestCompareVersionsAsNumbers(t *testing.T) {
+	// A helper that reads a version or fails the test.
+	v := func(s string) semver {
+		// Read it.
+		x, ok := parseOllamaVersion(s)
+		// The test data must be valid.
+		if !ok {
+			// Stop.
+			t.Fatalf("bad test version %q", s)
+		} // end of the check
+		// Hand it back.
+		return x
+	} // end of v
+	// The cases: two versions and the expected order.
+	cases := []struct {
+		a, b string
+		want int
+	}{
+		// Text order would say 0.100.0 is lower than 0.34.4.
+		{"0.100.0", "0.34.4", 1},
+		// The tested versions.
+		{"0.21.2", "0.34.4", -1},
+		// Equal.
+		{"0.34.4", "0.34.4", 0},
+		// The patch number decides.
+		{"0.34.5", "0.34.4", 1},
+		// The patch number decides, the other way.
+		{"0.34.3", "0.34.4", -1},
+		// The major number wins over the rest.
+		{"1.0.0", "0.99.99", 1},
+	} // end of the cases
+	// Run each case.
+	for _, c := range cases {
+		// Compare.
+		if got := compareVersions(v(c.a), v(c.b)); got != c.want {
+			// Report it.
+			t.Errorf("compare(%s, %s) = %d, want %d", c.a, c.b, got, c.want)
+		} // end of the check
+	} // end of the loop
+} // end of TestCompareVersionsAsNumbers
+
+// TestJudgeOllamaVersion checks every kind of verdict about the Ollama version that was found.
+func TestJudgeOllamaVersion(t *testing.T) {
+	// The cases: online flag, version text, the expected level, and words that must be in the sentence.
+	cases := []struct {
+		name   string
+		online bool
+		text   string
+		level  string
+		words  []string
+	}{
+		// The fully tested version: good.
+		{"fully tested", true, "0.34.4", "ok", []string{"0.34.4", "was tested with", "every feature"}},
+		// The version seen on Windows: a warning that says what failed.
+		{"tested in part", true, "0.21.2", "warn", []string{"0.21.2", "only in part", "model categories", "speed test", "3 November 2026, Europe/Brussels"}},
+		// An untested older version.
+		{"older, not tested", true, "0.30.0", "warn", []string{"older than 0.34.4", "not tested itself", "Some features may not work"}},
+		// One patch below the minimum.
+		{"one patch older", true, "0.34.3", "warn", []string{"older than 0.34.4"}},
+		// Much older.
+		{"much older", true, "0.5.0", "warn", []string{"older than 0.34.4"}},
+		// A newer patch: information only.
+		{"newer patch", true, "0.34.5", "info", []string{"newer than any version", "No problem is known", "not tested with this version"}},
+		// A newer minor version, with three digits (text order would call it older).
+		{"three digit minor", true, "0.100.0", "info", []string{"newer than any version"}},
+		// A newer major version.
+		{"newer major", true, "1.2.3", "info", []string{"newer than any version"}},
+		// A development build.
+		{"development build", true, "0.0.0", "info", []string{"development build", "not judged"}},
+		// A pre-release of a tested version is not judged.
+		{"pre-release", true, "0.34.4-rc1", "info", []string{"pre-release", "not judged"}},
+		// Text that is not a version.
+		{"unreadable", true, "banana", "info", []string{"cannot read", "not judged", "banana"}},
+		// Ollama did not answer.
+		{"offline", false, "", "info", []string{"not known", "did not answer"}},
+		// Answered but with an empty version.
+		{"empty version", true, "  ", "info", []string{"not known"}},
+	} // end of the cases
+	// Run each case.
+	for _, c := range cases {
+		// A named subtest.
+		t.Run(c.name, func(t *testing.T) {
+			// Judge it.
+			f := judgeOllamaVersion(c.online, c.text)
+			// The level.
+			if f.Level != c.level {
+				// Report it.
+				t.Fatalf("level = %q, want %q (text: %s)", f.Level, c.level, f.Text)
+			} // end of the level check
+			// The words.
+			for _, w := range c.words {
+				// Each must be there.
+				if !strings.Contains(f.Text, w) {
+					// Report it.
+					t.Errorf("sentence lacks %q: %s", w, f.Text)
+				} // end of the word check
+			} // end of the word loop
+		}) // end of the subtest
+	} // end of the loop
+} // end of TestJudgeOllamaVersion
+
+// TestJudgeSystemAllSixBuilds checks the verdict for each of the six builds and for a combination that is not one of them.
+func TestJudgeSystemAllSixBuilds(t *testing.T) {
+	// The cases: system, architecture, level, and words that must be in the sentence.
+	cases := []struct {
+		goos, goarch, level string
+		words               []string
+	}{
+		// The developer's machine: fully tested.
+		{"linux", "arm64", "ok", []string{"Linux arm64 (NVIDIA DGX Spark)", "every feature was tested"}},
+		// The Windows laptop: tested in part.
+		{"windows", "amd64", "info", []string{"Windows 11 x64", "tested in part", "Windows 10 was not tested"}},
+		// The four builds that were only compiled.
+		{"linux", "amd64", "info", []string{"Linux x64", "not run by the developer", "compiles for it"}},
+		// Windows on ARM.
+		{"windows", "arm64", "info", []string{"Windows arm64", "not run by the developer"}},
+		// macOS on Apple silicon.
+		{"darwin", "arm64", "info", []string{"macOS arm64", "not run by the developer"}},
+		// macOS on Intel.
+		{"darwin", "amd64", "info", []string{"macOS x64", "not run by the developer"}},
+		// Something else entirely.
+		{"freebsd", "amd64", "info", []string{"freebsd/amd64", "not one of the six", "not judged"}},
+	} // end of the cases
+	// Run each case.
+	for _, c := range cases {
+		// Judge it.
+		f := judgeSystem(c.goos, c.goarch)
+		// The level.
+		if f.Level != c.level {
+			// Report it.
+			t.Errorf("%s/%s level = %q, want %q", c.goos, c.goarch, f.Level, c.level)
+		} // end of the level check
+		// The words.
+		for _, w := range c.words {
+			// Each must be there.
+			if !strings.Contains(f.Text, w) {
+				// Report it.
+				t.Errorf("%s/%s sentence lacks %q: %s", c.goos, c.goarch, w, f.Text)
+			} // end of the word check
+		} // end of the word loop
+	} // end of the loop
+	// The table has exactly the six builds the project ships.
+	if len(platformTests) != 6 {
+		// Report it.
+		t.Errorf("platformTests has %d rows, want 6", len(platformTests))
+	} // end of the count check
+} // end of TestJudgeSystemAllSixBuilds
+
+// TestJudgeGoVersion checks the verdict about the Go version that built the program.
+func TestJudgeGoVersion(t *testing.T) {
+	// The same version as the project is developed with.
+	if f := judgeGoVersion("go" + testedGo); f.Level != "ok" || !strings.Contains(f.Text, "go"+testedGo) {
+		// Report it.
+		t.Errorf("same version: %+v", f)
+	} // end of the same-version check
+	// A different release.
+	if f := judgeGoVersion("go1.24.7"); f.Level != "info" || !strings.Contains(f.Text, "does not need Go to run") || !strings.Contains(f.Text, testedGo) {
+		// Report it.
+		t.Errorf("different version: %+v", f)
+	} // end of the different-version check
+	// A development build of Go.
+	if f := judgeGoVersion("devel go1.28-abc"); f.Level != "info" {
+		// Report it.
+		t.Errorf("devel build: %+v", f)
+	} // end of the development check
+} // end of TestJudgeGoVersion
+
+// TestEnvironmentTablesAreConsistent checks the data tables themselves, so a typo in them cannot reach the page.
+func TestEnvironmentTablesAreConsistent(t *testing.T) {
+	// The minimum must be a real version.
+	min, ok := parseOllamaVersion(minimumOllama)
+	// It must read.
+	if !ok || min.Pre {
+		// Report it.
+		t.Fatalf("minimumOllama %q is not a plain version", minimumOllama)
+	} // end of the minimum check
+	// The minimum must be listed as fully tested.
+	found := false
+	// Every row must be a plain version.
+	for _, r := range ollamaTests {
+		// Read it.
+		v, ok := parseOllamaVersion(r.Version)
+		// It must read, and not be a pre-release.
+		if !ok || v.Pre {
+			// Report it.
+			t.Errorf("tested version %q is not a plain version", r.Version)
+		} // end of the row check
+		// The minimum row.
+		if r.Version == minimumOllama {
+			// It must be a full test.
+			found = r.Full
+		} // end of the minimum row check
+		// A row that is not a full test must say what did not work or what was not tested.
+		if !r.Full && !strings.Contains(r.Result, "did not") && !strings.Contains(r.Result, "not tested") {
+			// Report it.
+			t.Errorf("partial row %q does not say what failed or what was not tested", r.Version)
+		} // end of the partial check
+		// A tested version below the minimum must not be marked as fully tested.
+		if r.Full && compareVersions(v, min) < 0 {
+			// Report it.
+			t.Errorf("fully tested version %q is below the minimum", r.Version)
+		} // end of the below-minimum check
+	} // end of the row loop
+	// The minimum row must exist.
+	if !found {
+		// Report it.
+		t.Errorf("minimumOllama %q is not listed as a fully tested version", minimumOllama)
+	} // end of the found check
+	// Every date in the tables names its time zone (a standing rule of the project).
+	texts := []string{testedDate}
+	// The Ollama rows.
+	for _, r := range ollamaTests {
+		// Add the text.
+		texts = append(texts, r.Result)
+	} // end of the Ollama loop
+	// The platform rows.
+	for _, p := range platformTests {
+		// Add the text.
+		texts = append(texts, p.Text)
+	} // end of the platform loop
+	// Check each text that contains a month name of this project's dates.
+	for _, s := range texts {
+		// A date such as "3 November 2026" must be followed by the zone.
+		if strings.Contains(s, "November 2026") && !strings.Contains(s, "Europe/Brussels") {
+			// Report it.
+			t.Errorf("a date without its time zone: %q", s)
+		} // end of the zone check
+	} // end of the text loop
+	// The Go version constant must look like a version.
+	if _, ok := parseOllamaVersion(testedGo); !ok {
+		// Report it.
+		t.Errorf("testedGo %q does not look like a version", testedGo)
+	} // end of the Go check
+	// The six builds must be unique.
+	seen := map[string]bool{}
+	// Go through them.
+	for _, p := range platformTests {
+		// The key.
+		k := p.OS + "/" + p.Arch
+		// A repeat is a mistake.
+		if seen[k] {
+			// Report it.
+			t.Errorf("build %s is listed twice", k)
+		} // end of the repeat check
+		// Remember it.
+		seen[k] = true
+	} // end of the loop
+} // end of TestEnvironmentTablesAreConsistent
+
+// envPage opens the System check page against a fake Ollama that reports the given version JSON.
+func envPage(t *testing.T, r *sysRig, versionBody string) string {
+	// Mark this as a helper.
+	t.Helper()
+	// A fake Ollama with that version.
+	srv := fakeOllama(t, replyWith(http.StatusOK, versionBody))
+	// A handler pointing at it, using the rig's monitor and settings.
+	h := newWebHandlerWith(mustResolve(t, srv.URL), time.Second, r.mon)
+	// The page.
+	code, _, body := get(t, h, http.MethodGet, "/systemcheck")
+	// It must open.
+	if code != http.StatusOK {
+		// Stop.
+		t.Fatalf("status = %d", code)
+	} // end of the status check
+	// Hand the page back.
+	return body
+} // end of envPage
+
+// TestSystemCheckShowsRequirements checks the new section on the real page, for several Ollama versions.
+func TestSystemCheckShowsRequirements(t *testing.T) {
+	// The Go version is fixed, so the page text is the same everywhere (the DGX Spark and every other machine).
+	old := goVersionNow
+	// Put it back at the end.
+	t.Cleanup(func() { goVersionNow = old })
+	// The version the project is developed with.
+	goVersionNow = func() string { return "go" + testedGo }
+	// The rig.
+	r := newSysRig(t, false, false)
+	// The parts that every version of the page must show.
+	always := []string{"What this tool needs", "Ollama, minimum version", "Ollama, versions tested", "Ollama, found here", "Systems tested", "Not needed to run this tool", "go" + testedGo, "go.mod", "Linux arm64 (NVIDIA DGX Spark)", "Windows 11 x64", "macOS arm64", "Europe/Brussels", "not a minimum published by Ollama"}
+	// The cases: the fake version reply and the words the verdict must contain.
+	cases := []struct {
+		name  string
+		reply string
+		words []string
+	}{
+		// The developed-on version.
+		{"fully tested", `{"version":"0.34.4"}`, []string{"is a version this tool was tested with"}},
+		// The Windows version.
+		{"tested in part", `{"version":"0.21.2"}`, []string{"was tested only in part"}},
+		// Older and untested.
+		{"older", `{"version":"0.30.0"}`, []string{"is older than 0.34.4"}},
+		// Newer.
+		{"newer", `{"version":"0.40.1"}`, []string{"is newer than any version this tool was tested with"}},
+		// A release candidate.
+		{"pre-release", `{"version":"0.35.0-rc2"}`, []string{"is a pre-release"}},
+		// Not a version.
+		{"unreadable", `{"version":"banana"}`, []string{"cannot read"}},
+	} // end of the cases
+	// Run each case.
+	for _, c := range cases {
+		// A named subtest.
+		t.Run(c.name, func(t *testing.T) {
+			// The page.
+			body := envPage(t, r, c.reply)
+			// The fixed parts.
+			for _, w := range always {
+				// Each must be there.
+				if !strings.Contains(body, w) {
+					// Report it.
+					t.Errorf("missing %q", w)
+				} // end of the check
+			} // end of the fixed loop
+			// The verdict words.
+			for _, w := range c.words {
+				// Each must be there.
+				if !strings.Contains(body, w) {
+					// Report it.
+					t.Errorf("missing verdict %q", w)
+				} // end of the check
+			} // end of the verdict loop
+			// The Go verdict for the same version.
+			if !strings.Contains(body, "the Go version the project is developed and tested with") {
+				// Report it.
+				t.Errorf("missing the Go verdict")
+			} // end of the Go check
+		}) // end of the subtest
+	} // end of the loop
+} // end of TestSystemCheckShowsRequirements
+
+// TestSystemCheckRequirementsWithoutOllama checks the section when Ollama does not answer.
+func TestSystemCheckRequirementsWithoutOllama(t *testing.T) {
+	// The rig.
+	r := newSysRig(t, false, false)
+	// A handler for an address where nothing listens.
+	h := newWebHandlerWith(mustResolve(t, "http://"+closedAddress(t)), time.Second, r.mon)
+	// The page.
+	_, _, body := get(t, h, http.MethodGet, "/systemcheck")
+	// The section is there, the version is "not found", and nothing is judged.
+	for _, want := range []string{"What this tool needs", "Ollama, found here", "not found", "Ollama&#39;s version is not known", "did not answer"} {
+		// Each must be there.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("missing %q", want)
+		} // end of the check
+	} // end of the loop
+} // end of TestSystemCheckRequirementsWithoutOllama
+
+// TestSystemCheckGoVersionOnPage checks that the page shows the Go version the program really reports, and judges a different one.
+func TestSystemCheckGoVersionOnPage(t *testing.T) {
+	// Replace the Go version, and put it back at the end.
+	old := goVersionNow
+	// Restore.
+	t.Cleanup(func() { goVersionNow = old })
+	// A different release.
+	goVersionNow = func() string { return "go1.99.9" }
+	// The rig.
+	r := newSysRig(t, false, false)
+	// The page.
+	body := envPage(t, r, `{"version":"0.34.4"}`)
+	// The page shows the version and the information verdict.
+	for _, want := range []string{"go1.99.9", "does not need Go to run", testedGo} {
+		// Each must be there.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("missing %q", want)
+		} // end of the check
+	} // end of the loop
+} // end of TestSystemCheckGoVersionOnPage
+
+// TestBuildEnvViewFollowsTheTables checks that the view is made from the tables and nothing else.
+func TestBuildEnvViewFollowsTheTables(t *testing.T) {
+	// Build the view for the DGX Spark with a fully tested Ollama.
+	v := buildEnvView(true, "0.34.4", "linux", "arm64")
+	// The minimum.
+	if v.MinOllama != minimumOllama {
+		// Report it.
+		t.Errorf("MinOllama = %q", v.MinOllama)
+	} // end of the minimum check
+	// One line per tested version and per build.
+	if len(v.Tested) != len(ollamaTests) || len(v.Systems) != len(platformTests) {
+		// Report it.
+		t.Errorf("lines: %d tested, %d systems", len(v.Tested), len(v.Systems))
+	} // end of the count check
+	// The found version.
+	if v.Found != "0.34.4" {
+		// Report it.
+		t.Errorf("Found = %q", v.Found)
+	} // end of the found check
+	// Offline: the words "not found".
+	if off := buildEnvView(false, "", "linux", "arm64"); off.Found != "not found" {
+		// Report it.
+		t.Errorf("offline Found = %q", off.Found)
+	} // end of the offline check
+	// The system verdict follows the arguments.
+	if w := buildEnvView(true, "0.34.4", "windows", "amd64"); !strings.Contains(w.SystemVerdict.Text, "Windows 11 x64") {
+		// Report it.
+		t.Errorf("windows verdict: %s", w.SystemVerdict.Text)
+	} // end of the system check
+} // end of TestBuildEnvViewFollowsTheTables
diff --git a/syscheck.go b/syscheck.go
index 9cea680..64ad514 100644
--- a/syscheck.go
+++ b/syscheck.go
@@ -138,6 +138,8 @@ type sysPage struct {
 	Findings []finding
 	// Source names the page the verdicts come from.
 	Source string
+	// Env is the "What this tool needs" section: the Ollama and Go versions it was tested with, and the systems it was tested on.
+	Env envView
 	// Items are the things an uninstall removes.
 	Items []uninstallItem
 	// Program is the full path of the program file the person deletes.
@@ -390,7 +392,7 @@ func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop
 		// Ask Ollama once.
 		res := checkOllama(r.Context(), addr.URL, mon.timeoutOr(defaultCheckTimeout))
 		// Fill in the page.
-		send(w, r, sysPage{Kind: "report", Rows: reportRows(rep), Online: res.Online, Address: addr.URL.Redacted(), Version: res.Version, Reason: res.Reason, Findings: judgeReport(rep), Source: ollamaGPUSource})
+		send(w, r, sysPage{Kind: "report", Rows: reportRows(rep), Online: res.Online, Address: addr.URL.Redacted(), Version: res.Version, Reason: res.Reason, Findings: judgeReport(rep), Source: ollamaGPUSource, Env: buildEnvView(res.Online, res.Version, reportOS, reportArch)})
 	} // end of show
 	// cont: remember the answer and open the monitor.
 	cont = func(w http.ResponseWriter, r *http.Request) {
diff --git a/web/systemcheck.html b/web/systemcheck.html
index d99f13a..9a0e0b9 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -39,12 +39,27 @@
 <p class="warn" role="alert"><strong>&#9888;</strong> Ollama was not found at <code>{{.Address}}</code>. <strong>This tool works with Ollama only.</strong> It does not work with other model servers such as vLLM. Install and start Ollama (ollama.com), or set its address under Settings.</p>
 {{if .Reason}}<p class="muted">{{.Reason}}</p>{{end}}
 {{end}}
+{{/* What this tool needs: the Ollama and Go versions it was tested with, and the systems it was tested on. Dates inside the text name their time zone. */}}
+<h2>What this tool needs</h2>
+<table class="settingtable"><tbody>
+{{/* The lowest Ollama version on which every feature was tested. */}}
+<tr><th scope="row">Ollama, minimum version</th><td><strong>{{.Env.MinOllama}}</strong><br><span class="muted">The lowest version on which every feature of this tool was tested. This is the developer&rsquo;s own testing, not a minimum published by Ollama. Older versions may work in part.</span></td></tr>
+{{/* Every Ollama version that was tested, with what was seen. */}}
+<tr><th scope="row">Ollama, versions tested</th><td>{{range $i, $l := .Env.Tested}}{{if $i}}<br>{{end}}<strong>{{$l.Label}}</strong>: {{$l.Text}}{{end}}</td></tr>
+{{/* The version found on this computer. */}}
+<tr><th scope="row">Ollama, found here</th><td>{{.Env.Found}}</td></tr>
+{{/* Go: not needed to run. */}}
+<tr><th scope="row">Go</th><td>Not needed to run this tool. This program was built with <strong>{{.Env.GoBuilt}}</strong>. The project is developed and tested with Go <strong>{{.Env.GoTested}}</strong>; to build it from source, use the Go version named in the project&rsquo;s <code>go.mod</code> file.</td></tr>
+{{/* The six builds and how far each was tested. */}}
+<tr><th scope="row">Systems tested</th><td>{{range $i, $l := .Env.Systems}}{{if $i}}<br>{{end}}<strong>{{$l.Label}}</strong>: {{$l.Text}}{{end}}</td></tr>
+</tbody></table>
+{{/* The three verdicts: this Ollama version, this Go version, this system. */}}
+{{template "level" .Env.OllamaVerdict}}
+{{template "level" .Env.GoVerdict}}
+{{template "level" .Env.SystemVerdict}}
 <h2>Against Ollama&rsquo;s published minimums</h2>
 {{range .Findings}}
-{{if eq .Level "ok"}}<p class="okline"><span class="symbol" aria-hidden="true">&#10004;</span> {{.Text}}</p>
-{{else if eq .Level "warn"}}<p class="warn"><strong>&#9888;</strong> {{.Text}}</p>
-{{else}}<p class="okline"><span class="symbol" aria-hidden="true">&#8505;</span> {{.Text}}</p>
-{{end}}
+{{template "level" .}}
 {{end}}
 <p class="muted">Source: {{.Source}}. It states no minimum for processor, memory or graphics memory, so these are shown without a verdict. A model larger than the graphics memory runs partly on the processor and is slower. Anything the system did not report is shown as &ldquo;not reported&rdquo; and is never guessed.</p>
 {{/* The two choices side by side, each with its tooltip. */}}
@@ -118,3 +133,8 @@
 </main>
 </body>{{/* end of the visible page. */}}
 </html>{{/* end of the page. */}}
+{{/* The shared block for one verdict line: a level (ok, warn or info) and a sentence. The symbol and the words always appear together, so colour is never the only signal. */}}
+{{define "level"}}{{if eq .Level "ok"}}<p class="okline"><span class="symbol" aria-hidden="true">&#10004;</span> {{.Text}}</p>
+{{else if eq .Level "warn"}}<p class="warn"><strong>&#9888;</strong> {{.Text}}</p>
+{{else}}<p class="okline"><span class="symbol" aria-hidden="true">&#8505;</span> {{.Text}}</p>
+{{end}}{{end}}
OCC_PATCH_84_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
[ "$(sha about.go)" = "$EXPECT_ABOUT_AFTER" ] || fail "about.go has an unexpected sha256 after the change"
# syscheck.go after the change.
[ "$(sha syscheck.go)" = "$EXPECT_SYSCHECK_AFTER" ] || fail "syscheck.go has an unexpected sha256 after the change"
# The page template after the change.
[ "$(sha web/systemcheck.html)" = "$EXPECT_HTML_AFTER" ] || fail "web/systemcheck.html has an unexpected sha256 after the change"
# environment.go after the change.
[ "$(sha environment.go)" = "$EXPECT_ENV_AFTER" ] || fail "environment.go has an unexpected sha256 after the change"
# environment_test.go after the change.
[ "$(sha environment_test.go)" = "$EXPECT_ENVTEST_AFTER" ] || fail "environment_test.go has an unexpected sha256 after the change"
# Report it.
pass "the five changed files have the expected sha256"

# gofmt -l lists files that are not formatted; no output means all are formatted.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once (the new tests use a fixed Go version text, so they give the same result on every machine).
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter . || fail "go build failed"
# Report it.
pass "build for this computer: bin/OllamaControlCenter"

# Compile (without keeping the result) for all six systems, to be sure there is no compile error anywhere; nothing here uses GitHub Actions.
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

# The Go version of this machine: the page shows it in the Go row, and the project is developed with 1.27.1.
GO_NOW="$(go version | cut -d' ' -f3)"
# Say it; this is information, not a pass or fail.
echo "NOTE  Go on this computer: $GO_NOW (the project is developed and tested with go1.27.1; the System check page shows the Go version the program was built with)"

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start the monitor and open http://127.0.0.1:8765/systemcheck, then read the new section \"What this tool needs\" (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
