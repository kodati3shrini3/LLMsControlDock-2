#!/usr/bin/env bash
# Script 62: the restore page says whether a snapshot of the parameters was kept; the key entry and the tooltip for the restore icon mention the parameters it had.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-history" ] || { echo "FAIL  not on feature/delete-history"; exit 1; }
# Script 61 must be applied first.
[ -e history.go ] || { echo "FAIL  script 61 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'Use View history below' web/delete.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/delete.go b/delete.go
index d605832..88edc78 100644
--- a/delete.go
+++ b/delete.go
@@ -97,6 +97,8 @@ type deletePage struct {
 	SnapFile string
 	// SnapErr is why no snapshot was saved (done page); empty when it was saved.
 	SnapErr string
+	// SnapCount is how many parameter snapshots are kept for the model (restore page).
+	SnapCount int
 	// Snaps are the snapshots of the model, newest first (history page).
 	Snaps []snapView
 	// LibText is what the check of the Ollama library found, in words (empty when no check was made).
@@ -413,7 +415,7 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore, hist
 			return
 		} // end of the unknown case
 		// Show the information page.
-		show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "restore", Model: d.Name, SizeText: formatSize(d.Size), Digest: d.Digest, When: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")}, d.Name, d.Digest, "restore"))
+		show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "restore", Model: d.Name, SizeText: formatSize(d.Size), Digest: d.Digest, SnapCount: len(hist.list(d.Name)), When: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")}, d.Name, d.Digest, "restore"))
 	} // end of restore
 	// forget removes the greyed row, without touching Ollama.
 	forget = func(w http.ResponseWriter, r *http.Request) {
diff --git a/delete_test.go b/delete_test.go
index 6de38cf..09b0f10 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -457,7 +457,7 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 	// The main page now shows the greyed row with a restore form, and the model is not in the installed rows.
 	_, _, page := get(t, rig.h, http.MethodGet, "/")
 	// The things that must be there.
-	for _, want := range []string{`data-deleted="alpha:1b"`, "<s>alpha:1b</s>", `action="/restore"`, "Restore: how to download this model again", "Deleted models", "1.3 GB"} {
+	for _, want := range []string{`data-deleted="alpha:1b"`, "<s>alpha:1b</s>", `action="/restore"`, "Restore: how to download this model again, and the parameters it had", "Deleted models", "1.3 GB"} {
 		// Look for it.
 		if !strings.Contains(page, want) {
 			// Report the gap.
diff --git a/history_test.go b/history_test.go
index 309ec6f..3195208 100644
--- a/history_test.go
+++ b/history_test.go
@@ -139,6 +139,11 @@ func TestDeleteSavesSnapshotFirst(t *testing.T) {
 	} // end of the content check
 	// The restore page offers the history.
 	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The page says a snapshot was kept, before the button is clicked.
+	if !strings.Contains(restore, "A snapshot of the parameters it had was kept (1). Use View history below.") {
+		// Report it.
+		t.Errorf("the restore page does not say a snapshot exists")
+	} // end of the snapshot line check
 	// The button.
 	if !strings.Contains(restore, `action="/restore/history"`) || !strings.Contains(restore, "View history") {
 		// Report it.
@@ -335,3 +340,27 @@ func TestDefaultHistoryDir(t *testing.T) {
 		t.Errorf("no-folder case gave %q, %q", d, note)
 	} // end of the none check
 } // end of TestDefaultHistoryDir
+
+// TestRestorePageSaysWhenNothingWasKept checks a model deleted without a snapshot says so on the restore page.
+func TestRestorePageSaysWhenNothingWasKept(t *testing.T) {
+	// Ollama cannot tell the parameters, so no snapshot is taken.
+	rig, f, _ := delRig(t)
+	// Make show fail.
+	f.failShow = true
+	// Delete alpha anyway.
+	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// The restore page.
+	body := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The honest line, and no claim that a snapshot exists.
+	if !strings.Contains(body, "No snapshot of its parameters was kept, so the old values are not known.") || strings.Contains(body, "was kept (") {
+		// Report it.
+		t.Errorf("the restore page does not say nothing was kept: %s", body)
+	} // end of the check
+	// The key explains the history too.
+	_, _, page := get(t, rig.h, http.MethodGet, "/")
+	// The key text.
+	if !strings.Contains(page, "how to download it again, and the parameters it had") {
+		// Report it.
+		t.Errorf("the key does not mention the parameters")
+	} // end of the key check
+} // end of TestRestorePageSaysWhenNothingWasKept
diff --git a/web/delete.html b/web/delete.html
index 1b9fd8d..2b0f600 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -134,6 +134,8 @@
 <p>Restoring means downloading the model again from the Ollama library. You get the latest version of this name, which may differ from the one that was deleted.</p>
 {{/* The loss of tuning gets its own box, because it is the part people forget. */}}
 <div class="lossbox" role="alert"><strong>You lose your tuning.</strong> Inference parameters you changed here are deleted with the model. A restored model comes back with the default parameters, so you must tune it again.</div>
+{{/* Whether the old parameter values were kept, so the person knows before clicking View history. */}}
+{{if .SnapCount}}<p class="goodnote">A snapshot of the parameters it had was kept ({{.SnapCount}}). Use View history below.</p>{{else}}<p class="warn">No snapshot of its parameters was kept, so the old values are not known.</p>{{end}}
 {{/* Models that cannot come back. */}}
 <p>A model you made yourself (from a Modelfile or an import) cannot be downloaded again.</p>
 {{if .ShowPull}}
diff --git a/web/index.html b/web/index.html
index f2b2526..1021e52 100644
--- a/web/index.html
+++ b/web/index.html
@@ -156,7 +156,7 @@
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: view and modify them; only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span><span><strong>Delete</strong>: removes a model from this computer; asks first</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></span><span><strong>Restore</strong>: on a greyed, deleted row; shows how to download the model again</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></span><span><strong>Restore</strong>: on a greyed, deleted row; how to download it again, and the parameters it had</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
 </ul>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
@@ -364,7 +364,7 @@
 {{/* The button. */}}
 <button type="submit" class="gear gear-restore" aria-label="Restore {{.Name}}" aria-describedby="tiprestore-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></button>
 {{/* The tip. */}}
-<span class="tip tip-icon" role="tooltip" id="tiprestore-{{.Name}}">Restore: how to download this model again</span>
+<span class="tip tip-icon" role="tooltip" id="tiprestore-{{.Name}}">Restore: how to download this model again, and the parameters it had</span>
 {{/* End of the tip area. */}}
 </span>
 {{/* End of the form. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
2a5b276824767ae98bfc796f1f97193c0d0c48c7f703983078bd2e051f787858  delete.go
b193aac09ed8b79b1a29140a15ea576b706b497fab74fc90c10f00fe1ed1cf9f  delete_test.go
88bf69bb571c1831bef506eaf6e6d865a69ae893dacdc3650ff251c5ebcdc9fd  history_test.go
1b6787f5e070d64c2295310086cea5b7ec871cb5243fdade09b38f730834e11b  web/delete.html
e501e3ef57bb4ba5ad99370c856abf339239c2c0479f0e0def6a77195195d1ff  web/index.html
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
