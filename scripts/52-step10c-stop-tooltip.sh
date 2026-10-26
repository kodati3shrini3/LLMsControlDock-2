#!/usr/bin/env bash
# Script 52: the Stop button tooltip now names this program: "Stop this OllamaControlCenter monitor program ...".
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on main: this change belongs on its own feature branch.
[ "$(git branch --show-current)" = "feature/monitor-controls" ] || { echo "FAIL  not on feature/monitor-controls"; exit 1; }
# Script 51 must be applied first (it adds the drawn icons).
grep -q 'class="ico"' web/index.html || { echo "FAIL  script 51 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'Stop this OllamaControlCenter monitor program' web/index.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/web/index.html b/web/index.html
index 07f363f..6664b39 100644
--- a/web/index.html
+++ b/web/index.html
@@ -63,7 +63,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 <button type="submit" class="unload ctlbtn" aria-describedby="tipstop"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1.5"/></svg> Stop</button>
-<span class="tip tip-icon" role="tooltip" id="tipstop">Stop the monitor program (it asks first; Ollama and its models are not touched)</span>
+<span class="tip tip-icon" role="tooltip" id="tipstop">Stop this OllamaControlCenter monitor program (it asks first; Ollama and its models are not touched)</span>
 </span>
 {{/* End of the stop form. */}}
 </form>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
d77b15fd49e5571fd43da4341a97448ff9a229594f9c1dced8b2193682116f4b  web/index.html
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
