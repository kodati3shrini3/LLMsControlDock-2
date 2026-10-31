// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides the request method names.
	"net/http"
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
