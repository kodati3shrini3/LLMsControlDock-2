#!/usr/bin/env bash
# Script 45: fixes the icon tooltips (chart, page, gear) so they follow their icon and are never cut off at the window edge.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-performance-test" ] || { echo "FAIL  not on feature/model-performance-test"; exit 1; }
# Script 44 must be applied first (it creates perf.go).
[ -f perf.go ] || { echo "FAIL  script 44 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'position-anchor: --tipicon' web/app.css; then
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
index 94bcc2f..7555876 100644
--- a/web/app.css
+++ b/web/app.css
@@ -791,6 +791,18 @@ h2 {
   width: max-content;
   /* Never wider than the normal bubble. */
   max-width: min(26rem, 92vw);
+  /* The bubble is tied to its own icon box, so it follows the icon when the page scrolls and stays on the screen (a plain fixed bubble stays where the icon was before scrolling). */
+  position-anchor: --tipicon;
+  /* Its bottom edge sits on the top edge of the icon, so it opens upwards... */
+  bottom: anchor(top);
+  /* ...and its left edge lines up with the icon (the icons are at the left edge of the window). */
+  left: anchor(left);
+  /* No centring shift: the older rule moved it left by half its width. */
+  transform: none;
+  /* A little gap between the bubble and the icon. */
+  margin: 0 0 0.25rem 0;
+  /* If there is no room above (the icon is at the top of the window), open downwards instead. */
+  position-try-fallbacks: flip-block;
 } /* end of rule */
 
 /* The Modelfile text: a monospace box that keeps every line break and space and scrolls sideways instead of cutting lines. */
@@ -1070,3 +1082,26 @@ button.btn-plain {
   /* Transparent background like the link version. */
   background: transparent;
 } /* end of rule */
+
+/* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
+.gearform .tipbox {
+  /* The name the bubble uses to find this box. */
+  anchor-name: --tipicon;
+  /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
+  anchor-scope: --tipicon;
+} /* end of rule */
+
+/* On a narrow window the bubble spans the window width instead, so it is never cut at the right edge. */
+@media (max-width: 40rem) {
+  /* The icon bubble. */
+  .tip-icon {
+    /* Start near the left edge. */
+    left: 0.5rem;
+    /* End near the right edge. */
+    right: 0.5rem;
+    /* Let the two edges decide the width. */
+    width: auto;
+    /* No upper limit other than the window. */
+    max-width: none;
+  } /* end of rule */
+} /* end of rule */
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprint (sha256) the file must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1d918500fa2759744f5623de7e5445033e6199298a1c5d2a5ceb5952716abdac  web/app.css
SUMS_END
# Compare the real fingerprint with the expected one.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The file is exactly as tested.
  echo "PASS  the file is exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
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
