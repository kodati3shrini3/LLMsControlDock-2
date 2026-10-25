// Package main tells Go that this test file belongs to the same program as loading.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides requests and status codes.
	"net/http"
	// net/url builds form data.
	"net/url"
	// regexp counts and finds pieces of the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestLoadWarningHasWaitingBox checks the warning page carries the hidden waiting box, the marked form and the script, and nothing that could run inline.
func TestLoadWarningHasWaitingBox(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Ask to load.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// Every part the script needs, and the honest wording.
	for _, want := range []string{`<form id="loadform" method="post" action="/load/confirm" data-loading>`, `id="choices"`, `id="loading" role="status" aria-live="polite" hidden`, `class="elapsed"`, `<script src="/loading.js" defer></script>`, "not a percentage"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("warning page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Exactly one script tag, and it is the monitor's own file (no inline code).
	if n := len(regexp.MustCompile(`<script`).FindAllString(body, -1)); n != 1 || strings.Contains(body, "<script>") {
		// Report the problem.
		t.Errorf("unexpected script tags: %d", n)
	} // end of the script check
	// No style attributes either, because the policy forbids inline styles.
	if strings.Contains(body, ` style=`) {
		// Report the problem.
		t.Errorf("the page has an inline style")
	} // end of the style check
	// The policy allows the monitor's own script only.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report the problem.
		t.Errorf("unexpected policy: %s", csp)
	} // end of the policy check
	// Still nothing was sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("the first step sent %d requests", n)
	} // end of the effect check
} // end of TestLoadWarningHasWaitingBox

// TestOtherLoadPagesHaveNoLoadingScript checks only the warning page gets the waiting script.
func TestOtherLoadPagesHaveNoLoadingScript(t *testing.T) {
	// One model loaded.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Ask to load a model that is already loaded.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// No loading script and the strict policy.
	if body := bodyOf(res); strings.Contains(body, "loading.js") || strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src") {
		// Report the problem.
		t.Errorf("an ordinary message page allows or contains the loading script")
	} // end of the check
} // end of TestOtherLoadPagesHaveNoLoadingScript

// TestLoadingScriptIsServed checks the script file is sent as JavaScript and contains the pieces that matter.
func TestLoadingScriptIsServed(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/loading.js")
	// Found, typed as JavaScript, with the timer and the Back-button reset.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "setInterval") || !strings.Contains(body, "pageshow") {
		// Report the problem.
		t.Errorf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
	// The script file is read-only content: a POST must be refused.
	if res := post(t, rig.h, "/loading.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("POST /loading.js = %d, want 405", res.StatusCode)
	} // end of the method check
} // end of TestLoadingScriptIsServed

// TestStateCellsAreAligned checks every state cell has the fixed-width label, so the buttons start at the same place.
func TestStateCellsAreAligned(t *testing.T) {
	// One model loaded, one not.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// Two models, so two labels.
	if n := strings.Count(body, `<span class="statelabel">`); n != 2 {
		// Report the difference.
		t.Errorf("state labels = %d, want 2", n)
	} // end of the count
} // end of TestStateCellsAreAligned

// TestLoadingStyles checks the stylesheet has the new rules.
func TestLoadingStyles(t *testing.T) {
	// The stylesheet text.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// The fixed-width label that aligns the buttons.
		"state label": ".statelabel {",
		// The label has a minimum width.
		"label width": "min-width: 8rem",
		// The moving bar.
		"bar": ".barfill {",
		// Its movement.
		"bar movement": "@keyframes slide",
		// People who ask for less motion get a still bar.
		"reduced motion": "prefers-reduced-motion: reduce",
		// The hidden attribute must win over every display rule.
		"hidden wins": "[hidden] {",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestLoadingStyles
