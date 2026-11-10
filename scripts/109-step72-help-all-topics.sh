#!/usr/bin/env bash
# Script 109 (Help page, all topics): the Help page now holds eleven topics as swimlane diagrams, in the order a person typically meets them: System check, Find LLM, Load a model, Tune a model, Performance test, Compare and re-test, Unload a model, Delete and restore a model, Settings, Stop the program and Uninstall. Every step was written from what the program's pages and handlers really do. Tests follow.
# Run it from the branch feature/help-topics-open-close (after script 108), or from a new branch made from main after script 108 is merged: cd ~/LLMsControlDock && bash scripts/109-step72-help-all-topics.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 108), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help.go"]="2d3041719ee1df54aae085e8a8ecf4781153336667071583323480df68dab175"
BEFORE["help_test.go"]="ba1b4ade36d6d53abed2d70d907d749461654f4c8f4e45df0c8107eda2aee4cd"
AFTER["help.go"]="a5cd05c3e84a5f46fc41f28508b6368a6f07d89fa2cf3581071fcb7b4cd03d19"
AFTER["help_test.go"]="1f2174fe0af00f9bd66049ba995bf13ccf9b09b12402da4c0650b85d8504d682"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/help-topics-open-close (git switch feature/help-topics-open-close)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 108 must have been applied: the Help topics are closed sections.
grep -q '<details class="helptopic"' web/help.html || fail "script 108 must be applied first"
# Report it.
pass "script 108 is applied"

# Refuse to run twice: the last topic exists when this change was applied before.
if grep -q 'ID:    "uninstall"' help.go; then fail "help.go already has all the topics: this script was already applied"; fi
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
diff --git a/help.go b/help.go
index a5682de..6ebafa3 100644
--- a/help.go
+++ b/help.go
@@ -46,8 +46,23 @@ type helpTopic struct {
 	Steps []helpStep
 } // end of helpTopic
 
-// helpTopics are the topics of the Help page; each one is checked against what the program really does.
+// helpTopics are the topics of the Help page, in the order a person typically meets them (first start, finding and loading a model, tuning, testing, comparing, tidying up, settings, stopping, uninstalling); each one is checked against what the program really does.
 var helpTopics = []helpTopic{
+	{
+		ID:    "system-check",
+		Title: "System check: what this computer offers",
+		Intro: "The first time the program starts, it shows this report before the monitor. It lists the processors, memory and graphics cards of this computer, checks that Ollama is found and states what the tool needs. If a problem stops the tool from working fully, an alert lists the steps to fix it. The report stays available later in the footer bar.",
+		Steps: []helpStep{
+			{0, "Start LLMsControlDock for the first time."},
+			{1, "Opens the System check before the monitor."},
+			{1, "Reads this computer: processors, memory, graphics cards."},
+			{1, "Asks Ollama for its version."},
+			{2, "Answers with its version, or does not answer."},
+			{1, "Shows the report. A problem opens an alert with the fixes."},
+			{0, "Read it and press Continue to the monitor."},
+			{1, "Remembers the answer and opens the monitor."},
+		},
+	},
 	{
 		ID:    "find-llm",
 		Title: "Find LLM: from your needs to a model you can install",
@@ -67,6 +82,142 @@ var helpTopics = []helpTopic{
 			{2, "Downloads the model when you run the command."},
 		},
 	},
+	{
+		ID:    "load-model",
+		Title: "Load a model into memory",
+		Intro: "Loading puts an installed model into memory, so that it answers quickly. Nothing is loaded until you confirm. If the free memory is short or close to what the model needs, the page warns you first.",
+		Steps: []helpStep{
+			{0, "Press Load on the model's row in the monitor."},
+			{1, "Shows the free memory and the memory the model needs."},
+			{0, "Choose how long it stays loaded and confirm."},
+			{1, "Asks Ollama to load the model."},
+			{2, "Reads the model from disk into memory."},
+			{1, "Asks Ollama until the model is listed as loaded."},
+			{2, "Reports its loaded models."},
+			{1, "Shows the result and the time before Ollama unloads it."},
+		},
+	},
+	{
+		ID:    "tune-model",
+		Title: "Tune a model: inference parameters",
+		Intro: "Inference parameters are stored inside the model in Ollama, so every program that loads the model without a value of its own uses them. The model must not be loaded: a loaded model keeps the settings it was loaded with. A saved setting can be changed but never emptied. The Modelfile button only shows the model's Modelfile, read-only.",
+		Steps: []helpStep{
+			{0, "Press the inference parameters icon on an unloaded model."},
+			{1, "Shows the saved values and a field for each new one."},
+			{0, "Type the new values and press Review the changes."},
+			{1, "Shows now and after saving, and warns that the model changes."},
+			{0, "Press Yes, save them into the model."},
+			{1, "Asks Ollama to save the values in the model."},
+			{2, "Stores them inside the model."},
+			{1, "Asks Ollama again what it reports and shows the result."},
+		},
+	},
+	{
+		ID:    "performance-test",
+		Title: "Performance test of a model",
+		Intro: "The test measures how fast a model runs on this machine. It uses the same fixed prompt every time and saves only numbers, never any text. Do not run it while the model is in use: a loaded model is refused, and the page warns when the machine looks busy.",
+		Steps: []helpStep{
+			{0, "Press Performance on an unloaded model's row."},
+			{1, "Shows the cautions, the steps of the test and its time."},
+			{0, "Make sure nobody uses the model and press Run."},
+			{1, "Sends a warm-up request; its load time is the cold figure."},
+			{2, "Loads the model from disk and answers."},
+			{1, "Sends three timed requests and keeps the median."},
+			{2, "Answers each timed request."},
+			{1, "Reads Ollama's report and the machine; saves numbers only."},
+			{2, "Unloads the model, so memory is left as it was found."},
+			{1, "Shows the speed and the tests saved for this model."},
+		},
+	},
+	{
+		ID:    "compare-models",
+		Title: "Compare tested models, and re-test",
+		Intro: "Compare lists the models that already went through a performance test, in groups, with the reason for each group and how to read the figures. A re-test adds new results for a group and keeps the old ones. A loaded model is left alone, because it may be in use.",
+		Steps: []helpStep{
+			{0, "Press Compare tested models on the monitor."},
+			{1, "Groups the tested models and shows their figures."},
+			{0, "Read the groups. Save a PDF or CSV if you wish."},
+			{0, "Press Re-test this group to add new results."},
+			{1, "Shows which models will be tested. Nothing runs yet."},
+			{0, "Press Yes, re-test."},
+			{1, "Tests the models one after another, as in a performance test."},
+			{2, "Loads each model, answers, and unloads it."},
+			{1, "Saves a new result for each model. Old results stay."},
+			{0, "Press Show the comparison to see the new figures."},
+		},
+	},
+	{
+		ID:    "unload-model",
+		Title: "Unload a model from memory",
+		Intro: "Unloading frees the memory of a loaded model. The monitor cannot see whether a model is working on a request right now, so the page warns you first. If you do nothing, Ollama unloads the model by itself after its time runs out.",
+		Steps: []helpStep{
+			{0, "Press Unload on a loaded model's row."},
+			{1, "Warns that it cannot see whether the model is in use."},
+			{0, "Press Yes, unload it now, only if nothing uses the model."},
+			{1, "Asks Ollama to unload the model now."},
+			{2, "Unloads the model."},
+			{1, "Checks that it left the loaded list and tells you."},
+		},
+	},
+	{
+		ID:    "delete-restore",
+		Title: "Delete a model, and restore it later",
+		Intro: "Delete removes a model from this computer and frees its disk space; the tuning you made is lost. Restore downloads the latest version of the same name again. A model you made yourself, from a Modelfile or an import, cannot be downloaded again. A loaded model asks for a hold, or for its name typed to force the delete.",
+		Steps: []helpStep{
+			{0, "Press Delete on the model's row."},
+			{1, "Explains what you lose and how much space it frees."},
+			{0, "Press Yes, delete it."},
+			{1, "Saves a snapshot of the model's inference parameters."},
+			{1, "Asks Ollama to delete the model."},
+			{2, "Removes the model and frees the disk space."},
+			{1, "Remembers name, size and time; greys the row out."},
+			{0, "Press Restore when you want the model back."},
+			{1, "Shows the pull command for each way Ollama runs."},
+			{0, "Run the command where Ollama runs."},
+			{3, "Sends the latest version of that name."},
+			{2, "Stores it; the greyed row disappears."},
+		},
+	},
+	{
+		ID:    "settings",
+		Title: "Settings",
+		Intro: "Settings holds the Ollama address, the check interval, the timeout, the chart history and the access from other machines. Values marked restart are used the next time the monitor starts; the others apply at once. The desktop icon is created, updated or removed on the same page.",
+		Steps: []helpStep{
+			{0, "Press Settings in the monitor's top bar."},
+			{1, "Shows each setting: in use now, new value and default."},
+			{0, "Change what you need and press Save settings."},
+			{1, "Checks every value. A wrong one is refused with a reason."},
+			{1, "Saves the values in the settings folder."},
+			{1, "Applies at once what is not marked restart."},
+			{0, "Stop and start the program for settings marked restart."},
+		},
+	},
+	{
+		ID:    "stop-program",
+		Title: "Stop the program",
+		Intro: "Stopping closes LLMsControlDock. Ollama and its models are not touched: whatever is loaded stays loaded.",
+		Steps: []helpStep{
+			{0, "Press Stop in the monitor's top bar."},
+			{1, "Asks first, and says what is running right now."},
+			{0, "Press Yes, stop the monitor."},
+			{1, "Closes the program."},
+			{2, "Stays as it was. Loaded models stay loaded."},
+			{0, "Start the program again when you need it."},
+		},
+	},
+	{
+		ID:    "uninstall",
+		Title: "Uninstall",
+		Intro: "Uninstalling deletes what this tool collected on this computer: its settings, the performance results and saved comparisons, the list of deleted models, the check history and the desktop icon. Ollama, its models and the program file are not touched. A running program cannot delete itself, so you delete the program file yourself.",
+		Steps: []helpStep{
+			{0, "Open System check and press Uninstall this tool."},
+			{1, "Lists what would be removed, and where."},
+			{0, "If data was saved, type uninstall and press OK."},
+			{1, "Deletes those items and stops the program."},
+			{2, "Not touched. Its models stay."},
+			{0, "Delete the program file yourself. The page shows where it is."},
+		},
+	},
 } // end of helpTopics
 
 // The measures of a diagram, in the units of its drawing area.
diff --git a/help_test.go b/help_test.go
index 422fecc..92532ac 100644
--- a/help_test.go
+++ b/help_test.go
@@ -112,17 +112,26 @@ func TestHelpPage(t *testing.T) {
 				} // end of the line check
 			} // end of the line loop
 		} // end of the step loop
-		// One box per step and one arrow between each pair.
-		if n := strings.Count(body, `class="lanebox"`); n != len(tp.Steps) {
-			// Report.
-			t.Errorf("%d boxes, want %d", n, len(tp.Steps))
-		} // end of the box check
-		// The arrows.
-		if n := strings.Count(body, `class="lanearrow"`); n != len(tp.Steps)-1 {
-			// Report.
-			t.Errorf("%d arrows, want %d", n, len(tp.Steps)-1)
-		} // end of the arrow check
 	} // end of the topic loop
+	// One box per step and one arrow between each pair, over all topics.
+	boxes, arrows := 0, 0
+	// Add them up.
+	for _, tp := range helpTopics {
+		// Steps and the arrows between them.
+		boxes += len(tp.Steps)
+		// One fewer arrow than steps.
+		arrows += len(tp.Steps) - 1
+	} // end of the sum loop
+	// Compare with the page.
+	if n := strings.Count(body, `class="lanebox"`); n != boxes {
+		// Report.
+		t.Errorf("%d boxes, want %d", n, boxes)
+	} // end of the box check
+	// The arrows.
+	if n := strings.Count(body, `class="lanearrow"`); n != arrows {
+		// Report.
+		t.Errorf("%d arrows, want %d", n, arrows)
+	} // end of the arrow check
 	// Every lane has its name.
 	for _, l := range helpLanes {
 		// Look for it.
@@ -149,9 +158,13 @@ func TestHelpPage(t *testing.T) {
 			t.Errorf("topic %s has no clickable title", tp.ID)
 		} // end of the title check
 		// An arrow at the top of the open topic (before the picture) and one at the bottom (after the list).
-		top, bottom := strings.Index(body, `id="tipback-`+tp.ID+`-top"`), strings.Index(body, `id="tipback-`+tp.ID+`-bottom"`)
+		start := strings.Index(body, `<details class="helptopic" id="`+tp.ID+`">`)
+		// The topic's own section.
+		sec := body[start : start+strings.Index(body[start:], `</details>`)]
+		// The arrows, the picture and the list inside it.
+		top, bottom := strings.Index(sec, `id="tipback-`+tp.ID+`-top"`), strings.Index(sec, `id="tipback-`+tp.ID+`-bottom"`)
 		// The picture and the list.
-		svg, list := strings.Index(body, `<svg class="swimlane"`), strings.Index(body, `<ol class="helpsteps">`)
+		svg, list := strings.Index(sec, `<svg class="swimlane"`), strings.Index(sec, `<ol class="helpsteps">`)
 		// Check the order.
 		if top < 0 || bottom < 0 || !(top < svg && list < bottom) {
 			// Report.
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
echo "NEXT  start bin/LLMsControlDock and open the Help page and open each topic (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
