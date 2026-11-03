#!/usr/bin/env bash
# Script 83b (GitHub username change, replaces script 83): the GitHub username changed from kodatishrini-beep to kodati3shrini3, so the repository link on the About page (about.go), the test for that link (about_test.go) and the FIRST LINE of go.mod (the module path) are updated. The rest of go.mod, such as the go version line, is left exactly as it is. No program behaviour changes except that link.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on main (every change goes through a branch).
[ "$(git branch --show-current)" != "main" ] || { echo "FAIL  this is main; create a feature branch first"; exit 1; }
# Refuse to run twice.
if head -n 1 go.mod | grep -q "kodati3shrini3"; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# The first line of go.mod must be exactly the old module path, or nothing is touched.
[ "$(head -n 1 go.mod)" = "module github.com/kodatishrini-beep/OllamaControlCenter" ] || { echo "FAIL  the first line of go.mod is not the expected old module path"; head -n 1 go.mod; exit 1; }
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 4395f61..cadf14e 100644
--- a/about.go
+++ b/about.go
@@ -44,7 +44,7 @@ const appDedication = "Dedicated to Ms. Meghna Kodati, without whom I would neve
 const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
 
 // appRepository is the address of the source code; the repository is private, so only its owner can open it.
-const appRepository = "https://github.com/kodatishrini-beep/OllamaControlCenter"
+const appRepository = "https://github.com/kodati3shrini3/OllamaControlCenter"
 
 // companyName is the developer's company, shown in the header, the footer bar and the About page.
 const companyName = "termGate Consulting"
diff --git a/about_test.go b/about_test.go
index f04b14a..423f487 100644
--- a/about_test.go
+++ b/about_test.go
@@ -69,7 +69,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The licence line.
 		"2026 Shrinivas Kodati. All rights reserved.",
 		// The repository link, safe to follow.
-		`href="https://github.com/kodatishrini-beep/OllamaControlCenter" target="_blank" rel="noopener noreferrer"`,
+		`href="https://github.com/kodati3shrini3/OllamaControlCenter" target="_blank" rel="noopener noreferrer"`,
 		// The way back.
 		`href="/"`,
 	} { // end of the list
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to about.go and about_test.go.
git apply "$PATCH_FILE"
# Change only line 1 of go.mod.
sed -i '1s#^module github.com/kodatishrini-beep/OllamaControlCenter$#module github.com/kodati3shrini3/OllamaControlCenter#' go.mod
# Check that line 1 now has the new module path.
[ "$(head -n 1 go.mod)" = "module github.com/kodati3shrini3/OllamaControlCenter" ] || { echo "FAIL  go.mod line 1 was not changed"; exit 1; }
# Report the change.
echo "PASS  go.mod line 1 changed; the other lines are untouched"
# The fingerprints (sha256) the two patched files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
612b64095709d68435d0559568441bb015a27ba4e488a7d9213aa0c90967eb0f  about.go
3d59b289b38e40814b08b74fad6988fe22c5e3dac51ed3c965ef968ed2450eac  about_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  about.go and about_test.go are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check that no tracked text file still has the old username.
if git ls-files -z | xargs -0 grep -Il "kodatishrini-beep" 2>/dev/null; then
  # Some file still has it.
  echo "FAIL  the old username is still in the files listed above"; exit 1
fi
# Report the check.
echo "PASS  the old username is gone from every tracked file"
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
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
# Tell the person what to look at.
echo "NEXT  commit and push; the new link shows on the About page of the monitor"
# List the changed files; nothing is committed yet.
git status --short
