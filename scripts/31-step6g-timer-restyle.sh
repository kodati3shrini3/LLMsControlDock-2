#!/usr/bin/env bash
# Script 31: restyle the unload timer (italic, in [square brackets], normal font and size, less space); applied on top of script 30 on the same branch.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch from script 30.
[ "$(git branch --show-current)" = "feature/loaded-unload-countdown" ] || { echo "FAIL  not on feature/loaded-unload-countdown"; exit 1; }
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/tooltips.go b/tooltips.go
index eb98faa..0b7e2b6 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -88,7 +88,7 @@ var helpTexts = map[string]tooltip{
 	// The loaded or not-loaded state.
 	"State": {
 		// What it means.
-		Plain: "In memory now (● Loaded, with a bold timer until Ollama unloads it) or only on disk (○ Not loaded).",
+		Plain: "In memory now (● Loaded, with [the time until Ollama unloads it]) or only on disk (○ Not loaded).",
 		// A real case.
 		Example: "A ○ Not loaded model needs a moment to load before it answers.",
 		// What it helps with.
diff --git a/web/app.css b/web/app.css
index 56f6792..c713c37 100644
--- a/web/app.css
+++ b/web/app.css
@@ -747,18 +747,30 @@ h2 {
 .timerslot {
   /* A box in the line, so it can have a width. */
   display: inline-block;
-  /* Wide enough for "11 min 59 s", "unloading now" and "stays loaded" in bold. */
-  min-width: 8.5rem;
-  /* Keep the digits in line with the words around them. */
+  /* Just wide enough for the longest timer text in square brackets. */
+  min-width: 6.8rem;
+  /* Keep the text in line with the words around it. */
   vertical-align: baseline;
 } /* end of rule */
 
-/* The unload timer itself: bold, with digits of equal width so the text does not jitter every second. */
+/* The unload timer itself: italic, in the same font and size as the text around it. */
 .timer {
-  /* Bold, as asked. */
-  font-weight: 700;
-  /* Digits of equal width. */
-  font-variant-numeric: tabular-nums;
+  /* Italic, not bold (the element is a strong one, so the weight is set back to normal). */
+  font-style: italic;
+  /* Normal weight. */
+  font-weight: normal;
+} /* end of rule */
+
+/* Square brackets are drawn by the stylesheet, so the timer text stays plain. */
+.timer::before {
+  /* The opening bracket. */
+  content: "[";
+} /* end of rule */
+
+/* The closing bracket. */
+.timer::after {
+  /* The closing bracket. */
+  content: "]";
 } /* end of rule */
 
 /* The hidden attribute must always win over any display rule. */
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files (was script 30 run?)"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
846bacbdf4a1ec2def5890bc590a8ce919711faecfca83da3294a0bb4b7d8751  tooltips.go
ce0d11cf710aa42bd7a94ef277299afeaaa228a7ea93bd24ec85589891e5ccff  web/app.css
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # Both files are exactly as tested.
  echo "PASS  both changed files match the tested versions"
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
# List the changed files; nothing is committed yet.
git status --short
