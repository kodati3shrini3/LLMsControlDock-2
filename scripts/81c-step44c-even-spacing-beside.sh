#!/usr/bin/env bash
# Script 81c (even spacing on the main page): the gaps above the Pause/Refresh/Settings/Stop buttons, between them and the "Monitoring details" button, and below it are now all the same 1rem (about 16 pixels). It must be run on the branch where script 81 was already applied.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run before script 81 is applied.
grep -q -- "margin-block: -0.66rem" web/app.css 2>/dev/null && [ "$(git branch --show-current)" != "main" ] || { echo "FAIL  script 81b is not applied here, or this is main"; exit 1; }
# Refuse to run twice.
if grep -q -- "headrow #watchline" web/app.css 2>/dev/null; then
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
index 4061860..6f59ce3 100644
--- a/web/app.css
+++ b/web/app.css
@@ -387,8 +387,14 @@ h2 {
   justify-content: space-between;
   /* Line the blocks up at the top. */
   align-items: flex-start;
-  /* No extra gap between the rows when the blocks wrap; the even 1rem rhythm below is set by the margins instead. */
-  gap: 0 1rem;
+  /* One rem between the rows when the blocks wrap, and between the blocks side by side. */
+  gap: 1rem;
+} /* end of rule */
+
+/* The last line of the title block leaves no space of its own: the header's gap and the bar below decide the distance, so it is the same 1rem whether the buttons sit beside the title or below it. */
+.headrow #watchline {
+  /* No space below the line. */
+  margin-bottom: 0;
 } /* end of rule */
 
 /* The theme form: the Auto button (when shown) and the switch in one line. */
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
743d855ccfaa53314b37e0f00225bbe675129f0f55ad7e9da4086b66dbc2dc7a  web/app.css
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
echo "NEXT  start ./bin/OllamaControlCenter and look at the top of the main page: in a wide window the gap between the Watching line and Monitoring details should equal the gap below it; then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
