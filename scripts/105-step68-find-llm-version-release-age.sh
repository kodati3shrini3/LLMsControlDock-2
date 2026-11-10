#!/usr/bin/env bash
# Script 105 (Find LLM page, version ages): every version now shows how long ago it was updated, copied as ollama.com writes it (for example "updated 1 year ago"; the website gives only rounded words, no exact date), and the versions of each model are listed with the most recently updated first, then the smaller download first (installed versions stay on top; fitting versions stay before the others). A short note on the page says how the ages are written and used. Tests follow.
# Run it from a new branch made from main after scripts 103, 103b and 104 are merged: cd ~/LLMsControlDock && git switch -c feature/find-llm-version-release-age && bash scripts/105-step68-find-llm-version-release-age.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 104), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findsite.go"]="590417e6a96dbb2f7ffa468910287a600a313408ccb1cd1d1bb1e6f45f9f550c"
BEFORE["findsite_test.go"]="699580c6f684ef343f1a621dce0c544fcbb704f290ccef22e80cd3c6804d1bd8"
BEFORE["findllm.go"]="ad2704751ec927dd5e0910393891c8ce152f134a69a9cd982aac165cf426acbb"
BEFORE["web/findllm.html"]="832a170ecfa62cda60cbd212849f732181600569d0d307e967a66446057f1d3b"
AFTER["findsite.go"]="3f126ff34bf89bd4542476a4994882de1f4059b91d4fdddc6850c6e2d88773d4"
AFTER["findsite_test.go"]="84dbe929b657c7519d6506face40dcf6a1a6399052b457cdad4fd5f1bc1b00a7"
AFTER["findllm.go"]="7ed811e335c535db49f1ace663a760f27aab82ad69d77ffdc77b532d2c4505d8"
AFTER["web/findllm.html"]="d6fb199a93721f5b2041f1671af2c2fb554ecfbf8f951017772e260c7d82b5e9"
AFTER["agesort_test.go"]="0c2906155b534c6578056f83a12ff65b1e5146e81298463ae7fa7e861538d5a4"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/find-llm-version-release-age"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 104 must have been applied: the small sort script exists.
[ -f web/sortpick.js ] || fail "script 104 must be applied first"
# Report it.
pass "script 104 is applied"

# Refuse to run twice: the new age reader exists when this change was applied before.
if grep -q 'tagAge' findsite.go; then fail "findsite.go already reads the update age: this script was already applied"; fi
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
diff --git a/agesort_test.go b/agesort_test.go
new file mode 100644
index 0000000..394f15b
--- /dev/null
+++ b/agesort_test.go
@@ -0,0 +1,92 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages the tests use.
+	// net/url builds the form values.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestAgeWordsAreRead checks the update age on a tags page: the words as written and their value in hours, for several units and for "an hour ago"; a block without an age gives -1.
+func TestAgeWordsAreRead(t *testing.T) {
+	// One block per age, in the page's own structure.
+	block := func(tag, age string) string {
+		// The same compact block as the real page, with the age words at the end.
+		return "<a href=\"/library/" + tag + "\" class=\"md:hidden flex flex-col\">\n<span>" + tag + "</span> • 1.0GB • 8K context window • Text input • " + age + "\n</a>\n"
+	} // end of block
+	// The page: three ages and one block with none.
+	page := block("m:a", "3 weeks ago") + block("m:b", "an hour ago") + block("m:c", "1 year ago") + block("m:d", "")
+	// Read it.
+	tags, err := parseSiteTags(page)
+	// It must work.
+	if err != nil || len(tags) != 4 {
+		// Stop.
+		t.Fatalf("parse: %v, %d tags", err, len(tags))
+	} // end of the check
+	// What each must give.
+	want := []struct {
+		age   string
+		hours int64
+	}{{"3 weeks ago", 504}, {"an hour ago", 1}, {"1 year ago", 8760}, {"", -1}}
+	// Compare each.
+	for i, w := range want {
+		// The words and the hours.
+		if tags[i].Age != w.age || tags[i].AgeHours != w.hours {
+			// Report.
+			t.Errorf("tag %d: %q %d, want %q %d", i, tags[i].Age, tags[i].AgeHours, w.age, w.hours)
+		} // end of the check
+	} // end of the loop
+} // end of TestAgeWordsAreRead
+
+// TestVersionsAreSortedByAgeThenSize checks the order of versions: the newest first, then the smaller download; no age or size comes last; equal versions keep the page's order.
+func TestVersionsAreSortedByAgeThenSize(t *testing.T) {
+	// The tags of one model, in a mixed order.
+	tags := []siteTag{
+		{Tag: "m:old-small", SizeBytes: 100, AgeHours: 8760},
+		{Tag: "m:new-big", SizeBytes: 900, AgeHours: 24},
+		{Tag: "m:new-small", SizeBytes: 300, AgeHours: 24},
+		{Tag: "m:noage", SizeBytes: 50, AgeHours: -1},
+		{Tag: "m:old-nosize", SizeBytes: 0, AgeHours: 8760},
+		{Tag: "m:old-small-twin", SizeBytes: 100, AgeHours: 8760},
+	}
+	// Build the view; no limits are set, so every version fits.
+	r := buildResult(siteModel{Name: "m"}, tags, "", findSelection{DiskGB: -1, MemGB: -1}, nil)
+	// The tags in the order shown.
+	var got []string
+	// Each version.
+	for _, v := range r.Versions {
+		// One tag.
+		got = append(got, v.Tag)
+	} // end of the loop
+	// The expected order.
+	want := "m:new-small,m:new-big,m:old-small,m:old-small-twin,m:old-nosize,m:noage"
+	// Compare.
+	if strings.Join(got, ",") != want {
+		// Report.
+		t.Errorf("order %q, want %q", strings.Join(got, ","), want)
+	} // end of the check
+} // end of TestVersionsAreSortedByAgeThenSize
+
+// TestFindPageShowsTheUpdateAge checks that a result page shows "updated 1 year ago" next to a version and explains the ages once.
+func TestFindPageShowsTheUpdateAge(t *testing.T) {
+	// The saved library list goes to a throw-away folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// A search.
+	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// The age is shown, and the note appears exactly once.
+	if !strings.Contains(body, "updated 1 year ago") || strings.Count(body, "not an exact date") != 1 {
+		// Report.
+		t.Error("the results lack the update age or its note")
+	} // end of the check
+} // end of TestFindPageShowsTheUpdateAge
diff --git a/findllm.go b/findllm.go
index 7539e55..49fa958 100644
--- a/findllm.go
+++ b/findllm.go
@@ -723,6 +723,10 @@ type versionView struct {
 	Installed bool
 	// Note is the line shown for an installed version: its saved answer speed with the date of the test, or that it was not tested yet (empty when not installed).
 	Note string
+	// Age is how long ago the version was updated, as ollama.com writes it (empty when not shown).
+	Age string
+	// ageHours and sizeBytes order the versions: newest first, then the smaller one first.
+	ageHours, sizeBytes int64
 	// Icon is the can-be-installed or cannot-be-installed symbol with its tooltip.
 	Icon iconView
 } // end of versionView
@@ -785,6 +789,44 @@ func installedFirst(vs []versionView) []versionView {
 	return append(have, other...)
 } // end of installedFirst
 
+// sortVersions orders versions by update age (newest first) and then by download size (smaller first); a version without an age or size comes after those that have one. The sort is stable, so equal versions keep the page's order.
+func sortVersions(vs []versionView) {
+	// A stable sort.
+	sort.SliceStable(vs, func(i, j int) bool {
+		// The ages; unknown (-1) counts as the oldest.
+		ai, aj := vs[i].ageHours, vs[j].ageHours
+		// Unknown last.
+		if ai < 0 {
+			// Treated as very old.
+			ai = 1 << 60
+		} // end of the first check
+		// Unknown last.
+		if aj < 0 {
+			// Treated as very old.
+			aj = 1 << 60
+		} // end of the second check
+		// The newer one first.
+		if ai != aj {
+			// Decide by age.
+			return ai < aj
+		} // end of the age check
+		// The sizes; unknown (0) counts as the largest.
+		si, sj := vs[i].sizeBytes, vs[j].sizeBytes
+		// Unknown last.
+		if si == 0 {
+			// Treated as very large.
+			si = 1 << 60
+		} // end of the first size check
+		// Unknown last.
+		if sj == 0 {
+			// Treated as very large.
+			sj = 1 << 60
+		} // end of the second size check
+		// The smaller one first.
+		return si < sj
+	}) // end of the sort
+} // end of sortVersions
+
 // installedName makes a model name comparable: Ollama writes a model without a tag as name:latest.
 func installedName(name string) string {
 	// No tag part: it is the latest one.
@@ -869,7 +911,7 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mar
 			continue
 		} // end of the cloud check
 		// Its view.
-		v := versionView{Tag: t.Tag, Command: "ollama pull " + t.Tag, Size: t.SizeText, Context: t.Context, Input: t.Input}
+		v := versionView{Tag: t.Tag, Command: "ollama pull " + t.Tag, Size: t.SizeText, Context: t.Context, Input: t.Input, Age: t.Age, ageHours: t.AgeHours, sizeBytes: t.SizeBytes}
 		// Whether this version is installed here, and what the saved tests say about it.
 		if mark != nil {
 			// Ask the marker.
@@ -906,7 +948,11 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mar
 		// The check mark state.
 		r.State = "fits"
 	} // end of the state choice
-	// The versions that fit first, then the others; inside each group the installed ones come first, then the page's order.
+	// Inside each group: the most recently updated first, then the smaller download first (versions with no age, or no size, come last).
+	sortVersions(fit)
+	// The same for the others.
+	sortVersions(nofit)
+	// The versions that fit first, then the others; inside each group the installed ones come first, then the order above.
 	all := append(installedFirst(fit), installedFirst(nofit)...)
 	// Cut the list.
 	if len(all) > maxFindVersions {
@@ -1016,6 +1062,8 @@ type findPage struct {
 	Summary string
 	// CopyNote says that the list is a saved copy, with its date and why; empty when the list was read live.
 	CopyNote string
+	// AgeNote is true when at least one version shows an update age, so the page explains how the ages are written and used.
+	AgeNote bool
 	// CanResort is true when models are listed, so the Sort by choice re-sorts them at once (the page then carries the small sort script).
 	CanResort bool
 	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
@@ -1188,6 +1236,11 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 					// One more.
 					data.InstalledCount++
 				} // end of the installed count
+				// An update age is shown.
+				if v.Age != "" {
+					// Explain the ages once.
+					data.AgeNote = true
+				} // end of the age check
 				// One that fits is enough.
 				if v.Fits {
 					// Show the buttons.
diff --git a/findsite.go b/findsite.go
index de69046..e806c6d 100644
--- a/findsite.go
+++ b/findsite.go
@@ -71,6 +71,10 @@ type siteTag struct {
 	Context string
 	// Input is what the version accepts, as the page writes it, for example "Text input"; empty when not shown.
 	Input string
+	// Age is how long ago the version was updated, as the page writes it (for example "1 year ago"); empty when not shown. The page gives no exact date.
+	Age string
+	// AgeHours is that age in hours, rounded the way the words are (a month counts as 730 hours, a year as 8760); -1 when no age was shown, so it sorts last.
+	AgeHours int64
 } // end of siteTag
 
 // listSplit cuts the list page at the start of every model entry.
@@ -169,6 +173,38 @@ var tagSize = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB|TB)`)
 // tagContext finds a context length such as 128K or 1M.
 var tagContext = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?[KM]?) context window`)
 
+// tagAge finds the update age such as "1 year ago", "3 weeks ago" or "an hour ago".
+var tagAge = regexp.MustCompile(`\b(\d+|an?) (second|minute|hour|day|week|month|year)s? ago\b`)
+
+// ageHours turns the words of an age into hours, rounded the way the words are; unreadable words give -1.
+func ageHours(count, unit string) int64 {
+	// "a" and "an" mean one.
+	n := int64(1)
+	// A written number.
+	if count != "a" && count != "an" {
+		// Read it; a failure means unreadable.
+		v, err := strconv.ParseInt(count, 10, 64)
+		// Unreadable.
+		if err != nil {
+			// Not known.
+			return -1
+		} // end of the read check
+		// Use it.
+		n = v
+	} // end of the number check
+	// Hours in one unit.
+	per := map[string]int64{"second": 0, "minute": 0, "hour": 1, "day": 24, "week": 168, "month": 730, "year": 8760}
+	// The unit must be known.
+	h, ok := per[unit]
+	// Unknown unit.
+	if !ok {
+		// Not known.
+		return -1
+	} // end of the unit check
+	// The age in hours.
+	return n * h
+} // end of ageHours
+
 // tagInput finds the input kinds such as "Text input" or "Text, Image input".
 var tagInput = regexp.MustCompile(`((?:Text|Image|Audio|Video)(?:, (?:Text|Image|Audio|Video))* input)`)
 
@@ -255,6 +291,15 @@ func parseSiteTags(page string) ([]siteTag, error) {
 			// As written.
 			t.Input = in[1]
 		} // end of the input
+		// The update age, with no age as -1.
+		t.AgeHours = -1
+		// The age words.
+		if a := tagAge.FindStringSubmatch(text); a != nil {
+			// As written.
+			t.Age = a[0]
+			// In hours.
+			t.AgeHours = ageHours(a[1], a[2])
+		} // end of the age
 		// Add the version.
 		out = append(out, t)
 	} // end of the block loop
diff --git a/findsite_test.go b/findsite_test.go
index 6d32892..f07358e 100644
--- a/findsite_test.go
+++ b/findsite_test.go
@@ -116,7 +116,7 @@ func TestParseSiteTagsReadsSizeContextAndInput(t *testing.T) {
 		t.Fatalf("got %d tags, want 3: %+v", len(got), got)
 	} // end of the count check
 	// The first version in full.
-	want0 := siteTag{Tag: "m:1b", SizeText: "3.3GB", SizeBytes: 3300000000, Context: "128K", Input: "Text input"}
+	want0 := siteTag{Tag: "m:1b", SizeText: "3.3GB", SizeBytes: 3300000000, Context: "128K", Input: "Text input", Age: "1 year ago", AgeHours: 8760}
 	// Compare.
 	if got[0] != want0 {
 		// Report.
diff --git a/web/findllm.html b/web/findllm.html
index 075fd3e..daad069 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -103,6 +103,8 @@
 <p class="muted" role="status">{{.Summary}}</p>
 {{/* The installed models could not be read: say so, because then no version is marked. */}}
 {{if .InstalledNote}}<p class="warn" role="status"><strong>&#9888;</strong> {{.InstalledNote}}</p>{{end}}
+{{/* The update ages are copied from ollama.com, which gives only words, no exact date. */}}
+{{if .AgeNote}}<p class="muted"><small>Under each model the versions are listed with the most recently updated first, then the smaller download first (installed versions stay on top). The update age is copied from ollama.com, which gives only rounded words such as "1 year ago", not an exact date; versions with the same words are ordered by size.</small></p>{{end}}
 {{/* Installed versions are marked; this line explains the marks. */}}
 {{if .InstalledCount}}
 <p class="muted">Versions you already have are marked <strong>Installed</strong>, with the answer speed from your saved performance test. Nothing is tested or installed from this page. To compare tested models, use the Compare tested models button on the home page.</p>
@@ -116,7 +118,7 @@
 {{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
 {{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
 <ul class="findversions">
-{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{template "stateicon" .Icon}} {{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
+{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{template "stateicon" .Icon}} {{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Age}} &middot; updated {{.Age}}{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
 {{if .Fits}}
 {{/* The command depends on where Ollama runs; the monitor cannot know that, so Docker and Kubernetes are offered too, folded away until wanted. */}}
 <details class="othercmds"><summary>Docker or Kubernetes</summary>
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
echo "NEXT  start bin/LLMsControlDock and look at the version lines of Find LLM results (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
