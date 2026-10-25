// Package main tells Go that this test file belongs to the same program as modelfile.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides requests and status codes.
	"net/http"
	// net/url builds form data.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// utf8 checks that a cut text is still valid.
	"unicode/utf8"
) // end of imports

// TestModelfilePageShowsText checks the page shows the Modelfile of a loaded and of a not-loaded model, escapes it, has no script, and changes nothing.
func TestModelfilePageShowsText(t *testing.T) {
	// A fake with a hostile-looking Modelfile and one loaded model.
	f := newGearFake()
	// The text contains markup that must never become markup.
	f.modelfile = "FROM x\nSYSTEM \"<script>alert(1)</script> & <b>bold</b>\"\nPARAMETER stop \"<end_of_turn>\"\n"
	// Mark one model loaded: the page must still work for it.
	f.loaded = []string{"alpha:1b"}
	// Build the rig.
	rig := gearRig(t, f)
	// Both a loaded and a not-loaded model.
	for _, model := range []string{"alpha:1b", "embed:1b"} {
		// Open the page.
		status, body, header := gearPost(t, rig, "/modelfile", model)
		// It must work.
		if status != http.StatusOK {
			// Report the problem.
			t.Fatalf("%s: status %d", model, status)
		} // end of the status check
		// The heading names the model, and the text is there, escaped.
		for _, want := range []string{"Modelfile of <code>" + model + "</code>", "FROM x", "&lt;script&gt;alert(1)&lt;/script&gt; &amp; &lt;b&gt;bold&lt;/b&gt;", "&lt;end_of_turn&gt;", "Read-only", `class="modelfile"`} {
			// Look for it.
			if !strings.Contains(body, want) {
				// Report the gap.
				t.Errorf("%s: page lacks %q", model, want)
			} // end of the check
		} // end of the loop
		// No raw markup from the text, no script, strict policy.
		if strings.Contains(body, "<script") || strings.Contains(body, "<b>") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
			// Report the problem.
			t.Errorf("%s: the page allows or contains a script or raw markup", model)
		} // end of the safety check
		// There is nothing to type and nothing to submit on this page.
		if strings.Contains(body, "<form") || strings.Contains(body, "<textarea") || strings.Contains(body, "<input") {
			// Report the problem.
			t.Errorf("%s: the Modelfile page has a form or a field", model)
		} // end of the read-only check
	} // end of the model loop
	// Reading changed nothing.
	if n := f.createCount(); n != 0 {
		// Report the problem.
		t.Errorf("%d create requests from a read-only page", n)
	} // end of the effect check
} // end of TestModelfilePageShowsText

// TestModelfilePageUnknownModel checks a model Ollama does not have gets a plain message.
func TestModelfilePageUnknownModel(t *testing.T) {
	// A fake with two models.
	rig := gearRig(t, newGearFake())
	// Ask for a model that is not installed.
	status, body, _ := gearPost(t, rig, "/modelfile", "nope:1b")
	// The page says so.
	if status != http.StatusOK || !strings.Contains(body, "not installed") {
		// Report the problem.
		t.Errorf("status %d, body lacks the not-installed text", status)
	} // end of the check
} // end of TestModelfilePageUnknownModel

// TestModelfilePageRefusals checks the same refusals as the other forms: other sites, no token, wrong token, no model, too much data, and the wrong method.
func TestModelfilePageRefusals(t *testing.T) {
	// A fake and a rig.
	f := newGearFake()
	// Build the rig.
	rig := gearRig(t, f)
	// The cases.
	for _, tc := range []struct {
		// name describes the case.
		name string
		// form is the posted form.
		form url.Values
		// headers are the request headers.
		headers map[string]string
		// want is the expected status.
		want int
	}{ // the cases follow
		// A page on another site posts the form.
		{"cross-site", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// A script without any browser headers.
		{"no origin headers", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{}, http.StatusForbidden},
		// The right origin but no token.
		{"missing token", url.Values{"model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
		// The right origin but a wrong token.
		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
		// No model name.
		{"no model", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
		// A body larger than the 2 KB limit.
		{"too large", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Send it.
			res := post(t, rig.h, "/modelfile", tc.form, tc.headers)
			// Compare the status.
			if res.StatusCode != tc.want {
				// Report the difference.
				t.Errorf("status %d, want %d", res.StatusCode, tc.want)
			} // end of the status check
		}) // end of the subtest
	} // end of the table loop
	// No refusal may have reached Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("a refused request reached Ollama: %d calls", n)
	} // end of the effect check
	// A GET must be refused.
	if status, _, _ := get(t, rig.h, http.MethodGet, "/modelfile"); status != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("GET /modelfile = %d, want 405", status)
	} // end of the method check
} // end of TestModelfilePageRefusals

// TestCutTextKeepsCharactersWhole checks a very long text is cut without splitting a character.
func TestCutTextKeepsCharactersWhole(t *testing.T) {
	// A short text stays whole.
	if got, cut := cutText("abc", 10); got != "abc" || cut {
		// Report the problem.
		t.Errorf("short text changed: %q %v", got, cut)
	} // end of the short check
	// A text of four-byte characters, cut in the middle of one.
	got, cut := cutText(strings.Repeat("😀", 10), 6)
	// It was cut, at a character boundary.
	if !cut || !utf8.ValidString(got) || got != "😀" {
		// Report the problem.
		t.Errorf("bad cut: %q %v", got, cut)
	} // end of the long check
} // end of TestCutTextKeepsCharactersWhole
