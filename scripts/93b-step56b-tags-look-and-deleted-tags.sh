#!/usr/bin/env bash
# Script 93b (Find LLM, change after slice 3): (1) the tags no longer look like buttons: each tag line is plain small text in the muted colour, starts with a small tag symbol, and the tags are separated by dots; there is no outline and no background. (2) Deleted models show their tags too: when a model is deleted, the size, memory and abilities Ollama reports are saved with it, and the greyed row shows its tags; an entry saved before this change shows size and memory from its saved performance tests when there are any (never from the name), otherwise it says that no tags were saved for it. Older saved entries still load. Four new tests.
# Run it from the project folder, on the branch feature/find-llm-tags after script 93: cd ~/LLMsControlDock && bash scripts/93b-step56b-tags-look-and-deleted-tags.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 93), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["delete.go"]="51f76d0d3b862e9b0fa90298eb4b38e4490607c3c0dc9ed4f3d3feeba8b6ec46"
BEFORE["delete_test.go"]="97ac350fe59406fc0666e200193d26791717a59702204bc622909d7d36d71e94"
BEFORE["deletestore.go"]="030fcdda19273874daee26bed568e7fc1400f7128f9a2440b88a17d724c4add9"
BEFORE["findllm_test.go"]="44f54d27e01107b6d00da54f6a176d35a5a2e30a6cf6757cd231ba863cd75975"
BEFORE["perfstore.go"]="3ce6cb31b50d18c5a6e3d4a46df8aa648109636865c1609493d57053435cf559"
BEFORE["tableview.go"]="1dfecf26da27cdf7c3fd13cf18f7d188a1a0ace4ea9b0e9938f578a114c96f11"
BEFORE["tags.go"]="0006f1b8ef856792751bb3199b8f47c773211606570b732fdb9ea54b9cd43ed5"
BEFORE["timezone_test.go"]="b92b0a8a3886bd37adb6fb0c352ec1cdee42cebd994c2e76630f7542801df28e"
BEFORE["web.go"]="9ac06158c2ad3b17aaae3cc228f2fe3b77d6d4b617da07961ed67c7251de588b"
BEFORE["web/app.css"]="bb5b4c95098c4b3174b6258b0e79b622b238614b79050414869929e057a82cd8"
BEFORE["web/index.html"]="8f7b8cd834ead120620d4eb07a0c7ffdc0cebe5037e86b818eac1cec0733f287"
AFTER["delete.go"]="5d2c3c9551e19396b4a0f5776b445d0199cd57ad0ffd8fb870748858fc2638b6"
AFTER["delete_test.go"]="867f58b041660e97c1db2263d7c385a1b6875fb86669c614d19f4cb18d28e974"
AFTER["deletestore.go"]="540575e533660842b989a7c64be841fe6274d5deb4b00d9fbb2646c8d5ee1c5c"
AFTER["findllm_test.go"]="2569db7a43facc4fe642a21c31556bad4fc9b84b00e5ac4e9f2d4f958c9cdcf0"
AFTER["perfstore.go"]="ccc64a9df1454deabdc4636d1f87b6fb77b90dbf1ea55df5d374cf9cc97a276b"
AFTER["tableview.go"]="42822c022a4b1412c96c20a2bf84498e848889be9d1c306de02ff9964f8b225c"
AFTER["tags.go"]="b54ad170ff19094f16ed4fafa2f5856218d676572fc427776c382191b635b3d3"
AFTER["timezone_test.go"]="4da152d8b1fd4642865e9b6319730546650a0d96418ae3e966d2badbab363eb3"
AFTER["web.go"]="305fcbb6ffd793b8311e6bcc98ece14a0b716669c8880a57f1034de655e01551"
AFTER["web/app.css"]="f8d78e2266ad12c86f39748adfcd7f3b941d03243bc91e41bc5e099de5fb264d"
AFTER["web/index.html"]="6d2b427150aa5c444b012297bd054b84e3b9c3fe33a71e020635d8e3e5370129"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-tags"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 93 must have been applied: its files exist.
[ -e tags.go ] && [ -e findcopy.go ] || fail "script 93 must be applied first"
# Report it.
pass "script 93 (tags and offline list) is applied"

# Refuse to run twice: the new function exists when this change was applied before.
if grep -q 'lastFacts' perfstore.go; then fail "perfstore.go already has the change: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_93B_END'
diff --git a/delete.go b/delete.go
index d3e6adc..fe48ead 100644
--- a/delete.go
+++ b/delete.go
@@ -309,7 +309,7 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore, hist
 		// Remember it, so the table can show it greyed out and Restore can offer it again.
 		note := ""
 		// Save; a failure does not undo the deletion, it only means the ghost row will be missing.
-		if err := store.add(deletedModel{Name: m.Name, Digest: m.Digest, Size: m.Size, DeletedAt: at}); err != nil {
+		if err := store.add(deletedModel{Name: m.Name, Digest: m.Digest, Size: m.Size, DeletedAt: at, ParameterSize: m.Details.ParameterSize, ContextLength: m.Details.ContextLength, Capabilities: m.Capabilities}); err != nil {
 			// Say so in words.
 			note = "The model is deleted, but this monitor could not remember it, so there will be no Restore row. " + err.Error()
 		} // end of the save check
diff --git a/delete_test.go b/delete_test.go
index b1f7934..8b506f7 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -461,13 +461,18 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 	// The main page now shows the greyed row with a restore form, and the model is not in the installed rows.
 	_, _, page := get(t, rig.h, http.MethodGet, "/")
 	// The things that must be there.
-	for _, want := range []string{`data-deleted="alpha:1b"`, "<s>alpha:1b</s>", `action="/restore"`, "Restore: how to download this model again, and the parameters it had", "Deleted models", "1.3 GB"} {
+	for _, want := range []string{`data-deleted="alpha:1b"`, "<s>alpha:1b</s>", `action="/restore"`, "Restore: how to download this model again, and the parameters it had", "Deleted models", "1.3 GB", `<span class="mtag">`} {
 		// Look for it.
 		if !strings.Contains(page, want) {
 			// Report the gap.
 			t.Errorf("the main page lacks %q", want)
 		} // end of the check
 	} // end of the loop
+	// The model was deleted by this version, so its tags were saved and the "no tags" note is not shown.
+	if strings.Contains(page, "no tags were saved for it") {
+		// Report it.
+		t.Errorf("the greyed row says no tags were saved although the model had them")
+	} // end of the note check
 	// The ghost row must not carry data-model (the refresh script compares those).
 	if strings.Contains(page, `data-model="alpha:1b"`) {
 		// Report it.
diff --git a/deletestore.go b/deletestore.go
index 5d5fbfa..d6f868d 100644
--- a/deletestore.go
+++ b/deletestore.go
@@ -42,6 +42,12 @@ type deletedModel struct {
 	Size int64 `json:"size"`
 	// DeletedAt is the moment of deletion.
 	DeletedAt time.Time `json:"deleted_at"`
+	// ParameterSize, ContextLength and Capabilities are what Ollama reported about the model at deletion time, so the greyed row can show its tags; entries saved by earlier versions do not have them.
+	ParameterSize string `json:"parameter_size,omitempty"`
+	// ContextLength is the largest context in tokens.
+	ContextLength int64 `json:"context_length,omitempty"`
+	// Capabilities are Ollama's own words for the abilities.
+	Capabilities []string `json:"capabilities,omitempty"`
 } // end of deletedModel
 
 // deletedFile is the layout of the file on disk.
diff --git a/findllm_test.go b/findllm_test.go
index 2cd4e89..d25a6e9 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -2,6 +2,8 @@
 package main
 
 import ( // import lists the standard-library packages this test file uses.
+	// encoding/json checks what is saved for a deleted model.
+	"encoding/json"
 	// html escapes a help text the way the page does.
 	"html"
 	// io reads a reply body.
@@ -766,3 +768,101 @@ func TestHomePageShowsTagsAndTheGroupingHelp(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 } // end of TestHomePageShowsTagsAndTheGroupingHelp
+
+// TestDeletedTags checks the tags of a deleted model: from what was saved at deletion, otherwise from the saved tests, never from the name.
+func TestDeletedTags(t *testing.T) {
+	// Saved tests know the size and memory of one model only.
+	facts := func(name string) (string, int64, bool) {
+		// Only this model was tested.
+		if name == "tested:1b" {
+			// Its facts.
+			return "1.1B", 8192, true
+		} // end of the name check
+		// Nothing for the others.
+		return "", 0, false
+	} // end of facts
+	// The cases.
+	for _, c := range []struct {
+		// d is the remembered model.
+		d deletedModel
+		// want are the tags in order.
+		want []string
+	}{
+		// Saved at deletion by this version: all three kinds of tag.
+		{deletedModel{Name: "a:27b", ParameterSize: "27.3B", ContextLength: 262144, Capabilities: []string{"completion", "vision", "tools"}}, []string{"Large model", "Very long memory", "Pictures", "Tools"}},
+		// Saved by an earlier version, but tested: size and memory only, no abilities.
+		{deletedModel{Name: "tested:1b"}, []string{"Small model", "Medium memory"}},
+		// Saved by an earlier version and never tested: nothing, and the name is not used to guess ("135m" is in it).
+		{deletedModel{Name: "smollm2:135m"}, nil},
+		// What was saved wins over the tests.
+		{deletedModel{Name: "tested:1b", ParameterSize: "8.0B", ContextLength: 131072}, []string{"Medium model", "Long memory"}},
+	} {
+		// Work it out.
+		got := deletedTags(c.d, facts)
+		// Compare.
+		if strings.Join(got, "|") != strings.Join(c.want, "|") {
+			// Report.
+			t.Errorf("tags of %s = %v, want %v", c.d.Name, got, c.want)
+		} // end of the comparison
+	} // end of the case loop
+	// No tests at all (nil lookup) is the same as nothing known.
+	if got := deletedTags(deletedModel{Name: "x:1b"}, nil); got != nil {
+		// Report.
+		t.Errorf("tags without any facts = %v", got)
+	} // end of the nil check
+} // end of TestDeletedTags
+
+// TestDeletedModelFileKeepsTheFacts checks that the new facts are saved in the file, and that a file written by an earlier version still loads.
+func TestDeletedModelFileKeepsTheFacts(t *testing.T) {
+	// Write and read back a model with facts.
+	body, err := json.Marshal(deletedModel{Name: "a:27b", ParameterSize: "27.3B", ContextLength: 262144, Capabilities: []string{"completion", "vision"}})
+	// A failure means the test is broken.
+	if err != nil {
+		// Stop.
+		t.Fatalf("marshal: %v", err)
+	} // end of the marshal check
+	// Read it back.
+	var back deletedModel
+	// Decode.
+	if err := json.Unmarshal(body, &back); err != nil || back.ParameterSize != "27.3B" || back.ContextLength != 262144 || len(back.Capabilities) != 2 {
+		// Report.
+		t.Errorf("facts lost: %+v (%v)", back, err)
+	} // end of the read-back check
+	// An entry of an earlier version has none of the new keys.
+	var old deletedModel
+	// Decode it.
+	if err := json.Unmarshal([]byte(`{"name":"smollm2:135m","digest":"d","size":271000000,"deleted_at":"2026-10-27T21:37:00Z"}`), &old); err != nil || old.Name != "smollm2:135m" || old.ParameterSize != "" || old.ContextLength != 0 || old.Capabilities != nil {
+		// Report.
+		t.Errorf("old entry not read cleanly: %+v (%v)", old, err)
+	} // end of the old-entry check
+	// A model without facts writes none of the new keys.
+	plain, _ := json.Marshal(deletedModel{Name: "x:1b"})
+	// They must be absent.
+	if strings.Contains(string(plain), "parameter_size") || strings.Contains(string(plain), "capabilities") || strings.Contains(string(plain), "context_length") {
+		// Report.
+		t.Errorf("empty facts were written: %s", plain)
+	} // end of the absence check
+} // end of TestDeletedModelFileKeepsTheFacts
+
+// TestPerfLastFacts checks that the newest recorded size and memory of a model come from its saved tests.
+func TestPerfLastFacts(t *testing.T) {
+	// A store with three runs of one model and one of another.
+	s := &perfStore{runs: []perfRun{
+		// The oldest run has a size and a memory.
+		{Model: "m:1b", ParameterSize: "1.0B", ContextLength: 4096},
+		// A run of another model.
+		{Model: "other:7b", ParameterSize: "7.0B", ContextLength: 32768},
+		// A newer run that recorded only the size.
+		{Model: "m:1b", ParameterSize: "1.1B"},
+	}}
+	// The newest size, and the memory from the older run that had it.
+	if p, c, ok := s.lastFacts("m:1b"); !ok || p != "1.1B" || c != 4096 {
+		// Report.
+		t.Errorf("lastFacts = %q, %d, %v", p, c, ok)
+	} // end of the check
+	// A model with no run.
+	if _, _, ok := s.lastFacts("never:1b"); ok {
+		// Report.
+		t.Error("lastFacts found facts for an untested model")
+	} // end of the absence check
+} // end of TestPerfLastFacts
diff --git a/perfstore.go b/perfstore.go
index e6be1cf..045ae2e 100644
--- a/perfstore.go
+++ b/perfstore.go
@@ -306,6 +306,38 @@ func (s *perfStore) forModel(model, kind string) []perfRun {
 	return out
 } // end of forModel
 
+// lastFacts returns the newest parameter size and context length that any saved test of the model recorded; the second answer is false when no test recorded either. It lets a deleted model, whose own facts were not saved, still show its size and memory tags.
+func (s *perfStore) lastFacts(model string) (string, int64, bool) {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// What was found.
+	var params string
+	// The context length found.
+	var ctx int64
+	// Walk from the newest to the oldest.
+	for i := len(s.runs) - 1; i >= 0; i-- {
+		// Only this model.
+		if s.runs[i].Model != model {
+			// Next run.
+			continue
+		} // end of the model check
+		// The newest parameter size.
+		if params == "" {
+			// Keep it.
+			params = s.runs[i].ParameterSize
+		} // end of the size check
+		// The newest context length.
+		if ctx == 0 {
+			// Keep it.
+			ctx = s.runs[i].ContextLength
+		} // end of the context check
+	} // end of the loop
+	// Whether anything was found.
+	return params, ctx, params != "" || ctx > 0
+} // end of lastFacts
+
 // count says how many runs are saved in all.
 func (s *perfStore) count() int {
 	// One reader at a time.
diff --git a/tableview.go b/tableview.go
index be848a9..8679546 100644
--- a/tableview.go
+++ b/tableview.go
@@ -91,10 +91,12 @@ type deletedRow struct {
 	SizeText string
 	// WhenText is the deletion time in words, with the year and the computer's own time zone.
 	WhenText string
+	// Tags are the plain-word tags of the model, from what was saved at deletion or, failing that, from its saved tests; empty when nothing is known.
+	Tags []string
 } // end of deletedRow
 
 // deletedRows turns the remembered deleted models into rows; a name that is installed again is left out (it was restored, or pulled by hand).
-func deletedRows(items []deletedModel, installed []installedModel) []deletedRow {
+func deletedRows(items []deletedModel, installed []installedModel, facts func(string) (string, int64, bool)) []deletedRow {
 	// The rows to show.
 	var rows []deletedRow
 	// Go through the remembered models, newest first.
@@ -105,7 +107,7 @@ func deletedRows(items []deletedModel, installed []installedModel) []deletedRow
 			continue
 		} // end of the installed check
 		// Add the row.
-		rows = append(rows, deletedRow{Name: d.Name, SizeText: formatSize(d.Size), WhenText: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")})
+		rows = append(rows, deletedRow{Name: d.Name, SizeText: formatSize(d.Size), WhenText: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST"), Tags: deletedTags(d, facts)})
 	} // end of the loop
 	// Hand back.
 	return rows
diff --git a/tags.go b/tags.go
index 5a33a79..9803d1e 100644
--- a/tags.go
+++ b/tags.go
@@ -73,3 +73,19 @@ func contextClassLabel(key string) string {
 	// Not reached for a key from contextClassOf.
 	return key
 } // end of contextClassLabel
+
+// deletedTags gives the tags of a deleted model: from what was saved when it was deleted; if that has no size and no memory (an entry made by an earlier version), from the newest saved performance test of the model, which knows its size and memory but not its abilities; nothing is guessed from the name.
+func deletedTags(d deletedModel, facts func(string) (string, int64, bool)) []string {
+	// What was saved at deletion.
+	m := installedModel{Capabilities: d.Capabilities, Details: modelDetails{ParameterSize: d.ParameterSize, ContextLength: d.ContextLength}}
+	// Nothing about size or memory was saved: ask the saved tests.
+	if d.ParameterSize == "" && d.ContextLength == 0 && facts != nil {
+		// The newest facts, when there are any.
+		if p, c, ok := facts(d.Name); ok {
+			// Use them.
+			m.Details.ParameterSize, m.Details.ContextLength = p, c
+		} // end of the facts check
+	} // end of the fallback
+	// The same rules as for an installed model.
+	return installedTags(m)
+} // end of deletedTags
diff --git a/timezone_test.go b/timezone_test.go
index ac294f6..45fef21 100644
--- a/timezone_test.go
+++ b/timezone_test.go
@@ -123,7 +123,7 @@ func TestSnapshotFileNameHasZone(t *testing.T) {
 // TestGreyedRowTimeHasYearAndZone checks the deleted-at text in the table carries the year and the zone.
 func TestGreyedRowTimeHasYearAndZone(t *testing.T) {
 	// A moment in a known zone; Local() would convert it, so the check is on the layout's parts.
-	rows := deletedRows([]deletedModel{{Name: "m:1", Size: 1, DeletedAt: time.Date(2026, 10, 27, 17, 30, 0, 0, time.UTC)}}, nil)
+	rows := deletedRows([]deletedModel{{Name: "m:1", Size: 1, DeletedAt: time.Date(2026, 10, 27, 17, 30, 0, 0, time.UTC)}}, nil, nil)
 	// One row.
 	if len(rows) != 1 {
 		// Stop the test.
diff --git a/web/app.css b/web/app.css
index c77f328..26317b1 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2605,32 +2605,50 @@ html[data-size="medium"] svg[width="22"] {
   font-size: 0.9rem;
 } /* end of rule */
 
-/* The tags under a model name sit on their own line and wrap on a narrow window. */
+/* The tags under a model name sit on their own line, as plain small text with a tag symbol in front, so they cannot be taken for buttons; they wrap on a narrow window. */
 .modeltags {
-  /* Chips side by side. */
+  /* Symbol and words side by side. */
   display: flex;
   /* Wrap when the column is narrow. */
   flex-wrap: wrap;
-  /* Space between the chips. */
-  gap: 0.25rem;
+  /* Level with the symbol. */
+  align-items: center;
+  /* Room between the symbol and the first word. */
+  gap: 0.2rem 0.3rem;
   /* A little room above, and none below. */
   margin-top: 0.25rem;
-} /* end of rule */
-
-/* One tag: a small outlined chip in normal weight, so the model name stays the strongest thing in the cell. */
-.mtag {
+  /* The muted text colour: tags are information, not actions. */
+  color: var(--muted);
   /* Small text. */
   font-size: 0.75rem;
   /* Normal weight, even inside the bold row heading. */
   font-weight: 400;
-  /* A thin outline. */
-  border: 1px solid var(--border);
-  /* Round corners. */
-  border-radius: 0.6rem;
-  /* Room inside. */
-  padding: 0 0.45rem;
-  /* The muted text colour. */
-  color: var(--muted);
-  /* A chip never breaks in the middle. */
+} /* end of rule */
+
+/* The tag symbol is as high as the text. */
+.tagicon {
+  /* Do not shrink in a narrow column. */
+  flex: none;
+} /* end of rule */
+
+/* A tag is plain text: no border, no background, no pointer. */
+.mtag {
+  /* A tag never breaks in the middle. */
   white-space: nowrap;
 } /* end of rule */
+
+/* A dot between two tags. */
+.mtag + .mtag::before {
+  /* The middle dot. */
+  content: "\00b7";
+  /* Room on both sides of it. */
+  margin-right: 0.3rem;
+} /* end of rule */
+
+/* The line "deleted ... " under the tags of a deleted model: on its own line, a little below the tags. */
+.modeltags + .ghostnote {
+  /* Its own line, because the tags above are a block and no line break follows them. */
+  display: block;
+  /* A little room above, the same as between the name and the tags. */
+  margin-top: 0.25rem;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 9b77344..d55391c 100644
--- a/web/index.html
+++ b/web/index.html
@@ -469,7 +469,7 @@
 </span>
 {{.Name}}
 {{/* The plain-word tags under the name: size, memory of a conversation and abilities; a figure Ollama did not report gives no tag. */}}
-{{if .Tags}}<span class="modeltags">{{range .Tags}}<span class="mtag">{{.}}</span>{{end}}</span>{{end}}</th>
+{{template "tags" .Tags}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
 {{/* Two small icons stacked in a fixed-width column, centred above each other: the Modelfile page icon on top (for every model) and the gear just below it (only for a model that is not loaded; on a loaded row the Modelfile icon is alone, level with the delete icon of the first column). */}}
@@ -587,7 +587,7 @@
 {{/* End of the icon column. */}}
 </span>
 {{/* The name is struck through; the line under it says when and how big. */}}
-<s>{{.Name}}</s><br><span class="muted ghostnote">deleted {{.WhenText}}, {{.SizeText}}</span></th>
+<s>{{.Name}}</s>{{if .Tags}}{{template "tags" .Tags}}{{else}}<br>{{end}}<span class="muted ghostnote">deleted {{.WhenText}}, {{.SizeText}}{{if not .Tags}}; no tags were saved for it{{end}}</span></th>
 {{/* One wide cell for the rest of the row. */}}
 <td colspan="9" class="muted">Deleted. Restore downloads it again.</td>
 </tr>{{/* end of the greyed row. */}}
@@ -629,6 +629,8 @@
 {{if .HasTable}}<script src="/countdown.js" defer></script>{{end}}
 </body>{{/* end of the visible page. */}}
 </html>{{/* end of the page. */}}
+{{/* The tags of a model: a small tag symbol, then the words separated by dots; plain text, not buttons. Nothing is drawn for a model without tags. */}}
+{{define "tags"}}{{if .}}<span class="modeltags"><svg class="tagicon" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8z"/><circle cx="7" cy="7" r="1"/></svg><span class="sr-only">Tags: </span>{{range .}}<span class="mtag">{{.}}</span>{{end}}</span>{{end}}{{end}}
 {{/* The help bubble content: three labelled parts, and the task names when there are any. */}}
 {{define "tip"}}
 {{/* What the heading means. */}}
diff --git a/web.go b/web.go
index c0863f0..370483b 100644
--- a/web.go
+++ b/web.go
@@ -407,7 +407,7 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 				// Build the table and switch it on.
 				data.Table = buildTableView(installed, loaded)
 				// Add the greyed rows of deleted models that are still gone.
-				data.Table.Deleted = deletedRows(deletedList.list(), installed)
+				data.Table.Deleted = deletedRows(deletedList.list(), installed, perfHistory.lastFacts)
 				// The table can be drawn now.
 				data.HasTable = true
 				// The event log may compare these lists too.
OCC_PATCH_93B_END
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
echo "NEXT  start bin/LLMsControlDock and look at the tags (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
