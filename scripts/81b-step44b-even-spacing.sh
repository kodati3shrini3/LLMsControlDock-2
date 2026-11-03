#!/usr/bin/env bash
# Script 81b (even spacing on the main page): the gaps above the Pause/Refresh/Settings/Stop buttons, between them and the "Monitoring details" button, and below it are now all the same 1rem (about 16 pixels). It must be run on the branch where script 81 was already applied.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run before script 81 is applied.
[ -e launchers.go ] && [ "$(git branch --show-current)" != "main" ] || { echo "FAIL  script 81 is not applied here, or this is main"; exit 1; }
# Refuse to run twice.
if grep -q -- "margin-block: -0.66rem" web/app.css 2>/dev/null; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/web/app.css b/web/app.css
index fb28c3e..4061860 100644
--- a/web/app.css
+++ b/web/app.css
@@ -387,8 +387,8 @@ h2 {
   justify-content: space-between;
   /* Line the blocks up at the top. */
   align-items: flex-start;
-  /* Space between the blocks when they wrap. */
-  gap: 0.5rem 1rem;
+  /* No extra gap between the rows when the blocks wrap; the even 1rem rhythm below is set by the margins instead. */
+  gap: 0 1rem;
 } /* end of rule */
 
 /* The theme form: the Auto button (when shown) and the switch in one line. */
@@ -1236,6 +1236,8 @@ button.btn-plain {
   justify-content: flex-end;
   /* Space between them. */
   gap: 0.5rem 1rem;
+  /* The two stacked switches are taller than the buttons and overhang them by about 0.66rem above and below; this pulls the block back so the gaps are measured from the buttons, which gives the same 1rem above and below them as between the other lines. */
+  margin-block: -0.66rem;
 } /* end of rule */
 
 /* The monitor controls in one row. */
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
6fa46e53ad723beb85b6b4330ded76c02e6c60b42164024614f338c73e91cb93  web/app.css
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any old monitor by its 15-character process name (Linux shortens longer names, so the full name would match nothing).
pgrep -x OllamaControlCe | xargs -r kill || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -x OllamaControlCe > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter and look at the top of the main page: the gaps above and below the buttons row, and below Monitoring details, should look the same; then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
