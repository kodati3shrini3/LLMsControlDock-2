#!/usr/bin/env bash
# Script 92 (Find LLM, slice 2 of 4: the Find LLM page): adds the "Find LLM" button in the top row of the home page and the page behind it. The person ticks what a model must do (chat, tools, pictures, audio, thinking, search), its size class and memory-of-conversation class, and checks the required facts about the computer (free disk space, memory, graphics card; prefilled and editable). Pressing the page's Find LLM button reads the public Ollama library list, drops cloud models, and shows the first ten matching models with their versions, download sizes and the ollama pull command; versions that do not fit are shown with the reason. Nothing is installed. Thirteen new tests (441 in total). The About page and README now say what the page reads from the internet. The version stays 0.31.0 until the Friday release.
# Run it from the project folder, on its own new branch that starts from feature/find-llm-reader (never on main): cd ~/LLMsControlDock && git checkout feature/find-llm-reader && git checkout -b feature/find-llm-page && bash scripts/92-step55-find-llm-page.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by scripts 87 to 91), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["README.md"]="0335fbd87d0a015c2691844daf465322d3c67377cdd6649f47e453dbc2f5e5ed"
BEFORE["web.go"]="54f85e9f3626983f458caf905f1807521ea151d8c1e87c09f519a466b876688c"
BEFORE["web/about.html"]="9488c9da8329839ab0d2c284b20449faf2f7f4bccdaea5a3c32155db8d3fca89"
BEFORE["web/app.css"]="816ac498602498929e6e6b57c760db3e2fcf2b3251b57711332c19743261e923"
BEFORE["web/index.html"]="56f9d711d086a245f776b2d227cab2b4bf0e21240e680aa843458f3e14320035"
AFTER["README.md"]="9b8e58541c8e8c66d3ecdd5a3c1d0e363cde936bdf60da21dc50adfe76f0c43d"
AFTER["diskfree_other.go"]="d1df87bf7f92cde172eb5b0e50799523177fcca7829cd4ca6a068cf49c41b9a4"
AFTER["diskfree_unix.go"]="0dcd33d433156cbb6539f903169b76ee1f685f1c0591098cdb6c1e8c063924c1"
AFTER["diskfree_windows.go"]="fc04ab2598eae78813b4f16f47a376c393c4f694d621d9c425c5d65b3a449171"
AFTER["findllm.go"]="ff6b6ba3d64bbae3a1bc2649fee62f7073830f8e2d0b117448741e2c3f0976f2"
AFTER["findllm_test.go"]="5f4d9880342dbb682516038a8742a5edbc5bffc99b440c3dcf2b868f8a2d15b0"
AFTER["findtips.go"]="3d6793ebaee1c321cbdf8b07ac0b8b1f54652ee765913c1fdf9f42aeba6d9cc6"
AFTER["web.go"]="9ac06158c2ad3b17aaae3cc228f2fe3b77d6d4b617da07961ed67c7251de588b"
AFTER["web/about.html"]="6bfa594538e128089729af1da5b4fe66d96dddbb17447e772fd0145f57d4e8d5"
AFTER["web/app.css"]="b7c3410711fa32b51ecd755112c1cfadf5cd0591c74490b35b1a7a1e61abd484"
AFTER["web/findllm.html"]="e7f5ee9c3c6d22ef96523e089c7d300958ba749adf118276a840fceee3530b7f"
AFTER["web/index.html"]="d9ead188703b0181f48465e949d7bf73e5a88af16b75552b332a3b3eb4a9983d"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git checkout feature/find-llm-reader && git checkout -b feature/find-llm-page"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Slice 1 (script 91) must be in this branch: its files exist.
[ -e findsite.go ] && [ -e findsite_test.go ] || fail "findsite.go is missing: this branch must start from feature/find-llm-reader (script 91)"
# Report it.
pass "slice 1 (script 91, the library reader) is in this branch"

# Refuse to run twice: the new file exists when the change was applied before.
if [ -e findllm.go ]; then fail "findllm.go exists: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_92_END'
diff --git a/README.md b/README.md
index 346e8fc..3ab6f80 100644
--- a/README.md
+++ b/README.md
@@ -19,7 +19,7 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 - The page listens on this computer only (`127.0.0.1:8765`) unless you change that in Settings.
 - Only the program's own page can use the Stop and Unload buttons.
 - No prompt or response text is stored.
-- The only internet requests are a read-only look-up of a model name in the public Ollama library before a delete, and the optional `-check-links` command.
+- The only internet requests are read-only: a look-up of a model name in the public Ollama library before a delete; the public model list and version lists, read when you press Find LLM (your choices are not sent); and the optional `-check-links` command.
 
 ## What is tested
 
diff --git a/diskfree_other.go b/diskfree_other.go
new file mode 100644
index 0000000..31b878d
--- /dev/null
+++ b/diskfree_other.go
@@ -0,0 +1,15 @@
+//go:build !linux && !darwin && !windows
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// errors makes the "not supported" error.
+	"errors"
+) // end of imports
+
+// osFreeDiskBytes reports that this system has no reader; the page then asks the person to type the figure.
+func osFreeDiskBytes(dir string) (uint64, error) {
+	// Not known.
+	return 0, errors.New("free disk space cannot be read on this system")
+} // end of osFreeDiskBytes
diff --git a/diskfree_unix.go b/diskfree_unix.go
new file mode 100644
index 0000000..6cf6415
--- /dev/null
+++ b/diskfree_unix.go
@@ -0,0 +1,22 @@
+//go:build linux || darwin
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// syscall asks the system for the free space of the disk that holds a folder.
+	"syscall"
+) // end of imports
+
+// osFreeDiskBytes returns the free space, in bytes, that a normal program can use on the disk that holds the folder.
+func osFreeDiskBytes(dir string) (uint64, error) {
+	// The system fills this in.
+	var st syscall.Statfs_t
+	// Ask about the folder; a failure is handed back.
+	if err := syscall.Statfs(dir, &st); err != nil {
+		// Not known.
+		return 0, err
+	} // end of the call check
+	// Free blocks for a normal program times the size of a block.
+	return uint64(st.Bavail) * uint64(st.Bsize), nil
+} // end of osFreeDiskBytes
diff --git a/diskfree_windows.go b/diskfree_windows.go
new file mode 100644
index 0000000..81c0573
--- /dev/null
+++ b/diskfree_windows.go
@@ -0,0 +1,36 @@
+//go:build windows
+
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// syscall loads the Windows library function and converts the folder name.
+	"syscall"
+	// unsafe passes the address of a number to the Windows function.
+	"unsafe"
+) // end of imports
+
+// getDiskFreeSpaceEx is the Windows function GetDiskFreeSpaceExW (documented by Microsoft in kernel32), loaded when first used.
+var getDiskFreeSpaceEx = syscall.NewLazyDLL("kernel32.dll").NewProc("GetDiskFreeSpaceExW")
+
+// osFreeDiskBytes returns the free space, in bytes, that the current user can use on the disk that holds the folder.
+func osFreeDiskBytes(dir string) (uint64, error) {
+	// Windows wants the folder name as UTF-16.
+	p, err := syscall.UTF16PtrFromString(dir)
+	// A name with a zero character cannot be converted.
+	if err != nil {
+		// Not known.
+		return 0, err
+	} // end of the name check
+	// The three numbers the function fills in: free for this user, total, and total free.
+	var free, total, totalFree uint64
+	// Call it.
+	r, _, callErr := getDiskFreeSpaceEx.Call(uintptr(unsafe.Pointer(p)), uintptr(unsafe.Pointer(&free)), uintptr(unsafe.Pointer(&total)), uintptr(unsafe.Pointer(&totalFree)))
+	// A zero result means failure.
+	if r == 0 {
+		// Not known.
+		return 0, callErr
+	} // end of the result check
+	// The space this user can use.
+	return free, nil
+} // end of osFreeDiskBytes
diff --git a/findllm.go b/findllm.go
new file mode 100644
index 0000000..0302532
--- /dev/null
+++ b/findllm.go
@@ -0,0 +1,876 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the page in memory first.
+	"bytes"
+	// context limits how long the reads may take.
+	"context"
+	// embed stores the page template inside the program.
+	_ "embed"
+	// fmt builds the number texts.
+	"fmt"
+	// html/template fills the page and escapes every value.
+	"html/template"
+	// log reports a template error.
+	"log"
+	// net/http is the web server.
+	"net/http"
+	// os reads the home folder and one environment variable.
+	"os"
+	// sort orders the results.
+	"sort"
+	// strconv turns typed text into numbers.
+	"strconv"
+	// strings trims and joins text.
+	"strings"
+	// sync runs the tag reads side by side.
+	"sync"
+	// time gives the reading time its zone.
+	"time"
+) // end of imports
+
+// findLLMTemplateText is the Find LLM page, stored inside the executable at build time.
+//
+//go:embed web/findllm.html
+var findLLMTemplateText string
+
+// maxFindResults is how many models get their tags page read and are shown; the most popular come first.
+const maxFindResults = 10
+
+// maxFindVersions is how many versions are listed under one model; the rest are counted.
+const maxFindVersions = 6
+
+// findParallel is how many tags pages are read at the same time.
+const findParallel = 5
+
+// paramClasses are the plain-language size classes, with the biggest number of billions each one holds (the last has no limit).
+var paramClasses = []struct {
+	// Key is the form field name.
+	Key string
+	// Label is the plain word shown.
+	Label string
+	// Range says what it means in numbers.
+	Range string
+	// Max is the largest number of billions in the class; 0 means no limit.
+	Max float64
+}{
+	// Up to one billion.
+	{"tiny", "Tiny", "up to 1 billion", 1},
+	// Over one up to four.
+	{"small", "Small", "over 1 up to 4 billion", 4},
+	// Over four up to fourteen.
+	{"medium", "Medium", "over 4 up to 14 billion", 14},
+	// Over fourteen up to forty.
+	{"large", "Large", "over 14 up to 40 billion", 40},
+	// Over forty.
+	{"huge", "Very large", "over 40 billion", 0},
+} // end of paramClasses
+
+// contextClasses are the plain-language classes for how much a model can remember of a conversation, with the biggest length in thousands each one holds (the last has no limit).
+var contextClasses = []struct {
+	// Key is the form field name.
+	Key string
+	// Label is the plain word shown.
+	Label string
+	// Range says what it means in numbers.
+	Range string
+	// Max is the largest length in thousands in the class; 0 means no limit.
+	Max float64
+}{
+	// Under eight thousand.
+	{"short", "Short", "under 8K", 7.999},
+	// Eight up to thirty-two thousand.
+	{"medium", "Medium", "8K to 32K", 32},
+	// Over thirty-two up to one hundred twenty-eight.
+	{"long", "Long", "over 32K to 128K", 128},
+	// Over one hundred twenty-eight.
+	{"verylong", "Very long", "over 128K", 0},
+} // end of contextClasses
+
+// paramsBillions turns a size label such as 0.6b, 350m or e4b into billions; ok is false for a label it cannot read.
+func paramsBillions(label string) (float64, bool) {
+	// An effective-size label such as e4b counts as its number.
+	l := strings.TrimPrefix(strings.ToLower(label), "e")
+	// The last letter is the unit.
+	if len(l) < 2 {
+		// Too short to read.
+		return 0, false
+	} // end of the length check
+	// The number part.
+	n, err := strconv.ParseFloat(l[:len(l)-1], 64)
+	// Not a number.
+	if err != nil {
+		// Unknown.
+		return 0, false
+	} // end of the number check
+	// Choose by unit.
+	switch l[len(l)-1] {
+	// Billions.
+	case 'b':
+		// As it is.
+		return n, true
+	// Millions.
+	case 'm':
+		// A thousandth of a billion.
+		return n / 1000, true
+	} // end of the unit switch
+	// Unknown unit.
+	return 0, false
+} // end of paramsBillions
+
+// paramClassOf returns the key of the size class of a number of billions.
+func paramClassOf(b float64) string {
+	// The first class that is large enough.
+	for _, c := range paramClasses {
+		// A class without a limit takes everything left.
+		if c.Max == 0 || b <= c.Max {
+			// Found it.
+			return c.Key
+		} // end of the limit check
+	} // end of the class loop
+	// Not reached: the last class has no limit.
+	return "huge"
+} // end of paramClassOf
+
+// contextThousands turns a context text such as 128K, 40K or 1M into thousands of tokens; ok is false for text it cannot read.
+func contextThousands(text string) (float64, bool) {
+	// Nothing shown on the page.
+	if text == "" {
+		// Unknown.
+		return 0, false
+	} // end of the empty check
+	// The unit is the last letter, the number is the rest.
+	unit := text[len(text)-1]
+	// The number part.
+	n, err := strconv.ParseFloat(text[:len(text)-1], 64)
+	// Not a number.
+	if err != nil {
+		// Unknown.
+		return 0, false
+	} // end of the number check
+	// Choose by unit.
+	switch unit {
+	// Thousands.
+	case 'K', 'k':
+		// As it is.
+		return n, true
+	// Millions count as a thousand thousands.
+	case 'M', 'm':
+		// Thousands of tokens.
+		return n * 1000, true
+	} // end of the unit switch
+	// Unknown unit.
+	return 0, false
+} // end of contextThousands
+
+// contextClassOf returns the key of the class of a number of thousands.
+func contextClassOf(k float64) string {
+	// The first class that is large enough.
+	for _, c := range contextClasses {
+		// A class without a limit takes everything left.
+		if c.Max == 0 || k <= c.Max {
+			// Found it.
+			return c.Key
+		} // end of the limit check
+	} // end of the class loop
+	// Not reached: the last class has no limit.
+	return "verylong"
+} // end of contextClassOf
+
+// pullsNumber turns a download count such as 120.9M, 3.4K or 87 into a number, for sorting; unreadable text counts as 0.
+func pullsNumber(text string) float64 {
+	// Nothing.
+	if text == "" {
+		// Zero.
+		return 0
+	} // end of the empty check
+	// The multiplier for the last letter.
+	mult := 1.0
+	// The number part starts as the whole text.
+	num := text
+	// Choose by unit.
+	switch text[len(text)-1] {
+	// Thousands.
+	case 'K':
+		// A thousand.
+		mult, num = 1e3, text[:len(text)-1]
+	// Millions.
+	case 'M':
+		// A million.
+		mult, num = 1e6, text[:len(text)-1]
+	// Billions.
+	case 'B':
+		// A billion.
+		mult, num = 1e9, text[:len(text)-1]
+	} // end of the unit switch
+	// Read the number.
+	f, err := strconv.ParseFloat(num, 64)
+	// Unreadable.
+	if err != nil {
+		// Zero.
+		return 0
+	} // end of the number check
+	// The value.
+	return f * mult
+} // end of pullsNumber
+
+// findSelection is what the person chose on the page.
+type findSelection struct {
+	// Chat is true when "Chat and writing" is ticked: the model is not a search-and-similarity model.
+	Chat bool
+	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding); a model must have all of them.
+	Abilities map[string]bool
+	// Sizes are the ticked size classes (empty means any size).
+	Sizes map[string]bool
+	// Contexts are the ticked memory classes (empty means any).
+	Contexts map[string]bool
+	// DiskGB is the free disk space in gigabytes; negative means not known.
+	DiskGB float64
+	// MemGB is the memory in gigabytes; negative means not known.
+	MemGB float64
+} // end of findSelection
+
+// abilityKeys are the ability tick boxes, in the order shown; each is also the label the library list page uses.
+var abilityKeys = []string{"tools", "vision", "audio", "thinking", "embedding"}
+
+// parseGB reads a typed number of gigabytes; empty text means "not known" (-1); a bad or absurd number is an error.
+func parseGB(text string) (float64, error) {
+	// Trim spaces and allow a decimal comma.
+	t := strings.ReplaceAll(strings.TrimSpace(text), ",", ".")
+	// Empty: not known.
+	if t == "" {
+		// Not known.
+		return -1, nil
+	} // end of the empty check
+	// Read it.
+	f, err := strconv.ParseFloat(t, 64)
+	// Not a number, or outside a sensible range.
+	if err != nil || f < 0 || f > 100000 {
+		// Refuse.
+		return 0, fmt.Errorf("%q is not a number between 0 and 100000", strings.TrimSpace(text))
+	} // end of the number check
+	// A good number.
+	return f, nil
+} // end of parseGB
+
+// parseFindForm reads the form fields into a selection; problems lists what was typed wrongly.
+func parseFindForm(get func(string) string) (findSelection, []string) {
+	// Start empty.
+	sel := findSelection{Abilities: map[string]bool{}, Sizes: map[string]bool{}, Contexts: map[string]bool{}}
+	// The problems found.
+	var problems []string
+	// Chat and writing.
+	sel.Chat = get("ab_chat") == "on"
+	// Each ability.
+	for _, k := range abilityKeys {
+		// Ticked.
+		if get("ab_"+k) == "on" {
+			// Keep it.
+			sel.Abilities[k] = true
+		} // end of the tick check
+	} // end of the ability loop
+	// Each size class.
+	for _, c := range paramClasses {
+		// Ticked.
+		if get("sz_"+c.Key) == "on" {
+			// Keep it.
+			sel.Sizes[c.Key] = true
+		} // end of the tick check
+	} // end of the size loop
+	// Each memory class.
+	for _, c := range contextClasses {
+		// Ticked.
+		if get("cx_"+c.Key) == "on" {
+			// Keep it.
+			sel.Contexts[c.Key] = true
+		} // end of the tick check
+	} // end of the context loop
+	// The disk figure.
+	d, err := parseGB(get("disk_gb"))
+	// A bad figure.
+	if err != nil {
+		// Say which.
+		problems = append(problems, "Free disk space: "+err.Error())
+	} // end of the disk check
+	// Keep it.
+	sel.DiskGB = d
+	// The memory figure.
+	m, err := parseGB(get("mem_gb"))
+	// A bad figure.
+	if err != nil {
+		// Say which.
+		problems = append(problems, "Memory: "+err.Error())
+	} // end of the memory check
+	// Keep it.
+	sel.MemGB = m
+	// The result.
+	return sel, problems
+} // end of parseFindForm
+
+// findCandidates applies the choices that the list page can answer: cloud models are left out, abilities and size classes are checked; the count of models without a readable size is returned when a size class is chosen.
+func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noSize int, cloud int) {
+	// Look at every model.
+	for _, m := range models {
+		// Cloud models run on Ollama's servers, not on this computer, and may need an account.
+		if m.Cloud {
+			// Count and skip.
+			cloud++
+			// Next.
+			continue
+		} // end of the cloud check
+		// The model's abilities as a set.
+		has := map[string]bool{}
+		// Fill it.
+		for _, a := range m.Abilities {
+			// One ability.
+			has[a] = true
+		} // end of the fill
+		// Chat and writing: not a search-and-similarity model.
+		if sel.Chat && has["embedding"] {
+			// Skip.
+			continue
+		} // end of the chat check
+		// Every ticked ability must be present.
+		ok := true
+		// Check each.
+		for a := range sel.Abilities {
+			// Missing one.
+			if !has[a] {
+				// Not this model.
+				ok = false
+			} // end of the check
+		} // end of the ability loop
+		// Skip a model that lacks one.
+		if !ok {
+			// Next.
+			continue
+		} // end of the skip
+		// Size classes: at least one of the model's sizes must be in a ticked class.
+		if len(sel.Sizes) > 0 {
+			// Whether any size matches, and whether any size could be read.
+			match, readable := false, false
+			// Check each size label.
+			for _, s := range m.Sizes {
+				// Read it.
+				if b, ok := paramsBillions(s); ok {
+					// At least one size is readable.
+					readable = true
+					// In a ticked class.
+					if sel.Sizes[paramClassOf(b)] {
+						// A match.
+						match = true
+					} // end of the class check
+				} // end of the read check
+			} // end of the size loop
+			// No readable size: count it, and leave the model out of a size search.
+			if !readable {
+				// Count it.
+				noSize++
+				// Next.
+				continue
+			} // end of the readable check
+			// No matching size.
+			if !match {
+				// Next.
+				continue
+			} // end of the match check
+		} // end of the size filter
+		// It passed.
+		out = append(out, m)
+	} // end of the model loop
+	// Most downloaded first; equal counts keep the name order, so the list is stable.
+	sort.SliceStable(out, func(i, j int) bool {
+		// Compare the download counts.
+		pi, pj := pullsNumber(out[i].Pulls), pullsNumber(out[j].Pulls)
+		// The higher count first.
+		if pi != pj {
+			// Decide by count.
+			return pi > pj
+		} // end of the count check
+		// Then by name.
+		return out[i].Name < out[j].Name
+	}) // end of the sort
+	// The result.
+	return out, noSize, cloud
+} // end of findCandidates
+
+// versionReason says why a version does not fit this computer; empty text means it fits.
+func versionReason(t siteTag, sel findSelection) string {
+	// The size in gigabytes (decimal), when the page showed one.
+	gb := float64(t.SizeBytes) / 1e9
+	// Disk space.
+	if sel.DiskGB >= 0 && t.SizeBytes > 0 && gb > sel.DiskGB {
+		// Too big for the disk.
+		return fmt.Sprintf("needs %s of disk space; you have %s free", findGBText(gb), findGBText(sel.DiskGB))
+	} // end of the disk check
+	// Memory: a model larger than all the memory cannot be loaded completely.
+	if sel.MemGB >= 0 && t.SizeBytes > 0 && gb > sel.MemGB {
+		// Too big for the memory.
+		return fmt.Sprintf("needs about %s of memory; you have %s", findGBText(gb), findGBText(sel.MemGB))
+	} // end of the memory check
+	// Memory-of-conversation classes.
+	if len(sel.Contexts) > 0 {
+		// Read the context length.
+		k, ok := contextThousands(t.Context)
+		// Unknown length: leave the version out of a context search.
+		if !ok {
+			// Say so.
+			return "the page does not show its context length"
+		} // end of the readable check
+		// Not in a ticked class.
+		if !sel.Contexts[contextClassOf(k)] {
+			// Say so.
+			return "its context length (" + t.Context + ") is not in the classes you ticked"
+		} // end of the class check
+	} // end of the context check
+	// It fits.
+	return ""
+} // end of versionReason
+
+// findGBText writes a number of gigabytes for a person.
+func findGBText(gb float64) string {
+	// One decimal, and the unit.
+	return strconv.FormatFloat(gb, 'f', 1, 64) + " GB"
+} // end of findGBText
+
+// versionView is one version as the page shows it.
+type versionView struct {
+	// Tag is the full name to download.
+	Tag string
+	// Command is the command that downloads it.
+	Command string
+	// Size is the download size as the page writes it.
+	Size string
+	// Context is the context length as the page writes it.
+	Context string
+	// Input is what it accepts.
+	Input string
+	// Fits is true when it fits this computer and the ticked classes.
+	Fits bool
+	// Reason says why it does not fit.
+	Reason string
+} // end of versionView
+
+// resultView is one model as the page shows it.
+type resultView struct {
+	// Name is the library name.
+	Name string
+	// Description is the one-line description.
+	Description string
+	// Abilities and Sizes are the labels shown.
+	Abilities, Sizes string
+	// Pulls is the download count as written on the page.
+	Pulls string
+	// URL is the official model page.
+	URL string
+	// Versions are the versions listed (the ones that fit first).
+	Versions []versionView
+	// More counts the versions not listed.
+	More int
+	// FitCount is how many versions fit.
+	FitCount int
+	// Unavailable says the tags page could not be read (empty when it was).
+	Unavailable string
+} // end of resultView
+
+// buildResult turns a model and its versions into the view; tags is nil when the tags page could not be read, and why says what went wrong.
+func buildResult(m siteModel, tags []siteTag, why string, sel findSelection) resultView {
+	// The basic facts.
+	r := resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Sizes: strings.Join(m.Sizes, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name}
+	// The tags page could not be read: say so, never guess.
+	if tags == nil {
+		// The reason.
+		r.Unavailable = "details are not available right now (" + why + ")"
+		// Done.
+		return r
+	} // end of the unavailable case
+	// Judge every version.
+	var fit, nofit []versionView
+	// Look at each.
+	for _, t := range tags {
+		// Its view.
+		v := versionView{Tag: t.Tag, Command: "ollama pull " + t.Tag, Size: t.SizeText, Context: t.Context, Input: t.Input}
+		// Why it does not fit, if it does not.
+		v.Reason = versionReason(t, sel)
+		// Fits when there is no reason.
+		v.Fits = v.Reason == ""
+		// Sort into the two lists.
+		if v.Fits {
+			// Fits.
+			fit = append(fit, v)
+		} else {
+			// Does not fit.
+			nofit = append(nofit, v)
+		} // end of the sorting
+	} // end of the version loop
+	// The count that fit.
+	r.FitCount = len(fit)
+	// The versions that fit first, then the others; the order inside each is the page's order.
+	all := append(fit, nofit...)
+	// Cut the list.
+	if len(all) > maxFindVersions {
+		// Count the rest.
+		r.More = len(all) - maxFindVersions
+		// Keep the first ones.
+		all = all[:maxFindVersions]
+	} // end of the cut
+	// Keep them.
+	r.Versions = all
+	// The finished view.
+	return r
+} // end of buildResult
+
+// findMachine is what this computer says about itself, for the prefilled fields.
+type findMachine struct {
+	// DiskGB is the free disk space in gigabytes, or -1 when not known.
+	DiskGB float64
+	// DiskWhere is the folder the figure was taken from.
+	DiskWhere string
+	// MemGB is the total memory in gigabytes, or -1 when not known.
+	MemGB float64
+	// GPU is the graphics card name, or empty when none was found.
+	GPU string
+	// Remote is true when Ollama runs on another computer, so none of these figures describe it.
+	Remote bool
+} // end of findMachine
+
+// readFindMachine reads the machine facts; for Ollama on another computer it reports only that.
+func readFindMachine(ctx context.Context, local bool) findMachine {
+	// Start with "not known".
+	fm := findMachine{DiskGB: -1, MemGB: -1, Remote: !local}
+	// Another computer: these figures would describe the wrong one.
+	if !local {
+		// Stop.
+		return fm
+	} // end of the remote case
+	// The memory and the graphics card come from the same reading the monitor uses.
+	snap := snapshotMachine(ctx, true)
+	// Memory.
+	if snap.MemTotalGB > 0 {
+		// Keep it.
+		fm.MemGB = snap.MemTotalGB
+	} // end of the memory check
+	// The graphics card.
+	fm.GPU = snap.GPUName
+	// The folder whose disk matters: the model folder when it is set, otherwise the home folder.
+	where := os.Getenv("OLLAMA_MODELS")
+	// Not set or not there: the home folder.
+	if st, err := os.Stat(where); where == "" || err != nil || !st.IsDir() {
+		// The home folder.
+		where, _ = os.UserHomeDir()
+	} // end of the folder choice
+	// Read the free space.
+	if where != "" {
+		// Ask the system.
+		if free, err := osFreeDiskBytes(where); err == nil {
+			// In gigabytes (decimal, like every size shown).
+			fm.DiskGB = float64(free) / 1e9
+			// Where it was read.
+			fm.DiskWhere = where
+		} // end of the read check
+	} // end of the folder check
+	// The facts.
+	return fm
+} // end of readFindMachine
+
+// findPage is everything the Find LLM template shows.
+type findPage struct {
+	// Theme and Size are the saved look choices.
+	Theme, Size string
+	// Token proves the form comes from this page.
+	Token string
+	// Tips are the help bubbles by name.
+	Tips map[string]tipView
+	// Abilities are the tick boxes with their state.
+	Abilities []findTick
+	// Sizes and Contexts are the class tick boxes with their state.
+	Sizes, Contexts []findTick
+	// Chat is whether "Chat and writing" is ticked.
+	Chat bool
+	// Disk and Mem are the typed numbers, as text.
+	Disk, Mem string
+	// DiskNote and MemNote explain where the numbers come from.
+	DiskNote, MemNote string
+	// GPU is the graphics card line.
+	GPU string
+	// Problems are the things wrong with what was typed.
+	Problems []string
+	// Searched is true after a search, so the results block is drawn.
+	Searched bool
+	// Error is the reason the library could not be read (empty when it could).
+	Error string
+	// ReadAt is when the list was read, with its zone.
+	ReadAt string
+	// Results are the models shown.
+	Results []resultView
+	// Summary is the sentence above the results: how many models match, which are shown, when the list was read, and what was left out.
+	Summary string
+} // end of findPage
+
+// findTick is one tick box.
+type findTick struct {
+	// Name is the form field name.
+	Name string
+	// Label is the plain wording.
+	Label string
+	// Range is the number explanation (for classes).
+	Range string
+	// On is true when ticked.
+	On bool
+	// Tip is the help bubble.
+	Tip tipView
+} // end of findTick
+
+// findLLMHandlers makes the two handlers of the Find LLM page: the first shows the choices, the second reads the library and shows the models; the second asks the public website, and only the address of its page leaves this computer.
+func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc) {
+	// Parse the template once.
+	page := template.Must(template.New("findllm").Parse(findLLMTemplateText + tipsTemplateText))
+	// Whether Ollama runs on this computer.
+	local := isLocalAddress(addr.URL)
+	// The help bubbles, by name.
+	tips := map[string]tipView{}
+	// Build them from the table of texts.
+	for key, heading := range findTipHeadings {
+		// One bubble.
+		tips[key] = makeFindTip("tip-find-"+key, heading)
+	} // end of the bubble loop
+	// render draws the page for a selection.
+	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, total, cloud, noSize int, errText, readAt string, status int) {
+		// The tick boxes.
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		// The abilities.
+		for _, k := range abilityKeys {
+			// One box.
+			data.Abilities = append(data.Abilities, findTick{Name: "ab_" + k, Label: findAbilityLabels[k], On: sel.Abilities[k], Tip: tips[k]})
+		} // end of the abilities
+		// The size classes.
+		for _, c := range paramClasses {
+			// One box.
+			data.Sizes = append(data.Sizes, findTick{Name: "sz_" + c.Key, Label: c.Label, Range: c.Range, On: sel.Sizes[c.Key]})
+		} // end of the sizes
+		// The memory classes.
+		for _, c := range contextClasses {
+			// One box.
+			data.Contexts = append(data.Contexts, findTick{Name: "cx_" + c.Key, Label: c.Label, Range: c.Range, On: sel.Contexts[c.Key]})
+		} // end of the contexts
+		// The typed numbers.
+		data.Disk, data.Mem = numberText(sel.DiskGB), numberText(sel.MemGB)
+		// Where the disk number comes from.
+		switch {
+		// Ollama is elsewhere.
+		case fm.Remote:
+			// Say so.
+			data.DiskNote = "Ollama is on another computer, so nothing was measured here. Type the free space on that computer, or leave it empty to skip this check."
+		// Measured.
+		case fm.DiskWhere != "":
+			// Say where.
+			data.DiskNote = "Measured on the disk of " + fm.DiskWhere + ". If Ollama runs in Docker or keeps its models on another disk, type the free space of that disk instead."
+		// Not measured.
+		default:
+			// Say so.
+			data.DiskNote = "The free space could not be measured. Type it, or leave it empty to skip this check."
+		} // end of the disk note
+		// Where the memory number comes from.
+		switch {
+		// Ollama is elsewhere.
+		case fm.Remote:
+			// Say so.
+			data.MemNote = "Type the memory of the computer Ollama runs on, or leave it empty to skip this check."
+		// Measured.
+		case fm.MemGB >= 0:
+			// Say so.
+			data.MemNote = "Measured: the total memory of this computer. On a computer with a graphics card that has its own memory, use that memory instead."
+		// Not measured.
+		default:
+			// Say so.
+			data.MemNote = "The memory could not be measured. Type it, or leave it empty to skip this check."
+		} // end of the memory note
+		// The graphics card.
+		switch {
+		// Ollama is elsewhere.
+		case fm.Remote:
+			// Say so.
+			data.GPU = "Not known (Ollama is on another computer)"
+		// Found.
+		case fm.GPU != "":
+			// The name.
+			data.GPU = "Found: " + fm.GPU
+		// Not found.
+		default:
+			// Say so.
+			data.GPU = "Not found by the graphics tool; models would run on the processor"
+		} // end of the graphics note
+		// Build the page in memory first, so a template error gives a clean 500.
+		var buf bytes.Buffer
+		// Fill the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("find LLM page error: %v", err)
+			// A plain 500.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// The status.
+		w.WriteHeader(status)
+		// Send the page.
+		w.Write(buf.Bytes())
+	} // end of render
+	// show draws the choices with the defaults and the measured machine figures; it asks nothing from the internet.
+	show := func(w http.ResponseWriter, r *http.Request) {
+		// Read the machine.
+		fm := readFindMachine(r.Context(), local)
+		// The starting choices: chat and writing, small and medium models, no ability or memory filter.
+		sel := findSelection{Chat: true, Abilities: map[string]bool{}, Sizes: map[string]bool{"small": true, "medium": true}, Contexts: map[string]bool{}, DiskGB: fm.DiskGB, MemGB: fm.MemGB}
+		// Draw.
+		render(w, r, sel, fm, nil, false, nil, 0, 0, 0, "", "", http.StatusOK)
+	} // end of show
+	// search reads the library and shows the models.
+	search := func(w http.ResponseWriter, r *http.Request) {
+		// Only the page's own form may start a search (it reads the internet).
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "forbidden", http.StatusForbidden)
+			// Stop.
+			return
+		} // end of the token check
+		// Read the machine again, for the notes.
+		fm := readFindMachine(r.Context(), local)
+		// The typed choices.
+		sel, problems := parseFindForm(r.PostFormValue)
+		// Typed wrongly: show the form again, read nothing.
+		if len(problems) > 0 {
+			// Draw with the problems.
+			render(w, r, sel, fm, problems, false, nil, 0, 0, 0, "", "", http.StatusBadRequest)
+			// Stop.
+			return
+		} // end of the problem check
+		// Read the current list from the library.
+		models, at, err := liveSiteList(r.Context(), time.Now)
+		// It could not be read: say why, show no data.
+		if err != nil {
+			// Draw with the reason.
+			render(w, r, sel, fm, nil, true, nil, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". Nothing is shown rather than something that may be out of date.", "", http.StatusOK)
+			// Stop.
+			return
+		} // end of the read check
+		// Apply the choices the list can answer.
+		cands, noSize, cloud := findCandidates(models, sel)
+		// The first ones get their tags pages read.
+		shown := cands
+		// Cut the list.
+		if len(shown) > maxFindResults {
+			// Keep the most downloaded.
+			shown = shown[:maxFindResults]
+		} // end of the cut
+		// The results, filled side by side.
+		results := make([]resultView, len(shown))
+		// Wait for all of them.
+		var wg sync.WaitGroup
+		// At most findParallel at the same time.
+		gate := make(chan struct{}, findParallel)
+		// Start one read per model.
+		for i := range shown {
+			// One more to wait for.
+			wg.Add(1)
+			// Take a place.
+			gate <- struct{}{}
+			// Run it.
+			go func(i int) {
+				// Free the place and report done.
+				defer func() { <-gate; wg.Done() }()
+				// Read the tags page.
+				tags, terr := fetchSiteTags(r.Context(), shown[i].Name)
+				// A failure.
+				if terr != nil {
+					// Never guess: the model is listed without versions.
+					results[i] = buildResult(shown[i], nil, terr.Error(), sel)
+					// Done.
+					return
+				} // end of the failure check
+				// The model with its versions.
+				results[i] = buildResult(shown[i], tags, "", sel)
+			}(i) // end of the goroutine
+		} // end of the model loop
+		// Wait.
+		wg.Wait()
+		// Models with a fitting version first (the order of popularity is kept inside each group).
+		sort.SliceStable(results, func(i, j int) bool {
+			// A model that fits somewhere comes first.
+			return (results[i].FitCount > 0) && (results[j].FitCount == 0)
+		}) // end of the sort
+		// Draw the results, with the time the list was read and its zone.
+		render(w, r, sel, fm, nil, true, results, len(cands), cloud, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), http.StatusOK)
+	} // end of search
+	// Hand back both.
+	return show, search
+} // end of findLLMHandlers
+
+// findSummary writes the sentence above the results in correct singular and plural.
+func findSummary(shown, total, cloud, noSize int, readAt string) string {
+	// Nothing matched.
+	if total == 0 {
+		// Say so, with the same facts.
+		return "No model matches your choices. Try ticking fewer of them. The library list was read on " + readAt + "." + findLeftOut(cloud, noSize)
+	} // end of the empty case
+	// How many are shown.
+	which := "all are shown"
+	// Fewer shown than matching.
+	if shown < total {
+		// Say how many.
+		which = fmt.Sprintf("the %d most downloaded are shown", shown)
+	} // end of the count check
+	// The verb agrees with the number.
+	verb := "match"
+	// One model.
+	if total == 1 {
+		// Singular.
+		verb = "matches"
+	} // end of the verb choice
+	// The sentence.
+	return countText(total) + " " + verb + " your choices; " + which + ". The library list was read on " + readAt + "." + findLeftOut(cloud, noSize)
+} // end of findSummary
+
+// findLeftOut says what was left out of the list and why; empty when nothing was.
+func findLeftOut(cloud, noSize int) string {
+	// The text so far.
+	s := ""
+	// Cloud models.
+	switch {
+	// One.
+	case cloud == 1:
+		// Singular.
+		s += " 1 cloud model (it runs on Ollama's servers, not on this computer) is left out."
+	// Several.
+	case cloud > 1:
+		// Plural.
+		s += fmt.Sprintf(" %d cloud models (they run on Ollama's servers, not on this computer) are left out.", cloud)
+	} // end of the cloud switch
+	// Models without a readable size.
+	switch {
+	// One.
+	case noSize == 1:
+		// Singular.
+		s += " 1 model that shows no size was left out because you chose a size."
+	// Several.
+	case noSize > 1:
+		// Plural.
+		s += fmt.Sprintf(" %d models that show no size were left out because you chose a size.", noSize)
+	} // end of the size switch
+	// The text.
+	return s
+} // end of findLeftOut
+
+// numberText writes a number for a text box: empty when not known.
+func numberText(v float64) string {
+	// Not known.
+	if v < 0 {
+		// Empty.
+		return ""
+	} // end of the unknown case
+	// One decimal.
+	return strconv.FormatFloat(v, 'f', 1, 64)
+} // end of numberText
diff --git a/findllm_test.go b/findllm_test.go
new file mode 100644
index 0000000..ad30534
--- /dev/null
+++ b/findllm_test.go
@@ -0,0 +1,513 @@
+// Package main tells Go that this test file belongs to the same program as findllm.go.
+package main
+
+import ( // import lists the standard-library packages this test file uses.
+	// io reads a reply body.
+	"io"
+	// net/http gives the status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// runtime says which system the test runs on.
+	"runtime"
+	// strings searches the page text.
+	"strings"
+	// sync/atomic reads the request counter safely.
+	"sync/atomic"
+	// testing is Go's built-in test framework.
+	"testing"
+	// unicode/utf8 counts characters of the help texts.
+	"unicode/utf8"
+) // end of imports
+
+// TestParamsBillionsAndClasses checks the size labels and the plain-language size classes.
+func TestParamsBillionsAndClasses(t *testing.T) {
+	// The cases: label, billions, class.
+	for _, c := range []struct {
+		// label is the page's size label.
+		label string
+		// want is the expected billions.
+		want float64
+		// class is the expected class key.
+		class string
+	}{{"0.6b", 0.6, "tiny"}, {"350m", 0.35, "tiny"}, {"1b", 1, "tiny"}, {"1.7b", 1.7, "small"}, {"4b", 4, "small"}, {"8b", 8, "medium"}, {"14b", 14, "medium"}, {"30b", 30, "large"}, {"70b", 70, "huge"}, {"e4b", 4, "small"}} {
+		// Read the label.
+		got, ok := paramsBillions(c.label)
+		// It must be readable and equal.
+		if !ok || got != c.want {
+			// Report.
+			t.Errorf("paramsBillions(%q) = %v, %v; want %v", c.label, got, ok, c.want)
+		} // end of the value check
+		// The class.
+		if k := paramClassOf(got); k != c.class {
+			// Report.
+			t.Errorf("class of %q = %q, want %q", c.label, k, c.class)
+		} // end of the class check
+	} // end of the case loop
+	// Unreadable labels are refused, never guessed.
+	for _, bad := range []string{"", "b", "x8b", "8x", "latest"} {
+		// Read it.
+		if _, ok := paramsBillions(bad); ok {
+			// Report.
+			t.Errorf("paramsBillions(%q) was accepted", bad)
+		} // end of the check
+	} // end of the bad loop
+} // end of TestParamsBillionsAndClasses
+
+// TestContextClasses checks the context lengths and the memory classes, including the boundaries.
+func TestContextClasses(t *testing.T) {
+	// The cases: text, class.
+	for _, c := range []struct {
+		// text is the page's context length.
+		text string
+		// class is the expected class key.
+		class string
+	}{{"4K", "short"}, {"8K", "medium"}, {"32K", "medium"}, {"40K", "long"}, {"128K", "long"}, {"256K", "verylong"}, {"1M", "verylong"}} {
+		// Read it.
+		k, ok := contextThousands(c.text)
+		// It must be readable.
+		if !ok {
+			// Report.
+			t.Errorf("contextThousands(%q) not readable", c.text)
+			// Next.
+			continue
+		} // end of the read check
+		// The class.
+		if got := contextClassOf(k); got != c.class {
+			// Report.
+			t.Errorf("class of %q = %q, want %q", c.text, got, c.class)
+		} // end of the class check
+	} // end of the case loop
+	// Unreadable text is refused.
+	for _, bad := range []string{"", "K", "abcK", "12"} {
+		// Read it.
+		if _, ok := contextThousands(bad); ok {
+			// Report.
+			t.Errorf("contextThousands(%q) was accepted", bad)
+		} // end of the check
+	} // end of the bad loop
+} // end of TestContextClasses
+
+// TestPullsNumber checks the download counts used for sorting.
+func TestPullsNumber(t *testing.T) {
+	// The cases.
+	for text, want := range map[string]float64{"120.9M": 120.9e6, "3.4K": 3400, "87": 87, "1.2B": 1.2e9, "": 0, "many": 0} {
+		// Convert.
+		if got := pullsNumber(text); got < want-1 || got > want+1 {
+			// Report.
+			t.Errorf("pullsNumber(%q) = %v, want %v", text, got, want)
+		} // end of the compare
+	} // end of the case loop
+} // end of TestPullsNumber
+
+// sampleModels is a small invented library list for the filter tests.
+func sampleModels() []siteModel {
+	// Six models of different kinds.
+	return []siteModel{
+		// A popular chat model with tools and thinking, three sizes.
+		{Name: "alpha", Abilities: []string{"tools", "thinking"}, Sizes: []string{"0.6b", "8b", "70b"}, Pulls: "10M"},
+		// A less popular chat model with pictures.
+		{Name: "beta", Abilities: []string{"vision"}, Sizes: []string{"7b"}, Pulls: "2M"},
+		// A search-and-similarity model without sizes.
+		{Name: "gamma", Abilities: []string{"embedding"}, Pulls: "5M"},
+		// A cloud model.
+		{Name: "delta", Cloud: true, Abilities: []string{"tools"}, Sizes: []string{"7b"}, Pulls: "9M"},
+		// A chat model whose size cannot be read.
+		{Name: "epsilon", Pulls: "1M"},
+		// A tiny chat model.
+		{Name: "zeta", Sizes: []string{"350m"}, Pulls: "10M"},
+	} // end of the list
+} // end of sampleModels
+
+// modelNames lists the model names of a result, in order.
+func modelNames(ms []siteModel) string {
+	// Collect.
+	var out []string
+	// Each model.
+	for _, m := range ms {
+		// Its name.
+		out = append(out, m.Name)
+	} // end of the loop
+	// Joined.
+	return strings.Join(out, ",")
+} // end of modelNames
+
+// TestFindCandidatesFilters checks the choices the list page can answer.
+func TestFindCandidatesFilters(t *testing.T) {
+	// The cases: the selection, the expected names in order, the cloud count and the no-size count.
+	for _, c := range []struct {
+		// name describes the case.
+		name string
+		// sel is the selection.
+		sel findSelection
+		// want is the expected names.
+		want string
+		// cloud and noSize are the expected counts.
+		cloud, noSize int
+	}{
+		// Nothing ticked: everything except cloud, most downloaded first, equal counts by name.
+		{"nothing", findSelection{}, "alpha,zeta,gamma,beta,epsilon", 1, 0},
+		// Chat and writing leaves out the embedding model.
+		{"chat", findSelection{Chat: true}, "alpha,zeta,beta,epsilon", 1, 0},
+		// Two abilities must both be present.
+		{"two abilities", findSelection{Abilities: map[string]bool{"tools": true, "thinking": true}}, "alpha", 1, 0},
+		// A size class: any of the model's sizes in the class is enough; the two models without a readable size (gamma and epsilon) are counted.
+		{"tiny", findSelection{Sizes: map[string]bool{"tiny": true}}, "alpha,zeta", 1, 2},
+		// Another class.
+		{"medium", findSelection{Sizes: map[string]bool{"medium": true}}, "alpha,beta", 1, 2},
+		// Embedding on its own.
+		{"embedding", findSelection{Abilities: map[string]bool{"embedding": true}}, "gamma", 1, 0},
+	} {
+		// Run the filter.
+		got, noSize, cloud := findCandidates(sampleModels(), c.sel)
+		// Compare the names.
+		if modelNames(got) != c.want {
+			// Report.
+			t.Errorf("%s: got %s, want %s", c.name, modelNames(got), c.want)
+		} // end of the names check
+		// Compare the counts.
+		if cloud != c.cloud || noSize != c.noSize {
+			// Report.
+			t.Errorf("%s: cloud=%d noSize=%d, want %d and %d", c.name, cloud, noSize, c.cloud, c.noSize)
+		} // end of the counts check
+	} // end of the case loop
+} // end of TestFindCandidatesFilters
+
+// TestVersionReason checks why a version does or does not fit.
+func TestVersionReason(t *testing.T) {
+	// A version of 1.6 GB with a 1M context.
+	v := siteTag{Tag: "m:1b", SizeText: "1.6GB", SizeBytes: 1600000000, Context: "1M"}
+	// It fits with plenty of room.
+	if r := versionReason(v, findSelection{DiskGB: 10, MemGB: 8}); r != "" {
+		// Report.
+		t.Errorf("should fit, got %q", r)
+	} // end of the fit check
+	// Too little disk.
+	if r := versionReason(v, findSelection{DiskGB: 1.0, MemGB: 8}); !strings.Contains(r, "disk") {
+		// Report.
+		t.Errorf("disk reason = %q", r)
+	} // end of the disk check
+	// Too little memory.
+	if r := versionReason(v, findSelection{DiskGB: 10, MemGB: 1.0}); !strings.Contains(r, "memory") {
+		// Report.
+		t.Errorf("memory reason = %q", r)
+	} // end of the memory check
+	// Unknown figures are not checked at all.
+	if r := versionReason(v, findSelection{DiskGB: -1, MemGB: -1}); r != "" {
+		// Report.
+		t.Errorf("unknown figures should not block, got %q", r)
+	} // end of the unknown check
+	// A chosen memory class that the version is not in.
+	if r := versionReason(v, findSelection{DiskGB: -1, MemGB: -1, Contexts: map[string]bool{"short": true}}); !strings.Contains(r, "context") {
+		// Report.
+		t.Errorf("context reason = %q", r)
+	} // end of the class check
+	// A chosen class that it is in.
+	if r := versionReason(v, findSelection{DiskGB: -1, MemGB: -1, Contexts: map[string]bool{"verylong": true}}); r != "" {
+		// Report.
+		t.Errorf("should fit the class, got %q", r)
+	} // end of the in-class check
+	// A version with no readable context length is left out of a context search, not guessed.
+	if r := versionReason(siteTag{Tag: "m:x", SizeBytes: 1}, findSelection{DiskGB: -1, MemGB: -1, Contexts: map[string]bool{"long": true}}); r == "" {
+		// Report.
+		t.Error("an unknown context length passed a context search")
+	} // end of the unknown-context check
+} // end of TestVersionReason
+
+// TestParseFindForm checks the typed numbers and the ticks.
+func TestParseFindForm(t *testing.T) {
+	// A form with ticks and numbers, one with a decimal comma.
+	v := url.Values{"ab_chat": {"on"}, "ab_tools": {"on"}, "sz_small": {"on"}, "cx_long": {"on"}, "disk_gb": {"12,5"}, "mem_gb": {""}}
+	// Read it.
+	sel, problems := parseFindForm(v.Get)
+	// No problems.
+	if len(problems) != 0 {
+		// Report.
+		t.Fatalf("problems: %v", problems)
+	} // end of the problem check
+	// The ticks and numbers.
+	if !sel.Chat || !sel.Abilities["tools"] || !sel.Sizes["small"] || !sel.Contexts["long"] || sel.DiskGB != 12.5 || sel.MemGB != -1 {
+		// Report.
+		t.Errorf("selection = %+v", sel)
+	} // end of the value check
+	// Bad numbers are problems.
+	for _, bad := range []string{"abc", "-3", "1000000", "1e3x"} {
+		// Read it.
+		_, problems := parseFindForm(url.Values{"disk_gb": {bad}}.Get)
+		// One problem.
+		if len(problems) != 1 {
+			// Report.
+			t.Errorf("disk %q: problems = %v", bad, problems)
+		} // end of the problem check
+	} // end of the bad loop
+} // end of TestParseFindForm
+
+// TestFindTipsAreCompleteAndShort checks the help texts follow the same house rules as the rest of the program.
+func TestFindTipsAreCompleteAndShort(t *testing.T) {
+	// Every bubble of the page has a text.
+	for key, heading := range findTipHeadings {
+		// Look it up.
+		tip, ok := findTexts[heading]
+		// It must exist.
+		if !ok {
+			// Report.
+			t.Errorf("no help text for %q (%s)", heading, key)
+			// Next.
+			continue
+		} // end of the lookup check
+		// The limits of the other tooltips: plain 130, example 120, decide 100.
+		for _, p := range []struct {
+			// part names the part.
+			part string
+			// text is its content.
+			text string
+			// limit is the longest allowed length.
+			limit int
+		}{{"Plain", tip.Plain, 130}, {"Example", tip.Example, 120}, {"Decide", tip.Decide, 100}} {
+			// Filled.
+			if strings.TrimSpace(p.text) == "" {
+				// Report.
+				t.Errorf("%q: %s is empty", heading, p.part)
+			} // end of the empty check
+			// Short.
+			if n := utf8.RuneCountInString(p.text); n > p.limit {
+				// Report.
+				t.Errorf("%q: %s is %d characters, the limit is %d", heading, p.part, n, p.limit)
+			} // end of the length check
+			// No markup characters.
+			if strings.ContainsAny(p.text, "<>{}") {
+				// Report.
+				t.Errorf("%q: %s contains markup characters", heading, p.part)
+			} // end of the markup check
+		} // end of the part loop
+		// The house rule on abbreviations: every one is followed by its full form in brackets.
+		all := tip.Plain + " | " + tip.Example + " | " + tip.Decide
+		// The abbreviations and their full forms.
+		for abbr, full := range map[string]string{"GB": "gigabytes", "GPU": "graphics processing unit", "UTC": "coordinated universal time"} {
+			// Every appearance must be an explained one.
+			if strings.Count(all, abbr) != strings.Count(all, abbr+" ("+full+")") {
+				// Report.
+				t.Errorf("%q: %q is not explained every time", heading, abbr)
+			} // end of the count check
+		} // end of the abbreviation loop
+	} // end of the bubble loop
+} // end of TestFindTipsAreCompleteAndShort
+
+// TestFreeDiskIsReadable checks the free-space reader on the systems that have one.
+func TestFreeDiskIsReadable(t *testing.T) {
+	// Only Linux, macOS and Windows have a reader.
+	if runtime.GOOS != "linux" && runtime.GOOS != "darwin" && runtime.GOOS != "windows" {
+		// Say why.
+		t.Skip("no reader on this system")
+	} // end of the system check
+	// Ask about a temporary folder.
+	free, err := osFreeDiskBytes(t.TempDir())
+	// It must work and give a positive number.
+	if err != nil || free == 0 {
+		// Report.
+		t.Errorf("osFreeDiskBytes = %d, %v", free, err)
+	} // end of the check
+} // end of TestFreeDiskIsReadable
+
+// findTestPages are the pages of a fake library: a list with a cloud model, and tags pages.
+func findTestPages() map[string]string {
+	// The list page: a normal model, a cloud model, an embedding model.
+	list := listEntry("alpha", "An invented chat model.", "tools", "0.6b", "8b") + listEntry("cloudy", "Runs far away.", "cloud", "tools", "8b") + listEntry("embedder", "Turns text into numbers.", "embedding")
+	// The pages.
+	return map[string]string{
+		// The list.
+		"/library": "<html><ul>" + list + "</ul></html>",
+		// The tags of alpha: one small version that fits, one large that does not.
+		"/library/alpha/tags": tagEntry("alpha:0.6b", "523MB", "40K") + tagEntry("alpha:8b", "5.2GB", "128K"),
+		// The tags of the embedding model.
+		"/library/embedder/tags": tagEntry("embedder:latest", "274MB", "2K"),
+	} // end of the pages
+} // end of findTestPages
+
+// postFind sends the search form with the given values and returns the status and the body.
+func postFind(t *testing.T, rig themeRig, v url.Values) (int, string) {
+	// Mark this as a helper.
+	t.Helper()
+	// Send it as the page's own form.
+	res := post(t, rig.h, "/findllm/search", v, fromThisPage)
+	// Close the body at the end.
+	defer res.Body.Close()
+	// Read it.
+	b, err := io.ReadAll(res.Body)
+	// A failure means the test is broken.
+	if err != nil {
+		// Stop.
+		t.Fatalf("read body: %v", err)
+	} // end of the read check
+	// The result.
+	return res.StatusCode, string(b)
+} // end of postFind
+
+// TestFindPageShowsTheChoicesAndAsksNothing checks the page before any search.
+func TestFindPageShowsTheChoicesAndAsksNothing(t *testing.T) {
+	// A fake library; it must not be asked.
+	hits := fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// Ask for the page.
+	status, _, body := get(t, rig.h, http.MethodGet, "/findllm")
+	// It must be there.
+	if status != http.StatusOK {
+		// Report.
+		t.Fatalf("status %d", status)
+	} // end of the status check
+	// The page has what the requirement lists.
+	for _, want := range []string{"Find LLM", "Your computer (required)", "Free disk space", "Memory (GB, gigabytes)", "Graphics card", "Always on", "Supported by Ollama", "Can be installed with Ollama", "Chat and writing", "Uses tools", "Understands pictures", "Model size", "Memory of a conversation", `name="token"`, "installs nothing"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The two fixed ticks are ticked and cannot be changed.
+	if strings.Count(body, `type="checkbox" checked disabled`) != 2 {
+		// Report.
+		t.Error("the two fixed ticks are not ticked and greyed")
+	} // end of the fixed check
+	// Chat and writing, and the small and medium sizes, are ticked at the start.
+	for _, want := range []string{`name="ab_chat" checked`, `name="sz_small" checked`, `name="sz_medium" checked`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("default missing: %s", want)
+		} // end of the look
+	} // end of the loop
+	// No results block, and no request to the library.
+	if strings.Contains(body, "<h2>Models found</h2>") || atomic.LoadInt32(hits) != 0 {
+		// Report.
+		t.Errorf("results shown or library asked before the button (hits=%d)", atomic.LoadInt32(hits))
+	} // end of the check
+} // end of TestFindPageShowsTheChoicesAndAsksNothing
+
+// TestFindSearchShowsFitAndNoFit checks a whole search against a fake library.
+func TestFindSearchShowsFitAndNoFit(t *testing.T) {
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	hits := fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// Chat and writing, 2 GB of disk, 8 GB of memory.
+	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
+	// It must work.
+	if status != http.StatusOK {
+		// Report.
+		t.Fatalf("status %d: %s", status, body)
+	} // end of the status check
+	// The model, its official link, the small version that fits with its command, and the large one with the reason.
+	for _, want := range []string{"<h2>Models found</h2>", ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", "1 cloud model (it runs on Ollama"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the results lack %q", want)
+		} // end of the look
+	} // end of the loop
+	// The cloud model and the embedding model are not listed.
+	if strings.Contains(body, ">cloudy<") || strings.Contains(body, ">embedder<") {
+		// Report.
+		t.Error("a cloud or embedding model was listed")
+	} // end of the absence check
+	// One list page and one tags page were read.
+	if n := atomic.LoadInt32(hits); n != 2 {
+		// Report.
+		t.Errorf("%d requests, want 2", n)
+	} // end of the count check
+	// The reading time carries a zone.
+	if !strings.Contains(body, "UTC") {
+		// Report.
+		t.Error("the reading time has no zone")
+	} // end of the zone check
+} // end of TestFindSearchShowsFitAndNoFit
+
+// TestFindSearchRules checks the refusals: wrong token, bad number, library down.
+func TestFindSearchRules(t *testing.T) {
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library with no pages at all: every request is a 404.
+	hits := fakeSite(t, map[string]string{})
+	// The rig.
+	rig := newThemeRig(t)
+	// A wrong token is refused and nothing is read.
+	if status, _ := postFind(t, rig, url.Values{"token": {"wrong"}}); status != http.StatusForbidden {
+		// Report.
+		t.Errorf("wrong token: status %d", status)
+	} // end of the token check
+	// A bad number is shown as a problem and nothing is read.
+	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"lots"}})
+	// Bad request, with the problem.
+	if status != http.StatusBadRequest || !strings.Contains(body, "Free disk space") {
+		// Report.
+		t.Errorf("bad number: status %d", status)
+	} // end of the number check
+	// Nothing reached the library so far.
+	if atomic.LoadInt32(hits) != 0 {
+		// Report.
+		t.Errorf("the library was asked %d times by refused forms", atomic.LoadInt32(hits))
+	} // end of the count check
+	// The library cannot be read: the reason is shown and no model is listed.
+	status, body = postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}})
+	// A normal page with a warning.
+	if status != http.StatusOK || !strings.Contains(body, "could not be read just now") || strings.Contains(body, "findresult") {
+		// Report.
+		t.Errorf("library down: status %d", status)
+	} // end of the down check
+	// A plain GET on the search address is not a route.
+	if status, _, _ := get(t, rig.h, http.MethodGet, "/findllm/search"); status == http.StatusOK {
+		// Report.
+		t.Error("GET /findllm/search was accepted")
+	} // end of the GET check
+} // end of TestFindSearchRules
+
+// TestHomePageHasTheFindLLMButton checks the entry point.
+func TestHomePageHasTheFindLLMButton(t *testing.T) {
+	// The rig.
+	rig := newThemeRig(t)
+	// The home page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// The button and its tooltip.
+	for _, want := range []string{`href="/findllm"`, "Find LLM", "installs nothing"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the home page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+} // end of TestHomePageHasTheFindLLMButton
+
+// TestFindSummaryWording checks singular and plural in the sentence above the results.
+func TestFindSummaryWording(t *testing.T) {
+	// The cases: shown, total, cloud, noSize and the words that must appear.
+	for _, c := range []struct {
+		// shown, total, cloud and noSize are the inputs.
+		shown, total, cloud, noSize int
+		// want are the phrases that must appear.
+		want []string
+	}{
+		// One model, nothing left out.
+		{1, 1, 0, 0, []string{"1 model matches your choices; all are shown.", "20:36:00 CET (UTC+01:00)"}},
+		// Many models, some not shown, cloud and size left out.
+		{10, 42, 24, 3, []string{"42 models match your choices; the 10 most downloaded are shown.", "24 cloud models (they run on Ollama's servers", "3 models that show no size were left out"}},
+		// None.
+		{0, 0, 1, 1, []string{"No model matches your choices.", "1 cloud model (it runs", "1 model that shows no size was left out"}},
+	} {
+		// Build it.
+		got := findSummary(c.shown, c.total, c.cloud, c.noSize, "2026-11-08 20:36:00 CET (UTC+01:00)")
+		// Each phrase.
+		for _, w := range c.want {
+			// Look for it.
+			if !strings.Contains(got, w) {
+				// Report.
+				t.Errorf("summary %q lacks %q", got, w)
+			} // end of the look
+		} // end of the phrase loop
+	} // end of the case loop
+} // end of TestFindSummaryWording
diff --git a/findtips.go b/findtips.go
new file mode 100644
index 0000000..0484acb
--- /dev/null
+++ b/findtips.go
@@ -0,0 +1,174 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+// findAbilityLabels are the plain words shown for the ability tick boxes, by the label the library list page uses.
+var findAbilityLabels = map[string]string{
+	// Tools.
+	"tools": "Uses tools",
+	// Vision.
+	"vision": "Understands pictures",
+	// Audio.
+	"audio": "Understands audio",
+	// Thinking.
+	"thinking": "Shows its step-by-step thinking",
+	// Embedding.
+	"embedding": "Search and similarity (embedding)",
+} // end of findAbilityLabels
+
+// findTipHeadings maps the name of each help bubble on the Find LLM page to the heading its text is stored under.
+var findTipHeadings = map[string]string{
+	// The page itself.
+	"page": "Find LLM",
+	// The mandatory computer figures.
+	"disk": "Free disk space",
+	// Memory.
+	"memory": "Memory to run a model",
+	// The graphics card.
+	"gpu": "Graphics card",
+	// Chat and writing.
+	"chat": "Chat and writing",
+	// The five abilities.
+	"tools": "Uses tools", "vision": "Understands pictures", "audio": "Understands audio", "thinking": "Shows its step-by-step thinking", "embedding": "Search and similarity (embedding)",
+	// The class groups.
+	"size": "Model size", "context": "Memory of a conversation",
+	// The two fixed ticks.
+	"supported": "Supported by Ollama", "installable": "Can be installed with Ollama",
+} // end of findTipHeadings
+
+// findTexts are the help texts of the Find LLM page, in the same four-part form as the rest of the program: what it means, a real case, and what it helps you decide. Every example comes from the saved library pages of 2026-11-08 (CET).
+var findTexts = map[string]tooltip{
+	// The page.
+	"Find LLM": {
+		// What it means.
+		Plain: "Lists only models that Ollama supports and that you can install with Ollama. This page installs nothing.",
+		// A real case.
+		Example: "qwen3:0.6b-q4_K_M is listed with the command ollama pull qwen3:0.6b-q4_K_M.",
+		// What it helps with.
+		Decide: "Which model to try next, before you download anything.",
+	}, // end of Find LLM
+	// Free disk space.
+	"Free disk space": {
+		// What it means.
+		Plain: "The space free where Ollama keeps its models. Versions that do not fit are greyed out. Required.",
+		// A real case.
+		Example: "granite4:1b-h needs 1.6 GB (gigabytes); granite4:1b needs 3.3 GB (gigabytes).",
+		// What it helps with.
+		Decide: "Which versions you can download without running out of space.",
+	}, // end of Free disk space
+	// Memory.
+	"Memory to run a model": {
+		// What it means.
+		Plain: "The memory of the computer that runs the model. A model larger than that cannot be loaded completely. Required.",
+		// A real case.
+		Example: "granite4:1b is 3.3 GB (gigabytes), so it needs a computer with more memory than that.",
+		// What it helps with.
+		Decide: "Which models your computer can really run.",
+	}, // end of Memory to run a model
+	// Graphics card.
+	"Graphics card": {
+		// What it means.
+		Plain: "Whether a graphics card, called a GPU (graphics processing unit), was found. Models run much faster on one. Required.",
+		// A real case.
+		Example: "Without one, a model runs on the processor and answers more slowly.",
+		// What it helps with.
+		Decide: "How fast to expect answers.",
+	}, // end of Graphics card
+	// Chat and writing.
+	"Chat and writing": {
+		// What it means.
+		Plain: "Models that write text, as opposed to search-and-similarity models. Ticked by default.",
+		// A real case.
+		Example: "granite4 is a chat model; nomic-embed-text is a search-and-similarity model.",
+		// What it helps with.
+		Decide: "Whether you want a model to talk with or one to search with.",
+	}, // end of Chat and writing
+	// Tools.
+	"Uses tools": {
+		// What it means.
+		Plain: "The model can ask a program to do something, such as look up a value, and use the answer.",
+		// A real case.
+		Example: "qwen3, llama3.2 and granite4 carry the label tools on the library page.",
+		// What it helps with.
+		Decide: "Whether you need the model to work with other programs.",
+	}, // end of Uses tools
+	// Pictures.
+	"Understands pictures": {
+		// What it means.
+		Plain: "The model can read pictures you give it, not only text.",
+		// A real case.
+		Example: "llava carries the label vision on the library page.",
+		// What it helps with.
+		Decide: "Whether you want to ask questions about images.",
+	}, // end of Understands pictures
+	// Audio.
+	"Understands audio": {
+		// What it means.
+		Plain: "The model can listen to sound you give it, not only read text.",
+		// A real case.
+		Example: "Seven models carry the label audio on the library page of 2026-11-08.",
+		// What it helps with.
+		Decide: "Whether you want to ask questions about recordings.",
+	}, // end of Understands audio
+	// Thinking.
+	"Shows its step-by-step thinking": {
+		// What it means.
+		Plain: "The model writes out its reasoning before the answer. Answers take longer.",
+		// A real case.
+		Example: "qwen3 carries the label thinking; granite4 does not.",
+		// What it helps with.
+		Decide: "Whether you value seeing the reasoning over speed.",
+	}, // end of thinking
+	// Embedding.
+	"Search and similarity (embedding)": {
+		// What it means.
+		Plain: "The model turns text into numbers so that similar texts can be found. It does not chat.",
+		// A real case.
+		Example: "nomic-embed-text and bge-m3 carry the label embedding.",
+		// What it helps with.
+		Decide: "Whether you need to search documents by meaning.",
+	}, // end of embedding
+	// Model size.
+	"Model size": {
+		// What it means.
+		Plain: "How many numbers the model learned, in billions. Bigger is usually smarter and needs more memory.",
+		// A real case.
+		Example: "qwen3 comes in 0.6b, 1.7b, 4b and 8b among others; 0.6b is Tiny.",
+		// What it helps with.
+		Decide: "How much quality to buy with your memory and disk.",
+	}, // end of Model size
+	// Memory of a conversation.
+	"Memory of a conversation": {
+		// What it means.
+		Plain: "How much text the model can keep in mind at once (context length). K means thousand, M million.",
+		// A real case.
+		Example: "granite4:1b-h shows 1M; qwen3:0.6b shows 40K.",
+		// What it helps with.
+		Decide: "Whether long documents or long chats will fit.",
+	}, // end of Memory of a conversation
+	// Supported by Ollama.
+	"Supported by Ollama": {
+		// What it means.
+		Plain: "Always on. Every model listed here is in the official Ollama library, so Ollama can run it.",
+		// A real case.
+		Example: "A model that exists only on another website is not listed.",
+		// What it helps with.
+		Decide: "Nothing to decide; it cannot be changed.",
+	}, // end of Supported by Ollama
+	// Installable with Ollama.
+	"Can be installed with Ollama": {
+		// What it means.
+		Plain: "Always on. Each model is listed with the command that downloads it with Ollama.",
+		// A real case.
+		Example: "ollama pull granite4:1b-h",
+		// What it helps with.
+		Decide: "Nothing to decide; it cannot be changed.",
+	}, // end of Can be installed with Ollama
+} // end of findTexts
+
+// makeFindTip builds one help bubble of the Find LLM page from its heading.
+func makeFindTip(id, heading string) tipView {
+	// A heading without a text gives empty parts; a test makes sure that never happens.
+	t := findTexts[heading]
+	// Build the view.
+	return tipView{Title: heading, ID: id, Plain: t.Plain, Example: t.Example, Decide: t.Decide, AlsoKnown: t.AlsoKnown}
+} // end of makeFindTip
diff --git a/web.go b/web.go
index 3ee8ea4..c0863f0 100644
--- a/web.go
+++ b/web.go
@@ -180,6 +180,12 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	}) // end of the icon route
 	// Route: a GET request for "/about" shows the read-only About page (see about.go).
 	mux.HandleFunc("GET /about", aboutHandler())
+	// Make the two Find LLM handlers: the page with the choices, and the search that reads the public library (see findllm.go).
+	findShow, findSearch := findLLMHandlers(addr, token)
+	// Route: a GET request for "/findllm" shows the choices and asks nothing from the internet.
+	mux.HandleFunc("GET /findllm", findShow)
+	// Route: a POST request for "/findllm/search" reads the library list and shows the matching models.
+	mux.HandleFunc("POST /findllm/search", findSearch)
 	// Make the two Settings handlers: the first shows the page, the second saves the form (see settingspage.go).
 	settingsShow, settingsSave := settingsHandlers(addr, mon, token)
 	// Route: a GET request for "/settings" shows the Settings page.
diff --git a/web/about.html b/web/about.html
index 6cfe3ac..304968d 100644
--- a/web/about.html
+++ b/web/about.html
@@ -42,7 +42,7 @@
 {{/* Where the source lives. */}}
 <tr><th scope="row">Source code</th><td><a href="{{.Repository}}" target="_blank" rel="noopener noreferrer">{{.Repository}}<span class="sr-only"> (opens in a new window)</span></a> (private repository; opens only for its owner)</td></tr>
 {{/* Where the data goes. */}}
-<tr><th scope="row">Privacy</th><td>Runs only on this computer. The one request to the outside is the optional check of Ollama's public library when a model is deleted, and it sends only the model's name. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
+<tr><th scope="row">Privacy</th><td>Runs only on this computer. The requests to the outside are read-only and go to the public Ollama website only: the optional check of a model's name before it is deleted, and, when you press Find LLM, a read of the public model list and of the version lists of the first ten models. Nothing about you or your choices is sent. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
 {{/* The licence. */}}
 <tr><th scope="row">Licence</th><td><a href="{{.LicenceURL}}" target="_blank" rel="noopener noreferrer">{{.Licence}}<span class="sr-only"> (opens in a new window)</span></a>. {{.Copyright}}</td></tr>
 {{/* End of the table. */}}
diff --git a/web/app.css b/web/app.css
index d2ec02a..50a7479 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2520,3 +2520,61 @@ html[data-size="medium"] svg[width="22"] {
   /* No ring on the title. */
   outline: none;
 } /* end of rule */
+
+/* Find LLM page: the required facts about this computer stand out in a coloured box with a thick left edge. */
+.mandatorybox {
+  /* The box colours come from the variables, so both themes work. */
+  background: var(--cat-bg);
+  /* Readable text on that background. */
+  color: var(--cat-text);
+  /* A thick edge, so the box stands out without colour too. */
+  border: 1px solid var(--border);
+  /* The thick left edge. */
+  border-left: 0.3rem solid var(--cat-accent);
+  /* Slightly rounded corners. */
+  border-radius: 0.4rem;
+  /* Room inside. */
+  padding: 0.6rem 0.9rem;
+  /* Room around. */
+  margin: 1rem 0;
+} /* end of rule */
+
+/* Find LLM page: a group of choices. */
+.findgroup {
+  /* A plain outline. */
+  border: 1px solid var(--border);
+  /* Slightly rounded corners. */
+  border-radius: 0.4rem;
+  /* Room inside. */
+  padding: 0.6rem 0.9rem;
+  /* Room around. */
+  margin: 1rem 0;
+} /* end of rule */
+
+/* Find LLM page: one tick box with its words, on its own line. */
+.tickrow {
+  /* One per line. */
+  display: block;
+  /* A little space between lines. */
+  margin: 0.3rem 0;
+} /* end of rule */
+
+/* Find LLM page: one model in the result list. */
+.findresult {
+  /* A line above it. */
+  border-top: 1px solid var(--border);
+  /* Room inside. */
+  padding: 0.8rem 0;
+} /* end of rule */
+
+/* Find LLM page: the download commands may be long; let them wrap instead of widening the page. */
+.findresult code {
+  /* Break inside a long name when needed. */
+  overflow-wrap: anywhere;
+} /* end of rule */
+
+/* Find LLM page: a version that does not fit is shown in the secondary colour, not hidden. */
+.nofit {
+  /* The secondary colour. */
+  color: var(--muted);
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
new file mode 100644
index 0000000..e180dca
--- /dev/null
+++ b/web/findllm.html
@@ -0,0 +1,91 @@
+{{/* Find LLM page template: the person ticks what a model must do, and the page lists models of the public Ollama library that fit. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in; the theme and the text size come from the saved choices. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Find LLM</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+<main>
+<section class="panel">
+{{/* The back arrow in the top right corner of this box. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
+{{/* The heading, with the help bubble that says what this page lists. */}}
+<h1><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.page.ID}}">Find LLM</span><span class="tip" role="tooltip" id="{{.Tips.page.ID}}">{{template "tip" .Tips.page}}</span></span></h1>
+{{/* What the page does, and the one request it makes. */}}
+<p>Tick what the model must do and press <strong>Find LLM</strong>. Only models of the official Ollama library are listed, and each comes with the command that installs it. This page installs nothing.</p>
+<p class="muted">Pressing the button reads the public list at ollama.com/library and, for the first ten models, their version lists. Your choices are not sent: the list is filtered on this computer.</p>
+{{/* Problems with what was typed; nothing was searched. */}}
+{{if .Problems}}<div class="warn" role="alert"><p><strong>&#9888; Not searched.</strong> Please correct:</p><ul>{{range .Problems}}<li>{{.}}</li>{{end}}</ul></div>{{end}}
+{{/* The form: it sends the page token and the choices. */}}
+<form method="post" action="/findllm/search">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The required facts about this computer, highlighted. */}}
+<fieldset class="mandatorybox">
+<legend><strong>Your computer (required)</strong></legend>
+<p><label for="disk_gb"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.disk.ID}}">Free disk space (GB, gigabytes)</span><span class="tip" role="tooltip" id="{{.Tips.disk.ID}}">{{template "tip" .Tips.disk}}</span></span></label> <input type="text" inputmode="decimal" id="disk_gb" name="disk_gb" value="{{.Disk}}" size="8"><br><small>{{.DiskNote}}</small></p>
+<p><label for="mem_gb"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.memory.ID}}">Memory (GB, gigabytes)</span><span class="tip" role="tooltip" id="{{.Tips.memory.ID}}">{{template "tip" .Tips.memory}}</span></span></label> <input type="text" inputmode="decimal" id="mem_gb" name="mem_gb" value="{{.Mem}}" size="8"><br><small>{{.MemNote}}</small></p>
+<p><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.gpu.ID}}">Graphics card</span><span class="tip" role="tooltip" id="{{.Tips.gpu.ID}}">{{template "tip" .Tips.gpu}}</span></span>: {{.GPU}}</p>
+</fieldset>
+{{/* The fixed ticks: shown ticked and greyed, they cannot be changed. */}}
+<fieldset class="findgroup">
+<legend><strong>Always on</strong></legend>
+<label class="tickrow"><input type="checkbox" checked disabled> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.supported.ID}}">Supported by Ollama</span><span class="tip" role="tooltip" id="{{.Tips.supported.ID}}">{{template "tip" .Tips.supported}}</span></span></label>
+<label class="tickrow"><input type="checkbox" checked disabled> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.installable.ID}}">Can be installed with Ollama</span><span class="tip" role="tooltip" id="{{.Tips.installable.ID}}">{{template "tip" .Tips.installable}}</span></span></label>
+</fieldset>
+{{/* What the model should be able to do. */}}
+<fieldset class="findgroup">
+<legend><strong>What it should do</strong></legend>
+<label class="tickrow"><input type="checkbox" name="ab_chat"{{if .Chat}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.chat.ID}}">Chat and writing</span><span class="tip" role="tooltip" id="{{.Tips.chat.ID}}">{{template "tip" .Tips.chat}}</span></span></label>
+{{range .Abilities}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tip.ID}}">{{.Label}}</span><span class="tip" role="tooltip" id="{{.Tip.ID}}">{{template "tip" .Tip}}</span></span></label>
+{{end}}
+</fieldset>
+{{/* How big the model may be. */}}
+<fieldset class="findgroup">
+<legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.size.ID}}"><strong>Model size</strong></span><span class="tip" role="tooltip" id="{{.Tips.size.ID}}">{{template "tip" .Tips.size}}</span></span> <small class="muted">(none ticked: any size)</small></legend>
+{{range .Sizes}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> {{.Label}} <small class="muted">({{.Range}})</small></label>
+{{end}}
+</fieldset>
+{{/* How much the model remembers of a conversation. */}}
+<fieldset class="findgroup">
+<legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.context.ID}}"><strong>Memory of a conversation</strong></span><span class="tip" role="tooltip" id="{{.Tips.context.ID}}">{{template "tip" .Tips.context}}</span></span> <small class="muted">(none ticked: any length)</small></legend>
+{{range .Contexts}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> {{.Label}} <small class="muted">({{.Range}})</small></label>
+{{end}}
+</fieldset>
+{{/* The button: the first and only thing that reads the internet. */}}
+<p><button type="submit" class="btn-solid">Find LLM</button></p>
+</form>
+{{/* The results appear only after the button was pressed. */}}
+{{if .Searched}}
+<h2>Models found</h2>
+{{if .Error}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.Error}}</p>{{else}}
+<p class="muted" role="status">{{.Summary}}</p>
+{{range .Results}}
+<div class="findresult">
+<h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a></h3>
+<p>{{.Description}}</p>
+<p class="muted"><small>Abilities: {{if .Abilities}}{{.Abilities}}{{else}}none listed{{end}} &middot; Sizes: {{if .Sizes}}{{.Sizes}}{{else}}none listed{{end}} &middot; Downloads: {{.Pulls}}</small></p>
+{{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
+{{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
+<ul class="findversions">
+{{range .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{if .Fits}}<strong>Fits:</strong>{{else}}<strong>Does not fit:</strong>{{end}} <code>{{.Command}}</code> &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}</li>
+{{end}}
+</ul>
+{{if .More}}<p class="muted"><small>{{.More}} more versions are on the official page.</small></p>{{end}}
+{{end}}
+</div>
+{{end}}
+{{end}}
+{{end}}
+</section>
+</main>
+</body>
+</html>
diff --git a/web/index.html b/web/index.html
index 0affd34..8ec8e5f 100644
--- a/web/index.html
+++ b/web/index.html
@@ -94,6 +94,11 @@
 <a class="btn-plain ctlbtn" href="/settings" aria-describedby="tipsettings"><svg class="ico" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h9"/><path d="M17 6h3"/><circle cx="15" cy="6" r="2"/><path d="M4 12h3"/><path d="M11 12h9"/><circle cx="9" cy="12" r="2"/><path d="M4 18h11"/><path d="M19 18h1"/><circle cx="17" cy="18" r="2"/></svg> Settings</a>
 <span class="tip tip-icon" role="tooltip" id="tipsettings">Settings: Ollama address, check interval, timeout, chart history, access from other machines</span>
 </span>
+{{/* Find LLM: a plain link to the Find LLM page; the page itself asks nothing from the internet until its own button is pressed. */}}
+<span class="tipbox">
+<a class="btn-plain ctlbtn" href="/findllm" aria-describedby="tipfindllm"><svg class="ico" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg> Find LLM</a>
+<span class="tip tip-icon" role="tooltip" id="tipfindllm">Find LLM: lists only models that Ollama supports and can install; installs nothing</span>
+</span>
 {{/* Stop: a small form that goes to the question page; nothing is stopped yet. */}}
 <form method="post" action="/stop">
 {{/* The page token proves the form comes from this monitor. */}}
OCC_PATCH_92_END

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

# The live check: start the new build on a spare port with throw-away settings folders, open the Find LLM page, press its button for real (this reads the public Ollama website, read-only, about eleven requests) and look at the answer.
SMOKE="$(mktemp -d)"
# Stop the test copy and remove the throw-away folders at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$SMOKE"' EXIT
# Start it in the background; its settings, data and state go to the throw-away folder only.
HOME="$SMOKE" XDG_CONFIG_HOME="$SMOKE/c" XDG_DATA_HOME="$SMOKE/d" XDG_STATE_HOME="$SMOKE/s" bin/LLMsControlDock -listen 127.0.0.1:18766 > "$SMOKE/log" 2>&1 &
# Remember its process number.
SERVER_PID=$!
# Wait up to ten seconds for the page to answer.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  # One try.
  curl -s -o "$SMOKE/page.html" http://127.0.0.1:18766/findllm && break
  # A second between tries.
  sleep 1
# End of the waiting loop.
done
# The page must have the heading and the button.
grep -q 'Your computer (required)' "$SMOKE/page.html" || fail "the Find LLM page did not answer correctly"
# Report it.
pass "live check: the Find LLM page opens"
# The page token, as the browser would send it.
TOKEN="$(grep -o 'name="token" value="[^"]*"' "$SMOKE/page.html" | head -1 | sed 's/.*value="//; s/"$//')"
# It must exist.
[ -n "$TOKEN" ] || fail "no page token found"
# Press the button: chat models of small and medium size, 50 GB disk, 16 GB memory (these numbers only filter; they are not read from this computer here).
curl -s -X POST -H "Sec-Fetch-Site: same-origin" -d "token=$TOKEN&ab_chat=on&sz_small=on&sz_medium=on&disk_gb=50&mem_gb=16" http://127.0.0.1:18766/findllm/search > "$SMOKE/result.html" || fail "the search request failed"
# The results block must be there.
grep -q '<h2>Models found</h2>' "$SMOKE/result.html" || fail "the answer has no results block"
# Count the install commands in the answer.
CMDS="$(grep -o 'ollama pull ' "$SMOKE/result.html" | wc -l | tr -d ' ')"
# With internet there are commands; without it the page says why, and that is reported, not failed.
if [ "$CMDS" -gt 0 ]; then
  # Report it.
  pass "live check: the real library answered, $CMDS install commands listed"
  # Show the first three model names found, for the person to see.
  echo "      first models: $(grep -o '<h3><a href="[^"]*"' "$SMOKE/result.html" | head -3 | sed 's/.*library\///; s/"$//' | tr '\n' ' ')"
else
  # Show the page's own reason.
  echo "WARN  live check: no models listed ($(grep -o 'could not be read just now[^<]*' "$SMOKE/result.html" | head -1))"
  # The page must have said why.
  grep -q 'could not be read just now' "$SMOKE/result.html" || fail "no models and no reason shown"
  # Report it.
  pass "live check: no internet, and the page said so instead of guessing"
# End of the live check.
fi

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and try the Find LLM button (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
