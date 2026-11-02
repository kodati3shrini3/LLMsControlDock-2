// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides the method name.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// os reads the template files.
	"os"
	// path/filepath lists the template files.
	"path/filepath"
	// strings searches the text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// backArrowMarkup is the round arrow link every sub-page carries at its top right.
const backArrowMarkup = `<a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback">`

// TestEverySubPageTemplateHasTheBackArrow checks, in the template files, that each sub-page has the arrow once, and the main page and the tips file have none.
func TestEverySubPageTemplateHasTheBackArrow(t *testing.T) {
	// Every template file.
	files, err := filepath.Glob("web/*.html")
	// The folder must be readable.
	if err != nil || len(files) < 10 {
		// Stop.
		t.Fatalf("template files not found: %v (%d)", err, len(files))
	} // end of the check
	// Go through them.
	for _, f := range files {
		// Read it.
		raw, err := os.ReadFile(f)
		// It must be readable.
		if err != nil {
			// Stop.
			t.Fatalf("cannot read %s: %v", f, err)
		} // end of the read check
		// How many arrows it has.
		n := strings.Count(string(raw), backArrowMarkup)
		// The main page and the shared bubble texts have none; every other page has exactly one.
		want := 1
		// The two exceptions.
		if g := filepath.ToSlash(f); g == "web/index.html" || g == "web/tips.html" {
			// None.
			want = 0
		} // end of the exception check
		// Compare.
		if n != want {
			// Report it.
			t.Errorf("%s has %d back arrows, want %d", f, n, want)
		} // end of the count check
	} // end of the loop
} // end of TestEverySubPageTemplateHasTheBackArrow

// TestBackArrowOnTheRenderedPages checks real pages: the arrow is there with its tooltip, the button at the bottom stays, and the last Stop page has no arrow.
func TestBackArrowOnTheRenderedPages(t *testing.T) {
	// A fake with one model loaded, so the unload page exists.
	f := newPerfFake()
	// Mark it loaded.
	f.mu.Lock()
	// In memory.
	f.loaded["chat:1b"] = true
	// Release the fake.
	f.mu.Unlock()
	// Count the stop requests instead of stopping.
	stops := 0
	// Remember the real one.
	old := stopRequest
	// Replace it.
	stopRequest = func() { stops++ }
	// Put it back at the end.
	t.Cleanup(func() { stopRequest = old })
	// Build the rig.
	rig, _ := perfRig(t, f)
	// The main page has no arrow.
	if _, _, body := get(t, rig.h, http.MethodGet, "/"); strings.Contains(body, `class="backcircle"`) {
		// Report it.
		t.Errorf("the main page has a back arrow")
	} // end of the main-page check
	// The pages to look at.
	pages := map[string]string{}
	// The About page is a plain GET.
	_, _, pages["about"] = get(t, rig.h, http.MethodGet, "/about")
	// The model pages are forms.
	for name, path := range map[string]string{"modelfile": "/modelfile", "unload": "/unload", "load": "/load", "delete": "/delete", "gear": "/gear", "performance": "/performance"} {
		// The model that fits the page: the unload page needs a loaded one.
		model := "embed:1b"
		// The unload page.
		if name == "unload" {
			// The loaded one.
			model = "chat:1b"
		} // end of the model choice
		// Send it.
		_, body, _ := perfPost(t, rig, path, model)
		// Keep it.
		pages[name] = body
	} // end of the loop
	// The question page of Stop.
	res := post(t, rig.h, "/stop", url.Values{"token": {rig.token}}, fromThisPage)
	// Keep it.
	pages["stop"] = bodyOf(res)
	// Check each.
	for name, body := range pages {
		// The arrow, its accessible name and its tooltip.
		for _, w := range []string{backArrowMarkup, `class="tipbox backtop"`, `id="tipback">Back to the monitor</span>`} {
			// Look for it.
			if !strings.Contains(body, w) {
				// Report the gap.
				t.Errorf("%s page lacks %q", name, w)
			} // end of the check
		} // end of the loop
		// The arrow comes before the first heading.
		if i, j := strings.Index(body, `class="tipbox backtop"`), strings.Index(body, "<h1"); i < 0 || j < 0 || i > j {
			// Report it.
			t.Errorf("%s page: the arrow is not at the top (%d, %d)", name, i, j)
		} // end of the order check
		// The links at the bottom stay: besides the arrow, the page still has its own way back (a Back to the monitor button, or the safe choice of a question page).
		if n := strings.Count(body, `href="/"`); n < 2 {
			// Report it.
			t.Errorf("%s page has %d links to the monitor, want the arrow plus its own button", name, n)
		} // end of the link check
	} // end of the loop
	// The last Stop page: the monitor is closing, so there is nothing to go back to.
	last := post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
	// No arrow.
	if body := bodyOf(last); strings.Contains(body, `class="backcircle"`) || !strings.Contains(body, "stopped") && !strings.Contains(body, "Stopped") {
		// Report it.
		t.Errorf("the last Stop page is wrong: %q", body)
	} // end of the last-page check
} // end of TestBackArrowOnTheRenderedPages
