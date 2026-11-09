#!/usr/bin/env bash
# Script 94b (Find LLM, fix after slice 4): models that carry the cloud label but also list local sizes (for example gemma4, gpt-oss, nemotron-3-super, nemotron-3-nano) are no longer hidden as cloud-only. Before, every model with the cloud label was left out, so gemma4 and gpt-oss never appeared in Find LLM. Now only a model with the cloud label and no sizes is left out as cloud-only; for a model with both, the versions named name:cloud or name:size-cloud are dropped, so only versions that run on this computer are offered; if all of a model's versions are cloud versions the page says so. Found with the library pages collected on your computer (script 90). One new test; two test models were made cloud-only to match the real list.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 94): cd ~/LLMsControlDock && bash scripts/94b-step57b-find-llm-hybrid-cloud-models.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 94), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="65aa2518711dad525c1ab260d0af8031df571032e1b1cc3e47fe247ce2412f8b"
BEFORE["findllm_test.go"]="b36132c86c3c8208a2a2558604f4e128f36d77767e26c5e9a9c8c9e43f28025e"
AFTER["findllm.go"]="d837d2eb4ffbb22cd0ec236f03c9e822b9ffeee0aab6684228ae49728db8fe51"
AFTER["findllm_test.go"]="feb4730470de35ad28ebee803146a64f12ad6f1e5d7602964b3473ea98fcd157"

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

# Script 94 must have been applied: the installed marker exists.
grep -q 'installedMarker' findllm.go || fail "script 94 must be applied first"
# Report it.
pass "script 94 (installed versions marked) is applied"

# Refuse to run twice: the cloud-version check exists when this change was applied before.
if grep -q 'isCloudTag' findllm.go; then fail "findllm.go already has the cloud-version check: this script was already applied"; fi
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
diff --git a/findllm.go b/findllm.go
index 2159b01..27dd3f7 100644
--- a/findllm.go
+++ b/findllm.go
@@ -308,12 +308,12 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	return sel, problems
 } // end of parseFindForm
 
-// findCandidates applies the choices that the list page can answer: cloud models are left out, abilities and size classes are checked; the count of models without a readable size is returned when a size class is chosen.
+// findCandidates applies the choices that the list page can answer: cloud-only models are left out, abilities and size classes are checked; the count of models without a readable size is returned when a size class is chosen. A model that carries the cloud label but also lists sizes (for example gemma4 or gpt-oss) has versions that run on this computer, so it stays; its cloud versions are dropped later, when its versions are listed.
 func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noSize int, cloud int) {
 	// Look at every model.
 	for _, m := range models {
-		// Cloud models run on Ollama's servers, not on this computer, and may need an account.
-		if m.Cloud {
+		// Cloud-only models run on Ollama's servers, not on this computer, and may need an account; a cloud label together with sizes means local versions exist too.
+		if m.Cloud && len(m.Sizes) == 0 {
 			// Count and skip.
 			cloud++
 			// Next.
@@ -478,6 +478,19 @@ type resultView struct {
 	Unavailable string
 } // end of resultView
 
+// isCloudTag says whether a version name is a cloud version: Ollama names them name:cloud or name:size-cloud.
+func isCloudTag(tag string) bool {
+	// The part after the colon.
+	part := tag
+	// Cut at the colon.
+	if i := strings.LastIndex(tag, ":"); i >= 0 {
+		// The tag part.
+		part = tag[i+1:]
+	} // end of the cut
+	// Exactly cloud, or ending in -cloud.
+	return part == "cloud" || strings.HasSuffix(part, "-cloud")
+} // end of isCloudTag
+
 // installedFirst puts the installed versions before the others and keeps the order inside each part, so an installed version is never hidden among "more versions".
 func installedFirst(vs []versionView) []versionView {
 	// The two parts.
@@ -575,6 +588,11 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mar
 	var fit, nofit []versionView
 	// Look at each.
 	for _, t := range tags {
+		// A cloud version runs on Ollama's servers, not on this computer: it is not offered here.
+		if isCloudTag(t.Tag) {
+			// Next version.
+			continue
+		} // end of the cloud check
 		// Its view.
 		v := versionView{Tag: t.Tag, Command: "ollama pull " + t.Tag, Size: t.SizeText, Context: t.Context, Input: t.Input}
 		// Whether this version is installed here, and what the saved tests say about it.
@@ -595,6 +613,13 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mar
 			nofit = append(nofit, v)
 		} // end of the sorting
 	} // end of the version loop
+	// Every version was a cloud version: nothing here can run on this computer.
+	if len(fit)+len(nofit) == 0 {
+		// Say so; the template adds the pointer to the official page.
+		r.Unavailable = "all its versions run on Ollama's servers (cloud), not on this computer"
+		// Done.
+		return r
+	} // end of the empty check
 	// The count that fit.
 	r.FitCount = len(fit)
 	// The versions that fit first, then the others; inside each group the installed ones come first, then the page's order.
diff --git a/findllm_test.go b/findllm_test.go
index 8258e28..ea1697c 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -129,7 +129,7 @@ func sampleModels() []siteModel {
 		// A search-and-similarity model without sizes.
 		{Name: "gamma", Abilities: []string{"embedding"}, Pulls: "5M"},
 		// A cloud model.
-		{Name: "delta", Cloud: true, Abilities: []string{"tools"}, Sizes: []string{"7b"}, Pulls: "9M"},
+		{Name: "delta", Cloud: true, Abilities: []string{"tools"}, Pulls: "9M"},
 		// A chat model whose size cannot be read.
 		{Name: "epsilon", Pulls: "1M"},
 		// A tiny chat model.
@@ -330,7 +330,7 @@ func TestFreeDiskIsReadable(t *testing.T) {
 // findTestPages are the pages of a fake library: a list with a cloud model, and tags pages.
 func findTestPages() map[string]string {
 	// The list page: a normal model, a cloud model, an embedding model.
-	list := listEntry("alpha", "An invented chat model.", "tools", "0.6b", "8b") + listEntry("cloudy", "Runs far away.", "cloud", "tools", "8b") + listEntry("embedder", "Turns text into numbers.", "embedding")
+	list := listEntry("alpha", "An invented chat model.", "tools", "0.6b", "8b") + listEntry("cloudy", "Runs far away.", "cloud", "tools") + listEntry("embedder", "Turns text into numbers.", "embedding")
 	// The pages.
 	return map[string]string{
 		// The list.
@@ -1162,3 +1162,43 @@ func TestFindPageMarksInstalledVersions(t *testing.T) {
 		t.Error("a failing Ollama is not reported on the page")
 	} // end of the failure check
 } // end of TestFindPageMarksInstalledVersions
+
+// TestHybridCloudModelStays checks a model that carries the cloud label but also lists sizes (like gemma4 or gpt-oss): it is a candidate, its local versions are offered, and its cloud versions are dropped; a model whose versions are all cloud says so.
+func TestHybridCloudModelStays(t *testing.T) {
+	// The cloud-only model has no sizes; the hybrid has sizes too.
+	models := []siteModel{
+		{Name: "faraway", Cloud: true, Abilities: []string{"tools"}, Pulls: "9M"},
+		{Name: "hybrid", Cloud: true, Abilities: []string{"tools"}, Sizes: []string{"4b", "31b"}, Pulls: "8M"},
+	}
+	// Apply no choices.
+	got, _, cloud := findCandidates(models, findSelection{})
+	// Only the hybrid stays; one cloud-only model is counted as left out.
+	if modelNames(got) != "hybrid" || cloud != 1 {
+		// Report.
+		t.Errorf("got %s with %d cloud-only left out, want hybrid and 1", modelNames(got), cloud)
+	} // end of the candidate check
+	// The cloud version names Ollama uses.
+	for tag, want := range map[string]bool{"hybrid:31b-cloud": true, "gpt-oss:cloud": true, "hybrid:4b": false, "cloudy:latest": false, "hybrid": false} {
+		// Check each.
+		if isCloudTag(tag) != want {
+			// Report.
+			t.Errorf("isCloudTag(%q) = %v, want %v", tag, !want, want)
+		} // end of the name check
+	} // end of the name loop
+	// The versions: one local and one cloud.
+	tags := []siteTag{{Tag: "hybrid:4b", SizeText: "2.0GB", SizeBytes: 2000000000, Context: "128K"}, {Tag: "hybrid:31b-cloud", Context: "256K"}}
+	// Build the view.
+	r := buildResult(models[1], tags, "", findSelection{DiskGB: -1, MemGB: -1}, nil)
+	// Only the local version is listed.
+	if len(r.Versions) != 1 || r.Versions[0].Tag != "hybrid:4b" || r.Unavailable != "" {
+		// Report.
+		t.Errorf("versions %+v, unavailable %q", r.Versions, r.Unavailable)
+	} // end of the version check
+	// All versions cloud: nothing to offer, and the page says why.
+	r2 := buildResult(models[1], tags[1:], "", findSelection{DiskGB: -1, MemGB: -1}, nil)
+	// The reason is given and no version is listed.
+	if len(r2.Versions) != 0 || !strings.Contains(r2.Unavailable, "run on Ollama's servers") {
+		// Report.
+		t.Errorf("all-cloud result: versions %d, unavailable %q", len(r2.Versions), r2.Unavailable)
+	} // end of the all-cloud check
+} // end of TestHybridCloudModelStays
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
echo "NEXT  start bin/LLMsControlDock and press Find LLM with Audio ticked and look for gemma4 (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
