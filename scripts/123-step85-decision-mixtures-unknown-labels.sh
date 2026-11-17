#!/usr/bin/env bash
# Script 123 (Find LLM reads the new "decision" label, mixture sizes, and reports labels it does not know): (1) "decision" becomes a known ability with its own tick "Decision models (classify, score, yes or no)" and a help bubble; "Chat and writing" now leaves decision models out, as it leaves out embedding models, because a decision model answers with a choice and probabilities, not with text (Ollama's page: docs.ollama.com/capabilities/decision; they need Ollama 0.35.0 or newer); (2) sizes written as a mixture, such as 8x7b or 128x17b, are read as a size (parts times size of one part) instead of falling into "Other", so those models are no longer left out of a size search as "no size"; (3) a label on the library page that is neither a size, cloud nor a known ability is reported in a notice on the results; (4) six new tests, one of them reads the structure of the real library page (copied from the page as read on 2026-11-16). Program change, version 0.33.1.
# Run it on the branch of script 122 (never main): cd ~/LLMsControlDock-2 && git switch feature/docker-it-flag && bash scripts/123-step85-decision-mixtures-unknown-labels.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the four changed files BEFORE the change (as after script 122) and AFTER it, and of the new test file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="7ed811e335c535db49f1ace663a760f27aab82ad69d77ffdc77b532d2c4505d8"
BEFORE["findsite.go"]="3f126ff34bf89bd4542476a4994882de1f4059b91d4fdddc6850c6e2d88773d4"
BEFORE["findtips.go"]="84fc1270a2dd8830d9c5541baa8647f4365f8a9cc3d0492678de20486bf33807"
BEFORE["findsite_test.go"]="84dbe929b657c7519d6506face40dcf6a1a6399052b457cdad4fd5f1bc1b00a7"
AFTER["findllm.go"]="5d434b1ee4f0642f188538562e6ab749e3c8c5ef7eaec3516a0da9baccbbbdda"
AFTER["findsite.go"]="4fdac429efc680d353921fa1cb8f550378fb712f983b94c4ec553f58b0fd2f78"
AFTER["findtips.go"]="bc4bc499ebd7a4231136ed42eb748dfd7586e92be4fe353182e2bd4e068e80fa"
AFTER["findsite_test.go"]="2787991beaff3b7f18e6e68825d595c8f6c88a9afaef3f5c0c293fd6b443014e"
AFTER["findlabels_test.go"]="56321fabedfb1546215f390f42c7caeff355ed5d31bbf541af8605be97741c86"

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
[ "$BRANCH" != "main" ] || fail "you are on main; switch to the branch of script 122: git switch feature/docker-it-flag"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 122 must be in: the Find LLM page has the -it lines.
grep -q 'docker exec -it' web/findllm.html || fail "script 122 (-it lines) is not in this branch; run it first"
# Report it.
pass "script 122 is in"

# Refuse to run twice: the new test file exists when this change was applied before.
if [ -e findlabels_test.go ]; then fail "findlabels_test.go exists: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_123_END'
diff --git a/findlabels_test.go b/findlabels_test.go
new file mode 100644
index 0000000..81685da
--- /dev/null
+++ b/findlabels_test.go
@@ -0,0 +1,303 @@
+// Package main tells Go that this test file belongs to the same program as findsite.go and findllm.go.
+package main
+
+import ( // import lists the standard-library packages this test file uses.
+	// html turns character codes in the page back into characters.
+	"html"
+	// net/http gives the status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// reflect compares lists.
+	"reflect"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// realListSample is the markup of the library list page as ollama.com wrote it on 2026-11-16 (read from the page on the test computer): the first entry is copied from the page (blank lines and the drawing of the icon shortened), the other two use the same structure with other names and labels. Only the structure matters here: if ollama.com changes it, the reader must notice.
+const realListSample = `<ul role="list" class="grid grid-cols-1 gap-y-3">
+
+    <li  class="flex items-baseline border-b border-neutral-200 py-6">
+      <a href="/library/llama3.1" class="group w-full space-y-5">
+        <div  title="llama3.1" class="flex flex-col">
+          <h2 class="truncate text-xl font-medium underline-offset-2 md:text-2xl">
+            <div class="flex space-x-2 items-center">
+              <span class="group-hover:underline truncate">llama3.1</span>
+
+            </div>
+          </h2>
+          <p class="max-w-lg break-words text-neutral-800 text-md">Llama 3.1 is a new state-of-the-art model from Meta available in 8B, 70B and 405B parameter sizes.</p>
+        </div>
+        <div class="flex flex-col space-y-2">
+          <div class="flex flex-wrap space-x-2">
+
+              <span  class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-600 sm:text-[13px]">tools</span>
+
+              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">8b</span>
+
+              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">70b</span>
+
+              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">405b</span>
+
+          </div>
+          <p class="flex space-x-5 text-[13px] font-medium text-neutral-500">
+              <span class="flex items-center">
+                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="mr-1.5 h-[14px] w-[14px] sm:h-4 sm:w-4"><path d="M3 16.5v2.25"></path></svg>
+                <span >121.2M</span>
+                <span class="hidden sm:flex">&nbsp;Pulls</span>
+              </span>
+          </p>
+        </div>
+      </a>
+    </li>
+    <li  class="flex items-baseline border-b border-neutral-200 py-6">
+      <a href="/library/decider" class="group w-full space-y-5">
+        <div  title="decider" class="flex flex-col">
+          <h2 class="truncate text-xl font-medium underline-offset-2 md:text-2xl">
+            <div class="flex space-x-2 items-center">
+              <span class="group-hover:underline truncate">decider</span>
+            </div>
+          </h2>
+          <p class="max-w-lg break-words text-neutral-800 text-md">An invented decision model.</p>
+        </div>
+        <div class="flex flex-col space-y-2">
+          <div class="flex flex-wrap space-x-2">
+              <span  class="inline-flex items-center rounded-md bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-600 sm:text-[13px]">decision</span>
+              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">e4b</span>
+          </div>
+          <p class="flex space-x-5 text-[13px] font-medium text-neutral-500">
+              <span class="flex items-center">
+                <span >2.5M</span>
+                <span class="hidden sm:flex">&nbsp;Pulls</span>
+              </span>
+          </p>
+        </div>
+      </a>
+    </li>
+    <li  class="flex items-baseline border-b border-neutral-200 py-6">
+      <a href="/library/mixer" class="group w-full space-y-5">
+        <div  title="mixer" class="flex flex-col">
+          <h2 class="truncate text-xl font-medium underline-offset-2 md:text-2xl">
+            <div class="flex space-x-2 items-center">
+              <span class="group-hover:underline truncate">mixer</span>
+            </div>
+          </h2>
+          <p class="max-w-lg break-words text-neutral-800 text-md">An invented mixture model.</p>
+        </div>
+        <div class="flex flex-col space-y-2">
+          <div class="flex flex-wrap space-x-2">
+              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">8x7b</span>
+              <span  class="inline-flex items-center rounded-md bg-[#ddf4ff] px-2 py-0.5 text-xs font-medium text-blue-600 sm:text-[13px]">128x17b</span>
+          </div>
+          <p class="flex space-x-5 text-[13px] font-medium text-neutral-500">
+              <span class="flex items-center">
+                <span >900K</span>
+                <span class="hidden sm:flex">&nbsp;Pulls</span>
+              </span>
+          </p>
+        </div>
+      </a>
+    </li>
+</ul>`
+
+// TestParseSiteListReadsTheRealMarkupSample checks the reader against the structure of the real page: names, abilities (including the new decision label), sizes (including mixtures such as 8x7b), download counts, and no unknown label.
+func TestParseSiteListReadsTheRealMarkupSample(t *testing.T) {
+	// Read the sample.
+	got, err := parseSiteList(realListSample)
+	// It must work.
+	if err != nil {
+		// Report.
+		t.Fatalf("parseSiteList: %v", err)
+	} // end of the error check
+	// Three entries.
+	if len(got) != 3 {
+		// Report.
+		t.Fatalf("got %d models, want 3", len(got))
+	} // end of the count check
+	// The first entry in full.
+	want0 := siteModel{Name: "llama3.1", Description: "Llama 3.1 is a new state-of-the-art model from Meta available in 8B, 70B and 405B parameter sizes.", Abilities: []string{"tools"}, Sizes: []string{"8b", "70b", "405b"}, Pulls: "121.2M"}
+	// Compare.
+	if !reflect.DeepEqual(got[0], want0) {
+		// Report.
+		t.Errorf("first model = %+v, want %+v", got[0], want0)
+	} // end of the first check
+	// The decision model: decision is an ability, e4b a size, nothing is left over.
+	if !reflect.DeepEqual(got[1].Abilities, []string{"decision"}) || !reflect.DeepEqual(got[1].Sizes, []string{"e4b"}) || len(got[1].Other) != 0 || got[1].Pulls != "2.5M" {
+		// Report.
+		t.Errorf("second model = %+v", got[1])
+	} // end of the second check
+	// The mixture model: both labels are sizes and nothing is left over.
+	if !reflect.DeepEqual(got[2].Sizes, []string{"8x7b", "128x17b"}) || len(got[2].Other) != 0 || len(got[2].Abilities) != 0 {
+		// Report.
+		t.Errorf("third model = %+v", got[2])
+	} // end of the third check
+	// Every label is known, so there is nothing to report.
+	if note := unknownLabelNote(got); note != "" {
+		// Report.
+		t.Errorf("unexpected unknown-label note: %s", note)
+	} // end of the note check
+} // end of TestParseSiteListReadsTheRealMarkupSample
+
+// TestParamsBillionsReadsMixtures checks that a mixture size is the number of parts times the size of one part, and that half-written ones are refused.
+func TestParamsBillionsReadsMixtures(t *testing.T) {
+	// The cases: label, billions, class.
+	for _, c := range []struct {
+		// label is the page's size label.
+		label string
+		// want is the expected billions.
+		want float64
+		// class is the expected class key.
+		class string
+	}{{"8x7b", 56, "huge"}, {"16x17b", 272, "huge"}, {"128x17b", 2176, "huge"}, {"8x22b", 176, "huge"}, {"4x500m", 2, "small"}} {
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
+	// The page's size pattern accepts mixtures and plain sizes, and refuses words.
+	for label, want := range map[string]bool{"8x7b": true, "128x17b": true, "e4b": true, "0.6b": true, "350m": true, "x8b": false, "8x": false, "latest": false, "decision": false} {
+		// Compare.
+		if sizeLabel.MatchString(label) != want {
+			// Report.
+			t.Errorf("sizeLabel(%q) = %v, want %v", label, !want, want)
+		} // end of the compare
+	} // end of the label loop
+} // end of TestParamsBillionsReadsMixtures
+
+// TestDecisionModelsAreNotChatModels checks that "Chat and writing" leaves out decision models and that the Decision tick finds them.
+func TestDecisionModelsAreNotChatModels(t *testing.T) {
+	// Chat and writing, with a decision model: not a chat model.
+	if abilitiesMatch(findSelection{Chat: true}, map[string]bool{"decision": true}) {
+		// Report.
+		t.Error("a decision model passed Chat and writing")
+	} // end of the chat check
+	// Chat and writing, with a plain model: a chat model.
+	if !abilitiesMatch(findSelection{Chat: true}, map[string]bool{"tools": true}) {
+		// Report.
+		t.Error("a plain model failed Chat and writing")
+	} // end of the plain check
+	// The Decision tick finds a decision model and not a plain one.
+	sel := findSelection{Abilities: map[string]bool{"decision": true}}
+	// The decision model.
+	if !abilitiesMatch(sel, map[string]bool{"decision": true}) || abilitiesMatch(sel, map[string]bool{"tools": true}) {
+		// Report.
+		t.Error("the Decision tick did not separate decision models from the others")
+	} // end of the tick check
+	// The tick is one of the ability keys, so the form reads it.
+	found := false
+	// Look for it.
+	for _, k := range abilityKeys {
+		// The same key.
+		if k == "decision" {
+			// Found.
+			found = true
+		} // end of the key check
+	} // end of the key loop
+	// It must be there.
+	if !found {
+		// Report.
+		t.Error("decision is not an ability key")
+	} // end of the found check
+} // end of TestDecisionModelsAreNotChatModels
+
+// TestUnknownLabelNote checks the notice for labels this program does not know.
+func TestUnknownLabelNote(t *testing.T) {
+	// Nothing unknown: no notice.
+	if n := unknownLabelNote([]siteModel{{Name: "a"}, {Name: "b", Abilities: []string{"tools"}}}); n != "" {
+		// Report.
+		t.Errorf("note for known labels: %q", n)
+	} // end of the empty check
+	// Two unknown labels on three models.
+	n := unknownLabelNote([]siteModel{{Name: "a", Other: []string{"preview"}}, {Name: "b", Other: []string{"preview", "alpha-x"}}, {Name: "c"}})
+	// Both labels with their numbers, in sorted order.
+	if !strings.Contains(n, "alpha-x (1), preview (2)") || !strings.Contains(n, "does not know yet") {
+		// Report.
+		t.Errorf("note = %q", n)
+	} // end of the note check
+} // end of TestUnknownLabelNote
+
+// TestFindPageHasTheDecisionTick checks that the starting page offers the Decision tick with its help text.
+func TestFindPageHasTheDecisionTick(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// The rig.
+	rig := newThemeRig(t)
+	// Ask for the page.
+	status, _, body := get(t, rig.h, http.MethodGet, "/findllm")
+	// It must be there.
+	if status != http.StatusOK {
+		// Report.
+		t.Fatalf("status %d", status)
+	} // end of the status check
+	// The tick and the help text.
+	for _, want := range []string{`name="ab_decision"`, "Decision models (classify, score, yes or no)", "Needs Ollama 0.35.0 or newer."} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+} // end of TestFindPageHasTheDecisionTick
+
+// TestFindSearchHandlesDecisionMixturesAndUnknownLabels runs whole searches against a fake library: Chat and writing leaves out the decision model, the Decision tick finds it, a mixture model counts in the Very large class, and an unknown label is reported.
+func TestFindSearchHandlesDecisionMixturesAndUnknownLabels(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library: a chat model, a decision model, a mixture model and a model with an unknown label.
+	list := listEntry("alpha", "An invented chat model.", "tools", "1b") + listEntry("decider", "An invented decision model.", "decision", "1b") + listEntry("mixer", "An invented mixture model.", "8x7b") + listEntry("newbie", "Has a label nobody knows.", "zzz-new", "1b")
+	// The pages.
+	hits := fakeSite(t, map[string]string{
+		"/library":              "<html><ul>" + list + "</ul></html>",
+		"/library/alpha/tags":   tagEntry("alpha:1b", "700MB", "8K"),
+		"/library/decider/tags": tagEntry("decider:1b", "700MB", "8K"),
+		"/library/mixer/tags":   tagEntry("mixer:8x7b", "26GB", "32K"),
+		"/library/newbie/tags":  tagEntry("newbie:1b", "700MB", "8K"),
+	})
+	// The rig.
+	rig := newThemeRig(t)
+	// Chat and writing, plenty of disk and memory.
+	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"1000"}, "mem_gb": {"1000"}})
+	// It must work.
+	if status != http.StatusOK {
+		// Report.
+		t.Fatalf("status %d: %s", status, body)
+	} // end of the status check
+	// The chat model and the mixture model are listed, the decision model is not, and the unknown label is reported.
+	if !strings.Contains(body, ">alpha<") || !strings.Contains(body, ">mixer<") || strings.Contains(body, ">decider<") || !strings.Contains(html.UnescapeString(body), "does not know yet: zzz-new (1)") {
+		// Report.
+		t.Errorf("chat search: unexpected page: %s", body)
+	} // end of the chat check
+	// The Decision tick alone finds the decision model.
+	_, body = postFind(t, rig, url.Values{"token": {rig.token}, "ab_decision": {"on"}, "disk_gb": {"1000"}, "mem_gb": {"1000"}})
+	// Only the decision model is listed.
+	if !strings.Contains(body, ">decider<") || strings.Contains(body, ">alpha<") || !strings.Contains(body, "Abilities: decision") {
+		// Report.
+		t.Errorf("decision search: unexpected page: %s", body)
+	} // end of the decision check
+	// The Very large class finds the mixture model by its size, not as "no size".
+	_, body = postFind(t, rig, url.Values{"token": {rig.token}, "sz_huge": {"on"}, "disk_gb": {"1000"}, "mem_gb": {"1000"}})
+	// The mixture model is listed.
+	if !strings.Contains(body, ">mixer<") || strings.Contains(body, ">alpha<") {
+		// Report.
+		t.Errorf("size search: unexpected page: %s", body)
+	} // end of the size check
+	// The library was asked at least once.
+	if *hits == 0 {
+		// Report.
+		t.Error("the fake library was never asked")
+	} // end of the hits check
+} // end of TestFindSearchHandlesDecisionMixturesAndUnknownLabels
diff --git a/findllm.go b/findllm.go
index 49fa958..2ee743e 100644
--- a/findllm.go
+++ b/findllm.go
@@ -153,8 +153,26 @@ var contextClasses = []struct {
 
 // paramsBillions turns a size label such as 0.6b, 350m or e4b into billions; ok is false for a label it cannot read.
 func paramsBillions(label string) (float64, bool) {
+	// The label in lower case.
+	l := strings.ToLower(label)
+	// A mixture such as 8x7b is 8 parts of 7 billion: all parts must be loaded, so the sizes are multiplied.
+	mult := 1.0
+	// The mixture sign must have a number in front of it.
+	if i := strings.Index(l, "x"); i > 0 {
+		// The number of parts.
+		f, err := strconv.ParseFloat(l[:i], 64)
+		// Not a number: unreadable.
+		if err != nil {
+			// Unknown.
+			return 0, false
+		} // end of the parts check
+		// Keep the number of parts and read the rest as a normal size.
+		mult = f
+		// The size of one part.
+		l = l[i+1:]
+	} // end of the mixture check
 	// An effective-size label such as e4b counts as its number.
-	l := strings.TrimPrefix(strings.ToLower(label), "e")
+	l = strings.TrimPrefix(l, "e")
 	// The last letter is the unit.
 	if len(l) < 2 {
 		// Too short to read.
@@ -171,12 +189,12 @@ func paramsBillions(label string) (float64, bool) {
 	switch l[len(l)-1] {
 	// Billions.
 	case 'b':
-		// As it is.
-		return n, true
+		// As it is, times the number of parts.
+		return n * mult, true
 	// Millions.
 	case 'm':
-		// A thousandth of a billion.
-		return n / 1000, true
+		// A thousandth of a billion, times the number of parts.
+		return n / 1000 * mult, true
 	} // end of the unit switch
 	// Unknown unit.
 	return 0, false
@@ -280,9 +298,9 @@ func pullsNumber(text string) float64 {
 
 // findSelection is what the person chose on the page.
 type findSelection struct {
-	// Chat is true when "Chat and writing" is ticked: the model is not a search-and-similarity model.
+	// Chat is true when "Chat and writing" is ticked: the model is not a search-and-similarity model and not a decision model.
 	Chat bool
-	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding).
+	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding, decision).
 	Abilities map[string]bool
 	// Sort is how the models are ordered: "downloads" (the default, also when empty) or "name".
 	Sort string
@@ -303,7 +321,7 @@ type findSelection struct {
 } // end of findSelection
 
 // abilityKeys are the ability tick boxes, in the order shown; each is also the label the library list page uses.
-var abilityKeys = []string{"tools", "vision", "audio", "thinking", "embedding"}
+var abilityKeys = []string{"tools", "vision", "audio", "thinking", "embedding", "decision"}
 
 // parseGB reads a typed number of gigabytes; empty text means "not known" (-1); a bad or absurd number is an error.
 func parseGB(text string) (float64, error) {
@@ -518,12 +536,12 @@ func modelBefore(sel findSelection, a, b siteModel) bool {
 func abilitiesMatch(sel findSelection, has map[string]bool) bool {
 	// How many items are ticked and how many of them the model satisfies.
 	ticked, hits := 0, 0
-	// Chat and writing: holds when the model is not an embedding model.
+	// Chat and writing: holds when the model is neither an embedding model nor a decision model (a decision model answers with a choice and probabilities, not with text).
 	if sel.Chat {
 		// One more ticked item.
 		ticked++
-		// Satisfied by a model that is not an embedding model.
-		if !has["embedding"] {
+		// Satisfied by a model that is not an embedding or a decision model.
+		if !has["embedding"] && !has["decision"] {
 			// One more hit.
 			hits++
 		} // end of the chat check
@@ -1399,6 +1417,16 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			// The reason, in plain words.
 			instNote = "The installed models could not be read just now (" + instErr.Error() + "), so installed versions are not marked."
 		} // end of the note check
+		// A label on ollama.com that this program does not know is reported instead of ignored.
+		if lab := unknownLabelNote(models); lab != "" {
+			// Keep an earlier note and add this one.
+			if instNote != "" {
+				// A space between the two sentences.
+				instNote += " "
+			} // end of the space check
+			// Add the sentence.
+			instNote += lab
+		} // end of the label note
 		// The cloud-only models get their own section: no versions are read for them, because nothing is downloaded.
 		cloudModels, cloudSkipped := findCloudModels(models, sel)
 		// How many are shown and how many are only counted.
diff --git a/findsite.go b/findsite.go
index e806c6d..bbc6a79 100644
--- a/findsite.go
+++ b/findsite.go
@@ -16,6 +16,8 @@ import ( // import lists the standard-library packages this file uses.
 	"net/http"
 	// regexp finds the parts of the page.
 	"regexp"
+	// sort puts the unknown labels in a fixed order.
+	"sort"
 	// strconv turns the number text of a download size into a number.
 	"strconv"
 	// strings splits and trims text.
@@ -47,7 +49,7 @@ type siteModel struct {
 	Name string
 	// Description is the one-line description from the page.
 	Description string
-	// Abilities are the ability labels the page shows: tools, vision, thinking, embedding, audio.
+	// Abilities are the ability labels the page shows: tools, vision, thinking, embedding, audio, decision.
 	Abilities []string
 	// Sizes are the size labels the page shows, for example "0.6b" or "350m".
 	Sizes []string
@@ -92,11 +94,11 @@ var entryBadge = regexp.MustCompile(`<span\s+class="inline-flex[^"]*"[^>]*>([^<]
 // entryPulls finds the download count inside one entry.
 var entryPulls = regexp.MustCompile(`<span >([^<]+)</span>\s*<span class="hidden sm:flex">&nbsp;Pulls`)
 
-// sizeLabel recognises a size label such as 0.6b, 350m, 8b or e4b.
-var sizeLabel = regexp.MustCompile(`^e?[0-9]+(\.[0-9]+)?[mb]$`)
+// sizeLabel recognises a size label such as 0.6b, 350m, 8b, e4b or a mixture such as 8x7b (8 parts of 7 billion).
+var sizeLabel = regexp.MustCompile(`^(?:[0-9]+x)?e?[0-9]+(\.[0-9]+)?[mb]$`)
 
 // knownAbility is the set of ability labels the reader understands.
-var knownAbility = map[string]bool{"tools": true, "vision": true, "thinking": true, "embedding": true, "audio": true}
+var knownAbility = map[string]bool{"tools": true, "vision": true, "thinking": true, "embedding": true, "audio": true, "decision": true}
 
 // parseSiteList reads the library list page; it returns errLayout when no entry can be read, and an entry without a name is an error too, so a changed page is noticed instead of half-read.
 func parseSiteList(page string) ([]siteModel, error) {
@@ -161,6 +163,43 @@ func parseSiteList(page string) ([]siteModel, error) {
 	return out, nil
 } // end of parseSiteList
 
+// unknownLabelNote says which labels of the library list this program does not know (not a size, not "cloud", not a known ability), so a new label on ollama.com is noticed instead of silently ignored; it returns empty text when every label is known.
+func unknownLabelNote(models []siteModel) string {
+	// How many models carry each unknown label.
+	seen := map[string]int{}
+	// Look at every model.
+	for _, m := range models {
+		// Count each unknown label once per model.
+		for _, l := range m.Other {
+			// One more model with this label.
+			seen[l]++
+		} // end of the label loop
+	} // end of the model loop
+	// Everything is known.
+	if len(seen) == 0 {
+		// Nothing to say.
+		return ""
+	} // end of the empty check
+	// The labels in a fixed order.
+	names := make([]string, 0, len(seen))
+	// Collect them.
+	for l := range seen {
+		// Add one.
+		names = append(names, l)
+	} // end of the collect loop
+	// Sort them so the text does not change between runs.
+	sort.Strings(names)
+	// Write each label with its number of models.
+	parts := make([]string, 0, len(names))
+	// One part per label.
+	for _, l := range names {
+		// For example: "preview (2 models)".
+		parts = append(parts, fmt.Sprintf("%s (%d)", l, seen[l]))
+	} // end of the parts loop
+	// The sentence.
+	return "ollama.com shows labels this program does not know yet: " + strings.Join(parts, ", ") + " (number of models). They cannot be ticked here and are not shown with the models. Please report them as an issue on the project page."
+} // end of unknownLabelNote
+
 // tagBlock finds the compact block the tags page writes for every version.
 var tagBlock = regexp.MustCompile(`(?s)<a href="/library/([A-Za-z0-9._:-]+)" class="md:hidden[^>]*>(.*?)</a>`)
 
diff --git a/findsite_test.go b/findsite_test.go
index f07358e..81505e2 100644
--- a/findsite_test.go
+++ b/findsite_test.go
@@ -53,7 +53,7 @@ func tagEntry(tag, size, context string) string {
 // TestParseSiteListReadsNamesAbilitiesSizesAndCloud checks what one list page gives.
 func TestParseSiteListReadsNamesAbilitiesSizesAndCloud(t *testing.T) {
 	// A page with three entries: a normal one, an embedding one without sizes, and a cloud one with an unknown label.
-	page := "<html><ul>" + listEntry("alpha", "A &amp; B model.", "tools", "thinking", "0.6b", "8b") + listEntry("beta-embed", "Turns text into numbers.", "embedding") + listEntry("gamma", "Runs far away.", "cloud", "decision", "e4b", "vision") + "</ul></html>"
+	page := "<html><ul>" + listEntry("alpha", "A &amp; B model.", "tools", "thinking", "0.6b", "8b") + listEntry("beta-embed", "Turns text into numbers.", "embedding") + listEntry("gamma", "Runs far away.", "cloud", "decision", "e4b", "vision", "invented-label") + "</ul></html>"
 	// Read it.
 	got, err := parseSiteList(page)
 	// It must work.
@@ -78,8 +78,8 @@ func TestParseSiteListReadsNamesAbilitiesSizesAndCloud(t *testing.T) {
 		// Report.
 		t.Errorf("second model = %+v", got[1])
 	} // end of the second check
-	// The cloud model is marked, keeps its unknown label apart, and counts e4b as a size.
-	if !got[2].Cloud || !reflect.DeepEqual(got[2].Other, []string{"decision"}) || !reflect.DeepEqual(got[2].Sizes, []string{"e4b"}) || !reflect.DeepEqual(got[2].Abilities, []string{"vision"}) {
+	// The cloud model is marked, keeps its unknown label apart, reads decision as an ability, and counts e4b as a size.
+	if !got[2].Cloud || !reflect.DeepEqual(got[2].Other, []string{"invented-label"}) || !reflect.DeepEqual(got[2].Sizes, []string{"e4b"}) || !reflect.DeepEqual(got[2].Abilities, []string{"decision", "vision"}) {
 		// Report.
 		t.Errorf("third model = %+v", got[2])
 	} // end of the third check
diff --git a/findtips.go b/findtips.go
index 683a2bd..085fee9 100644
--- a/findtips.go
+++ b/findtips.go
@@ -13,6 +13,8 @@ var findAbilityLabels = map[string]string{
 	"thinking": "Shows its step-by-step thinking",
 	// Embedding.
 	"embedding": "Search and similarity (embedding)",
+	// Decision.
+	"decision": "Decision models (classify, score, yes or no)",
 } // end of findAbilityLabels
 
 // findTipHeadings maps the name of each help bubble on the Find LLM page to the heading its text is stored under.
@@ -27,8 +29,8 @@ var findTipHeadings = map[string]string{
 	"gpu": "Graphics card",
 	// Chat and writing.
 	"chat": "Chat and writing",
-	// The five abilities.
-	"tools": "Uses tools", "vision": "Understands pictures", "audio": "Understands audio", "thinking": "Shows its step-by-step thinking", "embedding": "Search and similarity (embedding)",
+	// The six abilities.
+	"tools": "Uses tools", "vision": "Understands pictures", "audio": "Understands audio", "thinking": "Shows its step-by-step thinking", "embedding": "Search and similarity (embedding)", "decision": "Decision models (classify, score, yes or no)",
 	// The class groups.
 	"size": "Model size", "context": "Memory of a conversation",
 	// The two fixed ticks.
@@ -87,7 +89,7 @@ var findTexts = map[string]tooltip{
 	// Chat and writing.
 	"Chat and writing": {
 		// What it means.
-		Plain: "Models that write text, as opposed to search-and-similarity models. Ticked by default.",
+		Plain: "Models that write text, as opposed to search-and-similarity models and decision models. Ticked by default.",
 		// A real case.
 		Example: "granite4 is a chat model; nomic-embed-text is a search-and-similarity model.",
 		// What it helps with.
@@ -138,6 +140,15 @@ var findTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Whether you need to search documents by meaning.",
 	}, // end of embedding
+	// Decision.
+	"Decision models (classify, score, yes or no)": {
+		// What it means.
+		Plain: "It does not chat. It classifies text, answers yes or no, or scores text, with probabilities. Needs Ollama 0.35.0 or newer.",
+		// A real case.
+		Example: "nimble can answer: is a refund being requested in this ticket?",
+		// What it helps with.
+		Decide: "Whether you need to sort, route or check text automatically.",
+	}, // end of decision
 	// Model size.
 	"Model size": {
 		// What it means.
OCC_PATCH_123_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files and the new test file must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# The four changed files must be the only changed ones among the files git tracks.
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="findllm.go findsite.go findsite_test.go findtips.go "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only the four expected files changed, plus the new test file"

# The key lines must be in the program.
grep -q '"decision": true' findsite.go && grep -q '"decision"}' findllm.go && grep -q 'func unknownLabelNote' findsite.go || fail "a key line of the change is missing"
# Report it.
pass "decision ability, mixture sizes and the unknown-label notice are in the program"

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

# Run every test once; the delete-confirm test failed once without a known cause, so a single failure of exactly that test is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestDeleteConfirmRefusesLoadedModel failed, tell Claude)"
# Report it.
pass "go test: all tests pass"

# Build the program for all six systems.
for TARGET in linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Build to nowhere (/dev/null) just to see that it compiles.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -o /dev/null . || fail "build for $TARGET failed"
  # Report it.
  pass "program builds for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  try the page by hand (instructions follow in the chat), then commit and push."
# Show what changed in the project folder.
git status --short
