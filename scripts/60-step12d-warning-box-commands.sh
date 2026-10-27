#!/usr/bin/env bash
# Script 60: the loss of tuning gets its own red box on the delete and restore pages, and the restore page shows the pull command for a direct install, Docker and Kubernetes.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-model" ] || { echo "FAIL  not on feature/delete-model"; exit 1; }
# Script 59 must be applied first.
[ -e library.go ] || { echo "FAIL  script 59 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'lossbox' web/delete.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/delete_test.go b/delete_test.go
index 1a65d51..3617a8d 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -337,7 +337,7 @@ func TestDeleteWarningChangesNothing(t *testing.T) {
 		t.Fatalf("status %d", res.StatusCode)
 	} // end of the status check
 	// The warning words and both choices.
-	for _, want := range []string{"This removes the model from this computer", "1.3 GB", "Restore", "not</strong> restored", "tune them again", "cannot be downloaded again", "Yes, delete it", "No, keep it", `action="/delete/confirm"`} {
+	for _, want := range []string{"This removes the model from this computer", "1.3 GB", "Restore", `class="lossbox"`, "You lose your tuning.", "you must tune it again", "cannot be downloaded again", "Yes, delete it", "No, keep it", `action="/delete/confirm"`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
@@ -365,7 +365,7 @@ func TestDeleteBusyPage(t *testing.T) {
 	// The page.
 	body := bodyOf(res)
 	// The words that matter.
-	for _, want := range []string{"loaded right now, so it may be in use", "Hold: do not delete", "Force delete", `action="/delete/force"`, `name="typed"`, "unloads this model by itself in"} {
+	for _, want := range []string{"loaded right now, so it may be in use", "Hold: do not delete", "Force delete", `class="lossbox"`, `action="/delete/force"`, `name="typed"`, "unloads this model by itself in"} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
@@ -446,7 +446,7 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 	// The restore page shows the manual command.
 	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
 	// The words.
-	for _, want := range []string{"ollama pull alpha:1b", "latest version", "Inference parameters you changed are not restored", "cannot be downloaded again"} {
+	for _, want := range []string{"ollama pull alpha:1b", "latest version", `class="lossbox"`, "You lose your tuning.", "cannot be downloaded again", "docker exec &lt;container-name&gt; ollama pull alpha:1b", "kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b", "Directly on the computer"} {
 		// Look for it.
 		if !strings.Contains(restore, want) {
 			// Report the gap.
diff --git a/web/app.css b/web/app.css
index 098a03f..fa4581e 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1436,3 +1436,51 @@ a.btn-load {
   /* A light panel behind it, as for the warning. */
   background: var(--bg);
 } /* end of rule */
+
+/* The box that stresses the loss of tuning: a red outline, so it cannot be mistaken for a routine line. */
+.lossbox {
+  /* A solid outline in the problem colour. */
+  border: 2px solid var(--bad);
+  /* Rounded corners like the other boxes. */
+  border-radius: 0.6rem;
+  /* Room inside. */
+  padding: 0.7rem 1rem;
+  /* Room below it. */
+  margin: 0 0 1rem;
+  /* The page background, so it stands out from the grey panel. */
+  background: var(--bg);
+} /* end of rule */
+
+/* Its first words in the problem colour. */
+.lossbox strong {
+  /* The problem colour. */
+  color: var(--bad);
+} /* end of rule */
+
+/* The table of restore commands. */
+.cmds {
+  /* Use the full width. */
+  width: 100%;
+  /* One line between rows. */
+  border-collapse: collapse;
+  /* Room around it. */
+  margin: 0.4rem 0 1rem;
+} /* end of rule */
+
+/* Cells of the command table. */
+.cmds th, .cmds td {
+  /* Room inside. */
+  padding: 0.35rem 0.6rem;
+  /* A thin line under every row. */
+  border-bottom: 1px solid var(--border);
+  /* Text from the left. */
+  text-align: left;
+  /* Text from the top. */
+  vertical-align: top;
+} /* end of rule */
+
+/* Long commands wrap instead of pushing the page wider. */
+.cmds code {
+  /* Break long words. */
+  overflow-wrap: anywhere;
+} /* end of rule */
diff --git a/web/delete.html b/web/delete.html
index 3f5bd4f..5c5f05e 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -25,18 +25,16 @@
 <p class="warn" role="alert"><strong>This removes the model from this computer.</strong></p>
 {{/* What the check of the Ollama library found: good news or a caution. */}}
 {{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
+{{/* The loss of tuning gets its own box, because it is the part people forget. */}}
+<div class="lossbox" role="alert"><strong>You lose your tuning.</strong> Inference parameters you changed here are deleted with the model. A restored model comes back with the default parameters, so you must tune it again.</div>
 {{/* The consequences, one by one. */}}
 <ul>
 {{/* Disk space. */}}
 <li>It frees about <strong>{{.SizeText}}</strong> of disk space.</li>
 {{/* Applications. */}}
 <li>Every application that asks Ollama for <code>{{.Model}}</code> gets an error from now on.</li>
-{{/* Saved settings. */}}
-<li>Settings saved inside the model, such as inference parameters you changed here, are removed with it.</li>
 {{/* How to get it back. */}}
 <li>You can bring it back with <strong>Restore</strong>: it downloads the model again (about {{.SizeText}}) and gives you the latest version of the same name.</li>
-{{/* The lost tuning. */}}
-<li>A restored model is a fresh copy: any changes you made to its inference parameters are <strong>not</strong> restored, and you must tune them again.</li>
 {{/* Models that cannot come back. */}}
 <li>A model you made yourself (from a Modelfile or an import) cannot be downloaded again.</li>
 {{/* End of the consequences. */}}
@@ -67,6 +65,8 @@
 <p class="warn" role="alert"><strong>This model is loaded right now, so it may be in use.</strong></p>
 {{/* What the check of the Ollama library found: good news or a caution. */}}
 {{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
+{{/* The loss of tuning gets its own box, because it is the part people forget. */}}
+<div class="lossbox" role="alert"><strong>You lose your tuning.</strong> Inference parameters you changed here are deleted with the model. A restored model comes back with the default parameters, so you must tune it again.</div>
 {{/* What the monitor can and cannot see. */}}
 <p>This monitor cannot see whether an application is using it at this moment. Deleting a model that is in use can make that application fail or behave unexpectedly.</p>
 {{/* What happens by itself. */}}
@@ -125,15 +125,22 @@
 {{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
 {{/* What Restore means. */}}
 <p>Restoring means downloading the model again from the Ollama library. You get the latest version of this name, which may differ from the one that was deleted.</p>
-{{/* The lost tuning. */}}
-<p><strong>Inference parameters you changed are not restored.</strong> The model comes back as a fresh copy, so tune them again.</p>
+{{/* The loss of tuning gets its own box, because it is the part people forget. */}}
+<div class="lossbox" role="alert"><strong>You lose your tuning.</strong> Inference parameters you changed here are deleted with the model. A restored model comes back with the default parameters, so you must tune it again.</div>
 {{/* Models that cannot come back. */}}
 <p>A model you made yourself (from a Modelfile or an import) cannot be downloaded again.</p>
 {{if .ShowPull}}
-{{/* The manual way, until the in-page download arrives. */}}
-<p>For now, run this in a terminal on the computer that runs Ollama:</p>
-{{/* The command. */}}
-<pre><code>ollama pull {{.Model}}</code></pre>
+{{/* The command depends on where Ollama runs; the monitor cannot know that, so all three are shown. */}}
+<p>Run the command that matches how Ollama is installed. Replace the parts in angle brackets with your own names.</p>
+<table class="cmds">
+<thead><tr><th scope="col">Where Ollama runs</th><th scope="col">Command</th></tr></thead>
+<tbody>
+<tr><th scope="row">Directly on the computer</th><td><code>ollama pull {{.Model}}</code></td></tr>
+<tr><th scope="row">In Docker</th><td><code>docker exec &lt;container-name&gt; ollama pull {{.Model}}</code><br><span class="muted">find the name with: <code>docker ps</code></span></td></tr>
+<tr><th scope="row">In Kubernetes</th><td><code>kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull {{.Model}}</code><br><span class="muted">find the pod with: <code>kubectl get pods -n &lt;namespace&gt;</code></span></td></tr>
+</tbody>
+</table>
+<p class="muted">The command must run where Ollama runs, because the model is stored there. The Kubernetes line has not been tested on a real cluster.</p>
 {{end}}
 {{/* What happens afterwards. */}}
 <p class="muted">When the download is finished, this model appears in the table again and the greyed row disappears.</p>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
4265909a98d57bc03a7aeb597bb9fbff26db5ab603a7caaeea02334c419b4c7b  delete_test.go
502e484816aa11a1ba97a5ae9e23528bd0d213d4fa3e23e71c18fc888d90e667  web/app.css
698f05481979a54cae1526a49ea91381d4783285fd483eb8e8d6975a9212e3ad  web/delete.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# List the changed files; nothing is committed yet.
git status --short
