#!/usr/bin/env bash
# Script 122 (docker exec and kubectl exec get -it): the "In Docker" and "In Kubernetes" command lines on the Find LLM results and on the delete page now read "docker exec -it <container-name> ollama pull <model>" and "kubectl exec -it -n <namespace> <pod-name> -- ollama pull <model>". Ollama's own Docker page uses "docker exec -it ollama ollama run llama3.2", and both Docker and Kubernetes describe -i as keeping input open and -t as giving a terminal. The three tests that check the lines are changed to match. Program change (the pages are built into the program), so this belongs to version 0.33.1, not to the published 0.33.0 files.
# Run it on a new branch (never main): cd ~/LLMsControlDock-2 && git switch -c feature/docker-it-flag && bash scripts/122-step84-docker-it-flag.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the five files BEFORE the change (as on main after PR 57) and AFTER it.
declare -A BEFORE AFTER
BEFORE["copy_test.go"]="4be514e0e8ef368bf42398688e9e7d80dccbf87eb143982d5869f61fa033c2ab"
BEFORE["delete_test.go"]="867f58b041660e97c1db2263d7c385a1b6875fb86669c614d19f4cb18d28e974"
BEFORE["findllm_test.go"]="af587df3b3a56282e654300562435c424d45fe1aae0eeee9780e06891bfa06e6"
BEFORE["web/delete.html"]="a34a45660a4bad36f065308bd05da84ee185440cebdf0bc1b8f34e84592a39f7"
BEFORE["web/findllm.html"]="d6fb199a93721f5b2041f1671af2c2fb554ecfbf8f951017772e260c7d82b5e9"
AFTER["copy_test.go"]="178cb498eff740a773425cee7a4d0007ea2cdb54d4b8778194371f5ca10650fa"
AFTER["delete_test.go"]="c6fe4334d4e8a5e2039be051ebe0ceb757b68f94ef283e368034220631f472e3"
AFTER["findllm_test.go"]="e3343bc8f775d5ca4bb3fe4ed6c772e4694478f8d2ecc70e2dd97b1efd338788"
AFTER["web/delete.html"]="66d6b805d98534a87f276082de6a9a689d157169824a72833fb347772f8b2dfd"
AFTER["web/findllm.html"]="d16800af454b559edf9f04c4650715950ca3976085af7b49edd687d1fbb74b3a"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git switch -c feature/docker-it-flag"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Refuse to run twice: the -it is already in the Find LLM page when this change was applied before.
if grep -q 'docker exec -it' web/findllm.html; then fail "web/findllm.html already has docker exec -it: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_122_END'
diff --git a/copy_test.go b/copy_test.go
index 6e2de90..1223e38 100644
--- a/copy_test.go
+++ b/copy_test.go
@@ -84,11 +84,11 @@ func TestRestorePageHasCopyButtons(t *testing.T) {
 		// The direct command.
 		"cmd-local": "ollama pull alpha:1b",
 		// Docker.
-		"cmd-docker": "docker exec &lt;container-name&gt; ollama pull alpha:1b",
+		"cmd-docker": "docker exec -it &lt;container-name&gt; ollama pull alpha:1b",
 		// Docker, finding the name.
 		"cmd-docker-find": "docker ps",
 		// Kubernetes.
-		"cmd-k8s": "kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b",
+		"cmd-k8s": "kubectl exec -it -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b",
 		// Kubernetes, finding the pod.
 		"cmd-k8s-find": "kubectl get pods -n &lt;namespace&gt;",
 	} // end of the table
diff --git a/delete_test.go b/delete_test.go
index 8b506f7..7720bd1 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -490,7 +490,7 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 	// The restore page shows the manual command.
 	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
 	// The words.
-	for _, want := range []string{"ollama pull alpha:1b", "latest version", `class="lossbox"`, "You lose your tuning.", "cannot be downloaded again", "docker exec &lt;container-name&gt; ollama pull alpha:1b", "kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b", "Directly on the computer"} {
+	for _, want := range []string{"ollama pull alpha:1b", "latest version", `class="lossbox"`, "You lose your tuning.", "cannot be downloaded again", "docker exec -it &lt;container-name&gt; ollama pull alpha:1b", "kubectl exec -it -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b", "Directly on the computer"} {
 		// Look for it.
 		if !strings.Contains(restore, want) {
 			// Report the gap.
diff --git a/findllm_test.go b/findllm_test.go
index 912e902..367e791 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -584,7 +584,7 @@ func TestFindResultsHaveCopyButtons(t *testing.T) {
 		} // end of the target check
 	} // end of the loop
 	// The three ways of running the pull, for the version that fits.
-	for _, want := range []string{">ollama pull alpha:0.6b</code>", ">docker exec &lt;container-name&gt; ollama pull alpha:0.6b</code>", ">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:0.6b</code>"} {
+	for _, want := range []string{">ollama pull alpha:0.6b</code>", ">docker exec -it &lt;container-name&gt; ollama pull alpha:0.6b</code>", ">kubectl exec -it -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:0.6b</code>"} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report.
diff --git a/web/delete.html b/web/delete.html
index d518c39..bd39ff3 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -147,8 +147,8 @@
 <thead><tr><th scope="col">Where Ollama runs</th><th scope="col">Command</th></tr></thead>
 <tbody>
 <tr><th scope="row">Directly on the computer</th><td><code id="cmd-local">ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
-<tr><th scope="row">In Docker</th><td><code id="cmd-docker">docker exec &lt;container-name&gt; ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-docker" hidden aria-label="Copy command: in Docker"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the name with: <code id="cmd-docker-find">docker ps</code></span> <button type="button" class="copybtn" data-target="cmd-docker-find" hidden aria-label="Copy command: find the Docker container name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
-<tr><th scope="row">In Kubernetes</th><td><code id="cmd-k8s">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-k8s" hidden aria-label="Copy command: in Kubernetes"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the pod with: <code id="cmd-k8s-find">kubectl get pods -n &lt;namespace&gt;</code></span> <button type="button" class="copybtn" data-target="cmd-k8s-find" hidden aria-label="Copy command: find the Kubernetes pod name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Docker</th><td><code id="cmd-docker">docker exec -it &lt;container-name&gt; ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-docker" hidden aria-label="Copy command: in Docker"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the name with: <code id="cmd-docker-find">docker ps</code></span> <button type="button" class="copybtn" data-target="cmd-docker-find" hidden aria-label="Copy command: find the Docker container name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Kubernetes</th><td><code id="cmd-k8s">kubectl exec -it -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-k8s" hidden aria-label="Copy command: in Kubernetes"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the pod with: <code id="cmd-k8s-find">kubectl get pods -n &lt;namespace&gt;</code></span> <button type="button" class="copybtn" data-target="cmd-k8s-find" hidden aria-label="Copy command: find the Kubernetes pod name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
 </tbody>
 </table>
 <p class="muted">The command must run where Ollama runs, because the model is stored there. The Kubernetes line has not been tested on a real cluster. The Copy button only copies the text; you paste it into the terminal yourself.</p>
diff --git a/web/findllm.html b/web/findllm.html
index daad069..10bd747 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -123,8 +123,8 @@
 {{/* The command depends on where Ollama runs; the monitor cannot know that, so Docker and Kubernetes are offered too, folded away until wanted. */}}
 <details class="othercmds"><summary>Docker or Kubernetes</summary>
 <table class="cmds"><tbody>
-<tr><th scope="row">In Docker</th><td><code id="cmd-{{$ri}}-{{$vi}}-docker">docker exec &lt;container-name&gt; {{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-docker" hidden aria-label="Copy command: in Docker"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the name with: <code id="cmd-{{$ri}}-{{$vi}}-dockerfind">docker ps</code></span> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-dockerfind" hidden aria-label="Copy command: find the Docker container name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
-<tr><th scope="row">In Kubernetes</th><td><code id="cmd-{{$ri}}-{{$vi}}-k8s">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- {{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-k8s" hidden aria-label="Copy command: in Kubernetes"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the pod with: <code id="cmd-{{$ri}}-{{$vi}}-k8sfind">kubectl get pods -n &lt;namespace&gt;</code></span> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-k8sfind" hidden aria-label="Copy command: find the Kubernetes pod name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Docker</th><td><code id="cmd-{{$ri}}-{{$vi}}-docker">docker exec -it &lt;container-name&gt; {{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-docker" hidden aria-label="Copy command: in Docker"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the name with: <code id="cmd-{{$ri}}-{{$vi}}-dockerfind">docker ps</code></span> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-dockerfind" hidden aria-label="Copy command: find the Docker container name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Kubernetes</th><td><code id="cmd-{{$ri}}-{{$vi}}-k8s">kubectl exec -it -n &lt;namespace&gt; &lt;pod-name&gt; -- {{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-k8s" hidden aria-label="Copy command: in Kubernetes"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the pod with: <code id="cmd-{{$ri}}-{{$vi}}-k8sfind">kubectl get pods -n &lt;namespace&gt;</code></span> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-k8sfind" hidden aria-label="Copy command: find the Kubernetes pod name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
 </tbody></table>
 </details>
 {{end}}
OCC_PATCH_122_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed files have the expected sha256"

# Both pages must show the new lines, and neither may still show the old ones.
for P in web/findllm.html web/delete.html; do
  # The new Docker line.
  grep -q 'docker exec -it &lt;container-name&gt;' "$P" || fail "$P lacks the new docker exec -it line"
  # The new Kubernetes line.
  grep -q 'kubectl exec -it -n &lt;namespace&gt;' "$P" || fail "$P lacks the new kubectl exec -it line"
  # The old Docker line must be gone.
  if grep -q 'docker exec &lt;container-name&gt;' "$P"; then fail "$P still has the old docker exec line"; fi
  # The old Kubernetes line must be gone.
  if grep -q 'kubectl exec -n &lt;namespace&gt;' "$P"; then fail "$P still has the old kubectl exec line"; fi
# End of the loop over the pages.
done
# Report it.
pass "Find LLM and the delete page show docker exec -it and kubectl exec -it, and no old lines are left"

# Only the five expected files may be changed among the files git tracks.
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="copy_test.go delete_test.go findllm_test.go web/delete.html web/findllm.html "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only the five expected files changed (two pages, three tests)"

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

# Build the program for all six systems, because the pages are built into it.
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
echo "NEXT  commit, push, pull request and merge (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
