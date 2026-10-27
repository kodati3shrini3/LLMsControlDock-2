#!/usr/bin/env bash
# Script 65: the LinkedIn and source links on the About page open in a new window (no link back to the monitor, no referrer).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/about-and-text-size" ] || { echo "FAIL  not on feature/about-and-text-size"; exit 1; }
# Scripts 61 to 63 must be part of this branch already (merged into main).
[ -e about.go ] || { echo "FAIL  script 64 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'target="_blank"' web/about.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about_test.go b/about_test.go
index a33ff52..f04b14a 100644
--- a/about_test.go
+++ b/about_test.go
@@ -53,7 +53,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The developer.
 		"Shrinivas Kodati",
 		// The developer's LinkedIn profile, safe to follow.
-		`href="https://www.linkedin.com/in/shrinikodati/" rel="noopener noreferrer">LinkedIn profile</a>`,
+		`href="https://www.linkedin.com/in/shrinikodati/" target="_blank" rel="noopener noreferrer">LinkedIn profile<span class="sr-only"> (opens in a new window)</span></a>`,
 		// The assistant with its version.
 		"Claude (Sonnet 5.5), Anthropic",
 		// The dedication, exactly as the developer wrote it.
@@ -69,7 +69,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The licence line.
 		"2026 Shrinivas Kodati. All rights reserved.",
 		// The repository link, safe to follow.
-		`href="https://github.com/kodatishrini-beep/OllamaControlCenter" rel="noopener noreferrer"`,
+		`href="https://github.com/kodatishrini-beep/OllamaControlCenter" target="_blank" rel="noopener noreferrer"`,
 		// The way back.
 		`href="/"`,
 	} { // end of the list
diff --git a/web/about.html b/web/about.html
index cc849f9..4860149 100644
--- a/web/about.html
+++ b/web/about.html
@@ -28,7 +28,7 @@
 {{/* The table has a caption for screen readers. */}}
 <caption class="sr-only">Facts about this program</caption>
 {{/* Who developed it. */}}
-<tr><th scope="row">Developed by</th><td>{{.Developer}} &middot; <a href="{{.DeveloperProfile}}" rel="noopener noreferrer">LinkedIn profile</a></td></tr>
+<tr><th scope="row">Developed by</th><td>{{.Developer}} &middot; {{/* A new window; noopener cuts the link back to this page, noreferrer sends no address. */}}<a href="{{.DeveloperProfile}}" target="_blank" rel="noopener noreferrer">LinkedIn profile<span class="sr-only"> (opens in a new window)</span></a></td></tr>
 {{/* Who assisted. */}}
 <tr><th scope="row">Assisted by</th><td>{{.Assistant}}</td></tr>
 {{/* The version. */}}
@@ -38,7 +38,7 @@
 {{/* The platform. */}}
 <tr><th scope="row">Built with</th><td>Go standard library only, no third-party code ({{.Platform}})</td></tr>
 {{/* Where the source lives. */}}
-<tr><th scope="row">Source code</th><td><a href="{{.Repository}}" rel="noopener noreferrer">{{.Repository}}</a> (private repository; opens only for its owner)</td></tr>
+<tr><th scope="row">Source code</th><td><a href="{{.Repository}}" target="_blank" rel="noopener noreferrer">{{.Repository}}<span class="sr-only"> (opens in a new window)</span></a> (private repository; opens only for its owner)</td></tr>
 {{/* Where the data goes. */}}
 <tr><th scope="row">Privacy</th><td>Runs only on this computer. The one request to the outside is the optional check of Ollama's public library when a model is deleted, and it sends only the model's name.</td></tr>
 {{/* The licence. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
c0058a1a5dac0081bbbe4f98476a0e16ba101767f6336a59d5e2c9e5a30a7bdd  web/about.html
84a4cd67482e787500d8d9e145e2b16e38be4f9226948a845b242c4a1c241201  about_test.go
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
