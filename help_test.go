// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages the tests use.
	// html unescapes the page text before it is compared.
	"html"
	// net/http gives the method names and status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestWrapText checks the line breaking: words stay whole and lines stay within the width.
func TestWrapText(t *testing.T) {
	// A sentence that needs three lines.
	got := wrapText("1. Shows the choices, with free disk and memory filled in.", 23)
	// Every line fits.
	for _, l := range got {
		// Too long.
		if len(l) > 23 {
			// Report.
			t.Errorf("line %q is longer than 23", l)
		} // end of the check
	} // end of the loop
	// Nothing is lost.
	if strings.Join(got, " ") != "1. Shows the choices, with free disk and memory filled in." {
		// Report.
		t.Errorf("the words changed: %q", got)
	} // end of the words check
	// A single long word stays whole.
	if w := wrapText("extraordinarily-long-word", 10); len(w) != 1 || w[0] != "extraordinarily-long-word" {
		// Report.
		t.Errorf("long word: %q", w)
	} // end of the long-word check
} // end of TestWrapText

// TestHelpTopicsFitTheirBoxes checks the data of every topic: lanes in range, and every step's words fit in a box of three lines.
func TestHelpTopicsFitTheirBoxes(t *testing.T) {
	// Each topic.
	for _, tp := range helpTopics {
		// There must be steps and an introduction.
		if len(tp.Steps) < 2 || tp.Intro == "" || tp.ID == "" || tp.Title == "" {
			// Report.
			t.Errorf("topic %q is incomplete", tp.ID)
		} // end of the completeness check
		// Each step.
		for i, s := range tp.Steps {
			// The lane must exist.
			if s.Lane < 0 || s.Lane >= len(helpLanes) {
				// Report.
				t.Errorf("%s step %d: lane %d does not exist", tp.ID, i+1, s.Lane)
			} // end of the lane check
			// The words must fit.
			if n := len(wrapText("00. "+s.Text, helpWrap)); n > helpMaxLines {
				// Report.
				t.Errorf("%s step %d needs %d lines, the box holds %d: %q", tp.ID, i+1, n, helpMaxLines, s.Text)
			} // end of the fit check
		} // end of the step loop
	} // end of the topic loop
} // end of TestHelpTopicsFitTheirBoxes

// TestHelpPage checks the Help page: it is a plain read-only page with no script, each step is in the picture and in the list, the arrows join the steps, and the monitor links to it.
func TestHelpPage(t *testing.T) {
	// A rig.
	rig := newThemeRig(t)
	// Fetch the page.
	status, header, body := get(t, rig.h, http.MethodGet, "/help")
	// Found, as HTML, under the strict policy.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
		// Stop.
		t.Fatalf("status %d, type %q, policy %q", status, header.Get("Content-Type"), header.Get("Content-Security-Policy"))
	} // end of the check
	// No script, and only reading.
	if strings.Contains(body, "<script") {
		// Report.
		t.Error("the Help page carries a script")
	} // end of the script check
	// Only GET is allowed.
	if res := post(t, rig.h, "/help", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report.
		t.Errorf("POST /help = %d, want 405", res.StatusCode)
	} // end of the method check
	// The back arrow and the picture's accessible name.
	for _, want := range []string{backArrowMarkup, `role="img"`, `<title id="find-llm-svgtitle">`, "The steps in words", `<h1>Help</h1>`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the Help page lacks %q", want)
		} // end of the look
	} // end of the loop
	// The page as plain text for the comparison of the words.
	plain := html.UnescapeString(body)
	// Each step appears twice: in the picture (possibly split over lines) and in the list.
	for _, tp := range helpTopics {
		// Each step.
		for i, s := range tp.Steps {
			// In the list, whole.
			if !strings.Contains(plain, "</strong> "+s.Text+"</li>") {
				// Report.
				t.Errorf("%s step %d is not in the list", tp.ID, i+1)
			} // end of the list check
			// In the picture, line by line.
			for _, l := range wrapText(strings.Join([]string{itoa(i + 1), ". ", s.Text}, ""), helpWrap) {
				// Look for the line.
				if !strings.Contains(plain, ">"+l+"</text>") {
					// Report.
					t.Errorf("%s step %d: line %q is not in the picture", tp.ID, i+1, l)
				} // end of the line check
			} // end of the line loop
		} // end of the step loop
		// One box per step and one arrow between each pair.
		if n := strings.Count(body, `class="lanebox"`); n != len(tp.Steps) {
			// Report.
			t.Errorf("%d boxes, want %d", n, len(tp.Steps))
		} // end of the box check
		// The arrows.
		if n := strings.Count(body, `class="lanearrow"`); n != len(tp.Steps)-1 {
			// Report.
			t.Errorf("%d arrows, want %d", n, len(tp.Steps)-1)
		} // end of the arrow check
	} // end of the topic loop
	// Every lane has its name.
	for _, l := range helpLanes {
		// Look for it.
		if !strings.Contains(body, `>`+l+`</text>`) {
			// Report.
			t.Errorf("lane %q has no name in the picture", l)
		} // end of the look
	} // end of the lane loop
	// Each topic is a closed section that opens when its title is clicked, and the contents list links to it.
	for _, tp := range helpTopics {
		// The closed section (no "open" word).
		if !strings.Contains(body, `<details class="helptopic" id="`+tp.ID+`">`) || strings.Contains(body, `<details class="helptopic" id="`+tp.ID+`" open`) {
			// Report.
			t.Errorf("topic %s is not a closed section", tp.ID)
		} // end of the section check
		// The contents link.
		if !strings.Contains(body, `<li><a href="#`+tp.ID+`">`+html.EscapeString(tp.Title)+`</a></li>`) {
			// Report.
			t.Errorf("the contents list lacks a link to %s", tp.ID)
		} // end of the link check
		// The title is the clickable row.
		if !strings.Contains(body, `<summary class="helpsum"><h2 id="`+tp.ID+`-title">`) {
			// Report.
			t.Errorf("topic %s has no clickable title", tp.ID)
		} // end of the title check
		// An arrow at the top of the open topic (before the picture) and one at the bottom (after the list).
		top, bottom := strings.Index(body, `id="tipback-`+tp.ID+`-top"`), strings.Index(body, `id="tipback-`+tp.ID+`-bottom"`)
		// The picture and the list.
		svg, list := strings.Index(body, `<svg class="swimlane"`), strings.Index(body, `<ol class="helpsteps">`)
		// Check the order.
		if top < 0 || bottom < 0 || !(top < svg && list < bottom) {
			// Report.
			t.Errorf("topic %s: arrows at %d and %d, picture at %d, list at %d", tp.ID, top, bottom, svg, list)
		} // end of the arrow check
	} // end of the topic loop
	// The page's own arrow plus two for every topic.
	if n := strings.Count(body, `aria-label="Back to the monitor"`); n != 1+2*len(helpTopics) {
		// Report.
		t.Errorf("%d back arrows, want %d", n, 1+2*len(helpTopics))
	} // end of the arrow count
	// The monitor links to the Help page.
	if _, _, main := get(t, rig.h, http.MethodGet, "/"); !strings.Contains(main, `<a class="brandbtn" href="/help">Help</a>`) {
		// Report.
		t.Error("the monitor has no Help button")
	} // end of the link check
} // end of TestHelpPage

// itoa writes a small number as text.
func itoa(n int) string {
	// Digits.
	s := ""
	// A zero.
	if n == 0 {
		// Zero.
		return "0"
	} // end of the zero check
	// Build from the right.
	for n > 0 {
		// The last digit in front.
		s = string(rune('0'+n%10)) + s
		// The rest.
		n /= 10
	} // end of the loop
	// The text.
	return s
} // end of itoa
