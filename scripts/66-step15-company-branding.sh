#!/usr/bin/env bash
# Script 66: the developer's company (termGate Consulting) appears under the title, in a footer bar and in a card on the About page, with safe new-window links and a lowercase source tag.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/about-and-text-size" ] || { echo "FAIL  not on feature/about-and-text-size"; exit 1; }
# Scripts 61 to 63 must be part of this branch already (merged into main).
grep -q 'target="_blank"' web/about.html || { echo "FAIL  script 65 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e brand_test.go ]; then
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
index db56ace..3d74add 100644
--- a/about.go
+++ b/about.go
@@ -46,6 +46,46 @@ const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
 // appRepository is the address of the source code; the repository is private, so only its owner can open it.
 const appRepository = "https://github.com/kodatishrini-beep/OllamaControlCenter"
 
+// companyName is the developer's company, shown in the header, the footer bar and the About page.
+const companyName = "termGate Consulting"
+
+// companyTagline is the company's own tagline, as shown on its website.
+const companyTagline = "Transforming Healthcare through Data & Technology."
+
+// companyAILine connects this program to the company's work: models that run on the person's own hardware keep data on that computer.
+const companyAILine = "Private AI on your own hardware."
+
+// companySite is the company website; the program only links to it and never contacts it by itself.
+const companySite = "https://www.termgate.com/"
+
+// companyLink builds the address of the company website for one place on the page; the tag is all lowercase, names only this program and the place, and carries nothing about the person or the computer.
+func companyLink(placement string) string {
+	// The site, then the fixed source tags, then the place (header, footer or about-card).
+	return companySite + "?utm_source=ollama-control-center&utm_medium=app&utm_campaign=app-link&utm_content=" + placement
+} // end of companyLink
+
+// companyService is one service of the company, shown on the About page.
+type companyService struct {
+	// Name is the service name.
+	Name string
+	// Detail is a short line about it.
+	Detail string
+} // end of companyService
+
+// companyServices lists the services in the order shown: the one that fits this program's audience first. The wording follows the company website and must be checked by the company before release.
+var companyServices = []companyService{
+	// The service closest to people who run local models.
+	{"AI & Prompt Engineering", "clinical prompt design, language processing of clinical text, generative AI for decision support"},
+	// Terminology mapping.
+	{"Clinical Data Mapping", "SNOMED CT, LOINC, ICD-10, RxNorm, MedDRA, UCUM"},
+	// Data models.
+	{"Clinical Data Modeling", "HL7 FHIR, openEHR, OMOP CDM"},
+	// Strategy.
+	{"Strategy & Advisory", "IT product roadmaps, clinical use case design, regulatory and compliance guidance"},
+	// Training.
+	{"Clinical Terminology Training", "SNOMED CT fundamentals and implementation, LOINC mapping"},
+}
+
 // readBuildInfo reads the facts the Go tool recorded in the program; a test replaces it.
 var readBuildInfo = debug.ReadBuildInfo
 
@@ -75,6 +115,16 @@ type aboutPage struct {
 	Modified bool
 	// RevisionDate is the date of the source revision in UTC, with the zone written out, or empty.
 	RevisionDate string
+	// CompanyName is companyName.
+	CompanyName string
+	// CompanyTagline is companyTagline.
+	CompanyTagline string
+	// CompanyAILine is companyAILine.
+	CompanyAILine string
+	// CompanyURL is the company website address for the About card.
+	CompanyURL string
+	// Services are the company's services.
+	Services []companyService
 	// Platform is the Go version, the operating system and the processor type.
 	Platform string
 } // end of aboutPage
@@ -160,6 +210,16 @@ func aboutHandler() http.HandlerFunc {
 			Modified: modified,
 			// The revision date in UTC.
 			RevisionDate: when,
+			// The company name.
+			CompanyName: companyName,
+			// The company tagline.
+			CompanyTagline: companyTagline,
+			// The AI line.
+			CompanyAILine: companyAILine,
+			// The company website, tagged for this place.
+			CompanyURL: companyLink("about-card"),
+			// The services.
+			Services: companyServices,
 			// Go version, system and processor.
 			Platform: runtime.Version() + " on " + runtime.GOOS + "/" + runtime.GOARCH,
 		} // end of the data
diff --git a/brand_test.go b/brand_test.go
new file mode 100644
index 0000000..39ca65b
--- /dev/null
+++ b/brand_test.go
@@ -0,0 +1,140 @@
+// Package main tells Go that this test file belongs to the same program as about.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// net/http provides status codes.
+	"net/http"
+	// os reads the template sources.
+	"os"
+	// path/filepath lists the template files.
+	"path/filepath"
+	// regexp finds links in the templates.
+	"regexp"
+	// strings searches text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// TestCompanyLinkIsTaggedAndLowercase checks the tag is fixed, all lowercase, and names only the program and the place.
+func TestCompanyLinkIsTaggedAndLowercase(t *testing.T) {
+	// The three places.
+	for _, place := range []string{"header", "footer", "about-card"} {
+		// Build the address.
+		got := companyLink(place)
+		// The exact text, so nothing can slip in.
+		want := "https://www.termgate.com/?utm_source=ollama-control-center&utm_medium=app&utm_campaign=app-link&utm_content=" + place
+		// Compare.
+		if got != want {
+			// Report the difference.
+			t.Errorf("companyLink(%q) = %q, want %q", place, got, want)
+		} // end of the compare
+		// Tags are case-sensitive in analytics, so everything after the site must be lowercase.
+		if rest := strings.TrimPrefix(got, companySite); rest != strings.ToLower(rest) {
+			// Report the problem.
+			t.Errorf("the tag is not all lowercase: %q", rest)
+		} // end of the case check
+	} // end of the loop
+} // end of TestCompanyLinkIsTaggedAndLowercase
+
+// TestMainPageShowsTheCompany checks the header line and the footer bar, and that their links open safely in a new window.
+func TestMainPageShowsTheCompany(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// What must be there; the template escapes & as &amp; inside an address.
+	for _, want := range []string{
+		// The header line with the company name as a link.
+		`<p class="brandline">by <a href="https://www.termgate.com/?utm_source=ollama-control-center&amp;utm_medium=app&amp;utm_campaign=app-link&amp;utm_content=header" target="_blank" rel="noopener noreferrer">termGate Consulting`,
+		// The AI line.
+		"Private AI on your own hardware.",
+		// The footer bar.
+		`<footer class="brandbar"`,
+		// The tagline.
+		"Transforming Healthcare through Data &amp; Technology.",
+		// The footer button with its own place tag.
+		`utm_content=footer" target="_blank" rel="noopener noreferrer">Visit termgate.com`,
+		// The text for screen readers.
+		"(opens in a new window)",
+	} { // end of the list
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the problem.
+			t.Errorf("main page does not contain %q", want)
+		} // end of the check
+	} // end of the loop
+} // end of TestMainPageShowsTheCompany
+
+// TestAboutPageShowsTheCompanyCard checks the services, the order, and the link.
+func TestAboutPageShowsTheCompanyCard(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Fetch the page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/about")
+	// The card, with the AI service first.
+	first := strings.Index(body, "AI &amp; Prompt Engineering")
+	// The second service.
+	second := strings.Index(body, "Clinical Data Mapping")
+	// Both must be there, in that order.
+	if first < 0 || second < 0 || first > second {
+		// Report the problem.
+		t.Errorf("services missing or in the wrong order (%d, %d)", first, second)
+	} // end of the order check
+	// The five services of the company website, written out here so a changed name is noticed.
+	for _, name := range []string{"AI &amp; Prompt Engineering", "Clinical Data Mapping", "Clinical Data Modeling", "Strategy &amp; Advisory", "Clinical Terminology Training"} {
+		// Look for it.
+		if !strings.Contains(body, name) {
+			// Report the problem.
+			t.Errorf("service %q missing from the About page", name)
+		} // end of the check
+	} // end of the loop
+	// The card link and the plain promise.
+	for _, want := range []string{`utm_content=about-card" target="_blank" rel="noopener noreferrer">Visit termgate.com`, "nothing about you or your computer", "nothing is sent to them before that"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the problem.
+			t.Errorf("About page does not contain %q", want)
+		} // end of the check
+	} // end of the loop
+	// Exactly five services, matching the company website.
+	if len(companyServices) != 5 {
+		// Report the problem.
+		t.Errorf("%d services, want 5", len(companyServices))
+	} // end of the count check
+} // end of TestAboutPageShowsTheCompanyCard
+
+// TestEveryExternalLinkIsSafe is a guard: any link in a template that goes outside this program must open in a new window and carry noopener and noreferrer, so the other site gets no way back to the monitor and no address.
+func TestEveryExternalLinkIsSafe(t *testing.T) {
+	// All templates.
+	files, _ := filepath.Glob("web/*.html")
+	// A link to an outside address, written out or built by the template from a field that holds one.
+	link := regexp.MustCompile(`<a [^>]*href="(https?://[^"]*|\{\{\.(?:HeaderURL|FooterURL|CompanyURL|DeveloperProfile|Repository)\}\})"[^>]*>`)
+	// How many were checked, so the test cannot pass by finding nothing.
+	checked := 0
+	// Go through the templates.
+	for _, f := range files {
+		// Read it.
+		data, err := os.ReadFile(f)
+		// A failure here is a broken test setup.
+		if err != nil {
+			// Stop the test.
+			t.Fatalf("cannot read %s: %v", f, err)
+		} // end of the read check
+		// Every external link.
+		for _, m := range link.FindAllString(string(data), -1) {
+			// Count it.
+			checked++
+			// Each safety word must be there.
+			if !strings.Contains(m, `target="_blank"`) || !strings.Contains(m, `rel="noopener noreferrer"`) {
+				// Report the problem.
+				t.Errorf("%s: external link without target and rel: %s", f, m)
+			} // end of the safety check
+		} // end of the link loop
+	} // end of the file loop
+	// At least the header, the footer, the card, LinkedIn and the repository.
+	if checked < 5 {
+		// Report the problem.
+		t.Errorf("only %d external links found, want at least 5", checked)
+	} // end of the count check
+} // end of TestEveryExternalLinkIsSafe
diff --git a/size_test.go b/size_test.go
index df5ce97..8d7fae9 100644
--- a/size_test.go
+++ b/size_test.go
@@ -52,8 +52,8 @@ func TestSizeSwitchOnPage(t *testing.T) {
 		`<span class="knob knob-letter" aria-hidden="true">L</span>`,
 		// The help bubble with both sizes explained.
 		`role="tooltip" id="tipsize">Text size: now Large (L)`,
-		// The About link in the footer.
-		`<a href="/about">About Ollama Control Center</a>`,
+		// The About button in the footer bar.
+		`<a class="brandbtn" href="/about">About this program</a>`,
 	} { // end of the list
 		// Look for it.
 		if !strings.Contains(body, want) {
diff --git a/web.go b/web.go
index fe51159..6d95f25 100644
--- a/web.go
+++ b/web.go
@@ -53,6 +53,16 @@ type pageData struct {
 	Theme string
 	// Size is the saved text size, medium, or empty for the browser's own size.
 	Size string
+	// CompanyName is the developer's company, shown under the title and in the footer bar.
+	CompanyName string
+	// CompanyTagline is the company's tagline, shown in the footer bar.
+	CompanyTagline string
+	// CompanyAILine is the line that ties the program to the company's work.
+	CompanyAILine string
+	// HeaderURL is the company website address for the link under the title.
+	HeaderURL string
+	// FooterURL is the company website address for the footer bar.
+	FooterURL string
 	// Token is the page token that every form on the page carries.
 	Token string
 	// CompareCount is how many models have a saved performance test that can be compared.
@@ -191,6 +201,10 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			Theme: themeFromRequest(r),
 			// The saved text size, from the cookie; empty means the browser's own size.
 			Size: sizeFromRequest(r),
+			// The company name, tagline and AI line.
+			CompanyName: companyName, CompanyTagline: companyTagline, CompanyAILine: companyAILine,
+			// The company website addresses, tagged for the two places.
+			HeaderURL: companyLink("header"), FooterURL: companyLink("footer"),
 			// The page token for the forms.
 			Token: token,
 			// How many models can be compared.
diff --git a/web/about.html b/web/about.html
index 4860149..023f0cf 100644
--- a/web/about.html
+++ b/web/about.html
@@ -40,13 +40,31 @@
 {{/* Where the source lives. */}}
 <tr><th scope="row">Source code</th><td><a href="{{.Repository}}" target="_blank" rel="noopener noreferrer">{{.Repository}}<span class="sr-only"> (opens in a new window)</span></a> (private repository; opens only for its owner)</td></tr>
 {{/* Where the data goes. */}}
-<tr><th scope="row">Privacy</th><td>Runs only on this computer. The one request to the outside is the optional check of Ollama's public library when a model is deleted, and it sends only the model's name.</td></tr>
+<tr><th scope="row">Privacy</th><td>Runs only on this computer. The one request to the outside is the optional check of Ollama's public library when a model is deleted, and it sends only the model's name. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
 {{/* The licence. */}}
 <tr><th scope="row">Licence</th><td>{{.Copyright}}</td></tr>
 {{/* End of the table. */}}
 </table>
 {{/* The dedication, set apart so it stands out. */}}
 <blockquote class="dedication">{{.Dedication}}</blockquote>
+{{/* The developer's company: what it does, and a way to find out more. */}}
+<section class="companycard" aria-labelledby="companyname">
+{{/* The name. */}}
+<h2 id="companyname">{{.CompanyName}}</h2>
+{{/* The tagline and the AI line. */}}
+<p class="muted">{{.CompanyTagline}} {{.CompanyAILine}}</p>
+{{/* The services. */}}
+<ul>
+{{range .Services}}
+{{/* One service. */}}
+<li><strong>{{.Name}}</strong>: {{.Detail}}</li>
+{{/* End of the services. */}}
+{{end}}
+</ul>
+{{/* The company website, in a new window with no link back and no referrer. */}}
+<p><a class="brandbtn brandbtn-main" href="{{.CompanyURL}}" target="_blank" rel="noopener noreferrer">Visit termgate.com &#8599;<span class="sr-only"> (opens in a new window)</span></a> <span class="muted brandnote">Opens in a new window. The link carries only a source tag (utm_source=ollama-control-center); nothing about you or your computer.</span></p>
+{{/* End of the company card. */}}
+</section>
 {{/* A link back. */}}
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
 {{/* End of the card. */}}
diff --git a/web/app.css b/web/app.css
index 7182842..08cad1f 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1583,15 +1583,6 @@ html[data-size="medium"] svg[width="22"] {
   white-space: nowrap;
 } /* end of rule */
 
-/* The quiet footer with the About link. */
-.sitefooter {
-  /* Centred under the page. */
-  text-align: center;
-  /* Space above and below. */
-  margin: 1.5rem 0 2rem;
-  /* Small and quiet. */
-  font-size: 0.85rem;
-} /* end of rule */
 
 /* The About card: narrower than the tables so lines stay easy to read. */
 .aboutcard {
@@ -1687,3 +1678,133 @@ html[data-size="medium"] svg[width="22"] {
     right: 0.5rem;
   } /* end of rule */
 } /* end of rule */
+
+/* The quiet line under the title: who is behind the program. */
+.brandline {
+  /* Close to the title. */
+  margin: 0.2rem 0 0;
+  /* Small and quiet. */
+  font-size: 0.85rem;
+  /* Secondary colour from the variables. */
+  color: var(--muted);
+} /* end of rule */
+
+/* The company name in that line is a link: semi-bold so it can be found. */
+.brandline a {
+  /* Semi-bold. */
+  font-weight: 600;
+} /* end of rule */
+
+/* The footer bar at the bottom of the main page. */
+.brandbar {
+  /* Words on the left, buttons on the right. */
+  display: flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Push the two parts apart. */
+  justify-content: space-between;
+  /* Wrap on a narrow window. */
+  flex-wrap: wrap;
+  /* Space between the parts when they wrap. */
+  gap: 0.75rem 1rem;
+  /* Space above and below the bar. */
+  margin: 1.5rem 0 2rem;
+  /* Air inside. */
+  padding: 0.9rem 1.1rem;
+  /* The same solid outline and panel colour as the other boxes. */
+  border: 2px solid var(--border);
+  /* Rounded like the panels. */
+  border-radius: 0.5rem;
+  /* Panel colour. */
+  background: var(--panel);
+} /* end of rule */
+
+/* The company name in the bar, on its own line. */
+.brandbar strong {
+  /* A line of its own. */
+  display: block;
+} /* end of rule */
+
+/* The tagline in the bar. */
+.brandbar span {
+  /* Quiet colour. */
+  color: var(--muted);
+  /* Small. */
+  font-size: 0.85rem;
+} /* end of rule */
+
+/* The two buttons. */
+.brandbtns {
+  /* Side by side. */
+  display: flex;
+  /* Wrap on a narrow window. */
+  flex-wrap: wrap;
+  /* Space between them. */
+  gap: 0.6rem;
+} /* end of rule */
+
+/* A rounded link button with an outline. */
+.brandbtn {
+  /* An outline in the accent colour, visible without colour fill. */
+  border: 2px solid var(--cat-accent);
+  /* Pill shape. */
+  border-radius: 999px;
+  /* Room inside. */
+  padding: 0.3rem 0.9rem;
+  /* Small. */
+  font-size: 0.85rem;
+  /* No underline on a button. */
+  text-decoration: none;
+  /* Text colour from the variables. */
+  color: var(--text);
+  /* Keep on one line. */
+  white-space: nowrap;
+  /* Sits level with the words next to it. */
+  display: inline-block;
+} /* end of rule */
+
+/* The main button is filled. */
+.brandbtn-main {
+  /* Filled with the accent colour. */
+  background: var(--cat-accent);
+  /* Page colour on it for contrast in light and dark. */
+  color: var(--bg);
+  /* Semi-bold. */
+  font-weight: 600;
+} /* end of rule */
+
+/* A button under the pointer or the keyboard focus gets a strong outline. */
+.brandbtn:hover, .brandbtn:focus-visible {
+  /* Outline in the text colour. */
+  outline: 3px solid var(--text);
+  /* A little gap. */
+  outline-offset: 2px;
+} /* end of rule */
+
+/* The company card on the About page. */
+.companycard {
+  /* Space above the card. */
+  margin: 1.25rem 0;
+  /* Air inside. */
+  padding: 1rem 1.25rem;
+  /* A solid outline. */
+  border: 2px solid var(--border);
+  /* Rounded corners. */
+  border-radius: 0.5rem;
+} /* end of rule */
+
+/* The company name in the card. */
+.companycard h2 {
+  /* Tight to the top. */
+  margin: 0.1rem 0 0.3rem;
+  /* A little larger than body text. */
+  font-size: 1.1rem;
+} /* end of rule */
+
+/* The note next to the button. */
+.brandnote {
+  /* Small. */
+  font-size: 0.8rem;
+  /* A little room after the button. */
+  margin-left: 0.4rem;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index fab2cf3..83c5823 100644
--- a/web/index.html
+++ b/web/index.html
@@ -23,6 +23,8 @@
 <div>
 {{/* The main heading. */}}
 <h1>OllamaControlCenter</h1>
+{{/* A quiet line under the title: who is behind the program, with a link that opens in a new window. */}}
+<p class="brandline">by <a href="{{.HeaderURL}}" target="_blank" rel="noopener noreferrer">{{.CompanyName}}<span class="sr-only"> (opens in a new window)</span></a> &middot; {{.CompanyAILine}}</p>
 {{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
 <p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
 {{/* Says whether the page updates by itself, and how fresh it is; the symbol and the words carry the meaning. */}}
@@ -430,11 +432,25 @@
 </section>
 {{/* End of the main content. */}}
 </main>
-{{/* The footer: a quiet link to the About page. */}}
-<footer class="sitefooter">
-{{/* The link. */}}
-<a href="/about">About Ollama Control Center</a>
-{{/* End of the footer. */}}
+{{/* The footer bar: the company, its tagline, a way to the About page and a way to the company website. */}}
+<footer class="brandbar" aria-label="About this program and its developer">
+{{/* The words on the left. */}}
+<div>
+{{/* The company name. */}}
+<strong>{{.CompanyName}}</strong>
+{{/* Its tagline and the AI line. */}}
+<span>{{.CompanyTagline}} {{.CompanyAILine}}</span>
+{{/* End of the words. */}}
+</div>
+{{/* The two buttons on the right. */}}
+<div class="brandbtns">
+{{/* The About page of this program. */}}
+<a class="brandbtn" href="/about">About this program</a>
+{{/* The company website, in a new window with no link back and no referrer. */}}
+<a class="brandbtn brandbtn-main" href="{{.FooterURL}}" target="_blank" rel="noopener noreferrer">Visit termgate.com &#8599;<span class="sr-only"> (opens in a new window)</span></a>
+{{/* End of the buttons. */}}
+</div>
+{{/* End of the footer bar. */}}
 </footer>
 {{/* The monitor's own script ticks the timers and asks the monitor for fresh figures every few seconds; it is loaded only when a table is shown. */}}
 {{if .HasTable}}<script src="/countdown.js" defer></script>{{end}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
9d81f5d9a2e40d5140d545fe23817ba46ca5f9cae63d0a68aad596dde8e33baa  about.go
a9190ddb9ea78ab729c86f79ef9f426a7ad0bbe050db00f543e29c300b9a3fca  web.go
7f869df240ad9b1c36cb014fa6986baf1ca808f9a25ab5ed8d0d3247aa7c403f  size_test.go
fafe8acfd440b2eed7bb20ac645e36b739088704fabc73bebdfaf5641526b457  brand_test.go
3bfd26277dc8a4351325f0e7eab7aa9cd7f6720e7c593f98dde39fbc1fbbab13  web/index.html
f592cea22da72517f958b691c81d039ebdd7768cd7d43b63257e2bca6a9322c5  web/about.html
2ae04fbf40a7e070f71bcf9638cf9bcbf83b911d1fdb379de8a8f5e28ad709c3  web/app.css
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
