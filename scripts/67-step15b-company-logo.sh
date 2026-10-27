#!/usr/bin/env bash
# Script 67: the termGate Consulting logo (a 15 KB miniature, embedded in the program) appears in the footer bar and the About card; the security policy now allows images from this program only.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/about-and-text-size" ] || { echo "FAIL  not on feature/about-and-text-size"; exit 1; }
# Scripts 61 to 63 must be part of this branch already (merged into main).
[ -e brand_test.go ] || { echo "FAIL  script 66 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e web/termgate-logo.png ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 3d74add..17f6aaa 100644
--- a/about.go
+++ b/about.go
@@ -86,6 +86,11 @@ var companyServices = []companyService{
 	{"Clinical Terminology Training", "SNOMED CT fundamentals and implementation, LOINC mapping"},
 }
 
+// companyLogo is the company's logo, cropped and shrunk to 178 by 96 pixels (shown at 40 pixels high), stored inside the executable so nothing is downloaded from another site.
+//
+//go:embed web/termgate-logo.png
+var companyLogo []byte
+
 // readBuildInfo reads the facts the Go tool recorded in the program; a test replaces it.
 var readBuildInfo = debug.ReadBuildInfo
 
diff --git a/brand_test.go b/brand_test.go
index 39ca65b..0788f26 100644
--- a/brand_test.go
+++ b/brand_test.go
@@ -2,6 +2,10 @@
 package main
 
 import ( // import lists the packages this test file uses.
+	// bytes reads the image from memory.
+	"bytes"
+	// image/png decodes the logo, so a damaged file is noticed.
+	"image/png"
 	// net/http provides status codes.
 	"net/http"
 	// os reads the template sources.
@@ -138,3 +142,78 @@ func TestEveryExternalLinkIsSafe(t *testing.T) {
 		t.Errorf("only %d external links found, want at least 5", checked)
 	} // end of the count check
 } // end of TestEveryExternalLinkIsSafe
+
+// TestLogoIsServedAsAValidSmallPNG checks the logo route sends a decodable PNG of the expected size, and only on GET.
+func TestLogoIsServedAsAValidSmallPNG(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the logo.
+	status, header, body := get(t, rig.h, http.MethodGet, "/termgate-logo.png")
+	// It must be a PNG.
+	if status != http.StatusOK || header.Get("Content-Type") != "image/png" {
+		// Stop the test.
+		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
+	} // end of the status check
+	// Decode it: a damaged or wrong file fails here.
+	img, err := png.Decode(bytes.NewReader([]byte(body)))
+	// A failure means the file is not a PNG.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("the logo is not a valid PNG: %v", err)
+	} // end of the decode check
+	// The size the pages expect (twice the displayed size, so it stays sharp).
+	if b := img.Bounds(); b.Dx() != 178 || b.Dy() != 96 {
+		// Report the problem.
+		t.Errorf("logo is %dx%d, want 178x96", b.Dx(), b.Dy())
+	} // end of the size check
+	// A miniature must stay small.
+	if len(body) > 40*1024 {
+		// Report the problem.
+		t.Errorf("logo is %d bytes, want at most 40 KB", len(body))
+	} // end of the weight check
+	// Only GET is allowed.
+	if status, _, _ := get(t, rig.h, http.MethodPost, "/termgate-logo.png"); status != http.StatusMethodNotAllowed {
+		// Report the problem.
+		t.Errorf("POST /termgate-logo.png = %d, want 405", status)
+	} // end of the method check
+} // end of TestLogoIsServedAsAValidSmallPNG
+
+// TestLogoAppearsInFooterAndAboutCard checks both places, with the right alternative text.
+func TestLogoAppearsInFooterAndAboutCard(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// The main page: the logo names the company for screen readers.
+	_, _, main := get(t, rig.h, http.MethodGet, "/")
+	// The tag.
+	if !strings.Contains(main, `<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="termGate Consulting logo">`) {
+		// Report the problem.
+		t.Errorf("footer logo missing from the main page")
+	} // end of the main check
+	// The About page: the name is written beside it, so no alternative text.
+	_, _, about := get(t, rig.h, http.MethodGet, "/about")
+	// The tag.
+	if !strings.Contains(about, `<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="">`) {
+		// Report the problem.
+		t.Errorf("logo missing from the About card")
+	} // end of the about check
+} // end of TestLogoAppearsInFooterAndAboutCard
+
+// TestPoliciesAllowOnlyOwnImages checks every policy allows images from this program only: no other site, no inline data, no wildcard.
+func TestPoliciesAllowOnlyOwnImages(t *testing.T) {
+	// All three policies.
+	for name, policy := range map[string]string{"plain": contentSecurityPolicy, "with script": contentSecurityPolicyWithScript, "main page": contentSecurityPolicyMainPage} {
+		// The images rule must be exactly 'self'.
+		if !strings.Contains(policy, "img-src 'self';") {
+			// Report the problem.
+			t.Errorf("%s policy lacks img-src 'self': %s", name, policy)
+		} // end of the images check
+		// Nothing wider.
+		for _, bad := range []string{"data:", "https:", "http:", "img-src *", "unsafe-inline"} {
+			// Look for it.
+			if strings.Contains(policy, bad) {
+				// Report the problem.
+				t.Errorf("%s policy contains %q: %s", name, bad, policy)
+			} // end of the check
+		} // end of the bad loop
+	} // end of the policy loop
+} // end of TestPoliciesAllowOnlyOwnImages
diff --git a/countdown.go b/countdown.go
index b591015..3cf28cb 100644
--- a/countdown.go
+++ b/countdown.go
@@ -16,7 +16,7 @@ import ( // import lists the standard-library packages this file uses.
 var countdownJS []byte
 
 // contentSecurityPolicyWithScript is the policy for the message pages that show a ticking timer: the same as the main page plus scripts from this same address only (no inline scripts, no other sites).
-const contentSecurityPolicyWithScript = "default-src 'none'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
+const contentSecurityPolicyWithScript = "default-src 'none'; style-src 'self'; img-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
 
 // contentSecurityPolicyMainPage is the policy for the main page when it shows the table: the message-page policy plus connect-src 'self', so the script can ask this same address for fresh figures (still no inline scripts, no other sites).
 const contentSecurityPolicyMainPage = contentSecurityPolicyWithScript + "; connect-src 'self'"
diff --git a/web.go b/web.go
index 6d95f25..747d44c 100644
--- a/web.go
+++ b/web.go
@@ -26,8 +26,8 @@ var indexTemplateText string
 //go:embed web/app.css
 var appCSS []byte
 
-// contentSecurityPolicy tells the browser what the page may load: only our own stylesheet, no scripts, no frames, and forms that send only to this same page.
-const contentSecurityPolicy = "default-src 'none'; style-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
+// contentSecurityPolicy tells the browser what the page may load: only our own stylesheet and our own images, no scripts, no frames, and forms that send only to this same page.
+const contentSecurityPolicy = "default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
 
 // pageData is everything the page template can show.
 type pageData struct {
@@ -268,6 +268,13 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 		// Send it.
 		w.Write(appCSS)
 	}) // end of the stylesheet route
+	// Route: a GET request for "/termgate-logo.png" sends the embedded company logo.
+	mux.HandleFunc("GET /termgate-logo.png", func(w http.ResponseWriter, r *http.Request) {
+		// Tell the browser this is a PNG image.
+		w.Header().Set("Content-Type", "image/png")
+		// Send it.
+		w.Write(companyLogo)
+	}) // end of the logo route
 	// Wrap the router so every reply carries the safety headers.
 	return secureHeaders(mux)
 } // end of newWebHandler
diff --git a/web/about.html b/web/about.html
index 023f0cf..c849bff 100644
--- a/web/about.html
+++ b/web/about.html
@@ -49,8 +49,14 @@
 <blockquote class="dedication">{{.Dedication}}</blockquote>
 {{/* The developer's company: what it does, and a way to find out more. */}}
 <section class="companycard" aria-labelledby="companyname">
+{{/* The logo beside the name; the name is already written next to it, so the logo has no alternative text. */}}
+<div class="cardhead">
+{{/* The miniature logo, served from this program. */}}
+<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="">
 {{/* The name. */}}
 <h2 id="companyname">{{.CompanyName}}</h2>
+{{/* End of the logo and name. */}}
+</div>
 {{/* The tagline and the AI line. */}}
 <p class="muted">{{.CompanyTagline}} {{.CompanyAILine}}</p>
 {{/* The services. */}}
diff --git a/web/app.css b/web/app.css
index 08cad1f..983ba0c 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1719,12 +1719,6 @@ html[data-size="medium"] svg[width="22"] {
   background: var(--panel);
 } /* end of rule */
 
-/* The company name in the bar, on its own line. */
-.brandbar strong {
-  /* A line of its own. */
-  display: block;
-} /* end of rule */
-
 /* The tagline in the bar. */
 .brandbar span {
   /* Quiet colour. */
@@ -1808,3 +1802,45 @@ html[data-size="medium"] svg[width="22"] {
   /* A little room after the button. */
   margin-left: 0.4rem;
 } /* end of rule */
+
+/* The logo and the tagline side by side in the footer bar. */
+.brandwho {
+  /* Side by side. */
+  display: flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between the logo and the words. */
+  gap: 0.9rem;
+} /* end of rule */
+
+/* The miniature logo: 2.5 rem high (40 pixels at the normal size), so it follows the text size switch. */
+.brandlogo {
+  /* The height decides; the width follows the picture's shape. */
+  height: 2.5rem;
+  /* Keep the shape. */
+  width: auto;
+  /* Never squeezed by the words next to it. */
+  flex: none;
+  /* Softly rounded corners, like the boxes. */
+  border-radius: 0.4rem;
+  /* A white tile behind it, so the logo reads the same in the dark theme. */
+  background: #ffffff;
+} /* end of rule */
+
+/* The logo with the company name in the About card. */
+.cardhead {
+  /* Side by side. */
+  display: flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between the logo and the name. */
+  gap: 0.9rem;
+  /* Space below, before the tagline. */
+  margin-bottom: 0.3rem;
+} /* end of rule */
+
+/* The name next to the logo needs no extra space. */
+.cardhead h2 {
+  /* No margins inside the row. */
+  margin: 0;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 83c5823..af2ff94 100644
--- a/web/index.html
+++ b/web/index.html
@@ -434,11 +434,11 @@
 </main>
 {{/* The footer bar: the company, its tagline, a way to the About page and a way to the company website. */}}
 <footer class="brandbar" aria-label="About this program and its developer">
-{{/* The words on the left. */}}
-<div>
-{{/* The company name. */}}
-<strong>{{.CompanyName}}</strong>
-{{/* Its tagline and the AI line. */}}
+{{/* The logo and the words on the left; the logo carries the company name for screen readers. */}}
+<div class="brandwho">
+{{/* The miniature logo, served from this program. */}}
+<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="termGate Consulting logo">
+{{/* The tagline and the AI line. */}}
 <span>{{.CompanyTagline}} {{.CompanyAILine}}</span>
 {{/* End of the words. */}}
 </div>
diff --git a/web/termgate-logo.png b/web/termgate-logo.png
new file mode 100644
index 0000000000000000000000000000000000000000..70203e2d4ef600eb6d0146be7f40dfd0a2613052
GIT binary patch
literal 15471
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

literal 0
HcmV?d00001

PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1127f6577f72cf880f2e918a1db7245b57a2bfdb02337d1c52806258cff22e23  about.go
659cd519e4313ebd748bc0857a93e266b095e4fd01957bf8f5866da33401cfff  web.go
70c2d6ccf96b967c43b1d5f4c7162cfc583d8b3f342d05f537362e5735596648  countdown.go
15ae73dc2a2c797073be5f616297ca3739035f8159e3c266edd9386c2501a4e8  brand_test.go
9530e0b7d2eb9ca5a2c5e2a8179fdb05386bfed15b964c5a0941c084152e5386  web/index.html
d0c40278183e58e7d257f00a420169cf0b23dbe2c0bcefb64d8e8aefd239f9bd  web/about.html
f289c864d2f5a14aea72c68d4caa3a012f5a1187bc17db68cd53bbac5d003025  web/app.css
5508cba4f659f423c6ad0f905d96c9bb01a13803ba91f02402244b9b8cbc43e6  web/termgate-logo.png
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
