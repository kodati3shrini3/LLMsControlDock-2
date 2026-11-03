// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the sentences of the verdicts.
	"fmt"
	// runtime tells which Go version built this program.
	"runtime"
	// strconv turns the numbers of a version text into numbers.
	"strconv"
	// strings cuts and compares the version texts.
	"strings"
) // end of imports

// minimumOllama is the lowest Ollama version on which EVERY feature of this tool was tested. It is the developer's own testing, not a minimum published by Ollama; lower it only with a new, recorded test.
const minimumOllama = "0.34.4"

// testedGo is the Go version this project is developed and tested with (the DGX Spark). A person who only runs the program does not need Go at all.
const testedGo = "1.27.1"

// testedDate is the date the Windows observations below were made, with the time zone (the rule of this project: every date names its zone).
const testedDate = "3 November 2026, Europe/Brussels"

// ollamaTest is one Ollama version this tool was tested with, and what was seen.
type ollamaTest struct {
	// Version is the Ollama version text, as /api/version reports it.
	Version string
	// Full is true when every feature was tested and worked.
	Full bool
	// Result says what was seen, in plain words.
	Result string
} // end of ollamaTest

// ollamaTests are the Ollama versions this tool was tested with; add a row only after a real test.
var ollamaTests = []ollamaTest{
	// The version the tool was developed on (DGX Spark).
	{Version: "0.34.4", Full: true, Result: "this is the version the tool was developed on."},
	// The version seen on the Windows 11 laptop: the report and the main page worked, three things did not.
	{Version: "0.21.2", Full: false, Result: "on Windows 11 (observed " + testedDate + ") the System check, the main page and the desktop icon worked; the model categories, the Max context length column and the speed test did not. Other features were not tested."},
} // end of ollamaTests

// platformTest says how far one build of the program was tested.
type platformTest struct {
	// OS is the Go operating-system name (linux, windows, darwin).
	OS string
	// Arch is the Go architecture name (amd64, arm64).
	Arch string
	// Label is the name shown to the person.
	Label string
	// Level is "ok" (tested fully) or "info" (tested in part, or not run).
	Level string
	// Text says what was tested.
	Text string
} // end of platformTest

// notRunText is the sentence for a build that was compiled but never started on a real computer of its kind.
const notRunText = "not run by the developer on a real computer of this kind. The program compiles for it; nothing more is claimed."

// platformTests lists the six builds in a fixed order, with what was really tested.
var platformTests = []platformTest{
	// The developer's main machine.
	{OS: "linux", Arch: "arm64", Label: "Linux arm64 (NVIDIA DGX Spark)", Level: "ok", Text: "every feature was tested and worked."},
	// Linux on an Intel or AMD computer.
	{OS: "linux", Arch: "amd64", Label: "Linux x64 (Intel/AMD)", Level: "info", Text: notRunText},
	// Windows on an Intel or AMD computer: tested in part.
	{OS: "windows", Arch: "amd64", Label: "Windows 11 x64 (Intel/AMD)", Level: "info", Text: "tested in part (observed " + testedDate + "): the System check, the main page and the desktop icon worked; the model categories and the speed test did not with Ollama 0.21.2. Other features were not tested. Windows 10 was not tested."},
	// Windows on an ARM computer.
	{OS: "windows", Arch: "arm64", Label: "Windows arm64 (ARM)", Level: "info", Text: notRunText},
	// macOS on Apple silicon.
	{OS: "darwin", Arch: "arm64", Label: "macOS arm64 (Apple silicon)", Level: "info", Text: notRunText},
	// macOS on an Intel Mac.
	{OS: "darwin", Arch: "amd64", Label: "macOS x64 (Intel Mac)", Level: "info", Text: notRunText},
} // end of platformTests

// semver is a version number of the form major.minor.patch, with a flag for a pre-release.
type semver struct {
	// Major, Minor and Patch are the three numbers.
	Major, Minor, Patch int
	// Pre is true for a pre-release such as 0.30.0-rc22.
	Pre bool
} // end of semver

// parseOllamaVersion reads a version text such as 0.34.4, v0.34.4 or 0.30.0-rc22; ok is false when the text is not three numbers separated by dots.
func parseOllamaVersion(text string) (semver, bool) {
	// Spaces around the text do not matter, and a leading "v" is allowed.
	s := strings.TrimPrefix(strings.TrimSpace(text), "v")
	// Nothing to read.
	if s == "" {
		// Not a version.
		return semver{}, false
	} // end of the empty check
	// Build information after a plus sign is ignored (it does not make a pre-release).
	if i := strings.Index(s, "+"); i >= 0 {
		// Cut it off.
		s = s[:i]
	} // end of the build-information cut
	// Is there a pre-release part after a hyphen?
	pre := false
	// Look for the hyphen.
	if i := strings.Index(s, "-"); i >= 0 {
		// The text after it must not be empty.
		if i == len(s)-1 {
			// Not a version.
			return semver{}, false
		} // end of the empty-suffix check
		// A pre-release.
		pre = true
		// Keep only the numbers.
		s = s[:i]
	} // end of the pre-release cut
	// Exactly three parts separated by dots.
	parts := strings.Split(s, ".")
	// Anything else is not read.
	if len(parts) != 3 {
		// Not a version.
		return semver{}, false
	} // end of the count check
	// The three numbers.
	var n [3]int
	// Read each part.
	for i, p := range parts {
		// Only digits, and not too many of them.
		if p == "" || len(p) > 6 {
			// Not a version.
			return semver{}, false
		} // end of the length check
		// Turn the digits into a number.
		v, err := strconv.Atoi(p)
		// A sign or a letter makes it fail; a negative number is never a version.
		if err != nil || v < 0 || strings.ContainsAny(p, "+-") {
			// Not a version.
			return semver{}, false
		} // end of the number check
		// Keep it.
		n[i] = v
	} // end of the part loop
	// Hand back the three numbers.
	return semver{Major: n[0], Minor: n[1], Patch: n[2], Pre: pre}, true
} // end of parseOllamaVersion

// compareVersions returns -1, 0 or 1 when a is lower than, equal to, or higher than b; the numbers are compared as numbers (0.100.0 is higher than 0.34.4), and the pre-release flag is ignored.
func compareVersions(a, b semver) int {
	// Major first.
	if a.Major != b.Major {
		// Lower or higher.
		return cmpInt(a.Major, b.Major)
	} // end of the major check
	// Then minor.
	if a.Minor != b.Minor {
		// Lower or higher.
		return cmpInt(a.Minor, b.Minor)
	} // end of the minor check
	// Then patch.
	return cmpInt(a.Patch, b.Patch)
} // end of compareVersions

// cmpInt returns -1, 0 or 1 for two whole numbers.
func cmpInt(a, b int) int {
	// Lower.
	if a < b {
		// Minus one.
		return -1
	} // end of the lower case
	// Higher.
	if a > b {
		// Plus one.
		return 1
	} // end of the higher case
	// Equal.
	return 0
} // end of cmpInt

// judgeOllamaVersion judges the Ollama version that was found against the versions this tool was tested with; when it is unsure it says so (level "info") and never guesses.
func judgeOllamaVersion(online bool, text string) finding {
	// No answer from Ollama: nothing to judge.
	if !online || strings.TrimSpace(text) == "" {
		// Say so.
		return finding{"info", "Ollama's version is not known (Ollama did not answer), so it is not judged against the versions this tool was tested with."}
	} // end of the offline case
	// Read the version.
	v, ok := parseOllamaVersion(text)
	// Unreadable text: not judged.
	if !ok {
		// Say so, with the text as Ollama gave it.
		return finding{"info", fmt.Sprintf("Ollama reported the version text %q, which this tool cannot read as a version number, so it is not judged.", text)}
	} // end of the unreadable case
	// 0.0.0 is what a development build reports.
	if v.Major == 0 && v.Minor == 0 && v.Patch == 0 {
		// Not judged.
		return finding{"info", "Ollama reports version 0.0.0, which is what a development build reports, so it is not judged against the versions this tool was tested with."}
	} // end of the development case
	// A pre-release is not judged.
	if v.Pre {
		// Not judged.
		return finding{"info", fmt.Sprintf("Ollama %s is a pre-release, so it is not judged. This tool was fully tested on %s.", strings.TrimSpace(text), minimumOllama)}
	} // end of the pre-release case
	// Is it exactly one of the tested versions?
	for _, t := range ollamaTests {
		// The tested version, read the same way.
		tv, tok := parseOllamaVersion(t.Version)
		// A broken table row is skipped (a test makes sure there is none).
		if !tok {
			// Next row.
			continue
		} // end of the table check
		// Same three numbers.
		if compareVersions(v, tv) == 0 {
			// Fully tested.
			if t.Full {
				// Good.
				return finding{"ok", fmt.Sprintf("Ollama %s is a version this tool was tested with: every feature was tested and worked; %s", t.Version, t.Result)}
			} // end of the full case
			// Tested in part: a real warning.
			return finding{"warn", fmt.Sprintf("Ollama %s was tested only in part: %s This tool was fully tested on %s or newer, so some features may not work here.", t.Version, t.Result, minimumOllama)}
		} // end of the same-version check
	} // end of the table loop
	// The lowest fully tested version.
	min, _ := parseOllamaVersion(minimumOllama)
	// Older than that: a warning.
	if compareVersions(v, min) < 0 {
		// Some features may not work.
		return finding{"warn", fmt.Sprintf("Ollama %s is older than %s, the lowest version this tool was fully tested on, and was not tested itself. Some features may not work. A tested older version (0.21.2) did not show the model categories or run the speed test.", strings.TrimSpace(text), minimumOllama)}
	} // end of the older case
	// Newer than anything tested: information, no warning.
	return finding{"info", fmt.Sprintf("Ollama %s is newer than any version this tool was tested with (the highest is %s). No problem is known, but it was not tested with this version.", strings.TrimSpace(text), minimumOllama)}
} // end of judgeOllamaVersion

// judgeGoVersion compares the Go version that built this program with the one the project is developed with; running the program needs no Go at all.
func judgeGoVersion(built string) finding {
	// The Go version as "1.27.1", without the "go" in front.
	num := strings.TrimPrefix(built, "go")
	// The same version.
	if num == testedGo {
		// Good.
		return finding{"ok", fmt.Sprintf("This program was built with %s, the Go version the project is developed and tested with.", built)}
	} // end of the same-version case
	// A different version: information only.
	return finding{"info", fmt.Sprintf("This program was built with %s; the project is developed and tested with Go %s. The program does not need Go to run.", built, testedGo)}
} // end of judgeGoVersion

// judgeSystem says how far the build running here was tested; a combination that is not one of the six is not judged.
func judgeSystem(goos, goarch string) finding {
	// Look for the combination.
	for _, p := range platformTests {
		// Found.
		if p.OS == goos && p.Arch == goarch {
			// The level and the sentence come from the table.
			return finding{p.Level, fmt.Sprintf("This build is %s: %s", p.Label, p.Text)}
		} // end of the match check
	} // end of the loop
	// Not one of the six.
	return finding{"info", fmt.Sprintf("This build (%s/%s) is not one of the six builds this tool lists, so it is not judged.", goos, goarch)}
} // end of judgeSystem

// envLine is one labelled line of the requirements table.
type envLine struct {
	// Label names the item.
	Label string
	// Text says what is known about it.
	Text string
} // end of envLine

// envView is what the System check page shows under "What this tool needs".
type envView struct {
	// MinOllama is the lowest Ollama version on which every feature was tested.
	MinOllama string
	// Tested are the Ollama versions that were tested, with the result of each.
	Tested []envLine
	// Found is the Ollama version found here, or the words "not found".
	Found string
	// OllamaVerdict judges the version found.
	OllamaVerdict finding
	// GoBuilt is the Go version that built this program, as the program reports it.
	GoBuilt string
	// GoTested is the Go version the project is developed and tested with.
	GoTested string
	// GoVerdict compares the two.
	GoVerdict finding
	// Systems are the six builds with what was tested for each.
	Systems []envLine
	// SystemVerdict says how far the build running here was tested.
	SystemVerdict finding
} // end of envView

// goVersionNow is the Go version that built this program; a test replaces it.
var goVersionNow = runtime.Version

// buildEnvView collects everything the requirements section shows.
func buildEnvView(online bool, version, goos, goarch string) envView {
	// The version found, or the words that say none was.
	found := "not found"
	// An answer.
	if online && strings.TrimSpace(version) != "" {
		// Show the text as Ollama gave it.
		found = strings.TrimSpace(version)
	} // end of the found check
	// The tested Ollama versions, one line each.
	var tested []envLine
	// Go through the table.
	for _, t := range ollamaTests {
		// Label it with the version.
		// The words in front say how far the test went.
		lead := "tested in part: "
		// A full test says so.
		if t.Full {
			// Every feature.
			lead = "every feature was tested and worked; "
		} // end of the lead choice
		// The line.
		tested = append(tested, envLine{Label: t.Version, Text: lead + t.Result})
	} // end of the table loop
	// The six builds, one line each.
	var systems []envLine
	// Go through the table.
	for _, p := range platformTests {
		// Label it with the build name.
		systems = append(systems, envLine{Label: p.Label, Text: p.Text})
	} // end of the table loop
	// The Go version of this program.
	built := goVersionNow()
	// Put it together.
	return envView{
		MinOllama: minimumOllama, Tested: tested, Found: found, OllamaVerdict: judgeOllamaVersion(online, version),
		GoBuilt: built, GoTested: testedGo, GoVerdict: judgeGoVersion(built),
		Systems: systems, SystemVerdict: judgeSystem(goos, goarch),
	} // end of the view
} // end of buildEnvView
