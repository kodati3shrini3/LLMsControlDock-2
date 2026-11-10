// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides the request method names.
	"net/http"
	// os reads the style file.
	"os"
	// strings searches the pages.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestKeyTwistie checks the key to the symbols: closed by default, open with ?key=open, and no automatic update while it is open.
func TestKeyTwistie(t *testing.T) {
	// A fake Ollama and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// The page as it first opens.
	_, _, closed := get(t, rig.h, http.MethodGet, "/")
	// The page with the key opened.
	_, _, open := get(t, rig.h, http.MethodGet, "/?key=open")
	// Closed: the link to open it, the hint, no key box, and the automatic update is on.
	for _, want := range []string{`href="/?key=open#key"`, "Key to the symbols", "(click to show)", `http-equiv="refresh"`, "Watching: the page updates itself"} {
		// Look for it.
		if !strings.Contains(closed, want) {
			// Report the gap.
			t.Errorf("closed page lacks %q", want)
		} // end of the check
	} // end of the closed loop
	// Closed: the box with the entries is not drawn.
	if strings.Contains(closed, `<ul class="legend`) || strings.Contains(closed, "Dotted headings</strong>") {
		// Report the problem.
		t.Errorf("the key box is drawn while closed")
	} // end of the box check
	// Open: the link to close it, the hint, the key box, no automatic update, and the page says why.
	for _, want := range []string{`href="/#key"`, "(click to hide)", `<ul class="legend`, "Dotted headings</strong>", "Paused while the key to the symbols is open", "Close the key to carry on watching"} {
		// Look for it.
		if !strings.Contains(open, want) {
			// Report the gap.
			t.Errorf("open page lacks %q", want)
		} // end of the check
	} // end of the open loop
	// Open: no refresh tag at all, and no claim that the page updates itself.
	if strings.Contains(open, `http-equiv="refresh"`) || strings.Contains(open, "Watching: the page updates itself") {
		// Report the problem.
		t.Errorf("the open page still updates itself")
	} // end of the refresh check
	// Any other value of the parameter counts as closed.
	_, _, odd := get(t, rig.h, http.MethodGet, "/?key=<script>")
	// It must be closed and must not echo the value.
	if strings.Contains(odd, `<ul class="legend`) || strings.Contains(odd, "<script>") {
		// Report the problem.
		t.Errorf("an odd value opened the key or was echoed")
	} // end of the odd check
} // end of TestKeyTwistie

// TestTagsHelpAlwaysShown: the line "Tags under each name" sits in the same row as the key twistie, and is drawn whether the key is open or closed.
func TestTagsHelpAlwaysShown(t *testing.T) {
	// A fake Ollama and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// The page as it first opens, and with the key opened.
	_, _, closed := get(t, rig.h, http.MethodGet, "/")
	_, _, open := get(t, rig.h, http.MethodGet, "/?key=open")
	// Both pages must have the row, the twistie first and the tags help after it, inside the same row.
	for name, page := range map[string]string{"closed": closed, "open": open} {
		// Where the row starts, where the twistie is, where the tags line is, and where the row ends.
		row := strings.Index(page, `<div class="keyrow">`)
		toggle := strings.Index(page, `<p class="keytoggle" id="key">`)
		tags := strings.Index(page, `<p class="muted groupedhelp">Tags under each name:`)
		end := strings.Index(page[max(row, 0):], "</div>")
		// Every part must exist, in this order, and the row must close after the tags line.
		if row < 0 || toggle < row || tags < toggle || end < 0 || row+end < tags {
			// Report which page failed.
			t.Errorf("%s page: the key row is wrong (row %d, twistie %d, tags %d)", name, row, toggle, tags)
		} // end of the order check
		// The words of the tags line must be visible.
		if !strings.Contains(page, "How models are grouped") {
			// Report it.
			t.Errorf("%s page lacks the words How models are grouped", name)
		} // end of the words check
	} // end of the loop over the two pages
	// The row has a style that puts the two parts at the two ends.
	css, err := os.ReadFile("web/app.css")
	// The file must be readable.
	if err != nil {
		// Report it.
		t.Fatal(err)
	} // end of the read check
	// The rule must hold the two-ends layout.
	if !strings.Contains(string(css), ".keyrow {") || !strings.Contains(string(css), "justify-content: space-between;") {
		// Report it.
		t.Error("the style for the key row is missing")
	} // end of the style check
} // end of TestTagsHelpAlwaysShown

// TestTipsFollowTheirHeading: every help bubble is tied to its own heading box, so it stays next to the heading when the page is scrolled (a plain fixed bubble stays far off the screen).
func TestTipsFollowTheirHeading(t *testing.T) {
	// Read the style file.
	raw, err := os.ReadFile("web/app.css")
	// The file must be readable.
	if err != nil {
		// Report it.
		t.Fatal(err)
	} // end of the read check
	// The text of the style file.
	css := string(raw)
	// The rule of the heading box (.tipbox) must make the box an anchor with a private name.
	box := css[strings.Index(css, ".tipbox {"):]
	// Cut the rule at its end marker.
	box = box[:strings.Index(box, "} /* end of rule */")]
	// Both anchor lines must be in this rule.
	for _, want := range []string{"anchor-name: --tipicon;", "anchor-scope: --tipicon;"} {
		// Report a missing line.
		if !strings.Contains(box, want) {
			t.Errorf(".tipbox rule lacks %q", want)
		} // end of the line check
	} // end of the loop over the anchor lines
	// The rule of the heading bubbles (not icon bubbles) must tie them to that anchor and open them below it.
	at := strings.Index(css, ".tip:not(.tip-icon) {")
	// The rule must exist.
	if at < 0 {
		// Nothing more to check.
		t.Fatal("the rule for heading bubbles is missing")
	} // end of the existence check
	// Cut the rule at its end marker.
	rule := css[at:]
	// Only this rule.
	rule = rule[:strings.Index(rule, "} /* end of rule */")]
	// The lines that tie the bubble to its heading.
	for _, want := range []string{"position-anchor: --tipicon;", "top: anchor(bottom);", "left: anchor(left);", "transform: none;", "position-try-fallbacks:"} {
		// Report a missing line.
		if !strings.Contains(rule, want) {
			t.Errorf("heading bubble rule lacks %q", want)
		} // end of the line check
	} // end of the loop over the bubble lines
} // end of TestTipsFollowTheirHeading
