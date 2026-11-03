// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http holds the status codes and the method names.
	"net/http"
	// strings searches the page and the sentences.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time gives the fake Ollama handler its time limit.
	"time"
) // end of imports

// TestParseOllamaVersion checks how version texts are read, including the odd ones a real Ollama may send.
func TestParseOllamaVersion(t *testing.T) {
	// The cases: the text, whether it is a version, and whether it is a pre-release.
	cases := []struct {
		name string
		text string
		ok   bool
		pre  bool
		want semver
	}{
		// The ordinary form.
		{"plain", "0.34.4", true, false, semver{0, 34, 4, false}},
		// A leading v is allowed.
		{"leading v", "v0.34.4", true, false, semver{0, 34, 4, false}},
		// Spaces around it do not matter.
		{"spaces", "  0.21.2 \n", true, false, semver{0, 21, 2, false}},
		// A release candidate is a pre-release.
		{"release candidate", "0.30.0-rc22", true, true, semver{0, 30, 0, true}},
		// Build information is not a pre-release.
		{"build info", "0.34.4+abc123", true, false, semver{0, 34, 4, false}},
		// Big numbers are compared as numbers later.
		{"three digits", "0.100.0", true, false, semver{0, 100, 0, false}},
		// Empty text.
		{"empty", "", false, false, semver{}},
		// Two parts only.
		{"two parts", "0.34", false, false, semver{}},
		// Four parts.
		{"four parts", "0.34.4.1", false, false, semver{}},
		// Letters.
		{"letters", "a.b.c", false, false, semver{}},
		// A hyphen with nothing after it.
		{"empty suffix", "0.34.4-", false, false, semver{}},
		// A sign inside a number.
		{"signed number", "0.-3.4", false, false, semver{}},
		// A plus sign inside a number.
		{"plus number", "0.+3.4", false, false, semver{}},
		// A number that is far too long.
		{"too long", "0.1234567.4", false, false, semver{}},
		// Words.
		{"words", "unknown", false, false, semver{}},
	} // end of the cases
	// Run each case.
	for _, c := range cases {
		// A named subtest.
		t.Run(c.name, func(t *testing.T) {
			// Read the text.
			got, ok := parseOllamaVersion(c.text)
			// The verdict on the text.
			if ok != c.ok {
				// Report it.
				t.Fatalf("parse(%q) ok = %v, want %v", c.text, ok, c.ok)
			} // end of the ok check
			// For a version, the numbers and the flag must match.
			if ok && got != c.want {
				// Report it.
				t.Fatalf("parse(%q) = %+v, want %+v", c.text, got, c.want)
			} // end of the value check
		}) // end of the subtest
	} // end of the loop
} // end of TestParseOllamaVersion

// TestCompareVersionsAsNumbers checks that versions are compared as numbers and not as text.
func TestCompareVersionsAsNumbers(t *testing.T) {
	// A helper that reads a version or fails the test.
	v := func(s string) semver {
		// Read it.
		x, ok := parseOllamaVersion(s)
		// The test data must be valid.
		if !ok {
			// Stop.
			t.Fatalf("bad test version %q", s)
		} // end of the check
		// Hand it back.
		return x
	} // end of v
	// The cases: two versions and the expected order.
	cases := []struct {
		a, b string
		want int
	}{
		// Text order would say 0.100.0 is lower than 0.34.4.
		{"0.100.0", "0.34.4", 1},
		// The tested versions.
		{"0.21.2", "0.34.4", -1},
		// Equal.
		{"0.34.4", "0.34.4", 0},
		// The patch number decides.
		{"0.34.5", "0.34.4", 1},
		// The patch number decides, the other way.
		{"0.34.3", "0.34.4", -1},
		// The major number wins over the rest.
		{"1.0.0", "0.99.99", 1},
	} // end of the cases
	// Run each case.
	for _, c := range cases {
		// Compare.
		if got := compareVersions(v(c.a), v(c.b)); got != c.want {
			// Report it.
			t.Errorf("compare(%s, %s) = %d, want %d", c.a, c.b, got, c.want)
		} // end of the check
	} // end of the loop
} // end of TestCompareVersionsAsNumbers

// TestJudgeOllamaVersion checks every kind of verdict about the Ollama version that was found.
func TestJudgeOllamaVersion(t *testing.T) {
	// The cases: online flag, version text, the expected level, and words that must be in the sentence.
	cases := []struct {
		name   string
		online bool
		text   string
		level  string
		words  []string
	}{
		// The fully tested version: good.
		{"fully tested", true, "0.34.4", "ok", []string{"0.34.4", "was tested with", "every feature"}},
		// The version seen on Windows: a warning that says what failed.
		{"tested in part", true, "0.21.2", "warn", []string{"0.21.2", "only in part", "model categories", "speed test", "3 November 2026, Europe/Brussels"}},
		// An untested older version.
		{"older, not tested", true, "0.30.0", "warn", []string{"older than 0.34.4", "not tested itself", "Some features may not work"}},
		// One patch below the minimum.
		{"one patch older", true, "0.34.3", "warn", []string{"older than 0.34.4"}},
		// Much older.
		{"much older", true, "0.5.0", "warn", []string{"older than 0.34.4"}},
		// A newer patch: information only.
		{"newer patch", true, "0.34.5", "info", []string{"newer than any version", "No problem is known", "not tested with this version"}},
		// A newer minor version, with three digits (text order would call it older).
		{"three digit minor", true, "0.100.0", "info", []string{"newer than any version"}},
		// A newer major version.
		{"newer major", true, "1.2.3", "info", []string{"newer than any version"}},
		// A development build.
		{"development build", true, "0.0.0", "info", []string{"development build", "not judged"}},
		// A pre-release of a tested version is not judged.
		{"pre-release", true, "0.34.4-rc1", "info", []string{"pre-release", "not judged"}},
		// Text that is not a version.
		{"unreadable", true, "banana", "info", []string{"cannot read", "not judged", "banana"}},
		// Ollama did not answer.
		{"offline", false, "", "info", []string{"not known", "did not answer"}},
		// Answered but with an empty version.
		{"empty version", true, "  ", "info", []string{"not known"}},
	} // end of the cases
	// Run each case.
	for _, c := range cases {
		// A named subtest.
		t.Run(c.name, func(t *testing.T) {
			// Judge it.
			f := judgeOllamaVersion(c.online, c.text)
			// The level.
			if f.Level != c.level {
				// Report it.
				t.Fatalf("level = %q, want %q (text: %s)", f.Level, c.level, f.Text)
			} // end of the level check
			// The words.
			for _, w := range c.words {
				// Each must be there.
				if !strings.Contains(f.Text, w) {
					// Report it.
					t.Errorf("sentence lacks %q: %s", w, f.Text)
				} // end of the word check
			} // end of the word loop
		}) // end of the subtest
	} // end of the loop
} // end of TestJudgeOllamaVersion

// TestJudgeSystemAllSixBuilds checks the verdict for each of the six builds and for a combination that is not one of them.
func TestJudgeSystemAllSixBuilds(t *testing.T) {
	// The cases: system, architecture, level, and words that must be in the sentence.
	cases := []struct {
		goos, goarch, level string
		words               []string
	}{
		// The developer's machine: fully tested.
		{"linux", "arm64", "ok", []string{"Linux arm64 (NVIDIA DGX Spark)", "every feature was tested"}},
		// The Windows laptop: tested in part.
		{"windows", "amd64", "info", []string{"Windows 11 x64", "tested in part", "Windows 10 was not tested"}},
		// The four builds that were only compiled.
		{"linux", "amd64", "info", []string{"Linux x64", "not run by the developer", "compiles for it"}},
		// Windows on ARM.
		{"windows", "arm64", "info", []string{"Windows arm64", "not run by the developer"}},
		// macOS on Apple silicon.
		{"darwin", "arm64", "info", []string{"macOS arm64", "not run by the developer"}},
		// macOS on Intel.
		{"darwin", "amd64", "info", []string{"macOS x64", "not run by the developer"}},
		// Something else entirely.
		{"freebsd", "amd64", "info", []string{"freebsd/amd64", "not one of the six", "not judged"}},
	} // end of the cases
	// Run each case.
	for _, c := range cases {
		// Judge it.
		f := judgeSystem(c.goos, c.goarch)
		// The level.
		if f.Level != c.level {
			// Report it.
			t.Errorf("%s/%s level = %q, want %q", c.goos, c.goarch, f.Level, c.level)
		} // end of the level check
		// The words.
		for _, w := range c.words {
			// Each must be there.
			if !strings.Contains(f.Text, w) {
				// Report it.
				t.Errorf("%s/%s sentence lacks %q: %s", c.goos, c.goarch, w, f.Text)
			} // end of the word check
		} // end of the word loop
	} // end of the loop
	// The table has exactly the six builds the project ships.
	if len(platformTests) != 6 {
		// Report it.
		t.Errorf("platformTests has %d rows, want 6", len(platformTests))
	} // end of the count check
} // end of TestJudgeSystemAllSixBuilds

// TestJudgeGoVersion checks the verdict about the Go version that built the program.
func TestJudgeGoVersion(t *testing.T) {
	// The same version as the project is developed with.
	if f := judgeGoVersion("go" + testedGo); f.Level != "ok" || !strings.Contains(f.Text, "go"+testedGo) {
		// Report it.
		t.Errorf("same version: %+v", f)
	} // end of the same-version check
	// A different release.
	if f := judgeGoVersion("go1.24.7"); f.Level != "info" || !strings.Contains(f.Text, "does not need Go to run") || !strings.Contains(f.Text, testedGo) {
		// Report it.
		t.Errorf("different version: %+v", f)
	} // end of the different-version check
	// A development build of Go.
	if f := judgeGoVersion("devel go1.28-abc"); f.Level != "info" {
		// Report it.
		t.Errorf("devel build: %+v", f)
	} // end of the development check
} // end of TestJudgeGoVersion

// TestEnvironmentTablesAreConsistent checks the data tables themselves, so a typo in them cannot reach the page.
func TestEnvironmentTablesAreConsistent(t *testing.T) {
	// The minimum must be a real version.
	min, ok := parseOllamaVersion(minimumOllama)
	// It must read.
	if !ok || min.Pre {
		// Report it.
		t.Fatalf("minimumOllama %q is not a plain version", minimumOllama)
	} // end of the minimum check
	// The minimum must be listed as fully tested.
	found := false
	// Every row must be a plain version.
	for _, r := range ollamaTests {
		// Read it.
		v, ok := parseOllamaVersion(r.Version)
		// It must read, and not be a pre-release.
		if !ok || v.Pre {
			// Report it.
			t.Errorf("tested version %q is not a plain version", r.Version)
		} // end of the row check
		// The minimum row.
		if r.Version == minimumOllama {
			// It must be a full test.
			found = r.Full
		} // end of the minimum row check
		// A row that is not a full test must say what did not work or what was not tested.
		if !r.Full && !strings.Contains(r.Result, "did not") && !strings.Contains(r.Result, "not tested") {
			// Report it.
			t.Errorf("partial row %q does not say what failed or what was not tested", r.Version)
		} // end of the partial check
		// A tested version below the minimum must not be marked as fully tested.
		if r.Full && compareVersions(v, min) < 0 {
			// Report it.
			t.Errorf("fully tested version %q is below the minimum", r.Version)
		} // end of the below-minimum check
	} // end of the row loop
	// The minimum row must exist.
	if !found {
		// Report it.
		t.Errorf("minimumOllama %q is not listed as a fully tested version", minimumOllama)
	} // end of the found check
	// Every date in the tables names its time zone (a standing rule of the project).
	texts := []string{testedDate}
	// The Ollama rows.
	for _, r := range ollamaTests {
		// Add the text.
		texts = append(texts, r.Result)
	} // end of the Ollama loop
	// The platform rows.
	for _, p := range platformTests {
		// Add the text.
		texts = append(texts, p.Text)
	} // end of the platform loop
	// Check each text that contains a month name of this project's dates.
	for _, s := range texts {
		// A date such as "3 November 2026" must be followed by the zone.
		if strings.Contains(s, "November 2026") && !strings.Contains(s, "Europe/Brussels") {
			// Report it.
			t.Errorf("a date without its time zone: %q", s)
		} // end of the zone check
	} // end of the text loop
	// The Go version constant must look like a version.
	if _, ok := parseOllamaVersion(testedGo); !ok {
		// Report it.
		t.Errorf("testedGo %q does not look like a version", testedGo)
	} // end of the Go check
	// The six builds must be unique.
	seen := map[string]bool{}
	// Go through them.
	for _, p := range platformTests {
		// The key.
		k := p.OS + "/" + p.Arch
		// A repeat is a mistake.
		if seen[k] {
			// Report it.
			t.Errorf("build %s is listed twice", k)
		} // end of the repeat check
		// Remember it.
		seen[k] = true
	} // end of the loop
} // end of TestEnvironmentTablesAreConsistent

// envPage opens the System check page against a fake Ollama that reports the given version JSON.
func envPage(t *testing.T, r *sysRig, versionBody string) string {
	// Mark this as a helper.
	t.Helper()
	// A fake Ollama with that version.
	srv := fakeOllama(t, replyWith(http.StatusOK, versionBody))
	// A handler pointing at it, using the rig's monitor and settings.
	h := newWebHandlerWith(mustResolve(t, srv.URL), time.Second, r.mon)
	// The page.
	code, _, body := get(t, h, http.MethodGet, "/systemcheck")
	// It must open.
	if code != http.StatusOK {
		// Stop.
		t.Fatalf("status = %d", code)
	} // end of the status check
	// Hand the page back.
	return body
} // end of envPage

// TestSystemCheckShowsRequirements checks the new section on the real page, for several Ollama versions.
func TestSystemCheckShowsRequirements(t *testing.T) {
	// The Go version is fixed, so the page text is the same everywhere (the DGX Spark and every other machine).
	old := goVersionNow
	// Put it back at the end.
	t.Cleanup(func() { goVersionNow = old })
	// The version the project is developed with.
	goVersionNow = func() string { return "go" + testedGo }
	// The rig.
	r := newSysRig(t, false, false)
	// The parts that every version of the page must show.
	always := []string{"What this tool needs", "Ollama, minimum version", "Ollama, versions tested", "Ollama, found here", "Systems tested", "Not needed to run this tool", "go" + testedGo, "go.mod", "Linux arm64 (NVIDIA DGX Spark)", "Windows 11 x64", "macOS arm64", "Europe/Brussels", "not a minimum published by Ollama"}
	// The cases: the fake version reply and the words the verdict must contain.
	cases := []struct {
		name  string
		reply string
		words []string
	}{
		// The developed-on version.
		{"fully tested", `{"version":"0.34.4"}`, []string{"is a version this tool was tested with"}},
		// The Windows version.
		{"tested in part", `{"version":"0.21.2"}`, []string{"was tested only in part"}},
		// Older and untested.
		{"older", `{"version":"0.30.0"}`, []string{"is older than 0.34.4"}},
		// Newer.
		{"newer", `{"version":"0.40.1"}`, []string{"is newer than any version this tool was tested with"}},
		// A release candidate.
		{"pre-release", `{"version":"0.35.0-rc2"}`, []string{"is a pre-release"}},
		// Not a version.
		{"unreadable", `{"version":"banana"}`, []string{"cannot read"}},
	} // end of the cases
	// Run each case.
	for _, c := range cases {
		// A named subtest.
		t.Run(c.name, func(t *testing.T) {
			// The page.
			body := envPage(t, r, c.reply)
			// The fixed parts.
			for _, w := range always {
				// Each must be there.
				if !strings.Contains(body, w) {
					// Report it.
					t.Errorf("missing %q", w)
				} // end of the check
			} // end of the fixed loop
			// The verdict words.
			for _, w := range c.words {
				// Each must be there.
				if !strings.Contains(body, w) {
					// Report it.
					t.Errorf("missing verdict %q", w)
				} // end of the check
			} // end of the verdict loop
			// The Go verdict for the same version.
			if !strings.Contains(body, "the Go version the project is developed and tested with") {
				// Report it.
				t.Errorf("missing the Go verdict")
			} // end of the Go check
		}) // end of the subtest
	} // end of the loop
} // end of TestSystemCheckShowsRequirements

// TestSystemCheckRequirementsWithoutOllama checks the section when Ollama does not answer.
func TestSystemCheckRequirementsWithoutOllama(t *testing.T) {
	// The rig.
	r := newSysRig(t, false, false)
	// A handler for an address where nothing listens.
	h := newWebHandlerWith(mustResolve(t, "http://"+closedAddress(t)), time.Second, r.mon)
	// The page.
	_, _, body := get(t, h, http.MethodGet, "/systemcheck")
	// The section is there, the version is "not found", and nothing is judged.
	for _, want := range []string{"What this tool needs", "Ollama, found here", "not found", "Ollama&#39;s version is not known", "did not answer"} {
		// Each must be there.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("missing %q", want)
		} // end of the check
	} // end of the loop
} // end of TestSystemCheckRequirementsWithoutOllama

// TestSystemCheckGoVersionOnPage checks that the page shows the Go version the program really reports, and judges a different one.
func TestSystemCheckGoVersionOnPage(t *testing.T) {
	// Replace the Go version, and put it back at the end.
	old := goVersionNow
	// Restore.
	t.Cleanup(func() { goVersionNow = old })
	// A different release.
	goVersionNow = func() string { return "go1.99.9" }
	// The rig.
	r := newSysRig(t, false, false)
	// The page.
	body := envPage(t, r, `{"version":"0.34.4"}`)
	// The page shows the version and the information verdict.
	for _, want := range []string{"go1.99.9", "does not need Go to run", testedGo} {
		// Each must be there.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("missing %q", want)
		} // end of the check
	} // end of the loop
} // end of TestSystemCheckGoVersionOnPage

// TestBuildEnvViewFollowsTheTables checks that the view is made from the tables and nothing else.
func TestBuildEnvViewFollowsTheTables(t *testing.T) {
	// Build the view for the DGX Spark with a fully tested Ollama.
	v := buildEnvView(true, "0.34.4", "linux", "arm64")
	// The minimum.
	if v.MinOllama != minimumOllama {
		// Report it.
		t.Errorf("MinOllama = %q", v.MinOllama)
	} // end of the minimum check
	// One line per tested version and per build.
	if len(v.Tested) != len(ollamaTests) || len(v.Systems) != len(platformTests) {
		// Report it.
		t.Errorf("lines: %d tested, %d systems", len(v.Tested), len(v.Systems))
	} // end of the count check
	// The found version.
	if v.Found != "0.34.4" {
		// Report it.
		t.Errorf("Found = %q", v.Found)
	} // end of the found check
	// Offline: the words "not found".
	if off := buildEnvView(false, "", "linux", "arm64"); off.Found != "not found" {
		// Report it.
		t.Errorf("offline Found = %q", off.Found)
	} // end of the offline check
	// The system verdict follows the arguments.
	if w := buildEnvView(true, "0.34.4", "windows", "amd64"); !strings.Contains(w.SystemVerdict.Text, "Windows 11 x64") {
		// Report it.
		t.Errorf("windows verdict: %s", w.SystemVerdict.Text)
	} // end of the system check
} // end of TestBuildEnvViewFollowsTheTables
