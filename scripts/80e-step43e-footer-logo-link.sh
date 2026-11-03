#!/usr/bin/env bash
# Script 80e (footer of the main page): the "Visit termgate.com" button at the bottom right is removed, and the termGate Consulting logo at the bottom left is now the link to www.termgate.com, opening in a new tab with no link back and no referrer, with a tooltip. The About page keeps its own button. It must be run on the branch where scripts 80, 80b, 80c and 80d were already applied.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ -e syscheck.go ] && grep -q uninstallWord syscheck.go && [ "$(git branch --show-current)" = "feature/system-check" ] || { echo "FAIL  scripts 80 to 80d are not applied here, or this is not feature/system-check"; exit 1; }
# Refuse to run twice.
if grep -q brandlogolink web/index.html 2>/dev/null; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/brand_test.go b/brand_test.go
index f5da207..1a4e2e5 100644
--- a/brand_test.go
+++ b/brand_test.go
@@ -57,8 +57,10 @@ func TestMainPageShowsTheCompany(t *testing.T) {
 		`<footer class="brandbar"`,
 		// The tagline.
 		"Transforming Healthcare through Data &amp; Technology.",
-		// The footer button with its own place tag.
-		`utm_content=footer" target="_blank" rel="noopener noreferrer">Visit termgate.com`,
+		// The footer logo is the link to the company website, with its own place tag.
+		`utm_content=footer" target="_blank" rel="noopener noreferrer" aria-describedby="tiplogo"><img class="brandlogo"`,
+		// Its tooltip.
+		"Visit termgate.com (opens in a new window)",
 		// The text for screen readers.
 		"(opens in a new window)",
 	} { // end of the list
diff --git a/web/app.css b/web/app.css
index 6ae5e19..fb28c3e 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop {
+.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop, .brandwho .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -2446,3 +2446,21 @@ html[data-size="medium"] svg[width="22"] {
   /* Room above. */
   margin-top: 0.3rem;
 } /* end of rule */
+
+/* The logo in the footer is a link to the company website: it sits like the picture alone, and a keyboard user sees a clear ring when it has focus. */
+.brandlogolink {
+  /* Only as big as the picture. */
+  display: inline-block;
+  /* No extra gap below the picture. */
+  line-height: 0;
+  /* Same rounded shape as the picture, so the ring follows it. */
+  border-radius: 0.4rem;
+} /* end of rule */
+
+/* The focus ring of the logo link. */
+.brandlogolink:focus-visible {
+  /* A clear ring. */
+  outline: 3px solid var(--text);
+  /* A gap between picture and ring. */
+  outline-offset: 2px;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index aebfefe..d4f5103 100644
--- a/web/index.html
+++ b/web/index.html
@@ -581,24 +581,22 @@
 </section>
 {{/* End of the main content. */}}
 </main>
-{{/* The footer bar: the company, its tagline, a way to the About page and a way to the company website. */}}
+{{/* The footer bar: the company logo (a link to the company website), its tagline, and the ways to the System check and the About page. */}}
 <footer class="brandbar" aria-label="About this program and its developer">
 {{/* The logo and the words on the left; the logo carries the company name for screen readers. */}}
 <div class="brandwho">
-{{/* The miniature logo, served from this program. */}}
-<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="termGate Consulting logo">
+{{/* The miniature logo, served from this program; it is also the link to the company website, in a new window with no link back and no referrer. */}}
+<span class="tipbox"><a class="brandlogolink" href="{{.FooterURL}}" target="_blank" rel="noopener noreferrer" aria-describedby="tiplogo"><img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="termGate Consulting logo"><span class="sr-only"> (opens termgate.com in a new window)</span></a><span class="tip tip-icon" role="tooltip" id="tiplogo">Visit termgate.com (opens in a new window)</span></span>
 {{/* The tagline and the AI line. */}}
 <span>{{.CompanyTagline}} {{.CompanyAILine}}</span>
 {{/* End of the words. */}}
 </div>
-{{/* The two buttons on the right. */}}
+{{/* The buttons on the right. */}}
 <div class="brandbtns">
 {{/* The System check page: what this computer offers for Ollama. */}}
 <a class="brandbtn" href="/systemcheck">System check</a>
 {{/* The About page of this program. */}}
 <a class="brandbtn" href="/about">About this program</a>
-{{/* The company website, in a new window with no link back and no referrer. */}}
-<a class="brandbtn brandbtn-main" href="{{.FooterURL}}" target="_blank" rel="noopener noreferrer">Visit termgate.com &#8599;<span class="sr-only"> (opens in a new window)</span></a>
 {{/* End of the buttons. */}}
 </div>
 {{/* End of the footer bar. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
4bb0f611be445dc5bc464eea4f8395e67b58956ba0084b3c8eac2726f8c5c63f  brand_test.go
1b18420984f2dbb777012a0eeea3d48ad486d1f7dc5b5d3c12bc6f4e1bb01722  web/app.css
91b6fcdf8d425b3dcf7953a0cf35d955a9877866fd5846eb1af5e35a9fcfb820  web/index.html
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
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
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
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter and look at the bottom of the main page: no Visit termgate.com button on the right; hover the logo on the left (tooltip) and click it (www.termgate.com opens in a new tab); then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
