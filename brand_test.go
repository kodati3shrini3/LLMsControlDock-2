// Package main tells Go that this test file belongs to the same program as about.go.
package main

import ( // import lists the packages this test file uses.
	// bytes reads the image from memory.
	"bytes"
	// image/png decodes the logo, so a damaged file is noticed.
	"image/png"
	// net/http provides status codes.
	"net/http"
	// os reads the template sources.
	"os"
	// path/filepath lists the template files.
	"path/filepath"
	// regexp finds links in the templates.
	"regexp"
	// strings searches text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestCompanyLinkIsTaggedAndLowercase checks the tag is fixed, all lowercase, and names only the program and the place.
func TestCompanyLinkIsTaggedAndLowercase(t *testing.T) {
	// The three places.
	for _, place := range []string{"header", "footer", "about-card"} {
		// Build the address.
		got := companyLink(place)
		// The exact text, so nothing can slip in.
		want := "https://www.termgate.com/?utm_source=ollama-control-center&utm_medium=app&utm_campaign=app-link&utm_content=" + place
		// Compare.
		if got != want {
			// Report the difference.
			t.Errorf("companyLink(%q) = %q, want %q", place, got, want)
		} // end of the compare
		// Tags are case-sensitive in analytics, so everything after the site must be lowercase.
		if rest := strings.TrimPrefix(got, companySite); rest != strings.ToLower(rest) {
			// Report the problem.
			t.Errorf("the tag is not all lowercase: %q", rest)
		} // end of the case check
	} // end of the loop
} // end of TestCompanyLinkIsTaggedAndLowercase

// TestMainPageShowsTheCompany checks the header line and the footer bar, and that their links open safely in a new window.
func TestMainPageShowsTheCompany(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// What must be there; the template escapes & as &amp; inside an address.
	for _, want := range []string{
		// The header line with the company name as a link.
		`<p class="brandline">by <a href="https://www.termgate.com/?utm_source=ollama-control-center&amp;utm_medium=app&amp;utm_campaign=app-link&amp;utm_content=header" target="_blank" rel="noopener noreferrer">termGate Consulting`,
		// The AI line.
		"Private AI on your own hardware.",
		// The footer bar.
		`<footer class="brandbar"`,
		// The tagline.
		"Transforming Healthcare through Data &amp; Technology.",
		// The footer button with its own place tag.
		`utm_content=footer" target="_blank" rel="noopener noreferrer">Visit termgate.com`,
		// The text for screen readers.
		"(opens in a new window)",
	} { // end of the list
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("main page does not contain %q", want)
		} // end of the check
	} // end of the loop
} // end of TestMainPageShowsTheCompany

// TestAboutPageShowsTheCompanyCard checks the services, the order, and the link.
func TestAboutPageShowsTheCompanyCard(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/about")
	// The card, with the AI service first.
	first := strings.Index(body, "AI &amp; Prompt Engineering")
	// The second service.
	second := strings.Index(body, "Clinical Data Mapping")
	// Both must be there, in that order.
	if first < 0 || second < 0 || first > second {
		// Report the problem.
		t.Errorf("services missing or in the wrong order (%d, %d)", first, second)
	} // end of the order check
	// The five services of the company website, written out here so a changed name is noticed.
	for _, name := range []string{"AI &amp; Prompt Engineering", "Clinical Data Mapping", "Clinical Data Modeling", "Strategy &amp; Advisory", "Clinical Terminology Training"} {
		// Look for it.
		if !strings.Contains(body, name) {
			// Report the problem.
			t.Errorf("service %q missing from the About page", name)
		} // end of the check
	} // end of the loop
	// The card link and the plain promise.
	for _, want := range []string{`utm_content=about-card" target="_blank" rel="noopener noreferrer">Visit termgate.com`, "nothing about you or your computer", "nothing is sent to them before that"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("About page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// Exactly five services, matching the company website.
	if len(companyServices) != 5 {
		// Report the problem.
		t.Errorf("%d services, want 5", len(companyServices))
	} // end of the count check
} // end of TestAboutPageShowsTheCompanyCard

// TestEveryExternalLinkIsSafe is a guard: any link in a template that goes outside this program must open in a new window and carry noopener and noreferrer, so the other site gets no way back to the monitor and no address.
func TestEveryExternalLinkIsSafe(t *testing.T) {
	// All templates.
	files, _ := filepath.Glob("web/*.html")
	// A link to an outside address, written out or built by the template from a field that holds one.
	link := regexp.MustCompile(`<a [^>]*href="(https?://[^"]*|\{\{\.(?:HeaderURL|FooterURL|CompanyURL|DeveloperProfile|Repository)\}\})"[^>]*>`)
	// How many were checked, so the test cannot pass by finding nothing.
	checked := 0
	// Go through the templates.
	for _, f := range files {
		// Read it.
		data, err := os.ReadFile(f)
		// A failure here is a broken test setup.
		if err != nil {
			// Stop the test.
			t.Fatalf("cannot read %s: %v", f, err)
		} // end of the read check
		// Every external link.
		for _, m := range link.FindAllString(string(data), -1) {
			// Count it.
			checked++
			// Each safety word must be there.
			if !strings.Contains(m, `target="_blank"`) || !strings.Contains(m, `rel="noopener noreferrer"`) {
				// Report the problem.
				t.Errorf("%s: external link without target and rel: %s", f, m)
			} // end of the safety check
		} // end of the link loop
	} // end of the file loop
	// At least the header, the footer, the card, LinkedIn and the repository.
	if checked < 5 {
		// Report the problem.
		t.Errorf("only %d external links found, want at least 5", checked)
	} // end of the count check
} // end of TestEveryExternalLinkIsSafe

// TestLogoIsServedAsAValidSmallPNG checks the logo route sends a decodable PNG of the expected size, and only on GET.
func TestLogoIsServedAsAValidSmallPNG(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Fetch the logo.
	status, header, body := get(t, rig.h, http.MethodGet, "/termgate-logo.png")
	// It must be a PNG.
	if status != http.StatusOK || header.Get("Content-Type") != "image/png" {
		// Stop the test.
		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the status check
	// Decode it: a damaged or wrong file fails here.
	img, err := png.Decode(bytes.NewReader([]byte(body)))
	// A failure means the file is not a PNG.
	if err != nil {
		// Stop the test.
		t.Fatalf("the logo is not a valid PNG: %v", err)
	} // end of the decode check
	// The size the pages expect (twice the displayed size, so it stays sharp).
	if b := img.Bounds(); b.Dx() != 178 || b.Dy() != 96 {
		// Report the problem.
		t.Errorf("logo is %dx%d, want 178x96", b.Dx(), b.Dy())
	} // end of the size check
	// A miniature must stay small.
	if len(body) > 40*1024 {
		// Report the problem.
		t.Errorf("logo is %d bytes, want at most 40 KB", len(body))
	} // end of the weight check
	// Only GET is allowed.
	if status, _, _ := get(t, rig.h, http.MethodPost, "/termgate-logo.png"); status != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("POST /termgate-logo.png = %d, want 405", status)
	} // end of the method check
} // end of TestLogoIsServedAsAValidSmallPNG

// TestLogoAppearsInFooterAndAboutCard checks both places, with the right alternative text.
func TestLogoAppearsInFooterAndAboutCard(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// The main page: the logo names the company for screen readers.
	_, _, main := get(t, rig.h, http.MethodGet, "/")
	// The tag.
	if !strings.Contains(main, `<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="termGate Consulting logo">`) {
		// Report the problem.
		t.Errorf("footer logo missing from the main page")
	} // end of the main check
	// The About page: the name is written beside it, so no alternative text.
	_, _, about := get(t, rig.h, http.MethodGet, "/about")
	// The tag.
	if !strings.Contains(about, `<img class="brandlogo" src="/termgate-logo.png" width="89" height="48" alt="">`) {
		// Report the problem.
		t.Errorf("logo missing from the About card")
	} // end of the about check
} // end of TestLogoAppearsInFooterAndAboutCard

// TestPoliciesAllowOnlyOwnImages checks every policy allows images from this program only: no other site, no inline data, no wildcard.
func TestPoliciesAllowOnlyOwnImages(t *testing.T) {
	// All three policies.
	for name, policy := range map[string]string{"plain": contentSecurityPolicy, "with script": contentSecurityPolicyWithScript, "main page": contentSecurityPolicyMainPage} {
		// The images rule must be exactly 'self'.
		if !strings.Contains(policy, "img-src 'self';") {
			// Report the problem.
			t.Errorf("%s policy lacks img-src 'self': %s", name, policy)
		} // end of the images check
		// Nothing wider.
		for _, bad := range []string{"data:", "https:", "http:", "img-src *", "unsafe-inline"} {
			// Look for it.
			if strings.Contains(policy, bad) {
				// Report the problem.
				t.Errorf("%s policy contains %q: %s", name, bad, policy)
			} // end of the check
		} // end of the bad loop
	} // end of the policy loop
} // end of TestPoliciesAllowOnlyOwnImages
