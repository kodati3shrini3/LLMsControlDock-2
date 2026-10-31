#!/usr/bin/env bash
# Script 69m: reference 2 (NVIDIA NIM metrics) moves to its new address https://docs.nvidia.com/nim/benchmarking/llm/metrics. The page was read again on 31 October 2026: title Metrics, version 2.0.0 (Latest), and it still defines the speed and delay figures and says to compare results only when definitions align.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/reference-2-address" ] || { echo "FAIL  not on feature/reference-2-address"; exit 1; }
# Script 69l (even gaps) must be applied already (merged into main).
[ -e spacing_test.go ] || { echo "FAIL  script 69l was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "llm/metrics\"" references.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/references.go b/references.go
index 02428b0..cca6179 100644
--- a/references.go
+++ b/references.go
@@ -46,9 +46,9 @@ var compareReferences = []reference{
 		// Title.
 		Title: "Metrics (LLM section of the NVIDIA NIM Benchmarking Documentation)",
 		// Kind and version.
-		Where: "Documentation, version 2.0.0 (Latest) when read",
+		Where: "Documentation, version 2.0.0 (Latest); read again on 31 October 2026",
 		// Address.
-		URL: "https://docs.nvidia.com/nim/benchmarking/llm/latest/metrics.html",
+		URL: "https://docs.nvidia.com/nim/benchmarking/llm/metrics",
 		// What we take from it.
 		Used: "Definitions of the speed and delay figures, and the rule to compare results only when the definitions align.",
 	}, // end of source 2
diff --git a/references_test.go b/references_test.go
index 66e29c1..924a113 100644
--- a/references_test.go
+++ b/references_test.go
@@ -18,8 +18,8 @@ import ( // import lists the standard-library packages this file uses.
 var verifiedAddresses = map[int]string{
 	// NVIDIA blog article.
 	1: "https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts",
-	// NVIDIA NIM metrics page.
-	2: "https://docs.nvidia.com/nim/benchmarking/llm/latest/metrics.html",
+	// NVIDIA NIM metrics page (the old address .../latest/metrics.html now leads here; re-read on 31 October 2026).
+	2: "https://docs.nvidia.com/nim/benchmarking/llm/metrics",
 	// Artificial Analysis methodology.
 	3: "https://artificialanalysis.ai/methodology/performance-benchmarking",
 	// MLPerf Inference paper.
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
5e08354c7505295448bb720d9f3e856ddd313469c807c839ef666a69697c1ba6  references.go
599948625676337efa3a109b7560afd5a18f1f56e5391734daa0faf18473bb76  references_test.go
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
# Tell the person how to use the new command.
echo "NEXT  run: ./bin/OllamaControlCenter -check-links  (reference 2 should now show OK 200 without a moved-to line)"
# List the changed files; nothing is committed yet.
git status --short
